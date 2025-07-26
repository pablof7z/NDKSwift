import SwiftUI
import PhotosUI

struct CreatePostView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var caption = ""
    @State private var showCamera = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Photo picker
                if selectedImages.isEmpty {
                    VStack(spacing: 24) {
                        PhotosPicker(selection: $selectedItems,
                                   maxSelectionCount: 4,
                                   matching: .images) {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Select Photos")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showCamera = true }) {
                            Label("Take Photo", systemImage: "camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(hex: "667eea"))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                } else {
                    // Selected images preview
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedImages, id: \.self) { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 200, height: 200)
                                    .clipped()
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                    .frame(height: 220)
                    
                    // Caption input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Caption")
                            .font(.headline)
                        
                        TextEditor(text: $caption)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Post button
                    Button(action: createPost) {
                        Text("Post")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !selectedImages.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            selectedImages = []
                            selectedItems = []
                            caption = ""
                        }
                    }
                }
            }
            .onChange(of: selectedItems) { oldValue, newValue in
                Task {
                    selectedImages = []
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImages.append(image)
                        }
                    }
                }
            }
        }
    }
    
    private func createPost() {
        // Implement post creation logic
        print("Creating post with \(selectedImages.count) images")
    }
}