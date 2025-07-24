import SwiftUI
import NDKSwift

struct CreateHighlightView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var highlightText = ""
    @State private var comment = ""
    @State private var url = ""
    @State private var context = ""
    @State private var isPublishing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // UI State
    @State private var selectedTab = 0
    @State private var showUrlPaste = false
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.highlighterBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab selector
                    Picker("Source", selection: $selectedTab) {
                        Text("Manual").tag(0)
                        Text("From URL").tag(1)
                        Text("From Nostr").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Highlight text input
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Highlight", systemImage: "highlighter")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                                
                                TextEditor(text: $highlightText)
                                    .font(.highlighterQuote)
                                    .padding(12)
                                    .background(Color.highlighterCardBackground)
                                    .cornerRadius(12)
                                    .frame(minHeight: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.highlighterPurple.opacity(highlightText.isEmpty ? 0 : 0.3), lineWidth: 2)
                                    )
                            }
                            .padding(.horizontal)
                            
                            // Context input (if from URL)
                            if selectedTab == 1 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Context", systemImage: "text.quote")
                                        .font(.highlighterCaption)
                                        .foregroundColor(.highlighterSecondaryText)
                                    
                                    TextEditor(text: $context)
                                        .font(.highlighterBody)
                                        .padding(12)
                                        .background(Color.highlighterCardBackground)
                                        .cornerRadius(12)
                                        .frame(minHeight: 60)
                                }
                                .padding(.horizontal)
                            }
                            
                            // Comment input
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Your Thoughts", systemImage: "bubble.left")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                                
                                TextEditor(text: $comment)
                                    .font(.highlighterBody)
                                    .padding(12)
                                    .background(Color.highlighterCardBackground)
                                    .cornerRadius(12)
                                    .frame(minHeight: 80)
                            }
                            .padding(.horizontal)
                            
                            // Source URL input
                            if selectedTab != 2 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Source URL", systemImage: "link")
                                        .font(.highlighterCaption)
                                        .foregroundColor(.highlighterSecondaryText)
                                    
                                    HStack {
                                        TextField("https://...", text: $url)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        
                                        Button(action: { 
                                            if let pasteboardString = UIPasteboard.general.string {
                                                url = pasteboardString
                                            }
                                        }) {
                                            Image(systemName: "doc.on.clipboard")
                                                .foregroundColor(.highlighterPurple)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Publish button
                            Button(action: publishHighlight) {
                                HStack {
                                    if isPublishing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                        Text("Publish Highlight")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [.highlighterPurple, .highlighterPurple.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .disabled(highlightText.isEmpty || isPublishing)
                                .opacity(highlightText.isEmpty ? 0.6 : 1)
                                .scaleEffect(isPublishing ? 0.95 : 1)
                                .animation(.easeInOut(duration: 0.2), value: isPublishing)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, keyboardHeight > 0 ? 20 : 60)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Create Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.highlighterPurple)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.3)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = 0
            }
        }
    }
    
    private func publishHighlight() {
        guard !highlightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isPublishing = true
        HapticType.light.trigger()
        
        Task {
            do {
                guard let ndk = appState.ndk, let signer = appState.activeSigner else {
                    throw AuthError.noSigner
                }
                
                // Build tags for the highlight
                var tags: [[String]] = []
                
                if !context.isEmpty {
                    tags.append(["context", context])
                }
                
                if !url.isEmpty {
                    tags.append(["r", url])
                }
                
                if !comment.isEmpty {
                    tags.append(["comment", comment])
                }
                
                // Create and publish the event directly
                let event = try await NDKEventBuilder(ndk: ndk)
                    .kind(9802)
                    .content(highlightText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .tags(tags)
                    .build(signer: signer)
                
                _ = try await ndk.publish(event)
                
                await MainActor.run {
                    HapticType.success.trigger()
                    isPublishing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isPublishing = false
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticType.error.trigger()
                }
            }
        }
    }
}

#Preview {
    CreateHighlightView()
        .environmentObject(AppState())
}