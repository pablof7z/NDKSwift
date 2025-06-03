import SwiftUI
import NDKSwift

struct ContentView: View {
    @StateObject private var viewModel = NostrViewModel()
    @State private var messageText = ""
    @State private var showingNsecAlert = false
    @State private var bunkerUrl = ""
    @State private var showingBunkerInput = false
    @State private var showingAuthUrl = false
    @State private var newRelayUrl = ""
    @State private var showingRelaySheet = false
    @State private var showingNsecInput = false
    @State private var nsecInput = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if viewModel.nsec.isEmpty && !viewModel.isConnectedViaBunker {
                    loginView
                } else {
                    mainView
                }
            }
            .navigationTitle("Nostr App")
            .alert("Your Private Key", isPresented: $viewModel.accountCreated) {
                Button("Copy", action: {
                    UIPasteboard.general.string = viewModel.nsec
                })
                Button("OK", role: .cancel) {}
            } message: {
                Text("Keep this secret and secure!\n\n\(viewModel.nsec)")
            }
            .sheet(isPresented: $showingBunkerInput) {
                bunkerInputView
            }
            .alert("Authorization Required", isPresented: $viewModel.showingAuthUrl) {
                Button("Open in Browser", action: {
                    if let url = URL(string: viewModel.authUrl) {
                        UIApplication.shared.open(url)
                    }
                })
                Button("Copy URL", action: {
                    UIPasteboard.general.string = viewModel.authUrl
                })
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please authorize this connection in your bunker app:\n\n\(viewModel.authUrl)")
            }
            .sheet(isPresented: $showingNsecInput) {
                nsecInputView
            }
            .sheet(isPresented: $showingRelaySheet) {
                relaySheetView
            }
        }
    }
    
    private var loginView: some View {
        VStack(spacing: 20) {
            Text("Welcome to Nostr")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Create an account or login")
                .font(.headline)
                .foregroundColor(.secondary)
            
            createAccountButton
            
            Text("OR")
                .font(.headline)
                .foregroundColor(.secondary)
            
            loginWithNsecButton
            
            Text("OR")
                .font(.headline)
                .foregroundColor(.secondary)
            
            bunkerLoginButton
            
            bunkerConnectionStatus
            
            // Show status messages on login screen too
            statusMessages
            
            // Debug info for login screen
            if !viewModel.nsec.isEmpty {
                Text("DEBUG: nsec exists - should show main view!")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
            }
        }
        .padding()
    }
    
    private var createAccountButton: some View {
        Button(action: {
            viewModel.createAccount()
        }) {
            Text("Create Account")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(Color.blue)
                .cornerRadius(10)
        }
    }
    
    private var loginWithNsecButton: some View {
        Button(action: {
            showingNsecInput = true
        }) {
            Text("Login with nsec")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(Color.green)
                .cornerRadius(10)
        }
    }
    
    private var bunkerLoginButton: some View {
        Button(action: {
            showingBunkerInput = true
        }) {
            Text("Login with Bunker")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 200, height: 50)
                .background(Color.purple)
                .cornerRadius(10)
        }
    }
    
    @ViewBuilder
    private var bunkerConnectionStatus: some View {
        if viewModel.isBunkerConnecting {
            HStack {
                ProgressView()
                Text("Connecting to bunker...")
            }
            .padding()
        }
    }
    
    private var mainView: some View {
        VStack(alignment: .leading, spacing: 20) {
            accountInfoSection
            messageComposer
            relayStatusSection
            statusMessages
            Spacer()
        }
    }
    
    private var accountInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Account")
                .font(.headline)
            
            HStack {
                Text("Public Key (npub):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.npub)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.blue)
                    .onTapGesture {
                        UIPasteboard.general.string = viewModel.npub
                    }
            }
            
            HStack {
                Text("Public Key (hex):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(viewModel.pubkey)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.blue)
                    .onTapGesture {
                        UIPasteboard.general.string = viewModel.pubkey
                    }
            }
            
            if viewModel.isConnectedViaBunker {
                Text("Connected via Bunker")
                    .font(.caption)
                    .foregroundColor(.purple)
            } else {
                Button("Show Private Key") {
                    showingNsecAlert = true
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var messageComposer: some View {
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
    }
    
    private var relayStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connected Relays")
                    .font(.headline)
                Spacer()
                Button("Add Relay") {
                    showingRelaySheet = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if viewModel.connectedRelays.isEmpty {
                Text("No relays connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.connectedRelays) { relay in
                    RelayRowView(relay: relay) {
                        viewModel.removeRelay(relay.url)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private var statusMessages: some View {
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
    }
    
    private var bunkerInputView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Enter Bunker URL")
                    .font(.headline)
                
                Text("Paste your bunker:// connection string")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("bunker://...", text: $bunkerUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Example:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("bunker://pubkey?relay=wss://relay.nsec.app&secret=abc123")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Bunker Login")
            .navigationBarItems(
                leading: Button("Cancel") {
                    showingBunkerInput = false
                    bunkerUrl = ""
                },
                trailing: Button("Connect") {
                    showingBunkerInput = false
                    viewModel.connectWithBunker(bunkerUrl)
                }
                .disabled(bunkerUrl.isEmpty)
            )
        }
    }
    
    private var nsecInputView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Enter Your Private Key")
                    .font(.headline)
                
                Text("Paste your nsec private key to login")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SecureField("nsec1...", text: $nsecInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Security Notice:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("• Your private key is stored locally on this device")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Never share your private key with anyone")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Consider using a Bunker for better security")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Login with nsec")
            .navigationBarItems(
                leading: Button("Cancel") {
                    showingNsecInput = false
                    nsecInput = ""
                },
                trailing: Button("Login") {
                    print("DEBUG: Login button tapped with nsec: \(nsecInput)")
                    showingNsecInput = false
                    viewModel.loginWithNsec(nsecInput)
                    nsecInput = ""
                }
                .disabled(nsecInput.isEmpty || !nsecInput.hasPrefix("nsec1"))
            )
        }
    }
    
    private var relaySheetView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add New Relay")
                    .font(.headline)
                
                Text("Enter the WebSocket URL of the relay")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("wss://relay.example.com", text: $newRelayUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Add Relay")
            .navigationBarItems(
                leading: Button("Cancel") {
                    showingRelaySheet = false
                    newRelayUrl = ""
                },
                trailing: Button("Add") {
                    viewModel.addRelay(newRelayUrl)
                    showingRelaySheet = false
                    newRelayUrl = ""
                }
                .disabled(newRelayUrl.isEmpty || !newRelayUrl.hasPrefix("wss://"))
            )
        }
    }
}

// MARK: - Relay Row View

struct RelayRowView: View {
    let relay: RelayInfo
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(relay.url)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Circle()
                        .fill(relay.statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(relay.statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if relay.connectionState == .connected {
                        Text("↑\(relay.messagesSent) ↓\(relay.messagesReceived)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}

#Preview("Relay Row") {
    RelayRowView(
        relay: RelayInfo(
            url: "wss://relay.primal.net",
            connectionState: .connected,
            connectedAt: Date(),
            messagesSent: 42,
            messagesReceived: 123
        )
    ) {
        // Preview action
    }
    .padding()
}
