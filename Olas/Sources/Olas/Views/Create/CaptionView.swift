import SwiftUI

struct CaptionView: View {
    let image: UIImage
    @Binding var caption: String
    let onShare: () -> Void
    let onBack: () -> Void

    @State private var suggestedHashtags: [String] = [
        "#photography", "#nature", "#travel", "#art", "#nostr",
        "#bitcoin", "#landscape", "#portrait", "#street", "#urban"
    ]
    @State private var usedHashtags: Set<String> = []
    @State private var location: String?
    @State private var showLocationPicker = false

    @FocusState private var isCaptionFocused: Bool

    private let maxCharacters = 500

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Image preview
                    imagePreview

                    // Caption input
                    captionInput

                    // Hashtag suggestions
                    hashtagSuggestions

                    // Location picker
                    locationPicker
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            // Share button
            shareButton
        }
        .background(Color.black)
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .onAppear {
            isCaptionFocused = true
        }
    }

    private var imagePreview: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 280)
            .cornerRadius(16)
    }

    private var captionInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if caption.isEmpty {
                    Text("Write a caption...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $caption)
                    .focused($isCaptionFocused)
                    .frame(minHeight: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .background(Color(white: 0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isCaptionFocused
                            ? OlasTheme.Colors.deepTeal
                            : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )

            // Character count
            HStack {
                Spacer()
                Text("\(caption.count) / \(maxCharacters)")
                    .font(.system(size: 13))
                    .foregroundStyle(characterCountColor)
            }
            .padding(.horizontal, 4)
        }
    }

    private var characterCountColor: Color {
        if caption.count > maxCharacters {
            return .red
        } else if caption.count > Int(Double(maxCharacters) * 0.9) {
            return .orange
        }
        return .secondary
    }

    private var hashtagSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested hashtags")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            FlowLayout(spacing: 8) {
                ForEach(suggestedHashtags.filter { !usedHashtags.contains($0) }, id: \.self) { hashtag in
                    Button {
                        addHashtag(hashtag)
                    } label: {
                        Text(hashtag)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .cornerRadius(20)
                    }
                }
            }
        }
    }

    private var locationPicker: some View {
        Button {
            showLocationPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)

                if let location {
                    Text(location)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                } else {
                    Text("Add location")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(white: 0.1))
            .cornerRadius(14)
        }
    }

    private var shareButton: some View {
        Button(action: onShare) {
            Text("Share")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .cornerRadius(14)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .disabled(caption.count > maxCharacters)
        .opacity(caption.count > maxCharacters ? 0.5 : 1)
        .background(Color.black)
    }

    private func addHashtag(_ hashtag: String) {
        if !caption.isEmpty && !caption.hasSuffix(" ") {
            caption += " "
        }
        caption += hashtag
        usedHashtags.insert(hashtag)
    }
}

// MARK: - Flow Layout for Hashtag Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxX = max(maxX, currentX - spacing)
            }

            size = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}
