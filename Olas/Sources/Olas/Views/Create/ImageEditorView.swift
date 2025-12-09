import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Filter Definitions

enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case clarendon = "Clarendon"
    case gingham = "Gingham"
    case moon = "Moon"
    case lark = "Lark"
    case reyes = "Reyes"
    case juno = "Juno"
    case slumber = "Slumber"
    case crema = "Crema"
    case ludwig = "Ludwig"
    case aden = "Aden"
    case perpetua = "Perpetua"

    var id: String { rawValue }
}

enum ImageAdjustment: String, CaseIterable, Identifiable {
    case brightness = "Brightness"
    case contrast = "Contrast"
    case saturation = "Saturation"
    case warmth = "Warmth"
    case shadows = "Shadows"
    case highlights = "Highlights"
    case vignette = "Vignette"
    case sharpen = "Sharpen"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.righthalf.filled"
        case .saturation: return "drop.fill"
        case .warmth: return "thermometer.medium"
        case .shadows: return "square.lefthalf.filled"
        case .highlights: return "bolt.fill"
        case .vignette: return "camera.aperture"
        case .sharpen: return "triangle"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: return -1.0...1.0
        case .contrast: return 0.5...2.0
        case .saturation: return 0.0...2.0
        case .warmth: return -1.0...1.0
        case .shadows: return -1.0...1.0
        case .highlights: return -1.0...1.0
        case .vignette: return 0.0...2.0
        case .sharpen: return 0.0...2.0
        }
    }

    var defaultValue: Double {
        switch self {
        case .brightness: return 0.0
        case .contrast: return 1.0
        case .saturation: return 1.0
        case .warmth: return 0.0
        case .shadows: return 0.0
        case .highlights: return 0.0
        case .vignette: return 0.0
        case .sharpen: return 0.0
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case square = "1:1"
    case portrait = "4:5"
    case landscape = "16:9"
    case free = "Free"

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .square: return 1.0
        case .portrait: return 4.0 / 5.0
        case .landscape: return 16.0 / 9.0
        case .free: return nil
        }
    }
}

enum EditorPanel: String, CaseIterable {
    case crop = "Crop"
    case filters = "Filters"
    case adjust = "Adjust"

    var icon: String {
        switch self {
        case .crop: return "crop"
        case .filters: return "camera.filters"
        case .adjust: return "slider.horizontal.3"
        }
    }
}

// MARK: - Image Editor View

struct ImageEditorView: View {
    @Binding var image: UIImage
    let onComplete: (UIImage) -> Void
    let onBack: () -> Void

    @State private var activePanel: EditorPanel? = .filters
    @State private var selectedFilter: ImageFilter = .original
    @State private var filterIntensity: Double = 1.0
    @State private var adjustments: [ImageAdjustment: Double] = [:]
    @State private var selectedAdjustment: ImageAdjustment = .brightness
    @State private var selectedAspectRatio: AspectRatio = .square
    @State private var rotation: Double = 0
    @State private var isFlipped = false

    @State private var processedImage: UIImage?
    @State private var isProcessing = false

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    init(image: Binding<UIImage>, onComplete: @escaping (UIImage) -> Void, onBack: @escaping () -> Void) {
        self._image = image
        self.onComplete = onComplete
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Image preview
                imagePreview
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // Toolbar
                editorToolbar

                // Panel content
                if let panel = activePanel {
                    panelContent(for: panel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Button("Next") {
                        Task {
                            await finalizeImage()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await updatePreview() }
        }
        .onChange(of: filterIntensity) { _, _ in
            Task { await updatePreview() }
        }
        .onChange(of: adjustments) { _, _ in
            Task { await updatePreview() }
        }
        .task {
            await updatePreview()
        }
    }

    private var imagePreview: some View {
        GeometryReader { geometry in
            let displayImage = processedImage ?? image
            Image(uiImage: displayImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                .clipped()
                .cornerRadius(8)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.45)
    }

    private var editorToolbar: some View {
        HStack(spacing: 0) {
            ForEach(EditorPanel.allCases, id: \.self) { panel in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activePanel = activePanel == panel ? nil : panel
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 22))
                        Text(panel.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(activePanel == panel ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        activePanel == panel
                            ? Color(white: 0.15)
                            : Color.clear
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.1))
        }
    }

    @ViewBuilder
    private func panelContent(for panel: EditorPanel) -> some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            switch panel {
            case .crop:
                cropPanel
            case .filters:
                filtersPanel
            case .adjust:
                adjustPanel
            }
        }
        .background(Color(white: 0.1))
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }

    // MARK: - Crop Panel

