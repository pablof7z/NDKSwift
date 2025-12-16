import SwiftUI
import NDKSwiftCore

// MARK: - Callback Types

public typealias MentionTapHandler = (String) -> Void
public typealias HashtagTapHandler = (String) -> Void
public typealias LinkTapHandler = (URL) -> Void
public typealias ImageTapHandler = (URL) -> Void
public typealias EventTapHandler = (NDKEvent) -> Void

// MARK: - Renderer Protocols

public protocol MentionRenderer: View {
    init(pubkey: String, npub: String, onTap: MentionTapHandler?)
}

public protocol HashtagRenderer: View {
    init(tag: String, onTap: HashtagTapHandler?)
}

public protocol LinkRenderer: View {
    init(url: URL, onTap: LinkTapHandler?)
}

public protocol ImageRenderer: View {
    init(url: URL, onTap: ImageTapHandler?)
}

public protocol EventRenderer: View {
    init(event: NDKEvent, onTap: EventTapHandler?)
}
