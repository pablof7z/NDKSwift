import SwiftUI

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    @AppStorage("showVideos") public var showVideos: Bool = true
    @AppStorage("autoplayVideos") public var autoplayVideos: Bool = true

    private init() {}
}
