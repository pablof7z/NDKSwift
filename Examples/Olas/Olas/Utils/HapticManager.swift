import SwiftUI

#if os(iOS)
import UIKit

enum HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

#else

// Placeholder for macOS or other platforms
enum HapticManager {
    static func impact(_ style: Any) {
        // No-op on non-iOS platforms
    }
    
    static func notification(_ type: Any) {
        // No-op on non-iOS platforms
    }
    
    static func selection() {
        // No-op on non-iOS platforms
    }
}

#endif