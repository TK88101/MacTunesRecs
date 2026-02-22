import XCTest
@testable import MacTunesRecs

/// Tests for SpotifyClient genre-matching and normalization helpers.
/// These use the `_matchGenreForTesting` and `_normalizeForTesting` hooks
/// added to SpotifyClient as an internal testing extension.
final class SpotifyClientGenreMatchTests: XCTestCase {

    // MARK: - _normalizeForTesting

    func testNormalizeStripsSpecialChars() {
        // "Hip-Hop" -> lowercase, no hyphens -> "hiphop"
        let result = SpotifyClient._normalizeForTesting("Hip-Hop")
        XCTAssertEqual(result, "hiphop")
    }

    func testNormalizeStripsSpaces() {
        let result = SpotifyClient._normalizeForTesting("hard rock")
        XCTAssertEqual(result, "hardrock")
    }

    func testNormalizeEmpty() {
        // Empty string should not crash and should return empty string
        let result = SpotifyClient._normalizeForTesting("")
        XCTAssertEqual(result, "")
    }

    func testNormalizeLowercasesInput() {
        let result = SpotifyClient._normalizeForTesting("ROCK")
        XCTAssertEqual(result, "rock")
    }

    // MARK: - _matchGenreForTesting

    func testMatchGenreExact() {
        // "rock" is in the available list — should return "rock"
        let result = SpotifyClient._matchGenreForTesting(localGenre: "rock", availableGenres: ["rock", "pop"])
        XCTAssertEqual(result, "rock")
    }

    func testMatchGenreNoMatch() {
        // "gregorian-chant" normalized is "gregorianchant" — no match in ["rock", "pop"]
        let result = SpotifyClient._matchGenreForTesting(localGenre: "gregorian-chant", availableGenres: ["rock", "pop"])
        XCTAssertNil(result)
    }

    func testMatchGenreCaseInsensitive() {
        // "ROCK" normalized is "rock" — should match "rock" in available list
        let result = SpotifyClient._matchGenreForTesting(localGenre: "ROCK", availableGenres: ["rock"])
        XCTAssertEqual(result, "rock")
    }

    func testMatchGenreEmptyAvailable() {
        // Any local genre against an empty list should return nil
        let result = SpotifyClient._matchGenreForTesting(localGenre: "rock", availableGenres: [])
        XCTAssertNil(result)
    }

    func testMatchGenreSubstringMatch() {
        // "hard-rock" normalized is "hardrock"; "hard-rock" candidate normalized is "hardrock" — exact match
        let result = SpotifyClient._matchGenreForTesting(localGenre: "hard-rock", availableGenres: ["hard-rock", "pop"])
        XCTAssertEqual(result, "hard-rock")
    }

    func testMatchGenrePrefersBetterScore() {
        // "metal" normalized is "metal"; "metal" exact > "heavy-metal" substring
        // The scoring prefers exact match (score 10000) over substring (score 1000+len)
        let result = SpotifyClient._matchGenreForTesting(localGenre: "metal", availableGenres: ["heavy-metal", "metal"])
        XCTAssertEqual(result, "metal")
    }
}
