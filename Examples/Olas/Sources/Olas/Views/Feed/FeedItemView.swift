import SwiftUI
import NDKSwift

struct FeedItemView: View {
    let item: FeedItem
    @State private var isLiked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(item.profile?.name?.prefix(1) ?? "?")
                            .font(.headline)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.profile?.displayName ?? item.profile?.name ?? "Loading...")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("@\(item.profile?.name ?? String(item.event.pubkey.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Image placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .aspectRatio(4/5, contentMode: .fit)
                .overlay(
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("Image Loading")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                )
            
            // Actions
            HStack(spacing: 24) {
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isLiked.toggle()
                    }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(isLiked ? .red : .white)
                        .scaleEffect(isLiked ? 1.1 : 1.0)
                }
                
                Button(action: {}) {
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Button(action: {}) {
                    Image(systemName: "bolt")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Content
            if !item.event.content.isEmpty {
                Text(item.event.content)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.black)
    }
}