    private var cropPanel: some View {
        VStack(spacing: 16) {
            // Aspect ratios
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AspectRatio.allCases) { ratio in
                        AspectRatioButton(
                            ratio: ratio,
                            isSelected: selectedAspectRatio == ratio
                        ) {
                            selectedAspectRatio = ratio
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Rotate & Flip buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        rotation += 90
                    }
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(white: 0.15))
                        .cornerRadius(12)
                }

                Button {
                    withAnimation {
                        isFlipped.toggle()
                    }
                } label: {
                    Label("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(white: 0.15))
                        .cornerRadius(12)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .padding(.top, 8)
    }

    // MARK: - Filters Panel

    private var filtersPanel: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ImageFilter.allCases) { filter in
                        FilterThumbnail(
                            filter: filter,
                            sourceImage: image,
                            isSelected: selectedFilter == filter,
                            context: context
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Intensity slider
            if selectedFilter != .original {
                VStack(spacing: 8) {
                    HStack {
                        Text("Intensity")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(filterIntensity * 100))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Slider(value: $filterIntensity, in: 0...1)
                        .tint(OlasTheme.Colors.deepTeal)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer().frame(height: 34)
        }
        .padding(.top, 8)
    }

    // MARK: - Adjust Panel

    private var adjustPanel: some View {
        VStack(spacing: 16) {
            // Adjustment grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(ImageAdjustment.allCases) { adjustment in
                    AdjustmentButton(
                        adjustment: adjustment,
                        isSelected: selectedAdjustment == adjustment,
                        hasValue: adjustments[adjustment] != nil && adjustments[adjustment] != adjustment.defaultValue
                    ) {
                        selectedAdjustment = adjustment
                    }
                }
            }
            .padding(.horizontal, 16)

            // Slider for selected adjustment
            VStack(spacing: 8) {
                HStack {
                    Text(selectedAdjustment.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatAdjustmentValue(selectedAdjustment))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Slider(
                    value: Binding(
                        get: { adjustments[selectedAdjustment] ?? selectedAdjustment.defaultValue },
                        set: { adjustments[selectedAdjustment] = $0 }
                    ),
                    in: selectedAdjustment.range
                )
                .tint(OlasTheme.Colors.deepTeal)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer().frame(height: 34)
        }
        .padding(.top, 8)
    }

    private func formatAdjustmentValue(_ adjustment: ImageAdjustment) -> String {
        let value = adjustments[adjustment] ?? adjustment.defaultValue
        switch adjustment {
        case .brightness, .warmth, .shadows, .highlights:
            return String(format: "%+.0f", value * 100)
        case .contrast, .saturation:
            return String(format: "%.0f", (value - 1) * 100)
        case .vignette, .sharpen:
            return String(format: "%.0f", value * 50)
        }
    }

    // MARK: - Image Processing

    private func updatePreview() async {
        guard !isProcessing else { return }

        let filter = selectedFilter
        let intensity = filterIntensity
        let currentAdjustments = adjustments
        let sourceImage = image

        let result = await Task.detached(priority: .userInitiated) {
            self.applyEdits(to: sourceImage, filter: filter, intensity: intensity, adjustments: currentAdjustments)
        }.value

        await MainActor.run {
            processedImage = result
        }
    }

    private func finalizeImage() async {
        isProcessing = true
        defer { isProcessing = false }

        let filter = selectedFilter
        let intensity = filterIntensity
        let currentAdjustments = adjustments
        let sourceImage = image
        let currentRotation = rotation
        let flipped = isFlipped

        let result = await Task.detached(priority: .userInitiated) {
            var processed = self.applyEdits(to: sourceImage, filter: filter, intensity: intensity, adjustments: currentAdjustments)

            // Apply rotation and flip
            if currentRotation != 0 || flipped {
                processed = self.applyTransform(to: processed ?? sourceImage, rotation: currentRotation, flip: flipped)
            }

            return processed
        }.value

        await MainActor.run {
            onComplete(result ?? image)
        }
    }

    private func applyEdits(to image: UIImage, filter: ImageFilter, intensity: Double, adjustments: [ImageAdjustment: Double]) -> UIImage? {
        guard var ciImage = CIImage(image: image) else { return image }

        // Apply filter
        if filter != .original {
            if let filtered = applyFilter(filter, to: ciImage, intensity: intensity) {
                ciImage = filtered
            }
        }

        // Apply adjustments
        ciImage = applyAdjustments(adjustments, to: ciImage)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func applyFilter(_ filter: ImageFilter, to image: CIImage, intensity: Double) -> CIImage? {
        let filtered: CIImage?

        switch filter {
        case .original:
            return image

        case .clarendon:
            let contrast = CIFilter.colorControls()
            contrast.inputImage = image
            contrast.contrast = Float(1.0 + 0.2 * intensity)
            contrast.saturation = Float(1.0 + 0.35 * intensity)
            filtered = contrast.outputImage

        case .gingham:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.brightness = Float(0.05 * intensity)
            if let output = controls.outputImage {
                let hue = CIFilter.hueAdjust()
                hue.inputImage = output
                hue.angle = Float(-0.05 * intensity)
                filtered = hue.outputImage
            } else {
                filtered = nil
            }

        case .moon:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = image
            if let monoOutput = mono.outputImage {
                let contrast = CIFilter.colorControls()
                contrast.inputImage = monoOutput
                contrast.contrast = Float(1.0 + 0.1 * intensity)
                filtered = contrast.outputImage
            } else {
                filtered = nil
            }

        case .lark:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = Float(1.0 - 0.1 * intensity)
            controls.brightness = Float(0.1 * intensity)
            controls.saturation = Float(1.0 - 0.15 * intensity)
            filtered = controls.outputImage

        case .reyes:
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = image
            sepia.intensity = Float(0.22 * intensity)
            if let sepiaOutput = sepia.outputImage {
                let controls = CIFilter.colorControls()
                controls.inputImage = sepiaOutput
                controls.brightness = Float(0.1 * intensity)
                controls.contrast = Float(1.0 - 0.15 * intensity)
                controls.saturation = Float(1.0 - 0.25 * intensity)
                filtered = controls.outputImage
            } else {
                filtered = nil
            }

        case .juno:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = Float(1.0 + 0.1 * intensity)
            controls.brightness = Float(0.1 * intensity)
            controls.saturation = Float(1.0 + 0.4 * intensity)
            filtered = controls.outputImage

        case .slumber:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.3 * intensity)
            controls.brightness = Float(-0.05 * intensity)
            filtered = controls.outputImage

        case .crema:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.2 * intensity)
            if let output = controls.outputImage {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = output
                temp.neutral = CIVector(x: 6500, y: 0)
                temp.targetNeutral = CIVector(x: 6500 - 500 * intensity, y: 0)
                filtered = temp.outputImage
            } else {
                filtered = nil
            }

        case .ludwig:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.15 * intensity)
            controls.contrast = Float(1.0 + 0.05 * intensity)
            filtered = controls.outputImage

        case .aden:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 - 0.2 * intensity)
            controls.contrast = Float(1.0 - 0.1 * intensity)
            if let output = controls.outputImage {
                let hue = CIFilter.hueAdjust()
                hue.inputImage = output
                hue.angle = Float(0.05 * intensity)
                filtered = hue.outputImage
            } else {
                filtered = nil
            }

        case .perpetua:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = Float(1.0 + 0.1 * intensity)
            if let output = controls.outputImage {
                let temp = CIFilter.temperatureAndTint()
                temp.inputImage = output
                temp.neutral = CIVector(x: 6500, y: 0)
                temp.targetNeutral = CIVector(x: 7500, y: 0)
                filtered = temp.outputImage
            } else {
                filtered = nil
            }
        }

