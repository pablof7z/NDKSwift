
import NDKSwift
import SwiftUI

struct UserProfileView: View {
    let user: NDKUser
    @State private var profile: NDKUserProfile?
    @State private var status: String = ""

    var body: some View {
        VStack {
            Text("User Profile")
                .font(.largeTitle)

            if let profile = profile {
                AsyncImage(url: URL(string: profile.image ?? "")) {
                    $0.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } placeholder: {
                    Image(systemName: "person.circle")
                        .resizable()
                        .frame(width: 100, height: 100)
                }

                Text(profile.displayName ?? profile.name ?? "")
                    .font(.title)

                Text(profile.about ?? "")
                    .padding()

                if let nip05 = profile.nip05 {
                    Text("NIP-05: \(nip05)")
                        .padding()
                }

            } else {
                Text(status)
                ProgressView()
            }
        }
        .onAppear {
            fetchProfile()
        }
    }

    private func fetchProfile() {
        Task {
            do {
                let profile = try await user.fetchProfile()
                DispatchQueue.main.async {
                    self.profile = profile
                }
            } catch {
                self.status = "Error: \(error.localizedDescription)"
            }
        }
    }
}
