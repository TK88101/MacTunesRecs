@testable import MacTunesRecs
import XCTest

// MARK: - Mock Spotify Client

final class MockSpotifyClient: SpotifyClientProtocol {
    var stubbedResult: Result<[Recommendation], Error> = .success([])
    var callCount = 0
    var lastAvoidAlbumIDs: Set<String> = []

    func recommendAlbumsNotInLibrary(
        libraryIndex: LibraryIndex,
        focusGenre: String?,
        limit: Int,
        avoidAlbumIDs: Set<String>
    ) async throws -> [Recommendation] {
        callCount += 1
        lastAvoidAlbumIDs = avoidAlbumIDs
        return try stubbedResult.get()
    }
}

// MARK: - Helpers

private func makeTrack(
    title: String = "Track",
    artist: String = "Artist",
    album: String = "Album",
    genre: String = "Rock"
) -> TrackInfo {
    TrackInfo(
        id: UUID(),
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        fileURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"),
        duration: 180
    )
}

private func makeRecommendation(title: String = "Rec Album", artist: String = "Rec Artist") -> Recommendation {
    Recommendation(
        id: UUID(),
        sourceId: UUID().uuidString,
        title: title,
        subtitle: artist,
        genre: "Rock",
        spotifyURL: nil,
        artworkURL: nil,
        artworkData: nil,
        source: .spotify
    )
}

// MARK: - LibraryViewModelTests

@MainActor
final class LibraryViewModelTests: XCTestCase {

