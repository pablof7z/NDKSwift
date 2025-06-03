# Building a Nostr iOS App with NDKSwift

This tutorial will guide you through building a complete Nostr iOS app using NDKSwift. We'll create "NostrReader", a simple but fully functional Nostr client that can display posts, user profiles, and publish new notes.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Project Setup](#project-setup)
3. [Basic Architecture](#basic-architecture)
4. [Setting Up NDKSwift](#setting-up-ndkswift)
5. [User Authentication](#user-authentication)
6. [Displaying Events](#displaying-events)
7. [User Profiles](#user-profiles)
8. [Publishing Notes](#publishing-notes)
9. [Advanced Features](#advanced-features)
10. [Best Practices](#best-practices)

## Prerequisites

- Xcode 15.0+
- iOS 15.0+ deployment target
- Basic knowledge of Swift and SwiftUI
- Understanding of async/await

## Project Setup

### 1. Create a New iOS App

1. Open Xcode and create a new iOS app
2. Choose SwiftUI for the interface
3. Set minimum deployment target to iOS 15.0

### 2. Add NDKSwift Package

In Xcode:
1. Go to File → Add Package Dependencies
2. Enter: `https://github.com/pablof7z/NDKSwift.git`
3. Choose "Up to Next Major Version" with version 0.1.0

### 3. Configure Info.plist

Add App Transport Security settings for WebSocket connections:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## Basic Architecture

We'll use MVVM (Model-View-ViewModel) architecture with the following structure:

```
NostrReader/
├── Models/
│   ├── AppState.swift
│   └── UserSettings.swift
├── ViewModels/
│   ├── FeedViewModel.swift
│   ├── ProfileViewModel.swift
│   └── PublishViewModel.swift
├── Views/
│   ├── ContentView.swift
│   ├── FeedView.swift
│   ├── ProfileView.swift
│   └── PublishView.swift
├── Services/
│   └── NostrService.swift
└── NostrReaderApp.swift
```

## Setting Up NDKSwift

### 1. Create NostrService

```swift
// Services/NostrService.swift
import Foundation
import NDKSwift

@MainActor
class NostrService: ObservableObject {
    static let shared = NostrService()
    
    private let ndk: NDK
    @Published var isConnected = false
    @Published var currentUser: NDKUser?
    
    // Default relay URLs
    private let defaultRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
        "wss://relay.current.fyi"
    ]
    
    private init() {
        // Initialize with file cache for persistence
        let cacheAdapter = try? NDKFileCache(path: "nostr-cache")
        self.ndk = NDK(
            relayUrls: defaultRelays,
            cacheAdapter: cacheAdapter
        )
    }
    
    func connect() async {
        do {
            try await ndk.connect()
            isConnected = true
        } catch {
            print("Connection failed: \(error)")
            isConnected = false
        }
    }
    
    func disconnect() async {
        await ndk.disconnect()
        isConnected = false
    }
    
    func setSigner(_ signer: NDKSigner) {
        ndk.signer = signer
        if let pubkey = signer.publicKey {
            currentUser = NDKUser(pubkey: pubkey)
        }
    }
}
```

### 2. Create App State

```swift
// Models/AppState.swift
import Foundation
import NDKSwift

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var privateKey: String?
    
    init() {
        // Load saved credentials from Keychain if available
        loadCredentials()
    }
    
    func login(with nsec: String) throws {
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        NostrService.shared.setSigner(signer)
        
        // Save to Keychain (implement secure storage)
        privateKey = nsec
        isAuthenticated = true
        saveCredentials()
    }
    
    func logout() {
        privateKey = nil
        isAuthenticated = false
        clearCredentials()
    }
    
    private func loadCredentials() {
        // Implement Keychain loading
    }
    
    private func saveCredentials() {
        // Implement Keychain saving
    }
    
    private func clearCredentials() {
        // Implement Keychain clearing
    }
}
```

## User Authentication

### 1. Create Login View

```swift
// Views/LoginView.swift
import SwiftUI
import NDKSwift

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var nsecInput = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to NostrReader")
                .font(.largeTitle)
                .bold()
            
            Text("Enter your private key (nsec) to get started")
                .foregroundColor(.secondary)
            
            TextField("nsec1...", text: $nsecInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            HStack(spacing: 20) {
                Button("Generate New Key") {
                    generateNewKey()
                }
                .buttonStyle(.bordered)
                
                Button("Login") {
                    login()
                }
                .buttonStyle(.borderedProminent)
                .disabled(nsecInput.isEmpty)
            }
            
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private func generateNewKey() {
        let signer = NDKPrivateKeySigner.generate()
        do {
            let nsec = try Bech32.nsec(from: signer.privateKey)
            nsecInput = nsec
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    private func login() {
        do {
            try appState.login(with: nsecInput)
        } catch {
            showError("Invalid private key")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showError = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showError = false
        }
    }
}
```

## Displaying Events

### 1. Create Feed ViewModel

```swift
// ViewModels/FeedViewModel.swift
import Foundation
import NDKSwift
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    @Published var events: [NDKEvent] = []
    @Published var isLoading = false
    
    private var subscription: NDKSubscription?
    private let nostrService = NostrService.shared
    
    func loadFeed() {
        isLoading = true
        
        // Create filter for text notes (kind 1)
        let filter = NDKFilter(
            kinds: [1],
            limit: 50
        )
        
        // Subscribe to events
        subscription = nostrService.ndk.subscribe(
            filters: [filter],
            closeOnEOSE: false
        )
        
        // Handle incoming events
        subscription?.onEvent { [weak self] event in
            DispatchQueue.main.async {
                self?.handleNewEvent(event)
            }
        }
        
        subscription?.onEOSE { [weak self] in
            DispatchQueue.main.async {
                self?.isLoading = false
            }
        }
        
        Task {
            await subscription?.start()
        }
    }
    
    private func handleNewEvent(_ event: NDKEvent) {
        // Insert events sorted by timestamp
        let insertIndex = events.firstIndex { $0.createdAt < event.createdAt } ?? events.count
        events.insert(event, at: insertIndex)
        
        // Limit feed size
        if events.count > 100 {
            events = Array(events.prefix(100))
        }
    }
    
    func stopLoading() {
        Task {
            await subscription?.close()
        }
    }
}
```

### 2. Create Feed View

```swift
// Views/FeedView.swift
import SwiftUI
import NDKSwift

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.events) { event in
                EventRow(event: event)
            }
            .navigationTitle("Feed")
            .refreshable {
                viewModel.loadFeed()
            }
            .overlay {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    ProgressView("Loading...")
                }
            }
        }
        .onAppear {
            viewModel.loadFeed()
        }
        .onDisappear {
            viewModel.stopLoading()
        }
    }
}

struct EventRow: View {
    let event: NDKEvent
    @State private var author: NDKUser?
    @State private var authorName: String = "Loading..."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Author avatar
                AsyncImage(url: URL(string: author?.profile?.picture ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading) {
                    Text(authorName)
                        .font(.headline)
                    
                    Text(RelativeTimeFormatter.string(from: event.createdAt.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Text(event.content)
                .font(.body)
                .lineLimit(10)
            
            // Show images if present
            if let images = NDKImage.parseFromImeta(event.imetaTags) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(images, id: \.url) { image in
                            AsyncImage(url: URL(string: image.url)) { img in
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(height: 200)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .task {
            await loadAuthor()
        }
    }
    
    private func loadAuthor() async {
        author = NostrService.shared.ndk.getUser(pubkey: event.pubkey)
        
        // Try to load profile
        do {
            try await author?.fetchProfile()
            authorName = author?.profile?.displayName ?? 
                         author?.profile?.name ?? 
                         String(author?.npub.prefix(8) ?? "Unknown") + "..."
        } catch {
            authorName = String(author?.npub.prefix(8) ?? "Unknown") + "..."
        }
    }
}
```

## User Profiles

### 1. Create Profile ViewModel

```swift
// ViewModels/ProfileViewModel.swift
import Foundation
import NDKSwift

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: NDKUser
    @Published var events: [NDKEvent] = []
    @Published var isLoadingProfile = false
    @Published var isLoadingEvents = false
    
    private var subscription: NDKSubscription?
    
    init(user: NDKUser) {
        self.user = user
    }
    
    func loadProfile() async {
        isLoadingProfile = true
        do {
            try await user.fetchProfile()
        } catch {
            print("Failed to load profile: \(error)")
        }
        isLoadingProfile = false
    }
    
    func loadUserEvents() {
        isLoadingEvents = true
        events.removeAll()
        
        let filter = NDKFilter(
            authors: [user.pubkey],
            kinds: [1],
            limit: 50
        )
        
        subscription = NostrService.shared.ndk.subscribe(filters: [filter])
        
        subscription?.onEvent { [weak self] event in
            DispatchQueue.main.async {
                self?.events.append(event)
                self?.events.sort { $0.createdAt > $1.createdAt }
            }
        }
        
        subscription?.onEOSE { [weak self] in
            DispatchQueue.main.async {
                self?.isLoadingEvents = false
            }
        }
        
        Task {
            await subscription?.start()
        }
    }
    
    func stopLoading() {
        Task {
            await subscription?.close()
        }
    }
}
```

### 2. Create Profile View

```swift
// Views/ProfileView.swift
import SwiftUI
import NDKSwift

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    
    init(user: NDKUser) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(user: user))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Profile Header
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: viewModel.user.profile?.picture ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.user.profile?.displayName ?? "")
                            .font(.title2)
                            .bold()
                        
                        Text("@\(viewModel.user.profile?.name ?? "")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(String(viewModel.user.npub.prefix(16)) + "...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Bio
                if let about = viewModel.user.profile?.about {
                    Text(about)
                        .padding()
                }
                
                // User's Notes
                VStack(alignment: .leading) {
                    Text("Notes")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if viewModel.isLoadingEvents {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(viewModel.events) { event in
                            EventRow(event: event)
                                .padding(.horizontal)
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile()
            viewModel.loadUserEvents()
        }
        .onDisappear {
            viewModel.stopLoading()
        }
    }
}
```

## Publishing Notes

### 1. Create Publish ViewModel

```swift
// ViewModels/PublishViewModel.swift
import Foundation
import NDKSwift

@MainActor
class PublishViewModel: ObservableObject {
    @Published var content = ""
    @Published var isPublishing = false
    @Published var publishError: String?
    
    func publish() async {
        guard !content.isEmpty else { return }
        guard let signer = NostrService.shared.ndk.signer else {
            publishError = "No signer configured"
            return
        }
        
        isPublishing = true
        publishError = nil
        
        do {
            // Create event
            var event = NDKEvent(
                pubkey: signer.publicKey,
                createdAt: .now(),
                kind: 1,
                content: content
            )
            
            // Sign event
            try await event.sign(with: signer)
            
            // Publish
            try await NostrService.shared.ndk.publish(event)
            
            // Clear content on success
            content = ""
        } catch {
            publishError = error.localizedDescription
        }
        
        isPublishing = false
    }
}
```

### 2. Create Publish View

```swift
// Views/PublishView.swift
import SwiftUI

struct PublishView: View {
    @StateObject private var viewModel = PublishViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $viewModel.content)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isTextEditorFocused)
                
                if let error = viewModel.publishError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Publish") {
                        Task {
                            await viewModel.publish()
                            if viewModel.publishError == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.content.isEmpty || viewModel.isPublishing)
                }
            }
        }
        .onAppear {
            isTextEditorFocused = true
        }
    }
}
```

## Advanced Features

### 1. Implementing Reactions

```swift
extension EventRow {
    func react(with content: String) async {
        guard let signer = NostrService.shared.ndk.signer else { return }
        
        var reaction = NDKEvent(
            pubkey: signer.publicKey,
            createdAt: .now(),
            kind: 7,
            tags: [
                ["e", event.id],
                ["p", event.pubkey]
            ],
            content: content
        )
        
        do {
            try await reaction.sign(with: signer)
            try await NostrService.shared.ndk.publish(reaction)
        } catch {
            print("Failed to react: \(error)")
        }
    }
}
```

### 2. Following Users

```swift
extension ProfileViewModel {
    func follow() async {
        guard let signer = NostrService.shared.ndk.signer else { return }
        
        // Fetch current contacts
        let contactsFilter = NDKFilter(
            authors: [signer.publicKey],
            kinds: [3],
            limit: 1
        )
        
        let subscription = NostrService.shared.ndk.subscribe(filters: [contactsFilter])
        var currentContacts: [[String]] = []
        
        subscription.onEvent { event in
            currentContacts = event.tags.filter { $0.first == "p" }
        }
        
        await subscription.start()
        try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
        await subscription.close()
        
        // Add new follow
        currentContacts.append(["p", user.pubkey])
        
        // Create new contacts event
        var contactsEvent = NDKEvent(
            pubkey: signer.publicKey,
            createdAt: .now(),
            kind: 3,
            tags: currentContacts,
            content: ""
        )
        
        do {
            try await contactsEvent.sign(with: signer)
            try await NostrService.shared.ndk.publish(contactsEvent)
        } catch {
            print("Failed to follow: \(error)")
        }
    }
}
```

### 3. Direct Messages

```swift
// ViewModels/DirectMessageViewModel.swift
@MainActor
class DirectMessageViewModel: ObservableObject {
    @Published var messages: [NDKEvent] = []
    let recipient: NDKUser
    
    init(recipient: NDKUser) {
        self.recipient = recipient
    }
    
    func sendMessage(_ content: String) async {
        guard let signer = NostrService.shared.ndk.signer else { return }
        
        do {
            // Encrypt message
            let encrypted = try await signer.encrypt(content, to: recipient.pubkey)
            
            // Create DM event
            var dm = NDKEvent(
                pubkey: signer.publicKey,
                createdAt: .now(),
                kind: 4,
                tags: [["p", recipient.pubkey]],
                content: encrypted
            )
            
            try await dm.sign(with: signer)
            try await NostrService.shared.ndk.publish(dm)
        } catch {
            print("Failed to send DM: \(error)")
        }
    }
}
```

## Best Practices

### 1. Error Handling

Always wrap NDKSwift operations in proper error handling:

```swift
do {
    try await someOperation()
} catch NDKError.relayConnectionFailed(let message) {
    // Handle connection errors
} catch NDKError.signingFailed {
    // Handle signing errors
} catch {
    // Handle other errors
}
```

### 2. Memory Management

Properly manage subscriptions to avoid memory leaks:

```swift
class ViewModel: ObservableObject {
    private var subscription: NDKSubscription?
    
    deinit {
        Task {
            await subscription?.close()
        }
    }
}
```

### 3. Performance Optimization

Use caching to improve performance:

```swift
// Initialize NDK with file cache
let cache = try NDKFileCache(path: "nostr-cache")
let ndk = NDK(cacheAdapter: cache)

// Queries will check cache first
let cachedEvents = await cache.query(subscription: subscription)
```

### 4. Security

Never expose private keys:

```swift
// Store private keys securely in Keychain
import Security

func saveToKeychain(nsec: String) {
    let data = nsec.data(using: .utf8)!
    let query: [String: Any] = [
        kSecClass as String: kSecClassInternetPassword,
        kSecAttrAccount as String: "nostr-nsec",
        kSecValueData as String: data
    ]
    SecItemAdd(query as CFDictionary, nil)
}
```

### 5. UI Responsiveness

Keep the UI responsive by offloading work:

```swift
Task.detached {
    // Heavy processing
    let result = await processEvents(events)
    
    await MainActor.run {
        // Update UI
        self.processedEvents = result
    }
}
```

## Complete App Structure

### Main App File

```swift
// NostrReaderApp.swift
import SwiftUI

@main
struct NostrReaderApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            if appState.isAuthenticated {
                ContentView()
                    .environmentObject(appState)
                    .task {
                        await NostrService.shared.connect()
                    }
            } else {
                LoginView()
                    .environmentObject(appState)
            }
        }
    }
}
```

### Content View with Tab Navigation

```swift
// Views/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showPublishSheet = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet")
                }
                .tag(0)
            
            if let currentUser = NostrService.shared.currentUser {
                ProfileView(user: currentUser)
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { showPublishSheet = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
            }
            .padding()
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishView()
        }
    }
}
```

## Conclusion

You now have a fully functional Nostr iOS app! This tutorial covered:

- Setting up NDKSwift in an iOS project
- User authentication with private keys
- Displaying a feed of notes
- Showing user profiles
- Publishing new notes
- Advanced features like reactions and follows

Next steps:
- Add push notifications for mentions
- Implement Lightning payments
- Add media upload support
- Create custom themes
- Add relay management UI

For more information, check out the [NDKSwift API Reference](./API_REFERENCE.md) and the [Nostr protocol documentation](https://github.com/nostr-protocol/nips).