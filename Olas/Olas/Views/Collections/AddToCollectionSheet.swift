import SwiftUI
import NDKSwift

struct AddToCollectionSheet: View {
    let pictureEvent: NDKEvent

    @Environment(CollectionsManager.self) private var collectionsManager
    @Environment(\.dismiss) private var dismiss

    @State private var isAdding = false
    @State private var showCreateSheet = false
    @State private var addingToIdentifier: String?

    var body: some View {
        NavigationStack {
            Group {
                if collectionsManager.collections.isEmpty && !collectionsManager.isLoading {
                    emptyState
                } else {
                    collectionsList
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCollectionSheet()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Collections Yet")
                .font(.headline)

            Text("Create your first collection to start curating photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showCreateSheet = true
            } label: {
                Text("Create Collection")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(OlasTheme.Colors.brandPrimary)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    private var collectionsList: some View {
        List {
            ForEach(collectionsManager.collections, id: \.identifier) { collection in
                CollectionRowButton(
                    collection: collection,
                    isAlreadyAdded: collection.contains(eventId: pictureEvent.id),
                    isAdding: isAdding && addingToIdentifier == collection.identifier
                ) {
                    Task { await addToCollection(collection) }
                }
            }
        }
        .listStyle(.plain)
    }

    private func addToCollection(_ collection: NDKPictureCurationSet) async {
        guard !collection.contains(eventId: pictureEvent.id) else { return }

        isAdding = true
        addingToIdentifier = collection.identifier

        do {
            try await collectionsManager.addPicture(pictureEvent, to: collection)

            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.success)

            dismiss()
        } catch {
            addingToIdentifier = nil
            isAdding = false
        }
    }
}

// MARK: - Collection Row

private struct CollectionRowButton: View {
    let collection: NDKPictureCurationSet
    let isAlreadyAdded: Bool
    let isAdding: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                collectionThumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.title ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(collection.count) photo\(collection.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isAdding {
                    ProgressView()
                } else if isAlreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isAlreadyAdded || isAdding)
        .buttonStyle(.plain)
    }

    private var collectionThumbnail: some View {
        Group {
            if let imageUrl = collection.image, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .overlay(
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}
