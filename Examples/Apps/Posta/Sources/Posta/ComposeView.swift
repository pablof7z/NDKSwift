import SwiftUI
import NDKSwift

struct ComposeView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    
    @State private var content = ""
    @State private var isPublishing = false
    @State private var publishError: Error?
    @State private var confirmationState: EventConfirmationState?
    @State private var publishedEventId: String?
    @State private var monitoringTask: Task<Void, Never>?
    
    @FocusState private var isTextFieldFocused: Bool
    
    private let maxCharacters = 280
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isPublishing)
                    
                    Spacer()
                    
                    publishButton
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Compose area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Text editor
                        TextEditor(text: $content)
                            .font(.body)
                            .padding(4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .frame(minHeight: 150)
                            .focused($isTextFieldFocused)
                        
                        // Character count
                        HStack {
                            Spacer()
                            Text("\(content.count)/\(maxCharacters)")
                                .font(.caption)
                                .foregroundColor(content.count > maxCharacters ? .red : .secondary)
                        }
                        
                        // Publishing status
                        if isPublishing || confirmationState != nil {
                            publishingStatusView
                        }
                        
                        // Error message
                        if let error = publishError {
                            ErrorBanner(error: error)
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .onAppear {
            isTextFieldFocused = true
        }
        .onDisappear {
            monitoringTask?.cancel()
        }
    }
    
    private var publishButton: some View {
        Button(action: {
            Task {
                await publishNote()
            }
        }) {
            Group {
                if isPublishing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                        Text("Publishing...")
                    }
                } else {
                    Text("Post")
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isPublishEnabled ? Color.accentColor : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(20)
        }
        .disabled(!isPublishEnabled || isPublishing)
    }
    
    private var isPublishEnabled: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.count <= maxCharacters
    }
    
    private var publishingStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch confirmationState {
                case .optimistic:
                    Image(systemName: "arrow.up.circle")
                        .foregroundColor(.orange)
                    Text("Sending to relays...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                case .confirmed(let relay):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Confirmed by \(relay)")
                        .font(.caption)
                        .foregroundColor(.green)
                    
                case .none:
                    if isPublishing {
                        Image(systemName: "arrow.up.circle")
                            .foregroundColor(.blue)
                        Text("Preparing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.tertiarySystemFill))
            .cornerRadius(8)
        }
    }
    
    private func publishNote() async {
        guard let ndk = ndkManager.ndk,
              let signer = authManager.activeSigner else {
            publishError = NostrError.signerRequired
            return
        }
        
        isPublishing = true
        publishError = nil
        confirmationState = nil
        
        do {
            // Build and sign the event
            let event = try await NDKEventBuilder(ndk: ndk)
                .content(content)
                .kind(EventKind.textNote)
                .build(signer: signer)
            
            // Store the event ID for monitoring
            publishedEventId = event.id
            
            // Start monitoring confirmation state
            monitoringTask = Task {
                await monitorConfirmationState(eventId: event.id)
            }
            
            // Publish with optimistic dispatch
            let publishedRelays = try await ndk.publish(event)
            
            print("Published to \(publishedRelays.count) relays")
            
            // Wait a moment for final confirmation
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Check final state
            if case .confirmed = confirmationState {
                // Success - dismiss after brief delay
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await MainActor.run {
                    dismiss()
                }
            }
            
        } catch {
            publishError = error
            isPublishing = false
        }
    }
    
    private func monitorConfirmationState(eventId: String) async {
        guard let cache = ndkManager.ndk?.cache else { return }
        
        // Monitor confirmation state changes
        while !Task.isCancelled {
            if let state = await cache.getEventConfirmationState(eventId: eventId) {
                await MainActor.run {
                    self.confirmationState = state
                    
                    // Stop publishing indicator once we have any confirmation
                    if case .confirmed = state {
                        self.isPublishing = false
                    }
                }
                
                // Stop monitoring once fully confirmed
                if case .confirmed = state {
                    break
                }
            }
            
            // Check every 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

#Preview {
    ComposeView()
        .environment(NDKAuthManager.shared)
        .environment(NDKManager.shared)
}