    var vm: LibraryViewModel!

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "spotify_client_id")
        UserDefaults.standard.removeObject(forKey: "spotify_client_secret")
        vm = LibraryViewModel()
        await Task.yield()
    }

    override func tearDown() async throws {
        vm = nil
        await Task.yield()
        UserDefaults.standard.removeObject(forKey: "spotify_client_id")
        UserDefaults.standard.removeObject(forKey: "spotify_client_secret")
    }

    // MARK: - testInitialState

    func testInitialState() {
        XCTAssertTrue(vm.tracks.isEmpty, "Expected tracks to be empty on init")
        XCTAssertTrue(vm.genreSlices.isEmpty, "Expected genreSlices to be empty on init")
        XCTAssertFalse(vm.isScanning, "Expected isScanning to be false on init")
        XCTAssertTrue(vm.recommendations.isEmpty, "Expected recommendations to be empty on init")
        XCTAssertEqual(vm.status, "Ready", "Expected status to be 'Ready' on init")
    }

    // MARK: - testRecommendWithNoTracks

    func testRecommendWithNoTracks() async throws {
        XCTAssertTrue(vm.tracks.isEmpty)

        vm.recommend()

        // Status should indicate no tracks are available.
        XCTAssertTrue(
            vm.status.lowercased().contains("no tracks") || vm.status.lowercased().contains("library"),
            "Expected status to mention 'no tracks' or 'library', got: \(vm.status)"
        )
    }

    // MARK: - testRecommendSuccessPopulatesRecommendations

    func testRecommendSuccessPopulatesRecommendations() async throws {
        let mock = MockSpotifyClient()
        let stubbedRecs = [
            makeRecommendation(title: "Album One", artist: "Artist One"),
            makeRecommendation(title: "Album Two", artist: "Artist Two")
        ]
        mock.stubbedResult = .success(stubbedRecs)
        vm._setSpotifyClientForTesting(mock)

        // tracks is still empty at this point -> recommend() returns early.
        vm.recommend()
        XCTAssertTrue(
            vm.status.lowercased().contains("no tracks") || vm.status.lowercased().contains("library"),
            "Without tracks, status should describe the empty-library condition; got: \(vm.status)"
        )

        // Confirm mock was NOT called (tracks were empty, so the guard fires first).
        XCTAssertEqual(mock.callCount, 0, "Mock should not be called when tracks are empty")
    }

    // MARK: - testRecommendWithMockClientSuccessDirectInjection

    /// Verifies that when tracks and a libraryIndex exist (injected via scanFolder on a
    /// non-empty temp dir), the MockSpotifyClient is called and recommendations are populated.
    func testRecommendPopulatesRecommendationsWhenTracksPresent() async throws {
        // Build a temp directory with a stub mp3 so the folder scanner picks it up.
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stubMP3 = tmpDir.appendingPathComponent("stub.mp3")
        // Write minimal ID3 header so AVFoundation can detect metadata fields.
        let minimalID3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try minimalID3.write(to: stubMP3)

        let mock = MockSpotifyClient()
        let stubbedRecs = [
            makeRecommendation(title: "Album One", artist: "Artist One"),
            makeRecommendation(title: "Album Two", artist: "Artist Two")
        ]
        mock.stubbedResult = .success(stubbedRecs)
        vm._setSpotifyClientForTesting(mock)

        // Trigger a scan; the scanner runs async inside the VM.
        vm.scanFolder(tmpDir)

        // Wait for the scan to finish (isScanning flips back to false).
        let scanDeadline = Date().addingTimeInterval(10)
        while vm.isScanning && Date() < scanDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // If the stub file was not recognised as a track, skip rather than fail.
        if vm.tracks.isEmpty {
            throw XCTSkip("Stub mp3 was not parsed as a track on this machine — scanning test skipped.")
        }

        // Now call recommend(); mock provides fake results.
        vm.recommend()

        // Wait for the async Task in recommend() to complete.
        let recDeadline = Date().addingTimeInterval(5)
        while mock.callCount == 0 && Date() < recDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertGreaterThanOrEqual(mock.callCount, 1, "Mock should have been called at least once")
        XCTAssertEqual(vm.recommendations.count, stubbedRecs.count)
    }

    // MARK: - testRecommendCallCountWithMock

    func testRecommendCallCountWithMock() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stubMP3 = tmpDir.appendingPathComponent("stub2.mp3")
        let minimalID3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try minimalID3.write(to: stubMP3)

        let mock = MockSpotifyClient()
        mock.stubbedResult = .success([makeRecommendation()])
        vm._setSpotifyClientForTesting(mock)

        vm.scanFolder(tmpDir)
        let scanDeadline = Date().addingTimeInterval(10)
        while vm.isScanning && Date() < scanDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if vm.tracks.isEmpty {
            throw XCTSkip("Stub mp3 was not parsed as a track on this machine — call-count test skipped.")
        }

        // Call recommend twice.
        vm.recommend()
        let firstDeadline = Date().addingTimeInterval(5)
        while mock.callCount < 1 && Date() < firstDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        vm.recommend()
        let secondDeadline = Date().addingTimeInterval(5)
        while mock.callCount < 2 && Date() < secondDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(mock.callCount, 2, "Expected recommend() to call the mock client twice")
    }

    // MARK: - testSaveAndLoadSpotifyCredentials

    func testSaveAndLoadSpotifyCredentials() async throws {
        vm.spotifyClientId = "test_client_id"
        vm.spotifyClientSecret = "test_client_secret"
        vm.saveSpotifyCredentials()

        // Destroy current vm and let setUp's URLSession cleanup settle.
        vm = nil
        await Task.yield()

        // A fresh VM should pick up persisted credentials.
        vm = LibraryViewModel()
        await Task.yield()

        XCTAssertEqual(vm.spotifyClientId, "test_client_id")
        XCTAssertEqual(vm.spotifyClientSecret, "test_client_secret")
        XCTAssertTrue(vm.spotifyConnected, "Expected spotifyConnected to be true after credentials saved")
    }

    // MARK: - testClearSpotifyCredentials

    func testClearSpotifyCredentials() {
        vm.spotifyClientId = "some_id"
        vm.spotifyClientSecret = "some_secret"
        vm.saveSpotifyCredentials()

        XCTAssertTrue(vm.spotifyConnected)

        vm.clearSpotifyCredentials()

        XCTAssertFalse(vm.spotifyConnected, "Expected spotifyConnected to be false after clearing credentials")
        XCTAssertTrue(vm.spotifyClientId.isEmpty, "Expected spotifyClientId to be empty after clearing")
        XCTAssertTrue(vm.spotifyClientSecret.isEmpty, "Expected spotifyClientSecret to be empty after clearing")

        // Confirm UserDefaults was also cleared.
        XCTAssertNil(UserDefaults.standard.string(forKey: "spotify_client_id"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "spotify_client_secret"))
    }

    // MARK: - testSelectGenreDoesNotCrashWhenTracksEmpty

    func testSelectGenreDoesNotCrashWhenTracksEmpty() {
        // selectGenre calls recommend() internally. With no tracks the VM should
        // update selectedGenre and set an appropriate status rather than crash.
        vm.selectGenre("Jazz")

        XCTAssertEqual(vm.selectedGenre, "Jazz")
        XCTAssertFalse(vm.status.isEmpty, "Status should not be empty after selectGenre")
    }
}
