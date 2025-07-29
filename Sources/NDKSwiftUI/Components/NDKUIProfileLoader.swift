import SwiftUI
import NDKSwift

/// A utility view that loads and provides profile data to its content
///
/// This component handles:
/// - Automatic profile loading from NDK data sources
/// - Reactive updates when profile changes
/// - Profile caching and deduplication
/// - Contact metadata observation
///
/// ## Usage
///
/// ```swift
/// NDKUIProfileLoader(pubkey: pubkey) { profile in
///     VStack {
///         if let profile {
///             Text(profile.displayName ?? profile.name ?? "Unknown")
///             Text(profile.about ?? "No bio")
///         } else {
///             Text("Loading...")
///         }
///     }
/// }
/// ```
public struct NDKUIProfileLoader<Content: View>: View {
    let pubkey: String
    let maxAge: TimeInterval
    let content: (NDKUserProfile?) -> Content
    
    @Environment(\.ndk) private var ndk
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    public init(
        pubkey: String,
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping (NDKUserProfile?) -> Content
    ) {
        self.pubkey = pubkey
        self.maxAge = maxAge
        self.content = content
    }
    
    public init(
        user: NDKUser,
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping (NDKUserProfile?) -> Content
    ) {
        self.init(pubkey: user.pubkey, maxAge: maxAge, content: content)
    }
    
    public var body: some View {
        content(profile)
            .onAppear {
                loadProfile()
            }
            .onDisappear {
                profileTask?.cancel()
            }
            .onChange(of: pubkey) { _, _ in
                loadProfile()
            }
    }
    
    private func loadProfile() {
        profileTask?.cancel()
        profile = nil
        
        guard let ndk = ndk else { return }
        
        profileTask = Task {
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: maxAge) {
                await MainActor.run {
                    self.profile = profile
                }
            }
        }
    }
}

/// A view that loads multiple profiles at once
public struct NDKUIMultipleProfileLoader<Content: View>: View {
    let pubkeys: [String]
    let maxAge: TimeInterval
    let content: ([String: NDKUserProfile]) -> Content
    
    @Environment(\.ndk) private var ndk
    @State private var profiles: [String: NDKUserProfile] = [:]
    @State private var profileTasks: [String: Task<Void, Never>] = [:]
    
    public init(
        pubkeys: [String],
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping ([String: NDKUserProfile]) -> Content
    ) {
        self.pubkeys = pubkeys
        self.maxAge = maxAge
        self.content = content
    }
    
    public var body: some View {
        content(profiles)
            .onAppear {
                loadProfiles()
            }
            .onDisappear {
                cancelAllTasks()
            }
            .onChange(of: pubkeys) { _, _ in
                loadProfiles()
            }
    }
    
    private func loadProfiles() {
        cancelAllTasks()
        profiles = [:]
        
        guard let ndk = ndk else { return }
        
        for pubkey in pubkeys {
            let task = Task {
                for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: maxAge) {
                    await MainActor.run {
                        self.profiles[pubkey] = profile
                    }
                }
            }
            profileTasks[pubkey] = task
        }
    }
    
    private func cancelAllTasks() {
        for task in profileTasks.values {
            task.cancel()
        }
        profileTasks = [:]
    }
}

/// A view that provides access to the current user's profile
public struct NDKUICurrentUserProfile<Content: View>: View {
    let content: (NDKUserProfile?) -> Content
    
    @Environment(\.ndk) private var ndk
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    public init(@ViewBuilder content: @escaping (NDKUserProfile?) -> Content) {
        self.content = content
    }
    
    public var body: some View {
        content(profile)
            .onAppear {
                loadCurrentUserProfile()
            }
            .onDisappear {
                profileTask?.cancel()
            }
    }
    
    private func loadCurrentUserProfile() {
        profileTask?.cancel()
        
        guard let ndk = ndk,
              let signer = ndk.signer else { return }
        
        profileTask = Task {
            do {
                let currentUser = try await signer.user()
                for await profile in await ndk.profileManager.observe(for: currentUser.pubkey) {
                    await MainActor.run {
                        self.profile = profile
                    }
                }
            } catch {
                NDKLogger.log(.error, category: .general, "[NDKUIProfileLoader] Failed to get current user: \(error)")
            }
        }
    }
}

