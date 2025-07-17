import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage("hide_sensitive_content") private var hideSensitiveContent = false
    @AppStorage("require_auth_to_view") private var requireAuthToView = false
    @AppStorage("block_strangers") private var blockStrangers = false
    @AppStorage("hide_read_receipts") private var hideReadReceipts = false
    @AppStorage("disable_analytics") private var disableAnalytics = false
    @AppStorage("clear_cache_on_exit") private var clearCacheOnExit = false
    
    var body: some View {
        List {
            // Content Privacy
            Section {
                Toggle(isOn: $hideSensitiveContent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide Sensitive Content")
                        Text("Blur potentially sensitive media")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $requireAuthToView) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Require Authentication")
                        Text("Use biometrics to open the app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Content")
            }
            
            // Communication Privacy
            Section {
                Toggle(isOn: $blockStrangers) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Block Messages from Strangers")
                        Text("Only receive messages from people you follow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $hideReadReceipts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide Read Receipts")
                        Text("Don't send read confirmations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Communication")
            }
            
            // Data Privacy
            Section {
                Toggle(isOn: $disableAnalytics) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disable Analytics")
                        Text("Don't share usage data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle(isOn: $clearCacheOnExit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear Cache on Exit")
                        Text("Remove temporary data when closing app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: clearAllData) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("Clear All App Data")
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Data")
            }
            
            // Blocked Users
            Section {
                NavigationLink(destination: BlockedUsersView()) {
                    HStack {
                        Text("Blocked Users")
                        Spacer()
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                }
                
                NavigationLink(destination: MutedWordsView()) {
                    HStack {
                        Text("Muted Words")
                        Spacer()
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Filters")
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func clearAllData() {
        // Implementation for clearing app data
    }
}

struct BlockedUsersView: View {
    var body: some View {
        List {
            Text("No blocked users")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .navigationTitle("Blocked Users")
    }
}

struct MutedWordsView: View {
    var body: some View {
        List {
            Text("No muted words")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        }
        .navigationTitle("Muted Words")
    }
}