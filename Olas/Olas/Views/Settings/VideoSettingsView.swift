import SwiftUI

struct VideoSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        List {
            Section {
                @Bindable var settings = settings
                Toggle("Show videos in feed", isOn: $settings.showVideos)

                Toggle("Autoplay videos", isOn: $settings.autoplayVideos)
                    .disabled(!settings.showVideos)
            } footer: {
                Text("When autoplay is enabled, videos will play automatically when visible. Tap to unmute.")
            }
        }
        .navigationTitle("Video")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
