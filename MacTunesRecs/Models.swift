import Foundation

struct TrackInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let genre: String
    let fileURL: URL
    let duration: TimeInterval?
}

struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let artist: String
    let album: String
    let genre: String
    let trackCount: Int
    let artworkFileURL: URL?
}

struct GenreSlice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let count: Int
    let colorIndex: Int
}

enum RecommendationSource: String, Sendable {
    case library
    case spotify
}

struct Recommendation: Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceId: String?
    let title: String
    let subtitle: String
    let genre: String
    let spotifyURL: URL?
    let artworkURL: URL?
    let artworkData: Data?
    let source: RecommendationSource
}

struct LibraryIndex: Sendable {
    let albumKeys: Set<String>
    let topGenres: [String]
    let topArtists: [String]
}

// Compatibility type for older resolver signatures that may still exist in Xcode's index/cache.
struct AlbumLookup: Hashable, Sendable {
    let key: String
    let artist: String
    let album: String
}
