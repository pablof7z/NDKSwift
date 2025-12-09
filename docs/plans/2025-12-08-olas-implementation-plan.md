# Olas Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a fully functional Instagram-like photo sharing app on Nostr using NDKSwift.

**Architecture:** SwiftUI app with MVVM pattern. Views observe ViewModels that use NDKSwift directly for data. NostrDB for caching. Blossom for image hosting. No unnecessary abstractions.

**Tech Stack:** SwiftUI, NDKSwift, NDKSwiftUI, NostrDB, CoreImage (filters), PhotosUI

---

## Project Structure

```
Olas/
├── Package.swift                    # SPM package depending on NDKSwift
├── Sources/
│   └── Olas/
│       ├── OlasApp.swift           # App entry point
│       ├── Models/
│       │   └── OlasConstants.swift # App constants, default relays
│       ├── ViewModels/
│       │   ├── FeedViewModel.swift
│       │   ├── AuthViewModel.swift
│       │   ├── CreatePostViewModel.swift
│       │   ├── ProfileViewModel.swift
│       │   └── ExploreViewModel.swift
│       ├── Views/
│       │   ├── MainTabView.swift
│       │   ├── Feed/
│       │   ├── Explore/
│       │   ├── Create/
│       │   ├── Notifications/
│       │   ├── Profile/
│       │   ├── Auth/
│       │   └── Components/
│       └── Utils/
│           ├── ImageFilters.swift
│           └── Theme.swift
└── Tests/
    └── OlasTests/
        ├── ViewModels/
        └── TestHelpers/
```

---

## Milestone 1: Feed Display

**Deliverable:** App that displays a scrollable feed of image posts (kind 20) from public relays with author info and timestamps.

**Value:** Users can browse Nostr image content immediately.

### Task 1.1: Create Olas Package

**Files:**
- Create: `Olas/Package.swift`
- Create: `Olas/Sources/Olas/OlasApp.swift`
- Create: `Olas/Sources/Olas/Models/OlasConstants.swift`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olas",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Olas", targets: ["Olas"])
    ],
    dependencies: [
        .package(path: "..")  // NDKSwift parent package
    ],
    targets: [
        .target(
            name: "Olas",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
                .product(name: "NDKSwiftUI", package: "NDKSwift")
            ]
        ),
        .testTarget(
            name: "OlasTests",
            dependencies: ["Olas"]
        )
    ]
)
```

**Step 2: Create OlasConstants.swift**

```swift
import Foundation
import NDKSwift

public enum OlasConstants {
    public static let defaultRelays: [String] = [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    public static let blossomServers: [String] = [
        "https://blossom.primal.net",
        "https://nostr.build"
    ]

    public enum EventKinds {
        public static let image: Kind = 20
        public static let reaction: Kind = 7
        public static let comment: Kind = 1111
    }
}
```

**Step 3: Create minimal OlasApp.swift**

```swift
import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Olas")
        }
    }
}
```

**Step 4: Verify package builds**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): initialize Olas package with NDKSwift dependency"
```

---

### Task 1.2: Create FeedViewModel with Tests (TDD)

**Files:**
- Create: `Olas/Tests/OlasTests/ViewModels/FeedViewModelTests.swift`
- Create: `Olas/Tests/OlasTests/TestHelpers/MockNDK.swift`
- Create: `Olas/Sources/Olas/ViewModels/FeedViewModel.swift`

**Step 1: Write the failing test**

```swift
// FeedViewModelTests.swift
import XCTest
@testable import Olas
@testable import NDKSwift

final class FeedViewModelTests: XCTestCase {
    var ndk: NDK!

    override func setUp() async throws {
        ndk = NDK(relayUrls: [])
    }

    override func tearDown() async throws {
        await ndk.disconnect()
    }

    func testInitialStateIsEmpty() async {
        let viewModel = await FeedViewModel(ndk: ndk)

        await MainActor.run {
            XCTAssertTrue(viewModel.posts.isEmpty)
            XCTAssertFalse(viewModel.isLoading)
            XCTAssertNil(viewModel.error)
        }
    }

    func testPostsAreImageEvents() async {
        let viewModel = await FeedViewModel(ndk: ndk)

        // FeedViewModel should only accept kind 20 events
        await MainActor.run {
            XCTAssertEqual(viewModel.filter.kinds, [OlasConstants.EventKinds.image])
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Olas && swift test --filter FeedViewModelTests`
Expected: FAIL - "Cannot find 'FeedViewModel' in scope"

**Step 3: Write minimal FeedViewModel**

```swift
// FeedViewModel.swift
import Foundation
import SwiftUI
import NDKSwift
import Combine

@MainActor
public final class FeedViewModel: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    public let filter: NDKFilter

    private let ndk: NDK
    private var subscription: NDKSubscription<NDKEvent>?
    private var cancellables = Set<AnyCancellable>()

    public init(ndk: NDK) {
        self.ndk = ndk
        self.filter = NDKFilter(kinds: [OlasConstants.EventKinds.image], limit: 50)
    }

    public func startSubscription() {
        isLoading = true

        subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )

        subscription?.$data
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.posts = events.sorted { $0.createdAt > $1.createdAt }
                self?.isLoading = false
            }
            .store(in: &cancellables)

        subscription?.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.error = error
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }

    public func stopSubscription() {
        cancellables.removeAll()
        subscription = nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd Olas && swift test --filter FeedViewModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): add FeedViewModel with TDD"
```

