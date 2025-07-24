import UIKit

class HapticManager {
    static let shared = HapticManager()
    private init() {}
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    enum ImpactStyle {
        case light, medium, heavy
    }
    
    enum NotificationStyle {
        case success, warning, error
    }
    
    func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selection.prepare()
        notification.prepare()
    }
    
    func impact(_ style: ImpactStyle) {
        switch style {
        case .light:
            impactLight.impactOccurred()
        case .medium:
            impactMedium.impactOccurred()
        case .heavy:
            impactHeavy.impactOccurred()
        }
    }
    
    func triggerSelection() {
        selection.selectionChanged()
    }
    
    func notification(_ style: NotificationStyle) {
        switch style {
        case .success:
            notification.notificationOccurred(.success)
        case .warning:
            notification.notificationOccurred(.warning)
        case .error:
            notification.notificationOccurred(.error)
        }
    }
}