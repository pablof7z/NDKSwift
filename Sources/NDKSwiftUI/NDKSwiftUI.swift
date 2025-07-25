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
///             NDKProfilePicture(pubkey: pubkey)
///             NDKDisplayName(pubkey: pubkey)
///
///             HStack {
///                 NDKReactionButton.like(event: event)
///                 NDKZapButton(event: event)
///                 NDKFollowButton(pubkey: pubkey)
///             }
///         }
///         .environment(\.ndk, ndk)
///     }
/// }
/// ```
public struct NDKSwiftUI {
    /// The version of NDKSwiftUI
    public static let version = "0.2.1"
}

// MARK: - Environment Values

extension EnvironmentValues {
    /// The NDK instance to use for data fetching
    @Entry public var ndk: NDK?
}

// MARK: - Public Exports

// All public types are automatically exported from this module
// Users can import NDKSwiftUI and access all components directly