---

### Task 1.3: Create Theme System

**Files:**
- Create: `Olas/Sources/Olas/Utils/Theme.swift`

**Step 1: Create Theme.swift**

```swift
// Theme.swift
import SwiftUI

public enum OlasTheme {
    // MARK: - Colors
    public enum Colors {
        // Primary Ocean palette
        public static let deepTeal = Color(hex: "0D7377")
        public static let oceanBlue = Color(hex: "14919B")
        public static let seafoam = Color(hex: "7ED7C1")

        // Feedback colors
        public static let zapGold = Color(hex: "FFB800")
        public static let heartRed = Color(hex: "FF4757")
        public static let success = Color(hex: "2ED573")

        // Light mode
        public static let backgroundLight = Color(hex: "F8FFFE")
        public static let cardLight = Color.white.opacity(0.7)
        public static let textLight = Color(hex: "1A2B32")
        public static let secondaryLight = Color(hex: "6B8187")

        // Dark mode
        public static let backgroundDark = Color(hex: "0A1215")
        public static let cardDark = Color(hex: "142125").opacity(0.7)
        public static let textDark = Color(hex: "E8F4F5")
        public static let secondaryDark = Color(hex: "7B9BA1")
    }

    // MARK: - Glassmorphism
    public enum Glass {
        public static let cornerRadius: CGFloat = 20
        public static let shadowRadius: CGFloat = 20
        public static let shadowOpacity: Double = 0.1
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers
public struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(OlasTheme.Glass.cornerRadius)
            .shadow(
                color: .black.opacity(OlasTheme.Glass.shadowOpacity),
                radius: OlasTheme.Glass.shadowRadius,
                y: 10
            )
    }
}

extension View {
    public func glassBackground() -> some View {
        modifier(GlassBackground())
    }
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Utils/Theme.swift
git commit -m "feat(olas): add ocean theme system with glassmorphism"
```

---

### Task 1.4: Create PostCard Component with Tests

**Files:**
- Create: `Olas/Tests/OlasTests/Views/PostCardTests.swift`
- Create: `Olas/Sources/Olas/Views/Components/PostCard.swift`

**Step 1: Write the failing test**

```swift
// PostCardTests.swift
import XCTest
import SwiftUI
@testable import Olas
@testable import NDKSwift

final class PostCardTests: XCTestCase {

    func testPostCardExtractsImageURL() {
        // Create a mock image event with imeta tag
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: 20,
            tags: [
                ["imeta", "url https://example.com/image.jpg", "m image/jpeg"]
            ],
            content: "Test caption",
            sig: "sig123"
        )

        let image = NDKImage(event: event)
        XCTAssertEqual(image.primaryImageURL, "https://example.com/image.jpg")
    }

    func testPostCardDisplaysCaption() {
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: 1234567890,
            kind: 20,
            tags: [],
            content: "Beautiful sunset #photography",
            sig: "sig123"
        )

        XCTAssertEqual(event.content, "Beautiful sunset #photography")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd Olas && swift test --filter PostCardTests`
Expected: Tests should pass since we're using NDKSwift types

**Step 3: Create PostCard.swift**

```swift
// PostCard.swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct PostCard: View {
    let event: NDKEvent
    let ndk: NDK

    @State private var isLiked = false

    public init(event: NDKEvent, ndk: NDK) {
        self.event = event
        self.ndk = ndk
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            postHeader

            // Image
            postImage

            // Actions
            postActions

            // Caption
            postCaption
        }
        .background(Color(.systemBackground))
    }

    private var postHeader: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(pubkey: event.pubkey, ndk: ndk)
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(pubkey: event.pubkey, ndk: ndk)
                    .font(.subheadline.weight(.semibold))

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postImage: some View {
        Group {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(ProgressView())
                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isLiked = true
            }
        }
    }

    private var postActions: some View {
        HStack(spacing: 16) {
            Button {
                isLiked.toggle()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? OlasTheme.Colors.heartRed : .primary)
            }

            Button {
                // Comments action
            } label: {
                Image(systemName: "bubble.right")
            }

            Button {
                // Zap action
            } label: {
                Image(systemName: "bolt")
                    .foregroundStyle(OlasTheme.Colors.zapGold)
            }

            Spacer()
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postCaption: some View {
        Group {
            if !event.content.isEmpty {
                HStack {
                    Text(event.content)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
```

**Step 4: Run tests**

Run: `cd Olas && swift test --filter PostCardTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): add PostCard component for feed display"
```

---

### Task 1.5: Create FeedView

**Files:**
- Create: `Olas/Sources/Olas/Views/Feed/FeedView.swift`

**Step 1: Create FeedView.swift**

```swift
// FeedView.swift
import SwiftUI
import NDKSwift

public struct FeedView: View {
    @StateObject private var viewModel: FeedViewModel
    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        _viewModel = StateObject(wrappedValue: FeedViewModel(ndk: ndk))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.posts, id: \.id) { event in
                        PostCard(event: event, ndk: ndk)
                            .padding(.bottom, 8)
                    }
                }
            }
            .refreshable {
                viewModel.stopSubscription()
                viewModel.startSubscription()
            }
            .navigationTitle("Olas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Olas")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                }
            }
        }
        .onAppear {
            viewModel.startSubscription()
        }
        .onDisappear {
            viewModel.stopSubscription()
        }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            }

            if let error = viewModel.error {
                ContentUnavailableView(
                    "Unable to load feed",
                    systemImage: "wifi.slash",
                    description: Text(error.localizedDescription)
                )
            }

            if !viewModel.isLoading && viewModel.posts.isEmpty && viewModel.error == nil {
                ContentUnavailableView(
                    "No posts yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Follow some accounts or check back later")
                )
            }
        }
    }
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Views/Feed/FeedView.swift
git commit -m "feat(olas): add FeedView with pull-to-refresh"
```

