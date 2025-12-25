import Kingfisher
import SwiftUI

/// Fullscreen image viewer with swipe navigation, zoom, and dismiss gestures
public struct FullscreenImageViewer: View {
    let urls: [URL]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool

    @State private var scales: [Int: CGFloat] = [:]
    @State private var lastScales: [Int: CGFloat] = [:]
    @State private var offsets: [Int: CGSize] = [:]
    @State private var lastOffsets: [Int: CGSize] = [:]
    @GestureState private var dragOffset: CGSize = .zero
    @State private var showControls = true

    public init(urls: [URL], selectedIndex: Binding<Int>, isPresented: Binding<Bool>) {
        self.urls = urls
        self._selectedIndex = selectedIndex
        self._isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(dismissOpacity)

                #if os(iOS) || os(tvOS) || os(visionOS)
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            zoomableImage(url: url, index: index, geometry: geometry)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .offset(y: currentScale == 1.0 ? dragOffset.height : 0)
                    .gesture(dismissGesture)
                #else
                    // macOS fallback
                    zoomableImage(url: urls[selectedIndex], index: selectedIndex, geometry: geometry)
                #endif

                if showControls {
                    controlsOverlay
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
            }
        }
        #if os(iOS)
        .statusBarHidden(!showControls)
        #endif
    }

    // MARK: - Zoomable Image

    private func zoomableImage(url: URL, index: Int, geometry: GeometryProxy) -> some View {
        let scale = scales[index, default: 1.0]
        let offset = offsets[index, default: .zero]

        return KFImage(url)
            .resizable()
            .placeholder {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture(for: index))
            .gesture(scale > 1.0 ? panGesture(for: index, in: geometry) : nil)
            .onTapGesture(count: 2) {
                doubleTapZoom(index: index)
            }
    }

    // MARK: - Gestures

    private func magnificationGesture(for index: Int) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let lastScale = lastScales[index, default: 1.0]
                let newScale = lastScale * value
                scales[index] = min(max(newScale, 0.5), 5.0)
            }
            .onEnded { _ in
                let scale = scales[index, default: 1.0]
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3)) {
                        scales[index] = 1.0
                        offsets[index] = .zero
                    }
                    lastScales[index] = 1.0
                    lastOffsets[index] = .zero
                } else if scale > 4.0 {
                    withAnimation(.spring(response: 0.3)) {
                        scales[index] = 4.0
                    }
                    lastScales[index] = 4.0
                } else {
                    lastScales[index] = scale
                }
            }
    }

    private func panGesture(for index: Int, in geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let lastOffset = lastOffsets[index, default: .zero]
                offsets[index] = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffsets[index] = offsets[index, default: .zero]
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                if currentScale == 1.0 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if currentScale == 1.0 && abs(value.translation.height) > 150 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            }
    }

    // MARK: - Double Tap Zoom

    private func doubleTapZoom(index: Int) {
        let currentScale = scales[index, default: 1.0]
        withAnimation(.spring(response: 0.3)) {
            if currentScale > 1.0 {
                scales[index] = 1.0
                offsets[index] = .zero
                lastScales[index] = 1.0
                lastOffsets[index] = .zero
            } else {
                scales[index] = 2.0
                lastScales[index] = 2.0
            }
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
            }

            Spacer()

            if urls.count > 1 {
                pageIndicator
                    .padding(.bottom, 32)
            }
        }
    }

    private var pageIndicator: some View {
        Text("\(selectedIndex + 1) of \(urls.count)")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)
    }

    // MARK: - Helpers

    private var currentScale: CGFloat {
        scales[selectedIndex, default: 1.0]
    }

    private var dismissOpacity: Double {
        if currentScale == 1.0 {
            let progress = min(abs(dragOffset.height) / 300.0, 0.5)
            return 1.0 - Double(progress)
        }
        return 1.0
    }
}
