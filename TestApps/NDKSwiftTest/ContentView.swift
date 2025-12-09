
import SwiftUI
import NDKSwift

struct ContentView: View {
    
    @State private var privateKey: String = ""
    @State private var status = "Not connected"
    @State private var ndk: NDK?
    @State private var events: [NDKEvent] = []
    @State private var user: NDKUser?

    private let relayURL = "wss://relay.damus.io"

    var body: some View {
        NavigationView {
            VStack {
                Text("NDKSwift Test App")
                    .font(.largeTitle)
                
                Text("Disclaimer: This is a test application. Do not use your personal private key.")
                    .foregroundColor(.red)
                    .padding()
                
                TextField("Enter your private key (hex format)", text: $privateKey)
                    .padding()
                    .border(Color.gray, width: 1)
                
                Button("Login / Generate new key") {
                    setupNDK()
                }
                
                if let user = user {
                    NavigationLink(destination: UserProfileView(user: user)) {
                        Text("View Profile")
                    }
                }
                
                Text(status)
                
                Button("Publish Test Note") {
                    Task {
                        do {
                            guard let ndk = ndk else {
                                status = "Please login first."
                                return
                            }

                            _ = try await ndk.addRelay(url: relayURL)
                            try await ndk.connect()
                            
                            let event = try await ndk.publish(
                                NDKEventBuilder(ndk: ndk)
                                    .kind(1)
                                    .content("Hello from NDKSwiftTestApp! \(UUID().uuidString)")
                            )
                            
                            status = "Published event with ID: \(event.id)"
                            
                        } catch {
                            status = "Error: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(ndk == nil)
                
                List(events, id: \.id) {
                    Text($0.content)
                }
                
            }
            .padding()
            .onAppear(perform: setupNDK)
            .onDisappear {
                ndk?.disconnect()
            }
        }
    }
    
    private func setupNDK() {
        var signer: NDKSigner
        if !privateKey.isEmpty {
            signer = NDKKeypairSigner(privateKey: privateKey)!
        } else {
            let newKeypair = NDKKeypair.generate()
            signer = NDKKeypairSigner(keypair: newKeypair)!
            privateKey = newKeypair.privateKey!
            status = "Generated a new private key."
        }
        
        ndk = NDK(signer: signer)
        Task {
            self.user = try? await NDKUser(pubkey: signer.pubkey)
            self.user?.ndk = ndk
        }

        status = "Logged in successfully!"
        
        subscribeToEvents()
    }
    
    private func subscribeToEvents() {
        guard let ndk = ndk else { return }
        
        Task {
            do {
                _ = try await ndk.addRelay(url: relayURL)
                try await ndk.connect()
                
                let filter = NDKFilter(kinds: [1], limit: 20)
                ndk.subscribe(filter) { event in
                    // This closure will be called for each event
                    // that matches the filter
                    // Make sure to update the UI on the main thread
                    DispatchQueue.main.async {
                        if !self.events.contains(event) {
                            self.events.append(event)
                            self.events.sort { $0.createdAt > $1.createdAt }
                        }
                        
                    }
                }
                status = "Subscribed to events"
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
