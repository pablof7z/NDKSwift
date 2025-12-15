import SwiftUI
import MarkdownDemoFeature
import NDKSwiftCore

@main
struct MarkdownDemoApp: App {
    @State private var ndk = NDK()

    var body: some Scene {
        WindowGroup {
            EntityRendererDemoView(ndk: ndk)
        }
    }
}
