import SwiftUI

// MARK: - Multi-Image Layout Component

struct OlasMultiImageView: View {
    let imageURLs: [String]
    @State private var loadedImages: [String: Image] = [:]
    @State private var failedImages: Set<String> = []
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            
            switch imageURLs.count {
            case 1:
                singleImageLayout(width: width)
            case 2:
                doubleImageLayout(width: width)
            case 3:
                tripleImageLayout(width: width)
            case 4...:
                quadImageLayout(width: width)
            default:
                EmptyView()
            }
        }
        .aspectRatio(4/5, contentMode: .fit)
        .background(OlasDesign.Colors.background)
    }
    
    // MARK: - Layout Components
    
    @ViewBuilder
    private func singleImageLayout(width: CGFloat) -> some View {
        imageView(for: imageURLs[0], aspectRatio: 4/5)
    }
    
    @ViewBuilder
    private func doubleImageLayout(width: CGFloat) -> some View {
        HStack(spacing: 1) {
            imageView(for: imageURLs[0], aspectRatio: 8/9)
            imageView(for: imageURLs[1], aspectRatio: 8/9)
        }
    }
    
    @ViewBuilder
    private func tripleImageLayout(width: CGFloat) -> some View {
        HStack(spacing: 1) {
            // Hero image on left (8:9)
            imageView(for: imageURLs[0], aspectRatio: 8/9)
                .frame(width: width * 0.6)
            
            // Two stacked images on right (1:1)
            VStack(spacing: 1) {
                imageView(for: imageURLs[1], aspectRatio: 1)
                imageView(for: imageURLs[2], aspectRatio: 1)
            }
            .frame(width: width * 0.4 - 1)
        }
    }
    
    @ViewBuilder
    private func quadImageLayout(width: CGFloat) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                imageView(for: imageURLs[0], aspectRatio: 1)
                imageView(for: imageURLs[1], aspectRatio: 1)
            }
            HStack(spacing: 1) {
                imageView(for: imageURLs[2], aspectRatio: 1)
                if imageURLs.count > 3 {
                    ZStack {
                        imageView(for: imageURLs[3], aspectRatio: 1)
                        
                        // Show +N overlay for additional images
                        if imageURLs.count > 4 {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    Text("+\(imageURLs.count - 4)")
                                        .font(OlasDesign.Typography.title)
                                        .foregroundColor(.white)
                                        .olasTextShadow()
                                )
                        }
                    }
                } else {
                    imageView(for: imageURLs[2], aspectRatio: 1)
                }
            }
        }
    }
    
    // MARK: - Image View Builder
    
    @ViewBuilder
    private func imageView(for urlString: String, aspectRatio: CGFloat) -> some View {
        if let image = loadedImages[urlString] {
            // Already loaded
            image
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fill)
                .clipped()
        } else if failedImages.contains(urlString) {
            // Failed to load
            Rectangle()
                .fill(OlasDesign.Colors.surface)
                .aspectRatio(aspectRatio, contentMode: .fill)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundColor(OlasDesign.Colors.textTertiary)
                )
        } else {
            // Loading
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .clipped()
                        .onAppear {
                            loadedImages[urlString] = image
                        }
                case .failure(_):
                    Rectangle()
                        .fill(OlasDesign.Colors.surface)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        )
                        .onAppear {
                            failedImages.insert(urlString)
                        }
                case .empty:
                    Rectangle()
                        .fill(OlasDesign.Colors.surface)
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        )
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Image Interaction Overlay

struct OlasImageInteractionOverlay: View {
    let imageURLs: [String]
    @State private var currentIndex: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Binding var isPresented: Bool
    
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            backgroundView
            imageViewer
            closeButton
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        Color.black
            .opacity(opacity)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(OlasDesign.Animation.spring) {
                    isPresented = false
                }
            }
    }
    
    @ViewBuilder
    private var imageViewer: some View {
        TabView(selection: $currentIndex) {
            ForEach(imageURLs.indices, id: \.self) { index in
                imageView(at: index)
                    .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: imageURLs.count > 1 ? .always : .never))
        #endif
        .offset(dragOffset)
    }
    
    @ViewBuilder
    private func imageView(at index: Int) -> some View {
        AsyncImage(url: URL(string: imageURLs[index])) { phase in
            switch phase {
            case .success(let image):
                zoomableImage(image)
            case .failure(_):
                failureView
            case .empty:
                loadingView
            @unknown default:
                EmptyView()
            }
        }
    }
    
    @ViewBuilder
    private func zoomableImage(_ image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(zoomGesture)
            .onTapGesture(count: 2) {
                toggleZoom()
            }
    }
    
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { value in
                handleZoomEnd()
            }
            .simultaneously(with: dragGesture)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                handleDrag(value: value)
            }
            .onEnded { value in
                handleDragEnd(value: value)
            }
    }
    
    private func handleZoomEnd() {
        lastScale = scale
        withAnimation(OlasDesign.Animation.spring) {
            if scale < 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else if scale > 4 {
                scale = 4
                lastScale = 4
            }
        }
    }
    
    private func handleDrag(value: DragGesture.Value) {
        if scale > 1 {
            offset = CGSize(
                width: lastOffset.width + value.translation.width,
                height: lastOffset.height + value.translation.height
            )
        } else {
            dragOffset = value.translation
            let progress = abs(value.translation.height) / 200
            opacity = 1 - min(progress, 0.5)
        }
    }
    
    private func handleDragEnd(value: DragGesture.Value) {
        if scale > 1 {
            lastOffset = offset
        } else {
            if abs(value.translation.height) > 100 {
                withAnimation(OlasDesign.Animation.spring) {
                    isPresented = false
                }
            } else {
                withAnimation(OlasDesign.Animation.spring) {
                    dragOffset = .zero
                    opacity = 1
                }
            }
        }
    }
    
    private func toggleZoom() {
        withAnimation(OlasDesign.Animation.spring) {
            if scale > 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2
                lastScale = 2
            }
        }
        #if os(iOS)
        OlasDesign.Haptic.impact(.light)
        #else
        OlasDesign.Haptic.impact(0)
        #endif
    }
    
    @ViewBuilder
    private var failureView: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            Text("Failed to load image")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
    }
    
    @ViewBuilder
    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(1.5)
    }
    
    @ViewBuilder
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(OlasDesign.Animation.spring) {
                        isPresented = false
                    }
                    OlasDesign.Haptic.selection()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, Color.white.opacity(0.2))
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .padding(OlasDesign.Spacing.lg)
            }
            Spacer()
        }
    }
}

// MARK: - Preview

struct OlasMultiImageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            OlasMultiImageView(imageURLs: ["https://example.com/1.jpg"])
                .frame(height: 400)
            
            OlasMultiImageView(imageURLs: ["https://example.com/1.jpg", "https://example.com/2.jpg"])
                .frame(height: 400)
            
            OlasMultiImageView(imageURLs: ["https://example.com/1.jpg", "https://example.com/2.jpg", "https://example.com/3.jpg"])
                .frame(height: 400)
            
            OlasMultiImageView(imageURLs: ["https://example.com/1.jpg", "https://example.com/2.jpg", "https://example.com/3.jpg", "https://example.com/4.jpg", "https://example.com/5.jpg"])
                .frame(height: 400)
        }
        .padding()
        .background(OlasDesign.Colors.background)
    }
}