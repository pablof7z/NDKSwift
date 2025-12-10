import SwiftUI
import NDKSwift

struct CollectionDetailView: View {
    let collection: NDKPictureCurationSet
    let ndk: NDK

    @Environment(CollectionsManager.self) private var collectionsManager
    @Environment(\.dismiss) private var dismiss

    @State private var pictures: [NDKEvent] = []
    @State private var isLoading = true
    @State private var selectedPicture: NDKEvent?
    @State private var showCoverPicker = false

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 60)
                } else if pictures.isEmpty {
                    emptyState
                } else {
                    picturesGrid
                }
            }
        }
        .background(Color.black)
        .navigationTitle(collection.title ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCoverPicker = true
                    } label: {
                        Label("Set Cover", systemImage: "photo")
                    }
                    .disabled(pictures.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        Task { await deleteCollection() }
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .task {
            await loadPictures()
        }
        .fullScreenCover(item: $selectedPicture) { picture in
            FullscreenPostViewer(
                event: picture,
                ndk: ndk,
                isPresented: Binding(
                    get: { selectedPicture != nil },
                    set: { if !$0 { selectedPicture = nil } }
                )
            )
        }
        .sheet(isPresented: $showCoverPicker) {
            CoverPickerSheet(pictures: pictures) { selected in
                Task { await setCover(from: selected) }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Cover image
            if let imageUrl = collection.image, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color(white: 0.1))
                }
                .frame(height: 200)
                .clipped()
            }

            // Title and description
            VStack(alignment: .leading, spacing: 8) {
                if let description = collection.listDescription, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("\(collection.count) photo\(collection.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No photos yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Add photos using the share button on any post")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }

    private var picturesGrid: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(pictures, id: \.id) { picture in
                PictureGridCell(event: picture) {
                    selectedPicture = picture
                }
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await removePicture(picture) }
                    } label: {
                        Label("Remove from Collection", systemImage: "minus.circle")
                    }
                }
            }
        }
    }

    private func loadPictures() async {
        let eventIds = collection.pictureEventIds

        guard !eventIds.isEmpty else {
            isLoading = false
            return
        }

        let filter = NDKFilter(ids: eventIds)
        let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

        for await event in subscription.events {
            guard !Task.isCancelled else { break }
            if !pictures.contains(where: { $0.id == event.id }) {
                pictures.append(event)
                isLoading = false  // Hide loading after first picture arrives
            }
        }

        isLoading = false
    }

    private func removePicture(_ picture: NDKEvent) async {
        do {
            try await collectionsManager.removePicture(picture.id, from: collection)
            pictures.removeAll { $0.id == picture.id }
        } catch {
            // Handle error silently
        }
    }

    private func setCover(from picture: NDKEvent) async {
        let image = NDKImage(event: picture)
        guard let imageUrl = image.primaryImageURL else { return }

        do {
            try await collectionsManager.setCoverImage(imageUrl, for: collection)
        } catch {
            // Handle error silently
        }
    }

    private func deleteCollection() async {
        do {
            try await collectionsManager.deleteCollection(collection)
            dismiss()
        } catch {
            // Handle error
        }
    }
}

// MARK: - Picture Grid Cell

private struct PictureGridCell: View {
    let event: NDKEvent
    let onTap: () -> Void

    private var image: NDKImage {
        NDKImage(event: event)
    }

    var body: some View {
        GeometryReader { geo in
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { loadedImage in
                    loadedImage
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color(white: 0.1))
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color(white: 0.1))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Cover Picker Sheet

private struct CoverPickerSheet: View {
    let pictures: [NDKEvent]
    let onSelect: (NDKEvent) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(pictures, id: \.id) { picture in
                        Button {
                            onSelect(picture)
                            dismiss()
                        } label: {
                            PictureGridCell(event: picture) {}
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
