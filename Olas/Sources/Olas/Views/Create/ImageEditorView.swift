import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

public enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case vivid = "Vivid"
    case dramatic = "Dramatic"
    case mono = "Mono"
    case noir = "Noir"
    case fade = "Fade"
    case warm = "Warm"
    case cool = "Cool"

    public var id: String { rawValue }
}

public struct ImageEditorView: View {
    @Binding var image: UIImage
    @Binding var isPresented: Bool
    let onComplete: (UIImage) -> Void

    @State private var selectedFilter: ImageFilter = .original
    @State private var filteredImage: UIImage?
    @State private var isProcessing = false

    private let context = CIContext()

    public init(image: Binding<UIImage>, isPresented: Binding<Bool>, onComplete: @escaping (UIImage) -> Void) {
        self._image = image
        self._isPresented = isPresented
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview
                if let displayImage = filteredImage ?? Optional(image) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                        .clipped()
                }

                Spacer()

                // Filter selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ImageFilter.allCases) { filter in
                            FilterThumbnail(
                                filter: filter,
                                image: image,
                                isSelected: selectedFilter == filter,
                                context: context
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Button("Done") {
                            let finalImage = filteredImage ?? image
                            onComplete(finalImage)
                        }
                    }
                }
            }
            .onChange(of: selectedFilter) { _, newFilter in
                applyFilter(newFilter)
            }
        }
    }

    private func applyFilter(_ filter: ImageFilter) {
        guard filter != .original else {
            filteredImage = nil
            return
        }

        isProcessing = true

        Task.detached(priority: .userInitiated) {
            let result = Self.applyFilterToImage(image, filter: filter, context: context)
            await MainActor.run {
                filteredImage = result
                isProcessing = false
            }
        }
    }

    static func applyFilterToImage(_ image: UIImage, filter: ImageFilter, context: CIContext) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let filtered: CIImage?

        switch filter {
        case .original:
            return image

        case .vivid:
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = ciImage
            vibrance.amount = 0.5
            filtered = vibrance.outputImage

        case .dramatic:
            let contrast = CIFilter.colorControls()
            contrast.inputImage = ciImage
            contrast.contrast = 1.3
            contrast.saturation = 0.8
            filtered = contrast.outputImage

        case .mono:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = ciImage
            filtered = mono.outputImage

        case .noir:
            let noir = CIFilter.photoEffectNoir()
            noir.inputImage = ciImage
            filtered = noir.outputImage

        case .fade:
            let fade = CIFilter.photoEffectFade()
            fade.inputImage = ciImage
            filtered = fade.outputImage

        case .warm:
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = ciImage
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 4500, y: 0)
            filtered = temp.outputImage

        case .cool:
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = ciImage
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 9000, y: 0)
            filtered = temp.outputImage
        }

        guard let outputImage = filtered,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

struct FilterThumbnail: View {
    let filter: ImageFilter
    let image: UIImage
    let isSelected: Bool
    let context: CIContext
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? OlasTheme.Colors.deepTeal : .clear, lineWidth: 3)
                        )
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 70, height: 70)
                        .cornerRadius(8)
                }

                Text(filter.rawValue)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? OlasTheme.Colors.deepTeal : .secondary)
            }
        }
        .task {
            await generateThumbnail()
        }
    }

    private func generateThumbnail() async {
        let size = CGSize(width: 140, height: 140)
        let renderer = UIGraphicsImageRenderer(size: size)
        let smallImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        if filter == .original {
            thumbnail = smallImage
        } else {
            thumbnail = await Task.detached(priority: .utility) {
                ImageEditorView.applyFilterToImage(smallImage, filter: filter, context: context)
            }.value
        }
    }
}
