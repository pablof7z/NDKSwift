import SwiftUI
import NDKSwiftCore

// MARK: - Environment Keys

private struct OnMentionTapKey: EnvironmentKey {
    static let defaultValue: MentionTapHandler? = nil
}

private struct OnHashtagTapKey: EnvironmentKey {
    static let defaultValue: HashtagTapHandler? = nil
}

private struct OnLinkTapKey: EnvironmentKey {
    static let defaultValue: LinkTapHandler? = nil
}

private struct OnImageTapKey: EnvironmentKey {
    static let defaultValue: ImageTapHandler? = nil
}

private struct OnEventTapKey: EnvironmentKey {
    static let defaultValue: EventTapHandler? = nil
}

// MARK: - EnvironmentValues Extension

extension EnvironmentValues {
    public var onMentionTap: MentionTapHandler? {
        get { self[OnMentionTapKey.self] }
        set { self[OnMentionTapKey.self] = newValue }
    }

    public var onHashtagTap: HashtagTapHandler? {
        get { self[OnHashtagTapKey.self] }
        set { self[OnHashtagTapKey.self] = newValue }
    }

    public var onLinkTap: LinkTapHandler? {
        get { self[OnLinkTapKey.self] }
        set { self[OnLinkTapKey.self] = newValue }
    }

    public var onImageTap: ImageTapHandler? {
        get { self[OnImageTapKey.self] }
        set { self[OnImageTapKey.self] = newValue }
    }

    public var onEventTap: EventTapHandler? {
        get { self[OnEventTapKey.self] }
        set { self[OnEventTapKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {
    public func onMentionTap(_ handler: @escaping MentionTapHandler) -> some View {
        environment(\.onMentionTap, handler)
    }

    public func onHashtagTap(_ handler: @escaping HashtagTapHandler) -> some View {
        environment(\.onHashtagTap, handler)
    }

    public func onLinkTap(_ handler: @escaping LinkTapHandler) -> some View {
        environment(\.onLinkTap, handler)
    }

    public func onImageTap(_ handler: @escaping ImageTapHandler) -> some View {
        environment(\.onImageTap, handler)
    }

    public func onEventTap(_ handler: @escaping EventTapHandler) -> some View {
        environment(\.onEventTap, handler)
    }
}