---

### Task 1.6: Create MainTabView and Wire Up App

**Files:**
- Create: `Olas/Sources/Olas/Views/MainTabView.swift`
- Modify: `Olas/Sources/Olas/OlasApp.swift`

**Step 1: Create MainTabView.swift**

```swift
// MainTabView.swift
import SwiftUI
import NDKSwift

public struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var hasNotifications = false

    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(ndk: ndk)
                .tabItem {
                    Label("Home", systemImage: selectedTab == 0 ? "wave.3.up.circle.fill" : "wave.3.up.circle")
                }
                .tag(0)

            // Explore placeholder
            Text("Explore")
                .tabItem {
                    Label("Explore", systemImage: selectedTab == 1 ? "safari.fill" : "safari")
                }
                .tag(1)

            // Create placeholder
            Text("Create")
                .tabItem {
                    Label("", systemImage: "plus.app.fill")
                }
                .tag(2)

            // Notifications - only show if has notifications
            if hasNotifications {
                Text("Notifications")
                    .tabItem {
                        Label("Activity", systemImage: selectedTab == 3 ? "bell.fill" : "bell")
                    }
                    .tag(3)
            }

            // Profile placeholder
            Text("Profile")
                .tabItem {
                    Label("Profile", systemImage: selectedTab == 4 ? "person.fill" : "person")
                }
                .tag(4)
        }
        .tint(OlasTheme.Colors.deepTeal)
    }
}
```

**Step 2: Update OlasApp.swift**

```swift
// OlasApp.swift
import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @State private var ndk: NDK?
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let ndk = ndk, isInitialized {
                    MainTabView(ndk: ndk)
                } else {
                    ProgressView("Connecting...")
                        .task {
                            await initializeNDK()
                        }
                }
            }
        }
    }

    private func initializeNDK() async {
        let relayUrls = OlasConstants.defaultRelays.compactMap { RelayURL($0) }
        let newNDK = NDK(relayUrls: relayUrls)

        // Initialize NostrDB cache
        let cachePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("olas_cache")
            .path

        do {
            let cache = try NDKNostrDBCache(path: cachePath)
            newNDK.cache = cache
        } catch {
            print("Failed to initialize cache: \(error)")
        }

        await newNDK.connect()

        await MainActor.run {
            self.ndk = newNDK
            self.isInitialized = true
        }
    }
}
```

**Step 3: Verify build and run**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Olas/
git commit -m "feat(olas): wire up MainTabView with NDK initialization"
```

---

### Task 1.7: Create iOS App Target

**Files:**
- Create: `Olas/OlasApp/OlasApp.xcodeproj` (via Xcode or xcodegen)
- Create: `Olas/OlasApp/Info.plist`

**Step 1: Create Xcode project for iOS app**

This task requires creating an Xcode project that links against the Olas SPM package. Use the MCP Xcode tools:

```
mcp__xcode__scaffold_ios_project({
    projectName: "OlasApp",
    outputPath: "Olas/OlasApp",
    bundleIdentifier: "com.olas.app",
    deploymentTarget: "17.0"
})
```

**Step 2: Add Olas package dependency to project**

In Xcode, add local package dependency pointing to `Olas/Package.swift`.

**Step 3: Build and run on simulator**

```
mcp__xcode__build_run_sim({
    workspacePath: "Olas/OlasApp/OlasApp.xcworkspace",
    scheme: "OlasApp",
    simulatorName: "iPhone 16"
})
```

**Step 4: Verify feed loads**

Expected: App launches, connects to relays, displays image posts (kind 20) in feed.

**Step 5: Commit**

```bash
git add Olas/OlasApp/
git commit -m "feat(olas): add iOS app target for Milestone 1"
```

---

## Milestone 1 Verification

**Run all tests:**
```bash
cd Olas && swift test
```

**Manual verification:**
1. Launch app on simulator
2. Verify relays connect (check logs)
3. Verify image posts appear in feed
4. Verify author avatars and names load
5. Verify pull-to-refresh works
6. Verify double-tap like animation works

**Commit milestone:**
```bash
git tag -a milestone-1-feed -m "Milestone 1: Feed Display complete"
```

---

## Milestone 2: Authentication

**Deliverable:** Users can create new accounts or login with existing nsec. Keys stored securely in Keychain.

**Value:** Users have identity and can interact with content.

### Task 2.1: Create AuthViewModel with Tests

**Files:**
- Create: `Olas/Tests/OlasTests/ViewModels/AuthViewModelTests.swift`
- Create: `Olas/Sources/Olas/ViewModels/AuthViewModel.swift`

**Step 1: Write failing tests**

```swift
// AuthViewModelTests.swift
import XCTest
@testable import Olas
@testable import NDKSwift

final class AuthViewModelTests: XCTestCase {

