import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing event (kind:1) rendering
public struct EventDemoView: View {
    @State private var content = "Check out this note:\nnostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m"
    @State private var lastTapped = ""

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Content editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.headline)
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Event references like nostr:nevent1... are fetched and rendered inline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Rendered event variations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rendered Events")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        variationCard(title: "Full Content", description: "Complete note with all content displayed") {
                            DefaultStyleRichText(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Event: \(event.id.prefix(8))..."
                                }
                        }

                        variationCard(title: "Inline", description: "Minimal inline card with muted background, 3-line preview") {
                            EventInlineRichText(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Event: \(event.id.prefix(8))..."
                                }
                        }

                        variationCard(title: "Compact", description: "Compact card with avatar, name, and 4-line preview") {
                            EventCompactRichText(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Event: \(event.id.prefix(8))..."
                                }
                        }
                    }

                    // Technical note
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it works:")
                            .font(.headline)
                        Text("When the parser encounters nostr:nevent1..., it decodes the event reference, fetches the event from relays using NDK, and renders it inline. For kind:1 notes, different renderers can display the full content or compact previews.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Events (Kind:1)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom) {
            if !lastTapped.isEmpty {
                HStack {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.blue)
                    Text(lastTapped)
                        .font(.caption)
                    Spacer()
                    Button("Clear") {
                        lastTapped = ""
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func variationCard<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

#if DEBUG
struct EventDemoView_Previews: PreviewProvider {
    static var previews: some View {
        EventDemoView(ndk: NDK())
    }
}
#endif
