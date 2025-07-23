import SwiftUI

struct FullScreenImageView: View {
    let url: URL
    @Binding var isPresented: Bool
    
    @State private var dragOffset: CGSize = .zero
    @State private var dragVelocity: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var imageOpacity: Double = 0
    @State private var backgroundOpacity: Double = 0
    @GestureState private var magnifyBy = 1.0
    
    private let dismissThreshold: CGFloat = 100
    private let velocityThreshold: CGFloat = 500
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            // Image
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale * magnifyBy)
                        .offset(x: imageOffset.width + dragOffset.width,
                                y: imageOffset.height + dragOffset.height)
                        .opacity(imageOpacity)
                        .gesture(dragGesture)
                        .gesture(magnificationGesture)
                        .gesture(doubleTapGesture)
                        
                case .empty:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        
                case .failure(_):
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                        
                @unknown default:
                    EmptyView()
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7), Color.black.opacity(0.3))
                    }
                    .padding()
                }
                Spacer()
            }
            .opacity(imageOpacity)
        }
        .statusBarHidden()
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                imageOpacity = 1.0
                backgroundOpacity = 0.9
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            imageOpacity = 0
            backgroundOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale == 1.0 {
                    // Only allow dragging when not zoomed
                    dragOffset = value.translation
                    
                    // Calculate opacity based on drag distance
                    let distance = abs(value.translation.height)
                    let opacity = 1.0 - min(distance / 300, 0.5)
                    imageOpacity = Double(opacity)
                    backgroundOpacity = Double(opacity * 0.9)
                } else {
                    // When zoomed, pan the image
                    imageOffset = CGSize(
                        width: value.translation.width + imageOffset.width,
                        height: value.translation.height + imageOffset.height
                    )
                }
            }
            .onEnded { value in
                if scale == 1.0 {
                    let shouldDismiss = abs(value.translation.height) > dismissThreshold ||
                                       abs(value.predictedEndTranslation.height) > velocityThreshold
                    
                    if shouldDismiss {
                        // Dismiss with animation
                        dismiss()
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                            imageOpacity = 1.0
                            backgroundOpacity = 0.9
                        }
                    }
                }
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                lastScale *= value
                scale = min(max(lastScale, 1.0), 4.0)
                lastScale = scale
                
                // Reset offset if scale is back to 1
                if scale == 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        imageOffset = .zero
                    }
                }
            }
    }
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                        imageOffset = .zero
                    } else {
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
            }
    }
}

// Preview provider
struct FullScreenImageView_Previews: PreviewProvider {
    static var previews: some View {
        FullScreenImageView(
            url: URL(string: "https://example.com/image.jpg")!,
            isPresented: .constant(true)
        )
    }
}