    func testInitialStateIsLoggedOut() async {
        let viewModel = await AuthViewModel()

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoggedIn)
            XCTAssertNil(viewModel.currentUser)
        }
    }

    func testCreateAccountGeneratesKeys() async throws {
        let viewModel = await AuthViewModel()

        try await viewModel.createAccount(username: "testuser")

        await MainActor.run {
            XCTAssertTrue(viewModel.isLoggedIn)
            XCTAssertNotNil(viewModel.currentUser)
        }
    }

    func testLoginWithValidNsec() async throws {
        let viewModel = await AuthViewModel()

        // Generate a test keypair
        let keypair = try NDKPrivateKey.generate()
        let nsec = keypair.nsec

        try await viewModel.loginWithNsec(nsec)

        await MainActor.run {
            XCTAssertTrue(viewModel.isLoggedIn)
            XCTAssertEqual(viewModel.currentUser?.pubkey, keypair.publicKey.hex)
        }
    }

    func testLoginWithInvalidNsecThrows() async {
        let viewModel = await AuthViewModel()

        do {
            try await viewModel.loginWithNsec("invalid_nsec")
            XCTFail("Should have thrown an error")
        } catch {
            // Expected
        }
    }

    func testLogoutClearsState() async throws {
        let viewModel = await AuthViewModel()
        let keypair = try NDKPrivateKey.generate()

        try await viewModel.loginWithNsec(keypair.nsec)
        await viewModel.logout()

        await MainActor.run {
            XCTAssertFalse(viewModel.isLoggedIn)
            XCTAssertNil(viewModel.currentUser)
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd Olas && swift test --filter AuthViewModelTests`
Expected: FAIL - "Cannot find 'AuthViewModel' in scope"

**Step 3: Implement AuthViewModel**

```swift
// AuthViewModel.swift
import Foundation
import SwiftUI
import NDKSwift
import Security

@MainActor
public final class AuthViewModel: ObservableObject {
    @Published public private(set) var isLoggedIn = false
    @Published public private(set) var currentUser: NDKUser?
    @Published public private(set) var isLoading = false
    @Published public var error: Error?

    private var signer: NDKPrivateKeySigner?

    private let keychainService = "com.olas.keychain"
    private let keychainAccount = "user_nsec"

    public init() {
        // Try to restore session from keychain
        Task {
            await restoreSession()
        }
    }

    // MARK: - Public Methods

    public func createAccount(username: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let privateKey = try NDKPrivateKey.generate()
        try saveToKeychain(nsec: privateKey.nsec)

        signer = NDKPrivateKeySigner(privateKey: privateKey)
        currentUser = NDKUser(pubkey: privateKey.publicKey.hex)
        isLoggedIn = true
    }

    public func loginWithNsec(_ nsec: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard nsec.hasPrefix("nsec1") else {
            throw AuthError.invalidNsec
        }

        let privateKey = try NDKPrivateKey(nsec: nsec)
        try saveToKeychain(nsec: nsec)

        signer = NDKPrivateKeySigner(privateKey: privateKey)
        currentUser = NDKUser(pubkey: privateKey.publicKey.hex)
        isLoggedIn = true
    }

    public func logout() async {
        deleteFromKeychain()
        signer = nil
        currentUser = nil
        isLoggedIn = false
    }

    public func getSigner() -> NDKSigner? {
        return signer
    }

    // MARK: - Private Methods

    private func restoreSession() async {
        guard let nsec = loadFromKeychain() else { return }

        do {
            try await loginWithNsec(nsec)
        } catch {
            deleteFromKeychain()
        }
    }

    // MARK: - Keychain

    private func saveToKeychain(nsec: String) throws {
        let data = nsec.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let nsec = String(data: data, encoding: .utf8) else {
            return nil
        }

        return nsec
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum AuthError: LocalizedError {
    case invalidNsec
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidNsec:
            return "Invalid private key format. Must start with 'nsec1'"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
```

**Step 4: Run tests**

Run: `cd Olas && swift test --filter AuthViewModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): add AuthViewModel with keychain storage"
```

---

### Task 2.2: Create Onboarding Views

**Files:**
- Create: `Olas/Sources/Olas/Views/Auth/OnboardingView.swift`
- Create: `Olas/Sources/Olas/Views/Auth/LoginView.swift`
- Create: `Olas/Sources/Olas/Views/Auth/CreateAccountView.swift`

**Step 1: Create OnboardingView.swift**

```swift
// OnboardingView.swift
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var showLogin = false
    @State private var showCreateAccount = false

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Text("🌊")
                .font(.system(size: 80))

            Text("Olas")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(OlasTheme.Colors.deepTeal)

            Text("Share moments. Ride the wave.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    showCreateAccount = true
                } label: {
                    Text("Create Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }

                Button {
                    showLogin = true
                } label: {
                    Text("I have a Nostr account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showLogin) {
            LoginView(authViewModel: authViewModel)
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView(authViewModel: authViewModel)
        }
    }
}
```

**Step 2: Create LoginView.swift**

```swift
// LoginView.swift
import SwiftUI

public struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nsec = ""
    @State private var showError = false

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter your private key (nsec)")
                    .font(.headline)

                SecureField("nsec1...", text: $nsec)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                    Text("Your key stays on device and is never sent anywhere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        do {
                            try await authViewModel.loginWithNsec(nsec)
                            dismiss()
                        } catch {
                            showError = true
                        }
                    }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(OlasTheme.Colors.deepTeal)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(nsec.isEmpty || authViewModel.isLoading)

                Button("Paste from clipboard") {
                    if let clipboardContent = UIPasteboard.general.string {
                        nsec = clipboardContent
                    }
                }
                .font(.subheadline)
                .foregroundStyle(OlasTheme.Colors.oceanBlue)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Connect Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Login Failed", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(authViewModel.error?.localizedDescription ?? "Invalid private key")
            }
        }
    }
}
```

**Step 3: Create CreateAccountView.swift**

```swift
// CreateAccountView.swift
import SwiftUI

