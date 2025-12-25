import NDKSwiftCore
import SwiftUI

// MARK: - Callback Types

public typealias MentionTapHandler = (String) -> Void
public typealias HashtagTapHandler = (String) -> Void
public typealias LinkTapHandler = (URL) -> Void
public typealias ImageTapHandler = (URL, Int) -> Void
public typealias VideoTapHandler = (URL) -> Void
public typealias EventTapHandler = (NDKEvent) -> Void

// MARK: - Renderer Protocols

@MainActor
public protocol MentionRenderer: View {
    init(pubkey: String, npub: String, onTap: MentionTapHandler?)
}

@MainActor
public protocol HashtagRenderer: View {
    init(tag: String, onTap: HashtagTapHandler?)
}

@MainActor
public protocol LinkRenderer: View {
    init(url: URL, onTap: LinkTapHandler?)
}

@MainActor
public protocol ImageRenderer: View {
    init(urls: [URL], onTap: ImageTapHandler?)
}

@MainActor
public protocol VideoRenderer: View {
    init(url: URL, onTap: VideoTapHandler?)
}

@MainActor
public protocol EventRenderer: View {
    var event: NDKEvent { get }
    init(event: NDKEvent, onTap: EventTapHandler?)
}
