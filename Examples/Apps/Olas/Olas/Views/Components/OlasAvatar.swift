import SwiftUI
import CryptoKit

struct OlasAvatar: View {
    let url: String?
    let size: CGFloat
    let pubkey: String
    
    @State private var isLoading = true
    @State private var hasError = false
    
    private var placeholderGradient: LinearGradient {
        let hash = pubkey.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: hash)
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        
        // Generate colors based on pubkey hash
        let hue1 = Double(hashString.prefix(2).compactMap { $0.hexDigitValue }.reduce(0) { $0 * 16 + $1 }) / 255.0
        let hue2 = Double(hashString.dropFirst(2).prefix(2).compactMap { $0.hexDigitValue }.reduce(0) { $0 * 16 + $1 }) / 255.0
        
        return LinearGradient(
            colors: [
                Color(hue: hue1, saturation: 0.7, brightness: 0.8),
                Color(hue: hue2, saturation: 0.6, brightness: 0.7)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        ZStack {
            if let url = url, !url.isEmpty, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        // Loading state
                        Circle()
                            .fill(OlasDesign.Colors.surface)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    case .failure(_):
                        // Error state - show placeholder
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                // No URL - show placeholder
                placeholderAvatar
            }
        }
        .frame(width: size, height: size)
    }
    
    private var placeholderAvatar: some View {
        Circle()
            .fill(placeholderGradient)
            .overlay(
                Text(String(pubkey.prefix(2).uppercased()))
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// Preview
struct OlasAvatar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OlasAvatar(
                url: "https://example.com/avatar.jpg",
                size: 60,
                pubkey: "npub1234567890abcdef"
            )
            
            OlasAvatar(
                url: nil,
                size: 40,
                pubkey: "npub0987654321fedcba"
            )
            
            OlasAvatar(
                url: "",
                size: 80,
                pubkey: "npubabcdef1234567890"
            )
        }
        .padding()
        .background(Color.black)
    }
}