public struct CreateAccountView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var isAvailable = true

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose your username")
                    .font(.headline)

                HStack {
                    Text("@")
                        .foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                if !username.isEmpty {
                    HStack {
                        Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isAvailable ? .green : .red)
                        Text(isAvailable ? "Available" : "Username taken")
                            .font(.caption)
                    }
                }

                Button {
                    Task {
                        do {
                            try await authViewModel.createAccount(username: username)
                            dismiss()
                        } catch {
                            // Handle error
                        }
                    }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(username.isEmpty || authViewModel.isLoading)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

**Step 4: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Olas/Sources/Olas/Views/Auth/
git commit -m "feat(olas): add onboarding and authentication views"
```

---

### Task 2.3: Integrate Auth into App

**Files:**
- Modify: `Olas/Sources/Olas/OlasApp.swift`

**Step 1: Update OlasApp.swift**

```swift
// OlasApp.swift
import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var ndk: NDK?
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !isInitialized {
                    ProgressView("Connecting...")
                        .task {
                            await initializeNDK()
                        }
                } else if !authViewModel.isLoggedIn {
                    OnboardingView(authViewModel: authViewModel)
                } else if let ndk = ndk {
                    MainTabView(ndk: ndk)
                        .environmentObject(authViewModel)
                }
            }
            .onChange(of: authViewModel.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn, let signer = authViewModel.getSigner() {
                    ndk?.signer = signer
                } else {
                    ndk?.signer = nil
                }
            }
        }
    }

    private func initializeNDK() async {
        let relayUrls = OlasConstants.defaultRelays.compactMap { RelayURL($0) }
        let newNDK = NDK(relayUrls: relayUrls)

        // Set signer if logged in
        if let signer = authViewModel.getSigner() {
            newNDK.signer = signer
        }

        // Initialize NostrDB cache
        let cachePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("olas_cache")
            .path

        do {
            let cache = try NDKNostrDBCache(path: cachePath)
            newNDK.cache = cache
        } catch {
            print("Failed to initialize cache: \(error)")
        }

        await newNDK.connect()

        await MainActor.run {
            self.ndk = newNDK
            self.isInitialized = true
        }
    }
}
```

**Step 2: Run tests**

Run: `cd Olas && swift test`
Expected: All tests pass

**Step 3: Build and test on simulator**

```
mcp__xcode__build_run_sim({
    workspacePath: "Olas/OlasApp/OlasApp.xcworkspace",
    scheme: "OlasApp",
    simulatorName: "iPhone 16"
})
```

**Step 4: Verify flow**

1. App shows onboarding screen
2. "Create Account" generates keys and logs in
3. "I have a Nostr account" allows nsec entry
4. After login, feed is shown
5. App remembers login on restart

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): integrate authentication flow into app"
```

---

## Milestone 2 Verification

**Run all tests:**
```bash
cd Olas && swift test
```

**Manual verification:**
1. Fresh install shows onboarding
2. Create account works and persists
3. Login with valid nsec works
4. Login with invalid nsec shows error
5. App remembers session after restart
6. Logout clears session

**Commit milestone:**
```bash
git tag -a milestone-2-auth -m "Milestone 2: Authentication complete"
```

---

## Milestone 3: Posting

**Deliverable:** Users can create and publish image posts with captions, filters, and hashtags.

**Value:** Users can share their own content.

### Task 3.1: Create CreatePostViewModel with Tests

**Files:**
- Create: `Olas/Tests/OlasTests/ViewModels/CreatePostViewModelTests.swift`
- Create: `Olas/Sources/Olas/ViewModels/CreatePostViewModel.swift`

**Step 1: Write failing tests**

```swift
// CreatePostViewModelTests.swift
import XCTest
import UIKit
@testable import Olas
@testable import NDKSwift

final class CreatePostViewModelTests: XCTestCase {
    var ndk: NDK!

    override func setUp() async throws {
        ndk = NDK(relayUrls: [])
    }

    func testInitialStateIsEmpty() async {
        let viewModel = await CreatePostViewModel(ndk: ndk)

        await MainActor.run {
            XCTAssertNil(viewModel.selectedImage)
            XCTAssertTrue(viewModel.caption.isEmpty)
            XCTAssertTrue(viewModel.hashtags.isEmpty)
            XCTAssertFalse(viewModel.isPosting)
        }
    }

    func testExtractHashtagsFromCaption() async {
        let viewModel = await CreatePostViewModel(ndk: ndk)

        await MainActor.run {
            viewModel.caption = "Beautiful sunset #photography #ocean #nature"
            let extracted = viewModel.extractedHashtags

            XCTAssertEqual(extracted.count, 3)
            XCTAssertTrue(extracted.contains("photography"))
            XCTAssertTrue(extracted.contains("ocean"))
            XCTAssertTrue(extracted.contains("nature"))
        }
    }

    func testCannotPostWithoutImage() async {
        let viewModel = await CreatePostViewModel(ndk: ndk)

        await MainActor.run {
            XCTAssertFalse(viewModel.canPost)
        }
    }
}
```

