import SwiftUI
import SwiftData
import NDKSwift

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    
    @State private var userProfile: NDKUserProfile?
    @State private var currentUser: NDKUser?
    @State private var showPaymentAnimation = false
    @State private var debugAnimationAmount: Int64 = 21000
    @State private var profileTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    if let currentUser = currentUser {
                        NavigationLink(destination: AccountDetailView(user: currentUser, profile: userProfile)) {
                            HStack {
                                // Profile picture placeholder
                                Circle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .overlay(
                                        Text((userProfile?.displayName ?? userProfile?.name ?? "User").prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    )
                                    .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(userProfile?.displayName ?? userProfile?.name ?? "Nostr User")
                                        .font(.headline)
                                    
                                    Text(String(currentUser.npub.prefix(16)) + "...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        Text("No user logged in")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                }
                
                // Preferences
                Section {
                    Picker("Currency", selection: $appState.preferredConversionUnit) {
                        ForEach(CurrencyUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    
                    NavigationLink(destination: RelayManagementView()) {
                        Label("Relays", systemImage: "network")
                    }
                    
                    NavigationLink(destination: BackupView()) {
                        Label("Backup", systemImage: "lock.shield")
                    }
                    
                    NavigationLink(destination: UnpublishedEventsView()) {
                        HStack {
                            Label("Unpublished Events", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            UnpublishedEventsBadge()
                        }
                    }
                } header: {
                    Text("Preferences")
                }
                
                // Nutzap Settings
                Section {
                    NavigationLink(destination: NutzapSettingsView()) {
                        Label("Nutzap Settings", systemImage: "bolt.heart")
                    }
                    
                    NavigationLink(destination: WalletEventsView()) {
                        Label("Wallet Events", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Wallet")
                } footer: {
                    Text("Configure how others can send nutzaps to your wallet")
                }
                
                
                // App Info
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    
                    Link(destination: URL(string: "https://github.com/yourusername/nutsack")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        Label("About", systemImage: "info.circle")
                    }
                } header: {
                    Text("App")
                }
                
                // Debug section
                #if DEBUG
                Section {
                    Button(action: { showPaymentAnimation = true }) {
                        Label("Trigger Deposit Animation", systemImage: "sparkles")
                    }
                    
                    Stepper("Animation Amount: \(debugAnimationAmount) sats", 
                           value: $debugAnimationAmount, 
                           in: 100...1000000, 
                           step: 1000)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Test the payment animation without making a real deposit")
                }
                #endif
                
                // Danger zone
                Section {
                    Button(role: .destructive, action: logout) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                loadUserProfile()
            }
            .fullScreenCover(isPresented: $showPaymentAnimation) {
                PaymentReceivedAnimation(amount: debugAnimationAmount) {
                    showPaymentAnimation = false
                }
            }
            .onDisappear {
                profileTask?.cancel()
            }
        }
    }
    
    private func loadUserProfile() {
        Task {
            guard let user = await nostrManager.currentUser,
                  let ndk = nostrManager.ndk else {
                await MainActor.run {
                    currentUser = nil
                    userProfile = nil
                }
                return
            }
            
            await MainActor.run {
                currentUser = user
            }
            
            // Cancel previous profile observation
            profileTask?.cancel()
            
            // Observe profile updates
            profileTask = Task {
                let profileStream = await ndk.observeProfile(for: user.pubkey, closeOnEose: true)
                
                for await profile in profileStream {
                    await MainActor.run {
                        self.userProfile = profile
                    }
                    // For settings, we can close after first profile
                    if profile != nil {
                        break
                    }
                }
            }
        }
    }
    
    private func logout() {
        // Clear wallet data and cancel subscriptions
        walletManager.clearWalletData()
        
        // Clear authentication data
        nostrManager.logout()
        
        // Clear local state
        currentUser = nil
        userProfile = nil
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let user: NDKUser
    let profile: NDKUserProfile?
    @Environment(NostrManager.self) private var nostrManager
    @State private var showPrivateKey = false
    @State private var copiedKey = false
    @State private var nsecKey: String?
    
    var npub: String {
        user.npub
    }
    
    var body: some View {
        List {
            Section {
                LabeledContent("Display Name", value: profile?.displayName ?? profile?.name ?? "Nostr User")
                
                if let about = profile?.about {
                    LabeledContent("About") {
                        Text(about)
                            .font(.caption)
                    }
                }
                
                if let nip05 = profile?.nip05 {
                    LabeledContent("NIP-05", value: nip05)
                }
            } header: {
                Text("Profile")
            }
            
            Section {
                LabeledContent("Public Key (npub)") {
                    Text(npub)
                        .font(.caption)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                
                if let nsecKey = nsecKey {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key (nsec)")
                            Spacer()
                            Button(action: togglePrivateKey) {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if showPrivateKey {
                            Text(nsecKey)
                                .font(.caption)
                                .textSelection(.enabled)
                            
                            Button(action: copyPrivateKey) {
                                Label(
                                    copiedKey ? "Copied!" : "Copy Private Key",
                                    systemImage: copiedKey ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(copiedKey ? .green : .orange)
                        }
                    }
                } else {
                    Text("Private key access through secure authentication")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("Keep your private key secure. Anyone with this key can access your account.")
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadPrivateKey()
        }
    }
    
    private func loadPrivateKey() {
        guard let signer = nostrManager.authManager.activeSigner as? NDKPrivateKeySigner else {
            nsecKey = nil
            return
        }
        
        Task {
            do {
                let nsec = try signer.nsec
                await MainActor.run {
                    nsecKey = nsec
                }
            } catch {
                print("Failed to load private key: \(error)")
                await MainActor.run {
                    nsecKey = nil
                }
            }
        }
    }
    
    private func togglePrivateKey() {
        withAnimation {
            showPrivateKey.toggle()
        }
    }
    
    private func copyPrivateKey() {
        guard let nsec = nsecKey else { return }
        #if os(iOS)
        UIPasteboard.general.string = nsec
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(nsec, forType: .string)
        #endif
        withAnimation {
            copiedKey = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedKey = false
            }
        }
    }
}


// MARK: - Backup View
struct BackupView: View {
    var body: some View {
        List {
            Section {
                Text("Backup features coming soon")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Wallet Backup")
            } footer: {
                Text("Your wallets are automatically backed up to Nostr using NIP-60")
            }
        }
        .navigationTitle("Backup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Logo
                Image(systemName: "banknote.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange.gradient)
                    .padding(.top, 40)
                
                Text("Nutsack")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Lightning-fast payments with Nostr")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // Description
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.headline)
                    
                    Text("""
                    Nutsack is a Cashu ecash wallet that integrates seamlessly with Nostr. It implements NIP-60 for wallet backup and NIP-61 for nutzaps.
                    
                    Built with NDKSwift, this wallet showcases the power of combining ecash with the Nostr protocol for a truly decentralized payment experience.
                    """)
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Unpublished Events Badge
struct UnpublishedEventsBadge: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var unpublishedCount = 0
    @State private var timer: Timer?
    
    var body: some View {
        Group {
            if unpublishedCount > 0 {
                Text("\(unpublishedCount)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
        .onAppear {
            updateUnpublishedCount()
            startPeriodicUpdate()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func updateUnpublishedCount() {
        Task {
            guard let cache = nostrManager.cache else { return }
            let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
            await MainActor.run {
                unpublishedCount = unpublishedEvents.count
            }
        }
    }
    
    private func startPeriodicUpdate() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            updateUnpublishedCount()
        }
    }
}

// MARK: - Unpublished Events View
struct UnpublishedEventsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var unpublishedEvents: [(event: NDKEvent, targetRelays: Set<String>)] = []
    @State private var isLoading = true
    @State private var isRetrying = false
    @State private var lastRetryTime: Date?
    @State private var showRetrySuccess = false
    @State private var retriedCount = 0
    
    var body: some View {
        NavigationView {
            List {
                // Status Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unpublished Events")
                                .font(.headline)
                            if isLoading {
                                Text("Checking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(unpublishedEvents.count) events pending")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if unpublishedEvents.count > 0 {
                            Button(action: retryAllEvents) {
                                if isRetrying {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Retry All")
                                        .foregroundColor(.orange)
                                }
                            }
                            .disabled(isRetrying)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if let lastRetryTime = lastRetryTime {
                        Text("Last retry: \(lastRetryTime, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }
                
                // Events List
                if !unpublishedEvents.isEmpty {
                    Section {
                        ForEach(Array(unpublishedEvents.enumerated()), id: \.offset) { index, eventInfo in
                            UnpublishedEventRow(
                                event: eventInfo.event,
                                targetRelays: eventInfo.targetRelays,
                                onRetry: {
                                    retryEvent(at: index)
                                }
                            )
                        }
                    } header: {
                        Text("Pending Events")
                    } footer: {
                        Text("These events were published optimistically but haven't been confirmed by relays yet. You can retry individual events or all at once.")
                    }
                } else if !isLoading {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            
                            Text("All events published successfully!")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            
                            Text("Your events have been confirmed by the relays.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Unpublished Events")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .refreshable {
                await loadUnpublishedEvents()
            }
            .onAppear {
                Task {
                    await loadUnpublishedEvents()
                }
            }
            .alert("Retry Successful", isPresented: $showRetrySuccess) {
                Button("OK") { }
            } message: {
                Text("Successfully retried \(retriedCount) events")
            }
        }
    }
    
    private func loadUnpublishedEvents() async {
        guard let cache = nostrManager.cache else { 
            await MainActor.run {
                isLoading = false
            }
            return 
        }
        
        let events = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        await MainActor.run {
            unpublishedEvents = events
            isLoading = false
        }
    }
    
    private func retryAllEvents() {
        guard let ndk = nostrManager.ndk else { return }
        
        isRetrying = true
        
        Task {
            do {
                let retriedEvents = try await ndk.retryUnpublishedEvents(maxAge: 3600, limit: nil)
                await MainActor.run {
                    isRetrying = false
                    lastRetryTime = Date()
                    retriedCount = retriedEvents.count
                    showRetrySuccess = true
                }
                
                // Reload the list
                await loadUnpublishedEvents()
            } catch {
                await MainActor.run {
                    isRetrying = false
                }
                print("Failed to retry events: \(error)")
            }
        }
    }
    
    private func retryEvent(at index: Int) {
        guard let ndk = nostrManager.ndk, index < unpublishedEvents.count else { return }
        
        let eventInfo = unpublishedEvents[index]
        
        Task {
            do {
                _ = try await ndk.publish(eventInfo.event)
                
                // Reload the list
                await loadUnpublishedEvents()
            } catch {
                print("Failed to retry individual event: \(error)")
            }
        }
    }
}

// MARK: - Unpublished Event Row
struct UnpublishedEventRow: View {
    let event: NDKEvent
    let targetRelays: Set<String>
    let onRetry: () -> Void
    
    @State private var isRetrying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event content preview
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eventKindName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !event.content.isEmpty {
                        Text(event.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                
                Spacer()
                
                Button(action: retryEvent) {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.orange)
                    }
                }
                .disabled(isRetrying)
                .buttonStyle(.plain)
            }
            
            // Metadata
            HStack {
                Text("Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)), style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Text("\(targetRelays.count) relays")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // Target relays (abbreviated)
            if !targetRelays.isEmpty {
                Text("Targets: \(abbreviatedRelayList)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var eventKindName: String {
        switch event.kind {
        case 0: return "Profile"
        case 1: return "Note"
        case 3: return "Contacts"
        case 4: return "Direct Message"
        case 5: return "Deletion"
        case 6: return "Repost"
        case 7: return "Reaction"
        case 17375: return "NIP-60 Wallet"
        default: return "Event \(event.kind)"
        }
    }
    
    private var abbreviatedRelayList: String {
        let sorted = targetRelays.sorted()
        if sorted.count <= 2 {
            return sorted.map { shortRelayName($0) }.joined(separator: ", ")
        } else {
            let first = sorted.prefix(2).map { shortRelayName($0) }
            return first.joined(separator: ", ") + " +\(sorted.count - 2)"
        }
    }
    
    private func shortRelayName(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        // Remove common prefixes and show just the domain
        return host.replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "relay.", with: "")
    }
    
    private func retryEvent() {
        isRetrying = true
        onRetry()
        
        // Reset retry state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRetrying = false
        }
    }
}