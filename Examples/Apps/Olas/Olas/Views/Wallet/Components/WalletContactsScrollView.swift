import SwiftUI
import NDKSwift

struct WalletContactsScrollView: View {
    @Environment(NostrManager.self) private var nostrManager
    @State private var contacts: [(pubkey: String, profile: NDKUserProfile?)] = []
    @State private var isLoading = true
    @Binding var showNutZap: Bool
    @Binding var nutZapRecipient: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            // Header
            HStack {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Quick Send")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundStyle(OlasDesign.Colors.text)
                }
                
                Spacer()
                
                Button {
                    // Navigate to full contacts
                    OlasDesign.Haptic.selection()
                } label: {
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(OlasDesign.Typography.caption)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(OlasDesign.Colors.primary)
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            
            // Contacts scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OlasDesign.Spacing.md) {
                    // Add contact button
                    Button {
                        OlasDesign.Haptic.selection()
                        // Show add contact sheet
                    } label: {
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: OlasDesign.Colors.primaryGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                style: StrokeStyle(lineWidth: 2, dash: [5, 5])
                                            )
                                    )
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: OlasDesign.Colors.primaryGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            Text("Add")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(OlasDesign.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(ContactButtonStyle())
                    
                    // Contact items
                    if isLoading {
                        ForEach(0..<5) { _ in
                            ContactSkeletonView()
                        }
                    } else {
                        ForEach(contacts, id: \.pubkey) { contact in
                            ContactItemView(
                                pubkey: contact.pubkey,
                                profile: contact.profile
                            ) {
                                nutZapRecipient = contact.pubkey
                                showNutZap = true
                                OlasDesign.Haptic.selection()
                            }
                        }
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
            }
        }
        .task {
            await loadContacts()
        }
    }
    
    private func loadContacts() async {
        guard let ndk = nostrManager.ndk,
              let userPubkey = ndk.signer?.pubkey else { return }
        
        // Load contact list (kind 3)
        let filter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.contactList],
            limit: 1
        )
        
        do {
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 3600,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in dataSource.events {
                // Extract pubkeys from tags
                let pubkeys = event.tags
                    .filter { $0.count >= 2 && $0[0] == "p" }
                    .map { $0[1] }
                    .prefix(10) // Limit to 10 for horizontal scroll
                
                // Load profiles
                var loadedContacts: [(pubkey: String, profile: NDKUserProfile?)] = []
                
                for pubkey in pubkeys {
                    if let profileManager = ndk.profileManager {
                        let profile = await profileManager.fetchProfile(for: pubkey)
                        loadedContacts.append((pubkey: pubkey, profile: profile))
                    }
                }
                
                await MainActor.run {
                    self.contacts = loadedContacts
                    self.isLoading = false
                }
                
                break // Only need first contact list event
            }
        } catch {
            print("Error loading contacts: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct ContactItemView: View {
    let pubkey: String
    let profile: NDKUserProfile?
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: OlasDesign.Spacing.sm) {
                OlasAvatar(
                    url: profile?.picture,
                    size: 60,
                    pubkey: pubkey
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isPressed ? OlasDesign.Colors.primaryGradient : [Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .animation(.spring(), value: isPressed)
                )
                
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OlasDesign.Colors.text)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(ContactButtonStyle())
    }
    
    private var displayName: String {
        if let name = profile?.displayName ?? profile?.name {
            return name
        }
        return String(pubkey.prefix(8))
    }
}

struct ContactSkeletonView: View {
    @State private var shimmerAnimation = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.sm) {
            Circle()
                .fill(OlasDesign.Colors.surface)
                .overlay(shimmerGradient)
                .frame(width: 60, height: 60)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(OlasDesign.Colors.surface)
                .overlay(shimmerGradient)
                .frame(width: 50, height: 12)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerAnimation = true
            }
        }
    }
    
    private var shimmerGradient: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.1),
                Color.white.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .rotationEffect(.degrees(30))
        .offset(x: shimmerAnimation ? 300 : -300)
    }
}

struct ContactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}