**Step 2: Run tests**

Run: `cd Olas && swift test --filter CreatePostViewModelTests`
Expected: FAIL

**Step 3: Implement CreatePostViewModel**

```swift
// CreatePostViewModel.swift
import Foundation
import SwiftUI
import UIKit
import NDKSwift

@MainActor
public final class CreatePostViewModel: ObservableObject {
    @Published public var selectedImage: UIImage?
    @Published public var editedImage: UIImage?
    @Published public var caption = ""
    @Published public var hashtags: [String] = []
    @Published public var selectedFilter: ImageFilter = .original
    @Published public private(set) var isPosting = false
    @Published public var error: Error?
    @Published public var postSuccess = false

    private let ndk: NDK

    public var canPost: Bool {
        selectedImage != nil || editedImage != nil
    }

    public var extractedHashtags: [String] {
        let pattern = #"#(\w+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: caption, range: NSRange(caption.startIndex..., in: caption)) ?? []

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: caption) else { return nil }
            return String(caption[range]).lowercased()
        }
    }

    public var finalImage: UIImage? {
        editedImage ?? selectedImage
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public func applyFilter(_ filter: ImageFilter) {
        guard let image = selectedImage else { return }
        selectedFilter = filter
        editedImage = filter.apply(to: image)
    }

    public func post() async throws {
        guard let image = finalImage else {
            throw PostError.noImage
        }

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw PostError.compressionFailed
        }

        isPosting = true
        defer { isPosting = false }

        do {
            // Upload to Blossom and create image event
            let event = try await NDKEvent.createImageEvent(
                imageData: imageData,
                mimeType: "image/jpeg",
                caption: buildCaption(),
                ndk: ndk
            )

            // Add hashtag tags
            var eventBuilder = NDKEventBuilder(ndk: ndk)
                .content(event.content)
                .kind(EventKind.image)
                .tags(event.tags)

            for hashtag in extractedHashtags {
                eventBuilder = eventBuilder.tagHashtag(hashtag)
            }

            let finalEvent = try await eventBuilder.build()

            // Publish
            let publishedRelays = try await ndk.publish(finalEvent)

            if publishedRelays.isEmpty {
                throw PostError.publishFailed
            }

            postSuccess = true
            reset()

        } catch {
            self.error = error
            throw error
        }
    }

    public func reset() {
        selectedImage = nil
        editedImage = nil
        caption = ""
        hashtags = []
        selectedFilter = .original
        error = nil
    }

    private func buildCaption() -> String {
        var fullCaption = caption

        // Add hashtags not already in caption
        for tag in hashtags where !caption.contains("#\(tag)") {
            fullCaption += " #\(tag)"
        }

        return fullCaption.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Errors

public enum PostError: LocalizedError {
    case noImage
    case compressionFailed
    case uploadFailed
    case publishFailed

    public var errorDescription: String? {
        switch self {
        case .noImage: return "No image selected"
        case .compressionFailed: return "Failed to compress image"
        case .uploadFailed: return "Failed to upload image"
        case .publishFailed: return "Failed to publish to relays"
        }
    }
}
```

**Step 4: Run tests**

Run: `cd Olas && swift test --filter CreatePostViewModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): add CreatePostViewModel with Blossom upload"
```

---

### Task 3.2: Create Image Filters

**Files:**
- Create: `Olas/Sources/Olas/Utils/ImageFilters.swift`

**Step 1: Create ImageFilters.swift**

```swift
// ImageFilters.swift
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

public enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case ola = "Ola"
    case marea = "Marea"
    case coral = "Coral"
    case reef = "Reef"
    case tide = "Tide"
    case sunset = "Sunset"

    public var id: String { rawValue }

    public func apply(to image: UIImage) -> UIImage {
        guard self != .original else { return image }

        guard let ciImage = CIImage(image: image) else { return image }

        let filter: CIFilter?

        switch self {
        case .original:
            return image

        case .ola:
            // Cool blue tones
            filter = CIFilter.colorControls()
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(1.1, forKey: kCIInputSaturationKey)
            filter?.setValue(0.05, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.1, forKey: kCIInputContrastKey)

        case .marea:
            // High contrast with slight warmth
            filter = CIFilter.colorControls()
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(1.2, forKey: kCIInputSaturationKey)
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.2, forKey: kCIInputContrastKey)

        case .coral:
            // Warm, vibrant
            let colorFilter = CIFilter.temperatureAndTint()
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            colorFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            colorFilter.setValue(CIVector(x: 7000, y: 100), forKey: "inputTargetNeutral")
            filter = colorFilter

        case .reef:
            // Teal/aqua shift
            let colorFilter = CIFilter.temperatureAndTint()
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            colorFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            colorFilter.setValue(CIVector(x: 5500, y: -50), forKey: "inputTargetNeutral")
            filter = colorFilter

        case .tide:
            // Faded, film-like
            filter = CIFilter.photoEffectFade()
            filter?.setValue(ciImage, forKey: kCIInputImageKey)

        case .sunset:
            // Golden hour warmth
            let colorFilter = CIFilter.temperatureAndTint()
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            colorFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            colorFilter.setValue(CIVector(x: 8000, y: 50), forKey: "inputTargetNeutral")
            filter = colorFilter
        }

        guard let outputImage = filter?.outputImage else { return image }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    public func preview(for image: UIImage, size: CGSize = CGSize(width: 70, height: 70)) -> UIImage {
        let resized = image.preparingThumbnail(of: size) ?? image
        return apply(to: resized)
    }
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Utils/ImageFilters.swift
git commit -m "feat(olas): add ocean-themed CoreImage filters"
```

