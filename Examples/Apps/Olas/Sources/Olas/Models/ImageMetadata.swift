import Foundation

struct ImageMetadata: Codable {
    let url: URL
    let width: Int?
    let height: Int?
    let blurhash: String?
    let alt: String?
    let mimeType: String?
    
    init(url: URL, width: Int? = nil, height: Int? = nil, blurhash: String? = nil, alt: String? = nil, mimeType: String? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.blurhash = blurhash
        self.alt = alt
        self.mimeType = mimeType
    }
}