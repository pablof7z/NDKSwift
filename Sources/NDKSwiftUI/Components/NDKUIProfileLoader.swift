import NDKSwiftCore
import SwiftUI

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
/// NDKUIProfileLoader(ndk: ndk, pubkey: pubkey) { metadata in
///     VStack {
///         if let metadata {
///             Text(metadata.displayName ?? metadata.name ?? "Unknown")
///             Text(metadata.about ?? "No bio")
///         } else {
///             Text("Loading...")
///         }
///     }
/// }
/// ```
public struct NDKUIProfileLoader<Content: View>: View {
    private let ndk: NDK
    let pubkey: String
    let maxAge: TimeInterval
    let content: (NDKUserMetadata?) -> Content
    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    public init(
        ndk: NDK,
        pubkey: String,
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping (NDKUserMetadata?) -> Content
    ) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.maxAge = maxAge
        self.content = content
    }

    public init(
        ndk: NDK,
        user: NDKUser,
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping (NDKUserMetadata?) -> Content
    ) {
        self.init(ndk: ndk, pubkey: user.pubkey, maxAge: maxAge, content: content)
    }

    public var body: some View {
        content(metadata)
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
        metadata = nil

        profileTask = Task {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: maxAge) {
                await MainActor.run {
                    self.metadata = metadata
                }
            }
        }
    }
}

/// A view that loads multiple profiles at once
public struct NDKUIMultipleProfileLoader<Content: View>: View {
    private let ndk: NDK
    let pubkeys: [String]
    let maxAge: TimeInterval
    let content: ([String: NDKUserMetadata]) -> Content
    @State private var profiles: [String: NDKUserMetadata] = [:]
    @State private var profileTasks: [String: Task<Void, Never>] = [:]

    public init(
        ndk: NDK,
        pubkeys: [String],
        maxAge: TimeInterval = TimeConstants.hour,
        @ViewBuilder content: @escaping ([String: NDKUserMetadata]) -> Content
    ) {
        self.ndk = ndk
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

        for pubkey in pubkeys {
            let task = Task {
                for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: maxAge) {
                    await MainActor.run {
                        self.profiles[pubkey] = metadata
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
    private let ndk: NDK
    let content: (NDKUserMetadata?) -> Content
    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    public init(ndk: NDK, @ViewBuilder content: @escaping (NDKUserMetadata?) -> Content) {
        self.ndk = ndk
        self.content = content
    }

    public var body: some View {
        content(metadata)
            .onAppear {
                loadCurrentUserProfile()
            }
            .onDisappear {
                profileTask?.cancel()
            }
    }

    private func loadCurrentUserProfile() {
        profileTask?.cancel()

        guard let signer = ndk.signer else { return }

        profileTask = Task {
            do {
                let currentUser = try await signer.user()
                for await metadata in await ndk.profileManager.subscribe(for: currentUser.pubkey) {
                    await MainActor.run {
                        self.metadata = metadata
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
    private let ndk: NDK
    let pubkey: String
    let style: BadgeStyle
    @State private var metadata: NDKUserMetadata?
    @State private var verificationStatus: VerificationStatus = .loading
    @State private var profileTask: Task<Void, Never>?
    @State private var verificationTask: Task<Void, Never>?

    public enum BadgeStyle {
        case full // Shows checkmark + NIP-05 identifier
        case compact // Shows just checkmark
        case text // Shows just the NIP-05 identifier
    }

    public enum VerificationStatus {
        case loading
        case verified(String) // The NIP-05 identifier
        case unverified
        case failed
    }

    public init(ndk: NDK, pubkey: String, style: BadgeStyle = .full) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.style = style
    }

    public init(ndk: NDK, user: NDKUser, style: BadgeStyle = .full) {
        self.init(ndk: ndk, pubkey: user.pubkey, style: style)
    }

    public var body: some View {
        Group {
            switch (verificationStatus, style) {
            case let (.verified(nip05), .full):
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

            case let (.verified(nip05), .text):
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

        profileTask = Task {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey) {
                await MainActor.run {
                    self.metadata = metadata
                }

                // Verify NIP-05 when profile loads
                if let nip05 = metadata?.nip05 {
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
            let mockNDK = NDK(relayURLs: [])

            VStack(spacing: 20) {
                // Single profile loader
                NDKUIProfileLoader(ndk: mockNDK, pubkey: "sample_pubkey") { metadata in
                    VStack(alignment: .leading) {
                        Text("Name: \(metadata?.displayName ?? "Loading...")")
                        Text("Bio: \(metadata?.about ?? "No bio")")
                    }
                }

                Divider()

                // Multiple profiles loader
                NDKUIMultipleProfileLoader(ndk: mockNDK, pubkeys: ["pubkey1", "pubkey2", "pubkey3"]) { profiles in
                    VStack(alignment: .leading) {
                        ForEach(profiles.keys.sorted(), id: \.self) { pubkey in
                            if let metadata = profiles[pubkey] {
                                Text("\(pubkey.prefix(8)): \(metadata.displayName ?? metadata.name ?? "Unknown")")
                            }
                        }
                    }
                }

                Divider()

                // NIP-05 badge
                HStack {
                    NDKUINip05Badge(ndk: mockNDK, pubkey: "sample_pubkey", style: .full)
                    NDKUINip05Badge(ndk: mockNDK, pubkey: "sample_pubkey", style: .compact)
                    NDKUINip05Badge(ndk: mockNDK, pubkey: "sample_pubkey", style: .text)
                }
            }
            .padding()
        }
    }
#endif