---

### Task 3.3: Create Photo Selection View

**Files:**
- Create: `Olas/Sources/Olas/Views/Create/PhotoSelectionView.swift`

**Step 1: Create PhotoSelectionView.swift**

```swift
// PhotoSelectionView.swift
import SwiftUI
import PhotosUI

public struct PhotoSelectionView: View {
    @ObservedObject var viewModel: CreatePostViewModel
    @Binding var currentStep: CreateStep

    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false

    public init(viewModel: CreatePostViewModel, currentStep: Binding<CreateStep>) {
        self.viewModel = viewModel
        self._currentStep = currentStep
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Preview area
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            Text("Select a photo")
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            // Source toggle
            HStack(spacing: 0) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Gallery", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding()

            // Recent photos grid
            ScrollView {
                RecentPhotosGrid(selectedItem: $selectedItem)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.selectedImage = image
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: $viewModel.selectedImage)
        }
    }
}

// MARK: - Recent Photos Grid

struct RecentPhotosGrid: View {
    @Binding var selectedItem: PhotosPickerItem?
    @State private var recentPhotos: [PhotosPickerItem] = []

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
        .padding(2)
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Create Step

public enum CreateStep {
    case select
    case edit
    case share
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Views/Create/
git commit -m "feat(olas): add photo selection with camera and gallery"
```

---

### Task 3.4: Create Edit View

**Files:**
- Create: `Olas/Sources/Olas/Views/Create/EditView.swift`

**Step 1: Create EditView.swift**

```swift
// EditView.swift
import SwiftUI

public struct EditView: View {
    @ObservedObject var viewModel: CreatePostViewModel
    @Binding var currentStep: CreateStep

    @State private var selectedTool: EditTool = .filters

    public init(viewModel: CreatePostViewModel, currentStep: Binding<CreateStep>) {
        self.viewModel = viewModel
        self._currentStep = currentStep
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Preview
            if let image = viewModel.finalImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
            }

            // Tool selector
            HStack {
                ForEach(EditTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.title3)
                            Text(tool.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(selectedTool == tool ? OlasTheme.Colors.deepTeal : .secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))

            // Tool content
            switch selectedTool {
            case .filters:
                filtersView
            case .adjust:
                Text("Adjustments coming soon")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .crop:
                Text("Crop coming soon")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text:
                Text("Text overlay coming soon")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var filtersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(ImageFilter.allCases) { filter in
                    FilterButton(
                        filter: filter,
                        image: viewModel.selectedImage,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        viewModel.applyFilter(filter)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Edit Tool

enum EditTool: String, CaseIterable, Identifiable {
    case filters = "Filters"
    case adjust = "Adjust"
    case crop = "Crop"
    case text = "Text"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .filters: return "circle.lefthalf.filled"
        case .adjust: return "slider.horizontal.3"
        case .crop: return "crop"
        case .text: return "textformat"
        }
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let filter: ImageFilter
    let image: UIImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if let image = image {
                    Image(uiImage: filter.preview(for: image))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? OlasTheme.Colors.deepTeal : .clear, lineWidth: 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray)
                        .frame(width: 70, height: 70)
                }

                Text(filter.rawValue)
                    .font(.caption)
                    .foregroundStyle(isSelected ? OlasTheme.Colors.deepTeal : .secondary)
            }
        }
    }
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Views/Create/EditView.swift
git commit -m "feat(olas): add edit view with filter selection"
```

---

### Task 3.5: Create Share View

**Files:**
- Create: `Olas/Sources/Olas/Views/Create/ShareView.swift`

**Step 1: Create ShareView.swift**

```swift
// ShareView.swift
import SwiftUI

public struct ShareView: View {
    @ObservedObject var viewModel: CreatePostViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCollectionPicker = false

    private let suggestedHashtags = ["photography", "nature", "ocean", "travel", "art", "sunset"]

    public init(viewModel: CreatePostViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Preview + Caption
                HStack(alignment: .top, spacing: 16) {
                    if let image = viewModel.finalImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                    }

                    TextField("Write a caption...", text: $viewModel.caption, axis: .vertical)
                        .lineLimit(3...6)
                }

                Divider()

                // Hashtag suggestions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add hashtags")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(suggestedHashtags, id: \.self) { tag in
                            HashtagPill(tag: tag, isSelected: viewModel.hashtags.contains(tag)) {
                                if viewModel.hashtags.contains(tag) {
                                    viewModel.hashtags.removeAll { $0 == tag }
                                } else {
                                    viewModel.hashtags.append(tag)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Add to collection
                Button {
                    showCollectionPicker = true
                } label: {
                    HStack {
                        Text("Add to collection")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .padding()
        }
        .sheet(isPresented: $showCollectionPicker) {
            Text("Collection picker coming soon")
        }
    }
}

// MARK: - Hashtag Pill

struct HashtagPill: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? OlasTheme.Colors.deepTeal : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : OlasTheme.Colors.deepTeal)
                .cornerRadius(20)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing

                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}
```

