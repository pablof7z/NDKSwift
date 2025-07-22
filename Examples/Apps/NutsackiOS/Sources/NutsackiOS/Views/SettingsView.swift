import SwiftUI
import SwiftData
import NDKSwift

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    
    @State private var currentUser: NDKUser?
    @State private var copiedNpub = false
    
    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    if let currentUser = currentUser {
                        NavigationLink(destination: AccountDetailView(user: currentUser, profile: nostrManager.currentUserProfile)) {
                            HStack {
                                // Profile picture placeholder
                                Circle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .overlay(
                                        Text((nostrManager.currentUserProfile?.displayName ?? nostrManager.currentUserProfile?.name ?? "User").prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    )
                                    .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(nostrManager.currentUserProfile?.displayName ?? nostrManager.currentUserProfile?.name ?? "Nostr User")
                                        .font(.headline)
                                    
                                    HStack(spacing: 4) {
                                        Text(String(currentUser.npub.prefix(16)) + "...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Button(action: { copyNpub(currentUser.npub) }) {
                                            Image(systemName: copiedNpub ? "checkmark.circle.fill" : "doc.on.doc")
                                                .font(.caption)
                                                .foregroundColor(copiedNpub ? .green : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
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
                    Picker("Theme", selection: $appState.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    
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
                
                // Blacklisted Mints Section
                Section {
                    NavigationLink(destination: BlacklistedMintsView()) {
                        HStack {
                            Label("Blacklisted Mints", systemImage: "xmark.shield")
                            Spacer()
                            if !appState.blacklistedMints.isEmpty {
                                Text("\(appState.blacklistedMints.count)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Manage mints that are blocked from being used in your wallet")
                }
                
                // Nutzap Settings
                Section {
                    NavigationLink(destination: NutzapSettingsView()) {
                        Label("Nutzap Settings", systemImage: "bolt.heart")
                    }
                    
                    NavigationLink(destination: WalletEventsView()) {
                        Label("Wallet Events", systemImage: "list.bullet.rectangle")
                    }
                    
                    NavigationLink(destination: WalletHealthView()) {
                        Label("Wallet Health", systemImage: "heart.text.square")
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
                    NavigationLink(destination: DebugView()) {
                        Label("Debug", systemImage: "ladybug")
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Debug tools and cache statistics")
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
            .task {
                currentUser = await nostrManager.currentUser
            }
        }
    }
    
    private func copyNpub(_ npub: String) {
        #if os(iOS)
        UIPasteboard.general.string = npub
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(npub, forType: .string)
        #endif
        withAnimation {
            copiedNpub = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNpub = false
            }
        }
    }
    
    private func logout() {
        // Clear wallet data and cancel subscriptions
        walletManager.clearWalletData()
        
        // Clear authentication data
        nostrManager.logout()
        
    }
}

// MARK: - Wallet Health View
struct WalletHealthView: View {
    @Environment(WalletManager.self) private var walletManager
    @State private var isCheckingHealth = false
    @State private var healthStatus: WalletHealthMonitor.WalletHealthStatus?
    @State private var isReconciling = false
    @State private var reconciliationResult: ProofReconciliationResult?
    @State private var lastCheckTime: Date?
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            // Health Status Section
            Section {
                if let status = healthStatus {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(status.isHealthy ? .green : .orange)
                            
                            Text(status.isHealthy ? "Wallet is healthy" : "Wallet needs attention")
                                .font(.headline)
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Total Events:")
                                    .foregroundStyle(.secondary)
                                Text("\(status.totalEvents)")
                                    .fontWeight(.medium)
                            }
                            
                            GridRow {
                                Text("Synced Relays:")
                                    .foregroundStyle(.secondary)
                                Text("\(status.syncedRelays)")
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                            
                            GridRow {
                                Text("Out of Sync:")
                                    .foregroundStyle(.secondary)
                                Text("\(status.outOfSyncRelays)")
                                    .fontWeight(.medium)
                                    .foregroundColor(status.outOfSyncRelays > 0 ? .orange : .secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("Tap 'Check Health' to scan your wallet")
                        .foregroundStyle(.secondary)
                }
                
                Button(action: checkWalletHealth) {
                    HStack {
                        if isCheckingHealth {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Check Health")
                    }
                }
                .disabled(isCheckingHealth)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                if let lastCheck = lastCheckTime {
                    Text("Last checked: \(lastCheck, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Wallet Health")
            } footer: {
                Text("Checks if your wallet events are properly synced across all relays")
            }
            
            // Proof Validation Section
            Section {
                if let result = reconciliationResult {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: result.spentProofs.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(result.spentProofs.isEmpty ? .green : .orange)
                            
                            Text(result.spentProofs.isEmpty ? "All proofs valid" : "Found spent proofs")
                                .font(.headline)
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Total Checked:")
                                    .foregroundStyle(.secondary)
                                Text("\(result.totalChecked)")
                                    .fontWeight(.medium)
                            }
                            
                            GridRow {
                                Text("Spent Proofs:")
                                    .foregroundStyle(.secondary)
                                Text("\(result.spentProofs.count)")
                                    .fontWeight(.medium)
                                    .foregroundColor(result.spentProofs.count > 0 ? .orange : .green)
                            }
                            
                            GridRow {
                                Text("Pending Proofs:")
                                    .foregroundStyle(.secondary)
                                Text("\(result.pendingProofs.count)")
                                    .fontWeight(.medium)
                                    .foregroundColor(result.pendingProofs.count > 0 ? .yellow : .secondary)
                            }
                            
                            if result.errors > 0 {
                                GridRow {
                                    Text("Errors:")
                                        .foregroundStyle(.secondary)
                                    Text("\(result.errors)")
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                } else {
                    Text("Tap 'Validate Proofs' to check with mints")
                        .foregroundStyle(.secondary)
                }
                
                Button(action: validateProofs) {
                    HStack {
                        if isReconciling {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Validate Proofs")
                    }
                }
                .disabled(isReconciling)
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } header: {
                Text("Proof Validation")
            } footer: {
                Text("Validates your ecash proofs with their respective mints to ensure they haven't been spent")
            }
            
            // Relay Health Details
            if let status = healthStatus, !status.relayHealth.isEmpty {
                Section {
                    ForEach(status.relayHealth.indices, id: \.self) { index in
                        let relay = status.relayHealth[index]
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(relay.relay.url)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                Text("\(relay.knownEvents) events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Image(systemName: relay.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(relay.isHealthy ? .green : .orange)
                                
                                if !relay.isHealthy {
                                    Text("Issues")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Relay Status")
                } footer: {
                    Text("Individual relay synchronization status")
                }
            }
            
            // Error Display
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                } header: {
                    Text("Error")
                }
            }
        }
        .navigationTitle("Wallet Health")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await performHealthCheck()
        }
    }
    
    private func checkWalletHealth() {
        Task {
            await performHealthCheck()
        }
    }
    
    private func performHealthCheck() async {
        await MainActor.run {
            isCheckingHealth = true
            errorMessage = nil
        }
        
        do {
            guard let wallet = walletManager.wallet else {
                await MainActor.run {
                    errorMessage = "No wallet available"
                    isCheckingHealth = false
                }
                return
            }
            
            let status = try await wallet.checkWalletHealth()
            
            await MainActor.run {
                healthStatus = status
                lastCheckTime = Date()
                isCheckingHealth = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Health check failed: \(error.localizedDescription)"
                isCheckingHealth = false
            }
        }
    }
    
    private func validateProofs() {
        Task {
            await MainActor.run {
                isReconciling = true
                errorMessage = nil
            }
            
            do {
                guard let wallet = walletManager.wallet else {
                    await MainActor.run {
                        errorMessage = "No wallet available"
                        isReconciling = false
                    }
                    return
                }
                
                let result = try await wallet.validateProofs()
                
                await MainActor.run {
                    reconciliationResult = result
                    isReconciling = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Proof validation failed: \(error.localizedDescription)"
                    isReconciling = false
                }
            }
        }
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let user: NDKUser
    let profile: NDKUserProfile?
    @Environment(NostrManager.self) private var nostrManager
    @State private var showPrivateKey = false
    @State private var copiedKey = false
    @State private var copiedNpub = false
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Public Key (npub)")
                        Spacer()
                    }
                    
                    Text(npub)
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    Button(action: copyPublicKey) {
                        Label(
                            copiedNpub ? "Copied!" : "Copy npub",
                            systemImage: copiedNpub ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(copiedNpub ? .green : .blue)
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
    
    private func copyPublicKey() {
        #if os(iOS)
        UIPasteboard.general.string = npub
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(npub, forType: .string)
        #endif
        withAnimation {
            copiedNpub = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNpub = false
            }
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

// MARK: - Debug View
#if DEBUG
struct DebugView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var cacheStats: CacheStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdateTime: Date?
    
    var body: some View {
        NavigationStack {
            List {
                // Cache Statistics Section
                Section {
                    NavigationLink(destination: CacheStatsView()) {
                        HStack {
                            Label("Cache Statistics", systemImage: "cylinder.split.1x2")
                            Spacer()
                            if let stats = cacheStats {
                                Text("\(stats.totalEvents) events")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Database")
                } footer: {
                    if let lastUpdate = lastUpdateTime {
                        Text("Last updated: \(lastUpdate, style: .relative)")
                    } else {
                        Text("View detailed cache statistics and event counts")
                    }
                }
                
                // Quick Stats Overview
                if let stats = cacheStats {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cylinder.fill")
                                    .foregroundColor(.blue)
                                Text("Cache Overview")
                                    .font(.headline)
                            }
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                GridRow {
                                    Text("Total Events:")
                                        .foregroundStyle(.secondary)
                                    Text("\(stats.totalEvents)")
                                        .fontWeight(.medium)
                                }
                                
                                GridRow {
                                    Text("Event Types:")
                                        .foregroundStyle(.secondary)
                                    Text("\(stats.eventsByKind.count) kinds")
                                        .fontWeight(.medium)
                                }
                                
                                GridRow {
                                    Text("Most Common:")
                                        .foregroundStyle(.secondary)
                                    Text(stats.mostCommonKind)
                                        .fontWeight(.medium)
                                }
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Quick Stats")
                    }
                }
                
                // Error Display
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } header: {
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Debug")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .refreshable {
                await loadCacheStats()
            }
            .onAppear {
                Task {
                    await loadCacheStats()
                }
            }
        }
    }
    
    private func loadCacheStats() async {
        guard let cache = nostrManager.cache else {
            await MainActor.run {
                errorMessage = "No cache available"
                isLoading = false
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let stats = try await cache.getStatistics()
            await MainActor.run {
                cacheStats = stats
                lastUpdateTime = Date()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load cache stats: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - Cache Statistics View
struct CacheStatsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var cacheStats: CacheStatistics?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            // Total Events Section
            Section {
                if let stats = cacheStats {
                    HStack {
                        Image(systemName: "cylinder.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Events")
                                .font(.headline)
                            Text("\(stats.totalEvents) events in database")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(stats.totalEvents)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                } else if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading cache statistics...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No cache data available")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Overview")
            }
            
            // Events by Kind Section
            if let stats = cacheStats, !stats.eventsByKind.isEmpty {
                Section {
                    ForEach(stats.sortedEventKinds, id: \.kind) { kindStat in
                        HStack {
                            Text("Kind \(kindStat.kind)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(kindStat.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Events by Kind")
                } footer: {
                    Text("Breakdown of events stored in the cache by Nostr event kind")
                }
            }
            
            // Error Display
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                } header: {
                    Text("Error")
                }
            }
        }
        .navigationTitle("Cache Statistics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable {
            await loadCacheStats()
        }
        .onAppear {
            Task {
                await loadCacheStats()
            }
        }
    }
    
    private func loadCacheStats() async {
        guard let cache = nostrManager.cache else {
            await MainActor.run {
                errorMessage = "No cache available"
                isLoading = false
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let stats = try await cache.getStatistics()
            await MainActor.run {
                cacheStats = stats
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load cache stats: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - Cache Statistics Extensions
extension CacheStatistics {
    var sortedEventKinds: [EventKindStatistic] {
        eventsByKind.map { kind, count in
            EventKindStatistic(kind: kind, count: count)
        }.sorted { $0.count > $1.count }
    }
    
    var mostCommonKind: String {
        guard let mostCommon = sortedEventKinds.first else { return "None" }
        return "Kind \(mostCommon.kind) (\(mostCommon.count))"
    }
}

struct EventKindStatistic {
    let kind: Int
    let count: Int
}

// MARK: - Blacklisted Mints View
struct BlacklistedMintsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(WalletManager.self) private var walletManager
    @State private var showAddMintSheet = false
    @State private var availableMints: [String] = []
    
    var body: some View {
        List {
            if appState.blacklistedMints.isEmpty {
                ContentUnavailableView(
                    "No Blacklisted Mints",
                    systemImage: "xmark.shield",
                    description: Text("Blacklisted mints will not be used or shown in your wallet")
                )
            } else {
                Section {
                    ForEach(Array(appState.blacklistedMints).sorted(), id: \.self) { mintURL in
                        BlacklistedMintRowSettings(mintURL: mintURL) {
                            appState.unblacklistMint(mintURL)
                        }
                    }
                } header: {
                    Text("Blacklisted Mints")
                } footer: {
                    Text("These mints are blocked from being used in your wallet")
                }
            }
            
            Section {
                Button(action: { showAddMintSheet = true }) {
                    Label("Add to Blacklist", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Blacklisted Mints")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddMintSheet) {
            AddToBlacklistSheet(
                currentMints: availableMints,
                blacklistedMints: appState.blacklistedMints
            ) { mintURL in
                appState.blacklistMint(mintURL)
            }
        }
        .task {
            await loadAvailableMints()
        }
    }
    
    private func loadAvailableMints() async {
        guard let wallet = walletManager.activeWallet else { return }
        let mintURLs = await wallet.mints.getMintURLs()
        await MainActor.run {
            availableMints = mintURLs
        }
    }
}

// MARK: - Blacklisted Mint Row for Settings
struct BlacklistedMintRowSettings: View {
    let mintURL: String
    let onUnblock: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "xmark.shield.fill")
                .foregroundColor(.red)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(string: mintURL)?.host ?? "Unknown Mint")
                    .font(.headline)
                Text(mintURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Unblock") {
                onUnblock()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add to Blacklist Sheet
struct AddToBlacklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentMints: [String]
    let blacklistedMints: Set<String>
    let onBlock: (String) -> Void
    @State private var manualMintURL = ""
    
    var availableMintsToBlock: [String] {
        currentMints.filter { !blacklistedMints.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if !availableMintsToBlock.isEmpty {
                    Section("Active Mints") {
                        ForEach(availableMintsToBlock, id: \.self) { mintURL in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(URL(string: mintURL)?.host ?? "Unknown Mint")
                                        .font(.headline)
                                    Text(mintURL)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button("Block") {
                                    onBlock(mintURL)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section {
                    TextField("https://mint.example.com", text: $manualMintURL)
                        .textContentType(.URL)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                    
                    Button("Add to Blacklist") {
                        if !manualMintURL.isEmpty {
                            onBlock(manualMintURL)
                            dismiss()
                        }
                    }
                    .disabled(manualMintURL.isEmpty)
                } header: {
                    Text("Manual Entry")
                } footer: {
                    Text("Enter a mint URL to block it from being used")
                }
            }
            .navigationTitle("Add to Blacklist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#endif