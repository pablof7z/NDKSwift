import SwiftUI
import PhotosUI

struct CreateStoryView: View {
    @ObservedObject var storiesManager: StoriesManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedImage: UIImage?
    @State private var storyText = ""
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var isUploading = false
    @State private var selectedBackground = 0
    
    let gradientBackgrounds: [LinearGradient] = [
        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if selectedImage != nil {
                    Color.black.ignoresSafeArea()
                } else {
                    gradientBackgrounds[selectedBackground]
                        .ignoresSafeArea()
                }
                
                VStack {
                    // Content area
                    ZStack {
                        if let image = selectedImage {
                            // Show selected image
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Text-only story
                            VStack {
                                Spacer()
                                
                                TextField("What's on your mind?", text: $storyText, axis: .vertical)
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                                            .fill(Color.black.opacity(0.3))
                                    )
                                    .padding()
                                
                                Spacer()
                            }
                        }
                        
                        // Text overlay on image
                        if selectedImage != nil && !storyText.isEmpty {
                            VStack {
                                Spacer()
                                
                                Text(storyText)
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                                            .fill(Color.black.opacity(0.6))
                                    )
                                    .padding()
                                
                                Spacer()
                                    .frame(height: 100)
                            }
                        }
                    }
                    
                    // Bottom controls
                    VStack(spacing: OlasDesign.Spacing.md) {
                        if selectedImage == nil {
                            // Background selector for text-only stories
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OlasDesign.Spacing.sm) {
                                    ForEach(0..<gradientBackgrounds.count, id: \.self) { index in
                                        Circle()
                                            .fill(gradientBackgrounds[index])
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: selectedBackground == index ? 3 : 0)
                                            )
                                            .onTapGesture {
                                                withAnimation(.spring(response: 0.3)) {
                                                    selectedBackground = index
                                                }
                                                OlasDesign.Haptic.selection()
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Action buttons
                        HStack(spacing: OlasDesign.Spacing.lg) {
                            // Photo picker
                            Button {
                                showingImagePicker = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 24))
                                    Text("Gallery")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                            }
                            
                            // Camera
                            Button {
                                showingCamera = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 24))
                                    Text("Camera")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                            }
                            
                            if selectedImage != nil {
                                // Remove image
                                Button {
                                    withAnimation {
                                        selectedImage = nil
                                        storyText = ""
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 24))
                                        Text("Remove")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                        }
                        .padding()
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.5))
                        )
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Create Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Share") {
                        Task {
                            await shareStory()
                        }
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .disabled(selectedImage == nil && storyText.isEmpty)
                    .opacity((selectedImage == nil && storyText.isEmpty) ? 0.5 : 1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(capturedImage: $selectedImage)
        }
        .overlay {
            if isUploading {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    
                    VStack(spacing: OlasDesign.Spacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Sharing your story...")
                            .font(OlasDesign.Typography.body)
                            .foregroundColor(.white)
                    }
                    .padding(OlasDesign.Spacing.xl)
                    .background(
                        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                            .fill(Color.black.opacity(0.8))
                    )
                }
            }
        }
    }
    
    private func shareStory() async {
        isUploading = true
        defer { isUploading = false }
        
        // Convert image to data and create story
        if let selectedImage = selectedImage,
           let imageData = selectedImage.jpegData(compressionQuality: 0.8) {
            do {
                try await storiesManager.createStory(
                    with: imageData,
                    caption: storyText.isEmpty ? "" : storyText
                )
            } catch {
                print("Failed to create story: \(error)")
            }
        }
        
        dismiss()
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}