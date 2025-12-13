import LinkPresentation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif
import NDKSwiftCore

/// A reusable URL preview component that displays rich link previews or embedded images
public struct NDKUIURLPreview: View {
    let url: URL
    let style: Style

    @State private var linkMetadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var isImage = false
    @State private var imageLoadFailed = false
    @State private var showFullScreenImage = false

    public enum Style {
        case full // Full preview with image, title, and description
        case compact // Smaller preview for inline display
        case minimal // Just icon and title
        case embedded // For embedding in other content
    }

    public init(url: URL, style: Style = .full) {
        self.url = url
        self.style = style
    }

    public var body: some View {
        Group {
            if isImage && !imageLoadFailed {
                imagePreview
            } else if let metadata = linkMetadata {
                linkPreview(metadata: metadata)
            } else if isLoading {
                loadingView
            }
        }
        .onAppear {
            checkIfImage()
            if !isImage {
                fetchLinkMetadata()
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullScreenImage) {
            NDKUIFullScreenImage(url: url, isPresented: $showFullScreenImage)
        }
        #else
        .sheet(isPresented: $showFullScreenImage) {
                    NDKUIFullScreenImage(url: url, isPresented: $showFullScreenImage)
                }
        #endif
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: imageMaxHeight)
                .cornerRadius(cornerRadius)
                .shadow(color: Color.black.opacity(OpacityConstants.shadow), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.ndkBorder, lineWidth: 0.5)
                )
                .padding(.vertical, 4)
                .onTapGesture {
                    showFullScreenImage = true
                }
        } placeholder: {
            ProgressView()
                .frame(maxHeight: imageHeight)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Link Preview

    private func linkPreview(metadata: LPLinkMetadata) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Preview image if available and not minimal style
            if style != .minimal, let imageProvider = metadata.imageProvider {
                LinkPreviewImage(imageProvider: imageProvider, style: style)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    // Site icon
                    if let iconProvider = metadata.iconProvider {
                        LinkPreviewIcon(iconProvider: iconProvider)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // Title
                        if let title = metadata.title {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.medium)
                                .lineLimit(titleLineLimit)
                                .foregroundColor(.primary)
                        }

                        // URL host
                        Text(url.host ?? url.absoluteString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                // Description if not minimal style
                if style != .minimal, let description = metadata.value(forKey: "_summary") as? String {
                    Text(description)
                        .font(descriptionFont)
                        .foregroundColor(.secondary)
                        .lineLimit(descriptionLineLimit)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
        .onTapGesture {
            #if canImport(UIKit)
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
            #endif
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading preview...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.ndkTertiaryBackground)
        .cornerRadius(cornerRadius)
    }

    // MARK: - Helper Methods

    private func checkIfImage() {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg"]
        let pathExtension = url.pathExtension.lowercased()
        isImage = imageExtensions.contains(pathExtension)

        // Also check content type from URL if possible
        if !isImage {
            let urlString = url.absoluteString.lowercased()
            for ext in imageExtensions {
                if urlString.contains(".\(ext)?") || urlString.contains(".\(ext)&") {
                    isImage = true
                    break
                }
            }
        }
    }

    private func fetchLinkMetadata() {
        Task {
            let provider = LPMetadataProvider()
            provider.timeout = 5 // 5 second timeout

            do {
                let metadata = try await provider.startFetchingMetadata(for: url)
                await MainActor.run {
                    self.linkMetadata = metadata
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Style Properties

    private var imageHeight: CGFloat {
        switch style {
        case .full: return 200
        case .compact: return 120
        case .minimal: return 0
        case .embedded: return 150
        }
    }

    private var imageMaxHeight: CGFloat {
        switch style {
        case .full: return 500
        case .compact: return 200
        case .minimal: return 0
        case .embedded: return 300
        }
    }

    private var spacing: CGFloat {
        switch style {
        case .full: return 8
        case .compact: return 6
        case .minimal: return 4
        case .embedded: return 6
        }
    }

    private var titleFont: Font {
        switch style {
        case .full: return .subheadline
        case .compact: return .caption
        case .minimal: return .caption
        case .embedded: return .caption
        }
    }

    private var titleLineLimit: Int {
        switch style {
        case .full: return 2
        case .compact: return 2
        case .minimal: return 1
        case .embedded: return 2
        }
    }

    private var descriptionFont: Font {
        switch style {
        case .full: return .caption
        case .compact: return .caption2
        case .minimal: return .caption2
        case .embedded: return .caption2
        }
    }

    private var descriptionLineLimit: Int {
        switch style {
        case .full: return 3
        case .compact: return 2
        case .minimal: return 0
        case .embedded: return 2
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .full: return 12
        case .compact: return 10
        case .minimal: return 8
        case .embedded: return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .full: return 8
        case .compact: return 6
        case .minimal: return 4
        case .embedded: return 6
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .full: return Color.ndkSecondaryBackground
        case .compact: return Color.ndkSecondaryBackground
        case .minimal: return Color.ndkTertiaryBackground
        case .embedded: return Color.ndkTertiaryBackground
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .full: return 12
        case .compact: return 10
        case .minimal: return 8
        case .embedded: return 10
        }
    }
}

// MARK: - LinkPreviewImage

private struct LinkPreviewImage: View {
    let imageProvider: NSItemProvider
    let style: NDKUIURLPreview.Style

    #if canImport(UIKit)
        @State private var previewImage: UIImage?
    #elseif canImport(AppKit)
        @State private var previewImage: NSImage?
    #endif

    var body: some View {
        Group {
            if let image = previewImage {
                #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: imageHeight)
                        .clipped()
                        .cornerRadius(8)
                #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: imageHeight)
                        .clipped()
                        .cornerRadius(8)
                #endif
            }
        }
    }

    private var imageHeight: CGFloat {
        switch style {
        case .full: return 180
        case .compact: return 100
        case .minimal: return 0
        case .embedded: return 120
        }
    }

    init(imageProvider: NSItemProvider, style: NDKUIURLPreview.Style) {
        self.imageProvider = imageProvider
        self.style = style
        loadImage()
    }

    private func loadImage() {
        imageProvider.loadDataRepresentation(for: .image) { data, _ in
            if let data = data {
                #if canImport(UIKit)
                    if let image = UIImage(data: data) {
                        Task { @MainActor in
                            self.previewImage = image
                        }
                    }
                #elseif canImport(AppKit)
                    if let image = NSImage(data: data) {
                        Task { @MainActor in
                            self.previewImage = image
                        }
                    }
                #endif
            }
        }
    }
}

// MARK: - LinkPreviewIcon

private struct LinkPreviewIcon: View {
    let iconProvider: NSItemProvider

    #if canImport(UIKit)
        @State private var iconImage: UIImage?
    #elseif canImport(AppKit)
        @State private var iconImage: NSImage?
    #endif

    var body: some View {
        Group {
            if let icon = iconImage {
                #if canImport(UIKit)
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                #elseif canImport(AppKit)
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                #endif
            }
        }
    }

    init(iconProvider: NSItemProvider) {
        self.iconProvider = iconProvider
        loadIcon()
    }

    private func loadIcon() {
        iconProvider.loadDataRepresentation(for: .image) { data, _ in
            if let data = data {
                #if canImport(UIKit)
                    if let image = UIImage(data: data) {
                        Task { @MainActor in
                            self.iconImage = image
                        }
                    }
                #elseif canImport(AppKit)
                    if let image = NSImage(data: data) {
                        Task { @MainActor in
                            self.iconImage = image
                        }
                    }
                #endif
            }
        }
    }
}

// MARK: - NDKUIFullScreenImage

/// Full screen image viewer with drag to dismiss and pinch to zoom
public struct NDKUIFullScreenImage: View {
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

    public var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Image
            CachedAsyncImage(url: url) { image in
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
            } placeholder: {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
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
        #if os(iOS)
        .statusBarHidden()
        #endif
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

// MARK: - Preview

#if DEBUG
    struct NDKUIURLPreview_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 20) {
                NDKUIURLPreview(url: URL(string: "https://example.com")!, style: .full)
                NDKUIURLPreview(url: URL(string: "https://example.com/image.jpg")!, style: .full)
                NDKUIURLPreview(url: URL(string: "https://example.com")!, style: .compact)
                NDKUIURLPreview(url: URL(string: "https://example.com")!, style: .minimal)
            }
            .padding()
        }
    }
#endif
