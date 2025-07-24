import SwiftUI
import NDKSwift

struct BlossomSettingsView: View {
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    @State private var newServerUrl = ""
    @State private var showingAddServer = false
    @State private var showingDeleteConfirmation = false
    @State private var serverToDelete: String?
    
    var body: some View {
        List {
            Section {
                ForEach(blossomServerManager.servers, id: \.self) { server in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Text(formatServerUrl(server))
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        // Delete button (except for default server)
                        if server != "https://blossom.primal.net" {
                            Button(action: {
                                serverToDelete = server
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Blossom Servers")
                    .textCase(.uppercase)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            
            Section {
                Text("Blossom servers are used to upload and host your audio files. You can add multiple servers for redundancy.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddServer = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            SimpleAddServerSheet(
                serverUrl: $newServerUrl,
                onAdd: { url in
                    blossomServerManager.addServer(url)
                    newServerUrl = ""
                    showingAddServer = false
                }
            )
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let server = serverToDelete {
                    blossomServerManager.removeServer(server)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this server?")
        }
    }
    
    private func formatServerUrl(_ url: String) -> String {
        var formatted = url
        if formatted.hasPrefix("https://") {
            formatted = String(formatted.dropFirst(8))
        } else if formatted.hasPrefix("http://") {
            formatted = String(formatted.dropFirst(7))
        }
        if formatted.hasSuffix("/") {
            formatted = String(formatted.dropLast())
        }
        return formatted
    }
}

// Simple add server sheet without suggestions
struct SimpleAddServerSheet: View {
    @Binding var serverUrl: String
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Add Blossom Server")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                        
                        TextField("blossom.example.com", text: $serverUrl)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal)
                    
                    Text("Enter the URL of a Blossom server that supports file uploads")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                        
                        Button(action: {
                            addServer()
                        }) {
                            Text("Add")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue)
                                )
                        }
                        .disabled(serverUrl.isEmpty)
                        .opacity(serverUrl.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func addServer() {
        var url = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no protocol specified
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://\(url)"
        }
        
        onAdd(url)
    }
}