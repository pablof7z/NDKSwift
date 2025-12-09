import SwiftUI
import NDKSwift

public struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let ndk: NDK
    let currentProfile: NDKUserMetadata?
    let onSave: () -> Void

    @State private var displayName = ""
    @State private var about = ""
    @State private var pictureUrl = ""
    @State private var bannerUrl = ""
    @State private var website = ""
    @State private var nip05 = ""
    @State private var lud16 = ""

    @State private var isSaving = false
    @State private var error: Error?
    @State private var showError = false

    public init(ndk: NDK, currentProfile: NDKUserMetadata?, onSave: @escaping () -> Void) {
        self.ndk = ndk
        self.currentProfile = currentProfile
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Avatar preview
                    HStack {
                        Spacer()
                        if let url = URL(string: pictureUrl), !pictureUrl.isEmpty {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(.secondary.opacity(0.3))
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(.secondary.opacity(0.3))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                )
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Basic Info") {
                    TextField("Display Name", text: $displayName)
                    TextField("About", text: $about, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Profile Images") {
                    TextField("Profile Picture URL", text: $pictureUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Banner URL", text: $bannerUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("Links") {
                    TextField("Website", text: $website)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("NIP-05 (e.g., name@domain.com)", text: $nip05)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Lightning Address", text: $lud16)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await saveProfile() }
                        }
                    }
                }
            }
            .onAppear {
                loadCurrentProfile()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(error?.localizedDescription ?? "Failed to save profile")
            }
        }
    }

    private func loadCurrentProfile() {
        displayName = currentProfile?.displayName ?? currentProfile?.name ?? ""
        about = currentProfile?.about ?? ""
        pictureUrl = currentProfile?.picture ?? ""
        bannerUrl = currentProfile?.banner ?? ""
        website = currentProfile?.website ?? ""
        nip05 = currentProfile?.nip05 ?? ""
        lud16 = currentProfile?.lud16 ?? ""
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            var metadata: [String: String] = [:]

            if !displayName.isEmpty { metadata["display_name"] = displayName }
            if !displayName.isEmpty { metadata["name"] = displayName }
            if !about.isEmpty { metadata["about"] = about }
            if !pictureUrl.isEmpty { metadata["picture"] = pictureUrl }
            if !bannerUrl.isEmpty { metadata["banner"] = bannerUrl }
            if !website.isEmpty { metadata["website"] = website }
            if !nip05.isEmpty { metadata["nip05"] = nip05 }
            if !lud16.isEmpty { metadata["lud16"] = lud16 }

            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            _ = try await ndk.publish { builder in
                builder
                    .kind(EventKind.metadata)
                    .content(jsonString)
            }

            await MainActor.run {
                onSave()
                dismiss()
            }
        } catch {
            self.error = error
            showError = true
        }
    }
}
