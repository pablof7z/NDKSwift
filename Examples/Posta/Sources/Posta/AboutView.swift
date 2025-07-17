import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    // App Icon and Info
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(20)
                        
                        Text("Posta")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("A modern Nostr client for iOS")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Links Section
                    VStack(spacing: 12) {
                        LinkRow(
                            icon: "globe",
                            title: "Website",
                            subtitle: "posta.app",
                            action: openWebsite
                        )
                        
                        LinkRow(
                            icon: "envelope",
                            title: "Contact",
                            subtitle: "support@posta.app",
                            action: sendEmail
                        )
                        
                        LinkRow(
                            icon: "doc.text",
                            title: "Terms of Service",
                            subtitle: "View our terms",
                            action: openTerms
                        )
                        
                        LinkRow(
                            icon: "hand.raised",
                            title: "Privacy Policy",
                            subtitle: "How we handle your data",
                            action: openPrivacy
                        )
                        
                        LinkRow(
                            icon: "sparkles",
                            title: "What's New",
                            subtitle: "Latest features and fixes",
                            action: openChangelog
                        )
                    }
                    .padding(.horizontal)
                    
                    // Credits
                    VStack(spacing: 16) {
                        Text("Built with")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            VStack {
                                Image(systemName: "swift")
                                    .font(.title)
                                    .foregroundColor(.orange)
                                Text("Swift")
                                    .font(.caption)
                            }
                            
                            VStack {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.title)
                                    .foregroundColor(.blue)
                                Text("SwiftUI")
                                    .font(.caption)
                            }
                            
                            VStack {
                                Image(systemName: "bolt.fill")
                                    .font(.title)
                                    .foregroundColor(.purple)
                                Text("NDKSwift")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical)
                    
                    // Footer
                    VStack(spacing: 8) {
                        Text("Made with 💜 for the Nostr community")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("© 2024 Posta. All rights reserved.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
    
    private func openWebsite() {
        if let url = URL(string: "https://posta.app") {
            UIApplication.shared.open(url)
        }
    }
    
    private func sendEmail() {
        if let url = URL(string: "mailto:support@posta.app") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openTerms() {
        if let url = URL(string: "https://posta.app/terms") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openPrivacy() {
        if let url = URL(string: "https://posta.app/privacy") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openChangelog() {
        if let url = URL(string: "https://posta.app/changelog") {
            UIApplication.shared.open(url)
        }
    }
}

struct LinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}