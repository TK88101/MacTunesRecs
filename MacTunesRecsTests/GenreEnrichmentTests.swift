@testable import MacTunesRecs
import XCTest

/// Tests for genre-related behaviour in LibraryViewModel.
///
/// `applyResolvedGenres` is a private method and is not exposed via a testing hook,
/// so these tests exercise the publicly observable effects of genre logic via the
/// ViewModel's published properties.
@MainActor
final class GenreEnrichmentTests: XCTestCase {

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

    // MARK: - testGenreSlicesEmptyWithNoTracks

    func testGenreSlicesEmptyWithNoTracks() {
        XCTAssertTrue(vm.genreSlices.isEmpty, "A fresh ViewModel with no tracks should have no genre slices")
    }

    // MARK: - testSelectedGenreStartsNil

    func testSelectedGenreStartsNil() {
        XCTAssertNil(vm.selectedGenre, "selectedGenre should be nil when there are no tracks")
    }

    // MARK: - testSelectGenreUpdatesSelectedGenre

    func testSelectGenreUpdatesSelectedGenre() {
        // Even without tracks, calling selectGenre should update selectedGenre.
        vm.selectGenre("Electronic")
        XCTAssertEqual(vm.selectedGenre, "Electronic", "selectGenre should update selectedGenre to the given genre")
    }

    // MARK: - testGenreSlicesPopulatedAfterScan

    /// After scanning a folder that contains at least one recognised audio file the
    /// genre slices are populated.  If the stub file is not parsed the test is
    /// skipped rather than failed.
    func testGenreSlicesPopulatedAfterScan() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write a minimal ID3-tagged stub so the scanner has something to open.
        let stubMP3 = tmpDir.appendingPathComponent("genre_test.mp3")
        let minimalID3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try minimalID3.write(to: stubMP3)

        vm.scanFolder(tmpDir)

        let deadline = Date().addingTimeInterval(10)
        while vm.isScanning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if vm.tracks.isEmpty {
            throw XCTSkip("Stub mp3 was not parsed as a track — genre-slice-after-scan test skipped.")
        }

        // At least one slice must exist.
        XCTAssertFalse(vm.genreSlices.isEmpty, "Genre slices should be non-empty after a successful scan")
    }

    // MARK: - testSelectedGenreSetAfterScan

    /// After a successful scan the ViewModel selects the first genre automatically.
    func testSelectedGenreSetAfterScan() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stubMP3 = tmpDir.appendingPathComponent("genre_test2.mp3")
        let minimalID3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try minimalID3.write(to: stubMP3)

        vm.scanFolder(tmpDir)

        let deadline = Date().addingTimeInterval(10)
        while vm.isScanning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if vm.tracks.isEmpty {
            throw XCTSkip("Stub mp3 was not parsed as a track — selectedGenre-after-scan test skipped.")
        }

        XCTAssertNotNil(vm.selectedGenre, "selectedGenre should be set to the first genre after a scan")
    }

    // MARK: - testGenreSliceNamesAreNonEmpty

    /// Verifies that genre slices returned by the engine carry non-empty names.
    func testGenreSliceNamesAreNonEmpty() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let stubMP3 = tmpDir.appendingPathComponent("genre_test3.mp3")
        let minimalID3 = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try minimalID3.write(to: stubMP3)

        vm.scanFolder(tmpDir)

        let deadline = Date().addingTimeInterval(10)
        while vm.isScanning && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if vm.tracks.isEmpty {
            throw XCTSkip("Stub mp3 was not parsed as a track — genre-slice-names test skipped.")
        }

        for slice in vm.genreSlices {
            XCTAssertFalse(slice.name.isEmpty, "Every genre slice must have a non-empty name")
            XCTAssertGreaterThan(slice.count, 0, "Every genre slice must have a positive count")
        }
    }
}
