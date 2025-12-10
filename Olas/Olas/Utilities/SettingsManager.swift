import SwiftUI

@MainActor
@Observable
final class SettingsManager {
    public static let shared = SettingsManager()

    public var showVideos: Bool {
        get { UserDefaults.standard.bool(forKey: "showVideos") }
        set { UserDefaults.standard.set(newValue, forKey: "showVideos") }
    }

    public var autoplayVideos: Bool {
        get { UserDefaults.standard.bool(forKey: "autoplayVideos") }
        set { UserDefaults.standard.set(newValue, forKey: "autoplayVideos") }
    }

    private init() {
        // Set defaults if not already set
        if UserDefaults.standard.object(forKey: "showVideos") == nil {
            UserDefaults.standard.set(true, forKey: "showVideos")
        }
        if UserDefaults.standard.object(forKey: "autoplayVideos") == nil {
            UserDefaults.standard.set(true, forKey: "autoplayVideos")
        }
    }
}