/// A view that provides NIP-05 verification status
public struct NDKUINip05Badge: View {
    let pubkey: String
    let style: BadgeStyle
    
    @Environment(\.ndk) private var ndk
    @State private var profile: NDKUserProfile?
    @State private var verificationStatus: VerificationStatus = .loading
    @State private var profileTask: Task<Void, Never>?
    @State private var verificationTask: Task<Void, Never>?
    
    public enum BadgeStyle {
        case full       // Shows checkmark + NIP-05 identifier
        case compact    // Shows just checkmark
        case text       // Shows just the NIP-05 identifier
    }
    
    public enum VerificationStatus {
        case loading
        case verified(String)  // The NIP-05 identifier
        case unverified
        case failed
    }
    
    public init(pubkey: String, style: BadgeStyle = .full) {
        self.pubkey = pubkey
        self.style = style
    }
    
    public init(user: NDKUser, style: BadgeStyle = .full) {
        self.init(pubkey: user.pubkey, style: style)
    }
    
    public var body: some View {
        Group {
            switch (verificationStatus, style) {
            case (.verified(let nip05), .full):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.ndkAccent)
                    Text(nip05)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
            case (.verified(_), .compact):
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.ndkAccent)
                
            case (.verified(let nip05), .text):
                Text(nip05)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
            default:
                EmptyView()
            }
        }
        .onAppear {
            loadAndVerify()
        }
        .onDisappear {
            profileTask?.cancel()
            verificationTask?.cancel()
        }
    }
    
    private func loadAndVerify() {
        profileTask?.cancel()
        verificationTask?.cancel()
        
        guard let ndk = ndk else { return }
        
        profileTask = Task {
            for await profile in await ndk.profileManager.observe(for: pubkey) {
                await MainActor.run {
                    self.profile = profile
                }
                
                // Verify NIP-05 when profile loads
                if let nip05 = profile?.nip05 {
                    await verifyNip05(nip05)
                } else {
                    await MainActor.run {
                        self.verificationStatus = .unverified
                    }
                }
            }
        }
    }
    
    private func verifyNip05(_ identifier: String) async {
        verificationTask?.cancel()
        
        guard let ndk = ndk else { return }
        
        verificationTask = Task {
            do {
                let isValid = try await ndk.nip05Manager.verify(identifier: identifier, expectedPubkey: pubkey)
                await MainActor.run {
                    self.verificationStatus = isValid ? .verified(identifier) : .failed
                }
            } catch {
                await MainActor.run {
                    self.verificationStatus = .failed
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIProfileLoader_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Single profile loader
            NDKUIProfileLoader(pubkey: "sample_pubkey") { profile in
                VStack(alignment: .leading) {
                    Text("Name: \(profile?.displayName ?? "Loading...")")
                    Text("Bio: \(profile?.about ?? "No bio")")
                }
            }
            
            Divider()
            
            // Multiple profiles loader
            NDKUIMultipleProfileLoader(pubkeys: ["pubkey1", "pubkey2", "pubkey3"]) { profiles in
                VStack(alignment: .leading) {
                    ForEach(profiles.keys.sorted(), id: \.self) { pubkey in
                        if let profile = profiles[pubkey] {
                            Text("\(pubkey.prefix(8)): \(profile.displayName ?? profile.name ?? "Unknown")")
                        }
                    }
                }
            }
            
            Divider()
            
            // NIP-05 badge
            HStack {
                NDKUINip05Badge(pubkey: "sample_pubkey", style: .full)
                NDKUINip05Badge(pubkey: "sample_pubkey", style: .compact)
                NDKUINip05Badge(pubkey: "sample_pubkey", style: .text)
            }
        }
        .padding()
        .environment(\.ndk, nil)
    }
}
#endif