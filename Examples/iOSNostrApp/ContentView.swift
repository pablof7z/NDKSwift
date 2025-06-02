import SwiftUI
import NDKSwift

struct ContentView: View {
    @StateObject private var viewModel = NostrViewModel()
    @State private var messageText = ""
    @State private var showingNsecAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.nsec.isEmpty {
                    // Signup View
                    VStack(spacing: 20) {
                        Text("Welcome to Nostr")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Create your Nostr account")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            viewModel.createAccount()
                            showingNsecAlert = true
                        }) {
                            Text("Create Account")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    // Main View
                    VStack(alignment: .leading, spacing: 20) {
                        // Account Info Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your Account")
                                .font(.headline)
                            
                            HStack {
                                Text("Public Key:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(viewModel.npub)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Button("Show Private Key") {
                                showingNsecAlert = true
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        
                        // Message Composer
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Publish Message")
                                .font(.headline)
                            
                            TextEditor(text: $messageText)
                                .frame(height: 100)
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3))
                                )
                            
                            Button(action: {
                                viewModel.publishMessage(messageText)
                                messageText = ""
                            }) {
                                Text("Publish to Nostr")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled(messageText.isEmpty || viewModel.isPublishing)
                        }
                        .padding()
                        
                        // Status Messages
                        if viewModel.isPublishing {
                            HStack {
                                ProgressView()
                                Text("Publishing...")
                            }
                            .padding()
                        }
                        
                        if !viewModel.statusMessage.isEmpty {
                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundColor(viewModel.isError ? .red : .green)
                                .padding()
                        }
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Nostr App")
            .alert("Your Private Key", isPresented: $showingNsecAlert) {
                Button("Copy", action: {
                    UIPasteboard.general.string = viewModel.nsec
                })
                Button("OK", role: .cancel) {}
            } message: {
                Text("Keep this secret and secure!\n\n\(viewModel.nsec)")
            }
        }
    }
}

#Preview {
    ContentView()
}