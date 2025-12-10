import SwiftUI

struct FullscreenImageViewer: View {
    let url: URL
    let blurhash: String?
    let aspectRatio: CGFloat?
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                CachedAsyncImage(url: url, blurhash: blurhash, aspectRatio: aspectRatio) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .gesture(magnificationGesture)
                        .simultaneousGesture(dragGesture)
                        .onTapGesture(count: 2) { handleDoubleTap() }
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden()
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white.opacity(0.8))
                .padding()
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 1), 5)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 {
                    withAnimation(.spring()) {
                        scale = 1.0
                        offset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                if scale > 1 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if scale > 1 {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                } else if abs(value.translation.height) > 100 {
                    isPresented = false
                }
            }
    }

    private func handleDoubleTap() {
        withAnimation(.spring()) {
            if scale > 1 {
                scale = 1.0
                offset = .zero
            } else {
                scale = 2.5
            }
        }
    }
}
