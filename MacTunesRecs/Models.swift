import Foundation

/// Represents a single audio track loaded from the user's local music library.
struct TrackInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let genre: String
    /// Local file URL of the audio file on disk.
    let fileURL: URL
    /// Playback duration in seconds; `nil` if unavailable from metadata.
    let duration: TimeInterval?
}

/// A deduplicated album derived from one or more `TrackInfo` entries.
struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let artist: String
    let album: String
    let genre: String
    let trackCount: Int
    /// URL of the first track file, used to load embedded artwork.
    let artworkFileURL: URL?
}

/// A single slice of the genre pie chart with display metadata.
struct GenreSlice: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Display name of the genre (e.g. "Rock", "Other").
    let name: String
    /// Number of albums belonging to this genre slice.
    let count: Int
    /// Index into the app's colour palette for consistent colouring.
    let colorIndex: Int
}

/// Indicates whether a recommendation originated from the local library or from Spotify.
enum RecommendationSource: String, Sendable {
    case library
    case spotify
}

/// A single album recommendation shown to the user.
struct Recommendation: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Spotify album ID when the source is `.spotify`; `nil` for library recs.
    let sourceId: String?
    let title: String
    let subtitle: String
    let genre: String
    /// Deep-link URL to open the album in Spotify.
    let spotifyURL: URL?
    /// Remote artwork image URL (Spotify recommendations only).
    let artworkURL: URL?
    /// Raw artwork image data loaded from the local file (library recommendations only).
    let artworkData: Data?
    let source: RecommendationSource
}

/// Pre-computed summary of the user's library used for Spotify seed selection and deduplication.
struct LibraryIndex: Sendable {
    /// Normalised "artist||album" keys for every album already in the library.
    let albumKeys: Set<String>
    /// Most frequent genres, sorted by album count descending.
    let topGenres: [String]
    /// Most frequent artists, sorted by track count descending.
    let topArtists: [String]
}

// Compatibility type for older resolver signatures that may still exist in Xcode's index/cache.
/// Legacy lookup key struct retained for Xcode index/cache compatibility.
struct AlbumLookup: Hashable, Sendable {
    let key: String
    let artist: String
    let album: String
}
