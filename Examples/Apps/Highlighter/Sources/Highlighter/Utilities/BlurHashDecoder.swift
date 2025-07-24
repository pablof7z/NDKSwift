import UIKit
import SwiftUI

struct BlurHash {
    static func decode(blurhash: String, width: Int, height: Int) -> UIImage? {
        guard blurhash.count >= 6 else { return nil }
        
        let sizeFlag = String(blurhash[blurhash.startIndex]).decode83()
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1
        
        let quantisedMaximumValue = String(blurhash[blurhash.index(blurhash.startIndex, offsetBy: 1)]).decode83()
        let maximumValue = Float(quantisedMaximumValue + 1) / 166
        
        guard blurhash.count == 4 + 2 * numX * numY else { return nil }
        
        var colours: [(Float, Float, Float)] = []
        for i in 0 ..< numX * numY {
            if i == 0 {
                let value = String(blurhash[blurhash.index(blurhash.startIndex, offsetBy: 2) ..< blurhash.index(blurhash.startIndex, offsetBy: 6)]).decode83()
                colours.append(decodeDC(value))
            } else {
                let range = blurhash.index(blurhash.startIndex, offsetBy: 4 + i * 2) ..< blurhash.index(blurhash.startIndex, offsetBy: 4 + i * 2 + 2)
                let value = String(blurhash[range]).decode83()
                colours.append(decodeAC(value, maximumValue: maximumValue))
            }
        }
        
        let bytesPerRow = width * 3
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        
        for y in 0 ..< height {
            for x in 0 ..< width {
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0
                
                for j in 0 ..< numY {
                    for i in 0 ..< numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width)) * cos(Float.pi * Float(y) * Float(j) / Float(height))
                        let colour = colours[i + j * numX]
                        r += colour.0 * basis
                        g += colour.1 * basis
                        b += colour.2 * basis
                    }
                }
                
                let intR = UInt8(linearTosRGB(r))
                let intG = UInt8(linearTosRGB(g))
                let intB = UInt8(linearTosRGB(b))
                
                pixels[3 * x + 0 + y * bytesPerRow] = intR
                pixels[3 * x + 1 + y * bytesPerRow] = intG
                pixels[3 * x + 2 + y * bytesPerRow] = intB
            }
        }
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(dataInfo: nil, data: pixels, size: bytesPerRow * height, releaseData: { _, data, _ in
            data.deallocate()
        }) else { return nil }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        let intR = value >> 16
        let intG = (value >> 8) & 255
        let intB = value & 255
        return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
    }
    
    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        
        let rgb = (
            signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantB) - 9) / 9, 2) * maximumValue
        )
        
        return rgb
    }
    
    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255
        if v <= 0.04045 {
            return v / 12.92
        } else {
            return pow((v + 0.055) / 1.055, 2.4)
        }
    }
    
    private static func linearTosRGB(_ value: Float) -> Int {
        let v = max(0, min(1, value))
        if v <= 0.0031308 {
            return Int(v * 12.92 * 255 + 0.5)
        } else {
            return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
        }
    }
    
    private static func signPow(_ value: Float, _ exp: Float) -> Float {
        return copysign(pow(abs(value), exp), value)
    }
}

private extension String {
    func decode83() -> Int {
        var value: Int = 0
        for character in self {
            if let digit = decode83Map[character] {
                value = value * 83 + digit
            }
        }
        return value
    }
}

private let decode83Map: [Character: Int] = {
    let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
    var dict: [Character: Int] = [:]
    for (index, character) in chars.enumerated() {
        dict[character] = index
    }
    return dict
}()

// SwiftUI View Modifier
struct BlurHashModifier: ViewModifier {
    let blurhash: String?
    let size: CGSize
    @State private var blurImage: UIImage?
    
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if let blurImage = blurImage {
                        Image(uiImage: blurImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
            )
            .onAppear {
                if let blurhash = blurhash {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let image = BlurHash.decode(
                            blurhash: blurhash,
                            width: Int(size.width / 10), // Low res for performance
                            height: Int(size.height / 10)
                        )
                        DispatchQueue.main.async {
                            withAnimation(.easeIn(duration: 0.3)) {
                                self.blurImage = image
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func blurhashBackground(_ blurhash: String?, size: CGSize) -> some View {
        modifier(BlurHashModifier(blurhash: blurhash, size: size))
    }
}