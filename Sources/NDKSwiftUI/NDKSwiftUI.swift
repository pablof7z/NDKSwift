import SwiftUI
import NDKSwift

// MARK: - NDKSwiftUI Main Export

/// NDKSwiftUI provides SwiftUI components and data sources for building Nostr applications.
///
/// This module follows these core principles:
/// - **Composable, not prescriptive**: Provides building blocks, not complete screens
/// - **Data-driven**: Components react to NDK's data streams
/// - **Customizable**: Easy to style and extend
/// - **Progressive disclosure**: Simple defaults, advanced customization available
/// - **Streaming data**: No blocking UI, best-effort rendering as data arrives
/// - **Interactive**: Built-in support for reactions, zaps, follows, and more
///
/// ## Usage
///
/// ```swift
/// import NDKSwiftUI
///
/// struct ContentView: View {
///     let ndk: NDK
///     let pubkey: String
///
///     var body: some View {
///         VStack {
///             // All components now use direct NDK parameters
///             NDKUIProfilePicture(ndk: ndk, pubkey: pubkey)
///             NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
///
///             // Action buttons now also use direct NDK parameters
///             HStack {
///                 NDKUIReactionButton.like(ndk: ndk, event: event)
///                 NDKUIZapButton(ndk: ndk, event: event)
///                 NDKUIFollowButton(ndk: ndk, pubkey: pubkey)
///             }
///         }
///         // No environment injection needed anymore!
///     }
/// }
/// ```
public struct NDKSwiftUI {
    /// The version of NDKSwiftUI
    public static let version = "0.13"
}


// MARK: - Public Exports

// All public types are automatically exported from this module
// Users can import NDKSwiftUI and access all components directly