import XCTest
@testable import MacTunesRecs

final class RecommendationEngineTests: XCTestCase {

    // MARK: - Helper

    private func makeTrack(
        title: String = "T",
        artist: String = "A",
        album: String = "Album",
        genre: String = "Rock",
        fileURL: URL = URL(fileURLWithPath: "/tmp/test.mp3")
    ) -> TrackInfo {
        TrackInfo(
            id: UUID(),
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            fileURL: fileURL,
            duration: nil
        )
    }

    // MARK: - genreSlices

    func testGenreSlicesEmpty() {
        let result = RecommendationEngine.genreSlices(from: [], maxSlices: 8)
        XCTAssertTrue(result.slices.isEmpty)
        XCTAssertTrue(result.majorGenres.isEmpty)
    }

    func testGenreSlicesSingleGenre() {
        let tracks = (0..<10).map { i in
            makeTrack(title: "Track\(i)", album: "Album\(i)", genre: "Rock")
        }
        let result = RecommendationEngine.genreSlices(from: tracks, maxSlices: 8)
        // All distinct albums, all "Rock" genre
        XCTAssertEqual(result.slices.count, 1)
        XCTAssertEqual(result.slices[0].name, "Rock")
        XCTAssertEqual(result.slices[0].count, 10)
        XCTAssertEqual(result.majorGenres, ["Rock"])
    }

    func testGenreSlicesMultipleGenres() {
        var tracks: [TrackInfo] = []
        // 3 albums each genre: Rock, Pop, Jazz — unique artist+album combos
        for i in 0..<3 {
            tracks.append(makeTrack(title: "R\(i)", artist: "ArtistR", album: "RockAlbum\(i)", genre: "Rock"))
        }
        for i in 0..<3 {
            tracks.append(makeTrack(title: "P\(i)", artist: "ArtistP", album: "PopAlbum\(i)", genre: "Pop"))
        }
        for i in 0..<3 {
            tracks.append(makeTrack(title: "J\(i)", artist: "ArtistJ", album: "JazzAlbum\(i)", genre: "Jazz"))
        }
        let result = RecommendationEngine.genreSlices(from: tracks, maxSlices: 8)
        // With maxSlices: 8 and 3 genres, all 3 fit as major slices — no "Other" bucket needed
        let nonOtherSlices = result.slices.filter { $0.name != "Other" }
        XCTAssertEqual(nonOtherSlices.count, 3)
        let genreNames = Set(nonOtherSlices.map { $0.name })
        XCTAssertTrue(genreNames.contains("Rock"))
        XCTAssertTrue(genreNames.contains("Pop"))
        XCTAssertTrue(genreNames.contains("Jazz"))
    }

    func testGenreSlicesMaxSlices() {
        // Create 10 genres with distinct artist+album combos
        let genreNames = ["Rock", "Pop", "Jazz", "Blues", "Metal", "Country", "Folk", "Electronic", "Punk", "Ambient"]
        var tracks: [TrackInfo] = []
        for (i, genre) in genreNames.enumerated() {
            // 2 albums per genre
            for j in 0..<2 {
                tracks.append(makeTrack(
                    title: "\(genre)T\(j)",
                    artist: "Artist\(i)",
                    album: "\(genre)Album\(j)",
                    genre: genre
                ))
            }
        }
        let maxSlices = 8
        let result = RecommendationEngine.genreSlices(from: tracks, maxSlices: maxSlices)
        // Total slices must not exceed maxSlices
        XCTAssertLessThanOrEqual(result.slices.count, maxSlices)
        // With 10 genres and maxSlices=8, there should be an "Other" bucket for the overflow
        let hasOther = result.slices.contains { $0.name == "Other" }
        XCTAssertTrue(hasOther, "Expected an 'Other' bucket when genres exceed maxSlices")
    }

    // MARK: - Genre Normalization (tested via genreSlices)

    func testGenreNormalizationRock() {
        // "rock" should normalize to "Rock"
        let track = makeTrack(album: "AlbumA", genre: "rock")
        let result = RecommendationEngine.genreSlices(from: [track], maxSlices: 8)
        let sliceNames = result.slices.map { $0.name }
        XCTAssertTrue(sliceNames.contains("Rock"), "Expected 'rock' to normalize to 'Rock', got: \(sliceNames)")
    }

    func testGenreNormalizationHipHop() {
        // "hip-hop" or "hiphop" should normalize to "Hip-Hop"
        let track = makeTrack(album: "AlbumB", genre: "hip-hop")
        let result = RecommendationEngine.genreSlices(from: [track], maxSlices: 8)
        // The canonical map uses "hiphop" -> "Hip-Hop"; "hip-hop" after normalizeKey strips "-" -> "hiphop"
        let sliceNames = result.slices.map { $0.name }
        XCTAssertTrue(sliceNames.contains("Hip-Hop"), "Expected 'hip-hop' to normalize to 'Hip-Hop', got: \(sliceNames)")
    }

