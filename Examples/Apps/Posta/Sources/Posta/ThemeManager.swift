import SwiftUI

@MainActor
class ThemeManager: ObservableObject {
    enum Theme: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var colorScheme: ColorScheme? {
            switch self {
            case .system:
                return nil
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }
    }
    
    @Published var currentTheme: Theme = .system {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "app_theme")
        }
    }
    
    init() {
        if let savedTheme = UserDefaults.standard.string(forKey: "app_theme"),
           let theme = Theme(rawValue: savedTheme) {
            self.currentTheme = theme
        }
    }
}