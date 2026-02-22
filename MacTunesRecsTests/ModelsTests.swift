import XCTest
@testable import MacTunesRecs

final class ModelsTests: XCTestCase {

    // MARK: - TrackInfo

    func testTrackInfoHasID() {
        let track = TrackInfo(
            id: UUID(),
            title: "Song",
            artist: "Artist",
            album: "Album",
            genre: "Rock",
            fileURL: URL(fileURLWithPath: "/tmp/song.mp3"),
            duration: nil
        )
        XCTAssertNotNil(track.id)
    }

    func testTrackInfoIDIsUnique() {
        let t1 = TrackInfo(
            id: UUID(),
            title: "Song1",
            artist: "Artist",
            album: "Album",
            genre: "Rock",
            fileURL: URL(fileURLWithPath: "/tmp/song1.mp3"),
            duration: nil
        )
        let t2 = TrackInfo(
            id: UUID(),
            title: "Song2",
            artist: "Artist",
            album: "Album",
            genre: "Rock",
            fileURL: URL(fileURLWithPath: "/tmp/song2.mp3"),
            duration: nil
        )
        XCTAssertNotEqual(t1.id, t2.id)
    }

    // MARK: - RecommendationSource

    func testRecommendationSourceRawValues() {
        XCTAssertEqual(RecommendationSource.spotify.rawValue, "spotify")
        XCTAssertEqual(RecommendationSource.library.rawValue, "library")
    }

    func testRecommendationSourceFromRawValue() {
        XCTAssertEqual(RecommendationSource(rawValue: "spotify"), .spotify)
        XCTAssertEqual(RecommendationSource(rawValue: "library"), .library)
        XCTAssertNil(RecommendationSource(rawValue: "unknown"))
    }

    // MARK: - LibraryIndex

    func testLibraryIndexCanBeEmpty() {
        // Should not crash with all-empty collections
        let index = LibraryIndex(albumKeys: [], topGenres: [], topArtists: [])
        XCTAssertTrue(index.albumKeys.isEmpty)
        XCTAssertTrue(index.topGenres.isEmpty)
        XCTAssertTrue(index.topArtists.isEmpty)
    }

    func testLibraryIndexStoresValues() {
        let albumKeys: Set<String> = ["artist1||album1", "artist2||album2"]
        let topGenres = ["Rock", "Pop"]
        let topArtists = ["The Beatles", "Led Zeppelin"]
        let index = LibraryIndex(albumKeys: albumKeys, topGenres: topGenres, topArtists: topArtists)
        XCTAssertEqual(index.albumKeys, albumKeys)
        XCTAssertEqual(index.topGenres, topGenres)
        XCTAssertEqual(index.topArtists, topArtists)
    }

    // MARK: - GenreSlice

    func testGenreSliceHasNonNegativeCount() {
        let slice = GenreSlice(id: UUID(), name: "Rock", count: 5, colorIndex: 0)
        XCTAssertEqual(slice.count, 5)
        XCTAssertGreaterThanOrEqual(slice.count, 0)
    }

    func testGenreSliceNameIsStored() {
        let slice = GenreSlice(id: UUID(), name: "Jazz", count: 3, colorIndex: 2)
        XCTAssertEqual(slice.name, "Jazz")
    }

    func testGenreSliceColorIndex() {
        let slice = GenreSlice(id: UUID(), name: "Blues", count: 1, colorIndex: 7)
        XCTAssertEqual(slice.colorIndex, 7)
    }

    // MARK: - AlbumInfo

    func testAlbumInfoHasArtist() {
        let album = AlbumInfo(
            id: UUID(),
            artist: "Pink Floyd",
            album: "The Wall",
            genre: "Rock",
            trackCount: 26,
            artworkFileURL: nil
        )
        XCTAssertEqual(album.artist, "Pink Floyd")
    }

    func testAlbumInfoHasAlbumTitle() {
        let album = AlbumInfo(
            id: UUID(),
            artist: "Pink Floyd",
            album: "The Wall",
            genre: "Rock",
            trackCount: 26,
            artworkFileURL: nil
        )
        XCTAssertEqual(album.album, "The Wall")
    }

    func testAlbumInfoTrackCount() {
        let album = AlbumInfo(
            id: UUID(),
            artist: "Metallica",
            album: "Master of Puppets",
            genre: "Metal",
            trackCount: 8,
            artworkFileURL: nil
        )
        XCTAssertEqual(album.trackCount, 8)
    }

    func testAlbumInfoArtworkFileURLOptional() {
        let albumNoArt = AlbumInfo(
            id: UUID(),
            artist: "Artist",
            album: "Album",
            genre: "Rock",
            trackCount: 1,
            artworkFileURL: nil
        )
        XCTAssertNil(albumNoArt.artworkFileURL)

        let url = URL(fileURLWithPath: "/tmp/artwork.jpg")
        let albumWithArt = AlbumInfo(
            id: UUID(),
            artist: "Artist",
            album: "Album",
            genre: "Rock",
            trackCount: 1,
            artworkFileURL: url
        )
        XCTAssertEqual(albumWithArt.artworkFileURL, url)
    }

    // MARK: - Recommendation

    func testRecommendationSourceProperty() {
        let rec = Recommendation(
            id: UUID(),
            sourceId: "abc123",
            title: "Album Title",
            subtitle: "Artist Name",
            genre: "Pop",
            spotifyURL: nil,
            artworkURL: nil,
            artworkData: nil,
            source: .spotify
        )
        XCTAssertEqual(rec.source, .spotify)
    }

    func testRecommendationLibrarySource() {
        let rec = Recommendation(
            id: UUID(),
            sourceId: nil,
            title: "Local Album",
            subtitle: "Local Artist",
            genre: "Jazz",
            spotifyURL: nil,
            artworkURL: nil,
            artworkData: nil,
            source: .library
        )
        XCTAssertEqual(rec.source, .library)
        XCTAssertNil(rec.sourceId)
    }

    // MARK: - AlbumLookup (legacy compatibility type)

    func testAlbumLookupKeyProperty() {
        let lookup = AlbumLookup(key: "artist||album", artist: "Artist", album: "Album")
        XCTAssertEqual(lookup.key, "artist||album")
        XCTAssertEqual(lookup.artist, "Artist")
        XCTAssertEqual(lookup.album, "Album")
    }

    func testAlbumLookupHashable() {
        let l1 = AlbumLookup(key: "a||b", artist: "A", album: "B")
        let l2 = AlbumLookup(key: "a||b", artist: "A", album: "B")
        var set = Set<AlbumLookup>()
        set.insert(l1)
        set.insert(l2)
        XCTAssertEqual(set.count, 1)
    }
}