**Step 2: Verify build**

Run: `cd Olas && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Olas/Sources/Olas/Views/Create/ShareView.swift
git commit -m "feat(olas): add share view with hashtags"
```

---

### Task 3.6: Create Full Create Flow

**Files:**
- Create: `Olas/Sources/Olas/Views/Create/CreatePostView.swift`
- Modify: `Olas/Sources/Olas/Views/MainTabView.swift`

**Step 1: Create CreatePostView.swift**

```swift
// CreatePostView.swift
import SwiftUI

public struct CreatePostView: View {
    @StateObject private var viewModel: CreatePostViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: CreateStep = .select

    private let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        _viewModel = StateObject(wrappedValue: CreatePostViewModel(ndk: ndk))
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .select:
                    PhotoSelectionView(viewModel: viewModel, currentStep: $currentStep)
                case .edit:
                    EditView(viewModel: viewModel, currentStep: $currentStep)
                case .share:
                    ShareView(viewModel: viewModel)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelButtonTitle) {
                        if currentStep == .select {
                            dismiss()
                        } else {
                            withAnimation {
                                currentStep = previousStep
                            }
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == .share {
                        Button {
                            Task {
                                try? await viewModel.post()
                                if viewModel.postSuccess {
                                    dismiss()
                                }
                            }
                        } label: {
                            if viewModel.isPosting {
                                ProgressView()
                            } else {
                                Text("Post")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(!viewModel.canPost || viewModel.isPosting)
                    } else {
                        Button("Next") {
                            withAnimation {
                                currentStep = nextStep
                            }
                        }
                        .disabled(viewModel.selectedImage == nil)
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "Unknown error")
            }
        }
    }

    private var navigationTitle: String {
        switch currentStep {
        case .select: return "New Post"
        case .edit: return "Edit"
        case .share: return "Share"
        }
    }

    private var cancelButtonTitle: String {
        currentStep == .select ? "Cancel" : "Back"
    }

    private var previousStep: CreateStep {
        switch currentStep {
        case .select: return .select
        case .edit: return .select
        case .share: return .edit
        }
    }

    private var nextStep: CreateStep {
        switch currentStep {
        case .select: return .edit
        case .edit: return .share
        case .share: return .share
        }
    }
}
```

**Step 2: Update MainTabView to show create**

```swift
// In MainTabView.swift, update the Create tab:

// Create - opens as sheet
Color.clear
    .tabItem {
        Label("", systemImage: "plus.app.fill")
    }
    .tag(2)

// Add state and sheet:
@State private var showCreatePost = false

// Add to TabView:
.onChange(of: selectedTab) { oldValue, newValue in
    if newValue == 2 {
        showCreatePost = true
        selectedTab = oldValue  // Don't actually switch to this tab
    }
}
.sheet(isPresented: $showCreatePost) {
    CreatePostView(ndk: ndk)
}
```

**Step 3: Run tests**

Run: `cd Olas && swift test`
Expected: All tests pass

**Step 4: Build and test on simulator**

```
mcp__xcode__build_run_sim({
    workspacePath: "Olas/OlasApp/OlasApp.xcworkspace",
    scheme: "OlasApp",
    simulatorName: "iPhone 16"
})
```

**Step 5: Commit**

```bash
git add Olas/
git commit -m "feat(olas): complete create post flow with Blossom upload"
```

---

## Milestone 3 Verification

**Run all tests:**
```bash
cd Olas && swift test
```

**Manual verification:**
1. Tap + tab opens create flow
2. Can select photo from gallery
3. Can take photo with camera
4. Filters apply to preview
5. Can add caption and hashtags
6. Post button uploads to Blossom
7. Post appears in feed after publishing
8. Error handling works for failures

**Commit milestone:**
```bash
git tag -a milestone-3-posting -m "Milestone 3: Posting complete"
```

---

## Milestone 4: Interactions (Reactions, Comments, Zaps)

**Deliverable:** Users can react to posts with emojis, leave comments, and send zaps.

**Value:** Social engagement on content.

### Task 4.1 - 4.6: See expanded plan file...

---

## Milestone 5: Explore & Discovery

**Deliverable:** Explore tab with category-based content discovery and search.

**Value:** Users can discover new content and accounts.

---

## Milestone 6: Profile & Collections

**Deliverable:** Profile screen with user posts, bio, and curated collections.

**Value:** Users can showcase their content.

---

## Milestone 7: Polish & Final Features

**Deliverable:** Notifications, settings, performance optimizations.

**Value:** Production-ready app.

---

## Running the Full Test Suite

```bash
cd Olas && swift test
```

Expected: All tests pass before each milestone is considered complete.

---

## Summary

| Milestone | Deliverable | Key Tests |
|-----------|-------------|-----------|
| 1 | Feed Display | FeedViewModelTests, PostCardTests |
| 2 | Authentication | AuthViewModelTests |
| 3 | Posting | CreatePostViewModelTests |
| 4 | Interactions | ReactionTests, CommentTests, ZapTests |
| 5 | Explore | ExploreViewModelTests, SearchTests |
| 6 | Profile | ProfileViewModelTests, CollectionTests |
| 7 | Polish | Integration tests, E2E tests |
