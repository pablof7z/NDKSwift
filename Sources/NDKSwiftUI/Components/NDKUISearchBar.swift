import SwiftUI

// MARK: - NDKUISearchBar

/// Bottom-positioned search bar with modern iOS styling
///
/// Features:
/// - Bottom-aligned placement for thumb reach
/// - Clear button (X) when text is entered
/// - Real-time search as user types
///
/// ## Usage
///
/// ```swift
/// NDKUISearchBar(text: $searchText, onClear: {
///     // Handle clear action
/// })
/// ```
public struct NDKUISearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    let onClear: () -> Void

    public init(text: Binding<String>, onClear: @escaping () -> Void) {
        self._text = text
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))

            // Text field
            TextField("Search notes...", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            // Clear button (only shown when there's text)
            if !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear()
                    isFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.95))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
    }
}

#Preview {
    VStack {
        Spacer()
        NDKUISearchBar(text: .constant("bitcoin"), onClear: {})
    }
}
