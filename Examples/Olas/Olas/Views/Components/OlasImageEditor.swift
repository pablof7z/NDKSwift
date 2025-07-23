import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct OlasImageEditor: View {
    let originalImage: UIImage
    let currentFilter: String
    let onComplete: (UIImage, String) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedFilter = "No Filter"
    @State private var processedImage: UIImage?
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1
    @State private var saturation: Double = 1
    @State private var rotation: Double = 0
    @State private var showAdjustments = false
    
    private let context = CIContext()
    
    // Filter definitions
    let filters = [
        "No Filter",
        "Olas Classic",
        "Neon Tokyo", 
        "Golden Hour",
        "Nordic Frost",
        "Vintage Film",
        "Black Pearl",
        "Coral Dream",
        "Electric Blue",
        "Autumn Maple",
        "Mint Fresh",
        "Purple Haze"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Image preview
                    GeometryReader { geometry in
                        Image(uiImage: processedImage ?? originalImage)
                            .resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(rotation))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .background(OlasDesign.Colors.background)
                    
                    // Controls
                    VStack(spacing: 0) {
                        // Tab selector
                        Picker("Edit Mode", selection: $showAdjustments) {
                            Text("Filters").tag(false)
                            Text("Adjust").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(OlasDesign.Spacing.md)
                        
                        if showAdjustments {
                            adjustmentControls
                        } else {
                            filterSelector
                        }
                    }
                    .background(OlasDesign.Colors.surface)
                }
            }
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onComplete(processedImage ?? originalImage, selectedFilter)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(OlasDesign.Colors.primary)
                }
            }
        }
        .onAppear {
            selectedFilter = currentFilter
            applyCurrentSettings()
        }
    }
    
    @ViewBuilder
    private var filterSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.md) {
                ForEach(filters, id: \.self) { filter in
                    VStack(spacing: OlasDesign.Spacing.xs) {
                        // Filter preview thumbnail
                        if let thumbnail = generateThumbnail(for: filter) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedFilter == filter ? OlasDesign.Colors.primary : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                        }
                        
                        Text(filter)
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(
                                selectedFilter == filter ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary
                            )
                    }
                    .onTapGesture {
                        selectedFilter = filter
                        applyCurrentSettings()
                        OlasDesign.Haptic.selection()
                    }
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var adjustmentControls: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            // Brightness
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                HStack {
                    Image(systemName: "sun.max")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Text("Brightness")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(brightness * 100))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                Slider(value: $brightness, in: -1...1) { _ in
                    applyCurrentSettings()
                }
                .tint(OlasDesign.Colors.primary)
            }
            
            // Contrast
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                HStack {
                    Image(systemName: "circle.righthalf.filled")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Text("Contrast")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(contrast * 100))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                Slider(value: $contrast, in: 0.5...2) { _ in
                    applyCurrentSettings()
                }
                .tint(OlasDesign.Colors.primary)
            }
            
            // Saturation
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                HStack {
                    Image(systemName: "drop.fill")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Text("Saturation")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(saturation * 100))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                Slider(value: $saturation, in: 0...2) { _ in
                    applyCurrentSettings()
                }
                .tint(OlasDesign.Colors.primary)
            }
            
            // Rotation
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                HStack {
                    Image(systemName: "rotate.right")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Text("Rotation")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    Spacer()
                    Text("\(Int(rotation))°")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                HStack(spacing: OlasDesign.Spacing.md) {
                    Button("-90°") {
                        rotation -= 90
                        OlasDesign.Haptic.selection()
                    }
                    .buttonStyle(OlasSmallButtonStyle())
                    
                    Slider(value: $rotation, in: -45...45) { _ in
                        // No need to apply settings on every change for rotation
                    }
                    .tint(OlasDesign.Colors.primary)
                    
                    Button("+90°") {
                        rotation += 90
                        OlasDesign.Haptic.selection()
                    }
                    .buttonStyle(OlasSmallButtonStyle())
                }
            }
            
            // Reset button
            Button("Reset All") {
                brightness = 0
                contrast = 1
                saturation = 1
                rotation = 0
                applyCurrentSettings()
                OlasDesign.Haptic.impact(.light)
            }
            .font(OlasDesign.Typography.caption)
            .foregroundColor(OlasDesign.Colors.warning)
        }
        .padding()
    }
    
    private func applyCurrentSettings() {
        Task {
            processedImage = await applyFilters()
        }
    }
    
    @MainActor
    private func applyFilters() async -> UIImage {
        guard let ciImage = CIImage(image: originalImage) else { return originalImage }
        
        var outputImage = ciImage
        
        // Apply selected filter
        if selectedFilter != "No Filter" {
            outputImage = applyFilter(selectedFilter, to: outputImage)
        }
        
        // Apply adjustments
        outputImage = applyAdjustments(to: outputImage)
        
        // Apply rotation
        if rotation != 0 {
            let radians = rotation * .pi / 180
            outputImage = outputImage.transformed(by: CGAffineTransform(rotationAngle: CGFloat(radians)))
        }
        
        // Render final image
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return originalImage
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func applyFilter(_ filterName: String, to image: CIImage) -> CIImage {
        switch filterName {
        case "Olas Classic":
            return applyOlasClassic(to: image)
        case "Neon Tokyo":
            return applyNeonTokyo(to: image)
        case "Golden Hour":
            return applyGoldenHour(to: image)
        case "Nordic Frost":
            return applyNordicFrost(to: image)
        case "Vintage Film":
            return applyVintageFilm(to: image)
        case "Black Pearl":
            return applyBlackPearl(to: image)
        case "Coral Dream":
            return applyCoralDream(to: image)
        case "Electric Blue":
            return applyElectricBlue(to: image)
        case "Autumn Maple":
            return applyAutumnMaple(to: image)
        case "Mint Fresh":
            return applyMintFresh(to: image)
        case "Purple Haze":
            return applyPurpleHaze(to: image)
        default:
            return image
        }
    }
    
    private func applyAdjustments(to image: CIImage) -> CIImage {
        var result = image
        
        // Brightness
        if brightness != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.brightness = Float(brightness)
            result = filter.outputImage ?? result
        }
        
        // Contrast
        if contrast != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.contrast = Float(contrast)
            result = filter.outputImage ?? result
        }
        
        // Saturation
        if saturation != 1 {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.saturation = Float(saturation)
            result = filter.outputImage ?? result
        }
        
        return result
    }
    
    // MARK: - Filter Implementations
    
    private func applyOlasClassic(to image: CIImage) -> CIImage {
        // Subtle contrast boost with warmth
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.1
        colorControls.saturation = 1.05
        colorControls.brightness = 0.02
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add slight warmth
        let tempAndTint = CIFilter.temperatureAndTint()
        tempAndTint.inputImage = adjusted
        tempAndTint.neutral = CIVector(x: 6500, y: 0)
        tempAndTint.targetNeutral = CIVector(x: 5500, y: 0)
        
        return tempAndTint.outputImage ?? adjusted
    }
    
    private func applyNeonTokyo(to image: CIImage) -> CIImage {
        // Cyberpunk-inspired with high contrast and cool tones
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.3
        colorControls.saturation = 0.8
        colorControls.brightness = -0.05
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add blue/purple tone
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 0.9, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0.9, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0.1, y: 0.1, z: 1.2, w: 0)
        
        return colorMatrix.outputImage ?? adjusted
    }
    
    private func applyGoldenHour(to image: CIImage) -> CIImage {
        // Warm highlights, cool shadows
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.05
        colorControls.saturation = 1.1
        colorControls.brightness = 0.05
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add golden warmth
        let tempAndTint = CIFilter.temperatureAndTint()
        tempAndTint.inputImage = adjusted
        tempAndTint.neutral = CIVector(x: 6500, y: 0)
        tempAndTint.targetNeutral = CIVector(x: 4000, y: -10)
        
        return tempAndTint.outputImage ?? adjusted
    }
    
    private func applyNordicFrost(to image: CIImage) -> CIImage {
        // Desaturated with blue undertones
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 0.95
        colorControls.saturation = 0.6
        colorControls.brightness = 0.1
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add cool tone
        let tempAndTint = CIFilter.temperatureAndTint()
        tempAndTint.inputImage = adjusted
        tempAndTint.neutral = CIVector(x: 6500, y: 0)
        tempAndTint.targetNeutral = CIVector(x: 8000, y: 10)
        
        return tempAndTint.outputImage ?? adjusted
    }
    
    private func applyVintageFilm(to image: CIImage) -> CIImage {
        // Film look with vignette
        let sepia = CIFilter.sepiaTone()
        sepia.inputImage = image
        sepia.intensity = 0.2
        
        guard let sepiaOutput = sepia.outputImage else { return image }
        
        // Add vignette
        let vignette = CIFilter.vignette()
        vignette.inputImage = sepiaOutput
        vignette.intensity = 0.8
        vignette.radius = 1.5
        
        guard let vignetted = vignette.outputImage else { return sepiaOutput }
        
        // Adjust colors
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = vignetted
        colorControls.contrast = 1.1
        colorControls.saturation = 0.9
        
        return colorControls.outputImage ?? vignetted
    }
    
    private func applyBlackPearl(to image: CIImage) -> CIImage {
        // Rich black and white
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = image
        
        guard let noirOutput = noir.outputImage else { return image }
        
        // Boost contrast
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = noirOutput
        colorControls.contrast = 1.2
        colorControls.brightness = -0.02
        
        return colorControls.outputImage ?? noirOutput
    }
    
    private func applyCoralDream(to image: CIImage) -> CIImage {
        // Peachy tones with soft highlights
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 0.95
        colorControls.saturation = 1.15
        colorControls.brightness = 0.08
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add coral tint
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 1.1, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0.95, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: 0.9, w: 0)
        
        return colorMatrix.outputImage ?? adjusted
    }
    
    private func applyElectricBlue(to image: CIImage) -> CIImage {
        // High contrast with blue accent
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.25
        colorControls.saturation = 1.2
        colorControls.brightness = -0.03
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Boost blues
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 0.9, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0.95, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0.1, z: 1.3, w: 0)
        
        return colorMatrix.outputImage ?? adjusted
    }
    
    private func applyAutumnMaple(to image: CIImage) -> CIImage {
        // Warm oranges and deep reds
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.1
        colorControls.saturation = 1.2
        colorControls.brightness = 0.02
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add autumn colors
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 1.2, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0.1, y: 0.9, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: 0.8, w: 0)
        
        return colorMatrix.outputImage ?? adjusted
    }
    
    private func applyMintFresh(to image: CIImage) -> CIImage {
        // Cool greens with brightness
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.05
        colorControls.saturation = 1.1
        colorControls.brightness = 0.1
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add mint tint
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 0.9, y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 1.15, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0.05, z: 1.05, w: 0)
        
        return colorMatrix.outputImage ?? adjusted
    }
    
    private func applyPurpleHaze(to image: CIImage) -> CIImage {
        // Moody purples with fade
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 0.9
        colorControls.saturation = 0.95
        colorControls.brightness = 0.05
        
        guard let adjusted = colorControls.outputImage else { return image }
        
        // Add purple tint
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = adjusted
        colorMatrix.rVector = CIVector(x: 1.1, y: 0, z: 0.1, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: 0.9, z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0.1, y: 0, z: 1.2, w: 0)
        
        guard let tinted = colorMatrix.outputImage else { return adjusted }
        
        // Add slight fade
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = tinted
        exposure.ev = 0.15
        
        return exposure.outputImage ?? tinted
    }
    
    private func generateThumbnail(for filterName: String) -> UIImage? {
        // Create smaller version for performance
        let size = CGSize(width: 160, height: 160)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        originalImage.draw(in: CGRect(origin: .zero, size: size))
        guard let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        UIGraphicsEndImageContext()
        
        // Apply filter to thumbnail
        guard let ciImage = CIImage(image: thumbnailImage) else { return nil }
        let filteredImage = applyFilter(filterName, to: ciImage)
        
        guard let cgImage = context.createCGImage(filteredImage, from: filteredImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Button Style

struct OlasSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OlasDesign.Typography.caption)
            .foregroundColor(OlasDesign.Colors.primary)
            .padding(.horizontal, OlasDesign.Spacing.sm)
            .padding(.vertical, OlasDesign.Spacing.xs)
            .background(OlasDesign.Colors.primary.opacity(0.1))
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Preview

struct OlasImageEditor_Previews: PreviewProvider {
    static var previews: some View {
        if let image = UIImage(systemName: "photo") {
            OlasImageEditor(
                originalImage: image,
                currentFilter: "No Filter"
            ) { _, _ in }
        }
    }
}
#else
// Placeholder for non-iOS platforms
struct OlasImageEditor: View {
    let originalImage: Any
    let currentFilter: String
    let onComplete: (Any, String) -> Void
    
    var body: some View {
        Text("Image editor not available on this platform")
    }
}
#endif