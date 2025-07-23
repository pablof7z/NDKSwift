import SwiftUI
import NDKSwift

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile header
                    VStack(spacing: 16) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(appState.currentUser?.pubkey.prefix(2).uppercased() ?? "?")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(spacing: 4) {
                            Text("Anonymous User")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("@\(appState.currentUser?.pubkey.prefix(8) ?? "unknown")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Stats
                        HStack(spacing: 40) {
                            VStack {
                                Text("0")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Posts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("0")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Followers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("0")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Following")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical)
                        
                        Button(action: {}) {
                            Text("Edit Profile")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Posts grid placeholder
                    VStack {
                        Text("Your Posts")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                        Text("Posts will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: 300)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}