import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var tracks: [TrackInfo] = []
    @Published var genreSlices: [GenreSlice] = []
    @Published var selectedGenre: String? = nil
    @Published var recommendations: [Recommendation] = []
    @Published var status: String = "Ready"
    @Published var isScanning: Bool = false
    @Published var showSpotifySheet: Bool = false

    @Published var spotifyClientId: String = ""
    @Published var spotifyClientSecret: String = ""
    @Published var spotifyConnected: Bool = false

    private let defaults = UserDefaults.standard
    private let onlineGenreResolver = OnlineGenreResolver()
    private var spotifyClient: (any SpotifyClientProtocol)?
    private var libraryIndex: LibraryIndex?
    private var lastSpotifyAlbumIDs: Set<String> = []
    private var latestScanID: UUID = UUID()

    private let lastSpotifyAlbumsKey = "last_spotify_album_ids"

    init() {
        spotifyClientId = defaults.string(forKey: "spotify_client_id") ?? ""
        spotifyClientSecret = defaults.string(forKey: "spotify_client_secret") ?? ""
        refreshSpotifyClient()
        lastSpotifyAlbumIDs = Set(UserDefaults.standard.stringArray(forKey: lastSpotifyAlbumsKey) ?? [])
    }

    /// For dependency injection in tests only.
    func _setSpotifyClientForTesting(_ client: any SpotifyClientProtocol) {
        self.spotifyClient = client
    }

    func scanITunesLibrary() {
        guard !isScanning else { return }
        isScanning = true
        status = "Scanning iTunes/Music library..."

        Task {
            let scanner = LibraryScanner()
            do {
                let tracks = try await scanner.scanITunesLibrary { count in
                    self.status = "Scanning iTunes/Music library... (\(count) files)"
                }
                applyScanResults(tracks)
                isScanning = false
            } catch {
                status = "Scan failed: \(displayMessage(for: error))"
                isScanning = false
            }
        }
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            scanFolder(url)
        }
    }

    func scanFolder(_ folderURL: URL) {
        guard !isScanning else { return }
        isScanning = true
        status = "Scanning folder..."

        Task {
            let scanner = LibraryScanner()
            let tracks = await scanner.scanFolder(folderURL: folderURL) { count in
                self.status = "Scanning folder... (\(count) files)"
            }
            applyScanResults(tracks)
            isScanning = false
        }
    }

    func selectGenre(_ genre: String) {
        selectedGenre = genre
        recommend()
    }

    func recommend() {
        guard !tracks.isEmpty else {
            status = "No tracks to recommend from yet."
            return
        }
        guard let spotifyClient else {
            status = "Please set Spotify credentials to get new album recommendations."
            return
        }
        guard let libraryIndex else {
            status = "Please scan your library first."
            return
        }

        let genre = selectedGenre ?? genreSlices.first?.name ?? "Other"
        selectedGenre = genre
        status = "Generating Spotify recommendations..."

        Task {
            do {
                let recs = try await spotifyClient.recommendAlbumsNotInLibrary(
                    libraryIndex: libraryIndex,
                    focusGenre: genre == "Other" ? nil : genre,
                    limit: 8,
                    avoidAlbumIDs: lastSpotifyAlbumIDs
                )
                if recs.isEmpty {
                    status = "No new albums found. Try another genre."
                    recommendations = []
                    return
                }
                recommendations = recs
                lastSpotifyAlbumIDs = Set(recs.compactMap { $0.sourceId })
                UserDefaults.standard.set(Array(lastSpotifyAlbumIDs), forKey: lastSpotifyAlbumsKey)
                status = "Spotify recommendations (not in your library)"
            } catch {
                status = "Spotify failed: \(displayMessage(for: error))"
            }
        }
    }

    func saveSpotifyCredentials() {
        defaults.set(spotifyClientId, forKey: "spotify_client_id")
        defaults.set(spotifyClientSecret, forKey: "spotify_client_secret")
        refreshSpotifyClient()
    }

    func clearSpotifyCredentials() {
        spotifyClientId = ""
        spotifyClientSecret = ""
        defaults.removeObject(forKey: "spotify_client_id")
        defaults.removeObject(forKey: "spotify_client_secret")
        refreshSpotifyClient()
    }

    private func refreshSpotifyClient() {
        if !spotifyClientId.isEmpty && !spotifyClientSecret.isEmpty {
            spotifyClient = SpotifyClient(config: .init(clientId: spotifyClientId, clientSecret: spotifyClientSecret))
            spotifyConnected = true
        } else {
            spotifyClient = nil
            spotifyConnected = false
        }
    }

    private func applyScanResults(_ tracks: [TrackInfo]) {
        self.tracks = tracks
        refreshDerivedState(with: tracks)

        let scanID = UUID()
        latestScanID = scanID
        status = "Scan complete. \(tracks.count) tracks. Matching album genres online..."

        Task {
            await enrichGenresFromOnline(scanID: scanID, baseTracks: tracks)
        }
    }

    private func refreshDerivedState(with tracks: [TrackInfo]) {
        let result = RecommendationEngine.genreSlices(from: tracks, maxSlices: 8)
        self.genreSlices = result.slices
        self.libraryIndex = RecommendationEngine.buildLibraryIndex(from: tracks, topLimit: 8)
        if let current = selectedGenre, result.slices.contains(where: { $0.name == current }) {
            selectedGenre = current
        } else {
            selectedGenre = result.slices.first?.name
        }
    }

    private func enrichGenresFromOnline(scanID: UUID, baseTracks: [TrackInfo]) async {
        let albums = RecommendationEngine.uniqueAlbums(from: baseTracks)
        guard !albums.isEmpty else {
            if scanID == latestScanID {
                status = "Scan complete. \(baseTracks.count) tracks."
            }
            return
        }

        do {
            let resolvedGenres = try await onlineGenreResolver.resolveGenres(for: albums)
            guard scanID == latestScanID else { return }

            if resolvedGenres.isEmpty {
                status = "Scan complete. \(baseTracks.count) tracks. Online genre matching returned no results."
                return
            }

            let enrichedTracks = applyResolvedGenres(resolvedGenres, to: baseTracks)
            self.tracks = enrichedTracks
            refreshDerivedState(with: enrichedTracks)
            status = "Scan complete. \(enrichedTracks.count) tracks. Online genres matched for \(resolvedGenres.count) albums."
        } catch {
            guard scanID == latestScanID else { return }
            status = "Scan complete. \(baseTracks.count) tracks. Online genre matching unavailable: \(displayMessage(for: error))"
        }
    }

    private func applyResolvedGenres(_ resolvedGenres: [String: String], to tracks: [TrackInfo]) -> [TrackInfo] {
        tracks.map { track in
            let key = RecommendationEngine.albumKey(artist: track.artist, album: track.album)
            guard let onlineGenre = resolvedGenres[key], !onlineGenre.isEmpty else {
                return track
            }
            guard onlineGenre != track.genre else {
                return track
            }
            return TrackInfo(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                genre: onlineGenre,
                fileURL: track.fileURL,
                duration: track.duration
            )
        }
    }

    private func displayMessage(for error: Error) -> String {
        if let spotifyError = error as? SpotifyError {
            return spotifyError.localizedDescription
        }

        if let onlineGenreError = error as? OnlineGenreError {
            return onlineGenreError.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Cannot resolve Spotify host. In Xcode App Sandbox, enable Network -> Outgoing Connections (Client)."
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
                return "Network unavailable while contacting Spotify."
            default:
                return urlError.localizedDescription
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 4097 {
            let lower = nsError.localizedDescription.lowercased()
            if lower.contains("amp.library.framework") {
                return "Music library service unavailable. Open Music app once, grant Media & Apple Music permission, and verify sandbox music access."
            }
        }

        return error.localizedDescription
    }
}
