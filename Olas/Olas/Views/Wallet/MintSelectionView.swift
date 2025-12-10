// MintSelectionView.swift
import SwiftUI

struct MintSelectionView: View {
    let mints: [DiscoveredMint]
    @Binding var selectedMints: Set<String>

    var body: some View {
        List {
            ForEach(mints) { mint in
                MintRow(
                    mint: mint,
                    isSelected: selectedMints.contains(mint.url.absoluteString),
                    onToggle: {
                        toggleMint(mint.url.absoluteString)
                    }
                )
            }
        }
        .listStyle(.plain)
    }

    private func toggleMint(_ url: String) {
        if selectedMints.contains(url) {
            selectedMints.remove(url)
        } else {
            selectedMints.insert(url)
        }
    }
}

// MARK: - Mint Row

private struct MintRow: View {
    let mint: DiscoveredMint
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon
                if let iconURL = mint.iconURL {
                    AsyncImage(url: iconURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        mintPlaceholderIcon
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    mintPlaceholderIcon
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mint.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    if let description = mint.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        // Units
                        ForEach(mint.units.prefix(3), id: \.self) { unit in
                            Text(unit.uppercased())
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OlasTheme.Colors.deepTeal.opacity(0.1))
                                .foregroundStyle(OlasTheme.Colors.deepTeal)
                                .clipShape(Capsule())
                        }

                        // Recommendations
                        if mint.recommendationCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.caption2)
                                Text("\(mint.recommendationCount)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? OlasTheme.Colors.deepTeal : Color.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var mintPlaceholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 44, height: 44)

            Image(systemName: "building.columns.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