    func testGenreNormalizationUnknownGenre() {
        // Empty genre should not crash and should produce "Unknown Genre" or "Other"
        let track = makeTrack(album: "AlbumC", genre: "")
        let result = RecommendationEngine.genreSlices(from: [track], maxSlices: 8)
        // Should produce at least one slice without crashing
        XCTAssertFalse(result.slices.isEmpty, "Expected at least one slice for empty genre input")
    }

    // MARK: - albumKey Deduplication

    func testAlbumKeyDeduplication() {
        // Same artist+album with different case should produce the same albumKey
        let key1 = RecommendationEngine.albumKey(artist: "The Beatles", album: "Abbey Road")
        let key2 = RecommendationEngine.albumKey(artist: "the beatles", album: "abbey road")
        let key3 = RecommendationEngine.albumKey(artist: "THE BEATLES", album: "ABBEY ROAD")
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key2, key3)
    }

    // MARK: - buildLibraryIndex

    func testBuildLibraryIndexTopGenres() {
        var tracks: [TrackInfo] = []
        // 10 albums per genre, 3 genres
        for i in 0..<10 {
            tracks.append(makeTrack(title: "R\(i)", artist: "ArtR", album: "RAlbum\(i)", genre: "Rock"))
        }
        for i in 0..<10 {
            tracks.append(makeTrack(title: "P\(i)", artist: "ArtP", album: "PAlbum\(i)", genre: "Pop"))
        }
        for i in 0..<10 {
            tracks.append(makeTrack(title: "J\(i)", artist: "ArtJ", album: "JAlbum\(i)", genre: "Jazz"))
        }
        let index = RecommendationEngine.buildLibraryIndex(from: tracks, topLimit: 50)
        XCTAssertEqual(index.topGenres.count, 3)
    }

    func testBuildLibraryIndexAlbumKeys() {
        // 5 tracks from 3 distinct albums
        let tracks = [
            makeTrack(title: "T1", artist: "Artist1", album: "Album1", genre: "Rock"),
            makeTrack(title: "T2", artist: "Artist1", album: "Album1", genre: "Rock"), // duplicate
            makeTrack(title: "T3", artist: "Artist2", album: "Album2", genre: "Pop"),
            makeTrack(title: "T4", artist: "Artist3", album: "Album3", genre: "Jazz"),
            makeTrack(title: "T5", artist: "Artist3", album: "Album3", genre: "Jazz"), // duplicate
        ]
        let index = RecommendationEngine.buildLibraryIndex(from: tracks, topLimit: 50)
        XCTAssertEqual(index.albumKeys.count, 3)
    }

    // MARK: - uniqueAlbums

    func testUniqueAlbums() {
        // 10 tracks from 3 albums
        var tracks: [TrackInfo] = []
        for i in 0..<4 {
            tracks.append(makeTrack(title: "T\(i)", artist: "A1", album: "Album1"))
        }
        for i in 0..<3 {
            tracks.append(makeTrack(title: "T\(i+4)", artist: "A2", album: "Album2"))
        }
        for i in 0..<3 {
            tracks.append(makeTrack(title: "T\(i+7)", artist: "A3", album: "Album3"))
        }
        let result = RecommendationEngine.uniqueAlbums(from: tracks)
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - dominantGenre (tested indirectly via genreSlices)

    func testDominantGenre() {
        // 3 "Metal" tracks + 2 "Rock" tracks all on the same album
        // The dominant genre for that album should be "Metal"
        let tracks = [
            makeTrack(title: "M1", artist: "Band", album: "Masterpiece", genre: "Metal"),
            makeTrack(title: "M2", artist: "Band", album: "Masterpiece", genre: "Metal"),
            makeTrack(title: "M3", artist: "Band", album: "Masterpiece", genre: "Metal"),
            makeTrack(title: "R1", artist: "Band", album: "Masterpiece", genre: "Rock"),
            makeTrack(title: "R2", artist: "Band", album: "Masterpiece", genre: "Rock"),
        ]
        // All tracks are on one album; genreSlices should produce a slice for "Metal"
        let result = RecommendationEngine.genreSlices(from: tracks, maxSlices: 8)
        let metalSlice = result.slices.first { $0.name == "Metal" }
        XCTAssertNotNil(metalSlice, "Expected a 'Metal' slice reflecting the dominant genre")
        // Should be 1 album counted in the Metal slice
        XCTAssertEqual(metalSlice?.count, 1)
        // There should be no Rock slice since the album's dominant genre is Metal
        let rockSlice = result.slices.first { $0.name == "Rock" }
        XCTAssertNil(rockSlice, "Expected no 'Rock' slice since the album's dominant genre is 'Metal'")
    }
}