        // Blend with original based on intensity
        if let filtered, intensity < 1.0 {
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = image
            blend.targetImage = filtered
            blend.time = Float(intensity)
            return blend.outputImage
        }

        return filtered
    }

    private func applyAdjustments(_ adjustments: [ImageAdjustment: Double], to image: CIImage) -> CIImage {
        var result = image

        // Color controls (brightness, contrast, saturation)
        let brightness = adjustments[.brightness] ?? 0
        let contrast = adjustments[.contrast] ?? 1
        let saturation = adjustments[.saturation] ?? 1

        if brightness != 0 || contrast != 1 || saturation != 1 {
            let controls = CIFilter.colorControls()
            controls.inputImage = result
            controls.brightness = Float(brightness)
            controls.contrast = Float(contrast)
            controls.saturation = Float(saturation)
            result = controls.outputImage ?? result
        }

        // Warmth
        if let warmth = adjustments[.warmth], warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = result
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 - warmth * 2000, y: 0)
            result = temp.outputImage ?? result
        }

        // Highlights and shadows
        let shadows = adjustments[.shadows] ?? 0
        let highlights = adjustments[.highlights] ?? 0
        if shadows != 0 || highlights != 0 {
            let highlightShadow = CIFilter.highlightShadowAdjust()
            highlightShadow.inputImage = result
            highlightShadow.shadowAmount = Float(1 + shadows)
            highlightShadow.highlightAmount = Float(1 - highlights)
            result = highlightShadow.outputImage ?? result
        }

        // Vignette
        if let vignette = adjustments[.vignette], vignette > 0 {
            let vignetteFilter = CIFilter.vignette()
            vignetteFilter.inputImage = result
            vignetteFilter.intensity = Float(vignette)
            vignetteFilter.radius = Float(vignette * 2)
            result = vignetteFilter.outputImage ?? result
        }

        // Sharpen
        if let sharpen = adjustments[.sharpen], sharpen > 0 {
            let sharpenFilter = CIFilter.sharpenLuminance()
            sharpenFilter.inputImage = result
            sharpenFilter.sharpness = Float(sharpen * 0.5)
            result = sharpenFilter.outputImage ?? result
        }

        return result
    }

    private func applyTransform(to image: UIImage, rotation: Double, flip: Bool) -> UIImage? {
        let radians = rotation * .pi / 180
        var transform = CGAffineTransform.identity

        let size = image.size
        let rotatedSize: CGSize

        // Normalize rotation to 0-359 range and check if 90° or 270° (portrait orientation)
        let normalizedRotation = Int(rotation.truncatingRemainder(dividingBy: 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            rotatedSize = CGSize(width: size.height, height: size.width)
        } else {
            rotatedSize = size
        }

        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }

        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        if flip {
            context.scaleBy(x: -1, y: 1)
        }
        context.translateBy(x: -size.width / 2, y: -size.height / 2)

        image.draw(at: .zero)

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result
    }
}

