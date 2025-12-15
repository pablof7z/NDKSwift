import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

@main
struct MarkdownDemoApp: App {
    @StateObject private var ndk = NDK()

    var body: some Scene {
        WindowGroup {
            MarkdownDemoView(ndk: ndk)
                .environmentObject(ndk)
        }
    }
}
