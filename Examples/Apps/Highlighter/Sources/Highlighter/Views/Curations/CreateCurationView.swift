import SwiftUI
import NDKSwift

struct CreateCurationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var curationName = ""
    @State private var curationTitle = ""
    @State private var description = ""
    @State private var imageUrl = ""
    @State private var isPublishing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header image placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.highlighterPurple.opacity(0.3),
                                        Color.highlighterOrange.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 200)
                        
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                            
                            Text("Add Cover Image")
                                .font(.highlighterCaption)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Form fields
                    VStack(spacing: 20) {
                        // Name (identifier)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Curation ID", systemImage: "number")
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                            
                            TextField("my-reading-list", text: $curationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Title", systemImage: "textformat")
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                            
                            TextField("My Reading List", text: $curationTitle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                            
                            TextEditor(text: $description)
                                .font(.highlighterBody)
                                .padding(8)
                                .background(Color.highlighterCardBackground)
                                .cornerRadius(8)
                                .frame(minHeight: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        // Image URL
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Cover Image URL", systemImage: "link")
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                            
                            TextField("https://...", text: $imageUrl)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .padding(.horizontal)
                    
                    // Info box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.highlighterPurple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What are Article Curations?")
                                .font(.highlighterCaption)
                                .fontWeight(.medium)
                            
                            Text("Create themed collections of articles, highlights, and content. You can add items to your curation later.")
                                .font(.highlighterCaption)
                                .foregroundColor(.highlighterSecondaryText)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.highlighterPurple.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Create button
                    Button(action: createCuration) {
                        HStack {
                            if isPublishing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "folder.badge.plus")
                                Text("Create Curation")
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
                        .disabled(curationName.isEmpty || curationTitle.isEmpty || isPublishing)
                        .opacity(curationName.isEmpty || curationTitle.isEmpty ? 0.6 : 1)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(Color.highlighterBackground)
            .navigationTitle("New Curation")
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
    }
    
    private func createCuration() {
        guard !curationName.isEmpty, !curationTitle.isEmpty else { return }
        
        isPublishing = true
        HapticType.light.trigger()
        
        Task {
            do {
                try await appState.createCuration(
                    name: curationName,
                    title: curationTitle,
                    description: description.isEmpty ? nil : description,
                    image: imageUrl.isEmpty ? nil : imageUrl
                )
                
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
    CreateCurationView()
        .environmentObject(AppState())
}