// MARK: - Supporting Views

private struct AspectRatioButton: View {
    let ratio: AspectRatio
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? OlasTheme.Colors.deepTeal : Color.secondary, lineWidth: 2)
                    .frame(width: ratioWidth, height: ratioHeight)

                Text(ratio.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? OlasTheme.Colors.deepTeal.opacity(0.15)
                    : Color(white: 0.15)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OlasTheme.Colors.deepTeal : Color.clear, lineWidth: 2)
            )
        }
    }

    private var ratioWidth: CGFloat {
        switch ratio {
        case .square: return 32
        case .portrait: return 26
        case .landscape: return 32
        case .free: return 32
        }
    }

    private var ratioHeight: CGFloat {
        switch ratio {
        case .square: return 32
        case .portrait: return 32
        case .landscape: return 18
        case .free: return 24
        }
    }
}

private struct FilterThumbnail: View {
    let filter: ImageFilter
    let sourceImage: UIImage
    let isSelected: Bool
    let context: CIContext
    let onTap: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipped()
                    } else {
                        Color(white: 0.15)
                            .frame(width: 72, height: 72)
                    }
                }
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? OlasTheme.Colors.deepTeal : Color.clear, lineWidth: 3)
                )

                Text(filter.rawValue)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
        .task {
            await generateThumbnail()
        }
    }

    private func generateThumbnail() async {
        let size = CGSize(width: 144, height: 144)
        let renderer = UIGraphicsImageRenderer(size: size)
        let smallImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: size))
        }

        if filter == .original {
            thumbnail = smallImage
            return
        }

        thumbnail = await Task.detached(priority: .utility) {
            guard let ciImage = CIImage(image: smallImage) else { return smallImage }

            // Simplified filter application for thumbnail
            let filtered: CIImage?
            switch filter {
            case .original:
                return smallImage
            case .clarendon:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.contrast = 1.2
                f.saturation = 1.35
                filtered = f.outputImage
            case .moon:
                let f = CIFilter.photoEffectMono()
                f.inputImage = ciImage
                filtered = f.outputImage
            case .gingham:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.brightness = 0.05
                filtered = f.outputImage
            case .lark:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.contrast = 0.9
                f.brightness = 0.1
                f.saturation = 0.85
                filtered = f.outputImage
            case .reyes:
                let f = CIFilter.sepiaTone()
                f.inputImage = ciImage
                f.intensity = 0.22
                filtered = f.outputImage
            case .juno:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.contrast = 1.1
                f.saturation = 1.4
                filtered = f.outputImage
            case .slumber:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.saturation = 0.7
                f.brightness = -0.05
                filtered = f.outputImage
            case .crema:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.saturation = 0.8
                filtered = f.outputImage
            case .ludwig:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.saturation = 0.85
                f.contrast = 1.05
                filtered = f.outputImage
            case .aden:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.saturation = 0.8
                f.contrast = 0.9
                filtered = f.outputImage
            case .perpetua:
                let f = CIFilter.colorControls()
                f.inputImage = ciImage
                f.saturation = 1.1
                filtered = f.outputImage
            }

            guard let output = filtered,
                  let cgImage = context.createCGImage(output, from: output.extent) else {
                return smallImage
            }

            return UIImage(cgImage: cgImage)
        }.value
    }
}

private struct AdjustmentButton: View {
    let adjustment: ImageAdjustment
    let isSelected: Bool
    let hasValue: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: adjustment.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? OlasTheme.Colors.deepTeal : .secondary)

                    if hasValue {
                        Circle()
                            .fill(OlasTheme.Colors.deepTeal)
                            .frame(width: 6, height: 6)
                            .offset(x: 12, y: -10)
                    }
                }

                Text(adjustment.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? OlasTheme.Colors.deepTeal.opacity(0.15)
                    : Color(white: 0.15)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OlasTheme.Colors.deepTeal : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
