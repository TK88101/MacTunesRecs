import Foundation
import AVFoundation
#if canImport(iTunesLibrary)
import iTunesLibrary
#endif

final class LibraryScanner {
    private let supportedExtensions: Set<String> = ["m4a", "mp3", "aac", "flac", "wav", "aiff"]

    func scanITunesLibrary(progress: @escaping (Int) -> Void) async throws -> [TrackInfo] {
        #if canImport(iTunesLibrary)
        let library = try ITLibrary(apiVersion: "1.0")
        let items = library.allMediaItems
        var results: [TrackInfo] = []
        results.reserveCapacity(items.count)
        var count = 0
        for item in items {
            guard let url = item.location else { continue }
            let title = item.title.isEmpty ? url.deletingPathExtension().lastPathComponent : item.title
            let albumArtist = item.album.albumArtist ?? item.artist?.name ?? "Unknown Artist"
            let album = item.album.title ?? "Unknown Album"
            let genre = item.genre.isEmpty ? "Unknown Genre" : item.genre
            let duration = item.totalTime > 0 ? TimeInterval(item.totalTime) / 1000.0 : nil

            results.append(TrackInfo(
                id: UUID(),
                title: title,
                artist: albumArtist,
                album: album,
                genre: genre,
                fileURL: url,
                duration: duration
            ))

            count += 1
            if count % 50 == 0 {
                progress(count)
                await Task.yield()
            }
        }
        progress(count)
        return results
        #else
        throw NSError(domain: "LibraryScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "iTunesLibrary framework not available."])
        #endif
    }

    func scanFolder(folderURL: URL, progress: @escaping (Int) -> Void) async -> [TrackInfo] {
        var urls: [URL] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            while let fileURL = enumerator.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if supportedExtensions.contains(ext) {
                    urls.append(fileURL)
                }
            }
        }
        return await scanURLs(urls: urls, progress: progress)
    }

    private func scanURLs(urls: [URL], progress: @escaping (Int) -> Void) async -> [TrackInfo] {
        var results: [TrackInfo] = []
        results.reserveCapacity(urls.count)
        var count = 0
        for url in urls {
            if let info = await Self.readMetadata(from: url) {
                results.append(info)
            }
            count += 1
            if count % 50 == 0 {
                progress(count)
                await Task.yield()
            }
        }
        progress(count)
        return results
    }

    private static func readMetadata(from url: URL) async -> TrackInfo? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []
        let title = await metadataString(metadata, key: .commonKeyTitle) ?? url.deletingPathExtension().lastPathComponent
        let artist = await metadataString(metadata, key: .commonKeyArtist) ?? "Unknown Artist"
        let album = await metadataString(metadata, key: .commonKeyAlbumName) ?? "Unknown Album"
        let genre = await genreString(metadata) ?? "Unknown Genre"
        let duration = (try? await asset.load(.duration)).flatMap { $0.isNumeric ? $0.seconds : nil }

        return TrackInfo(
            id: UUID(),
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            fileURL: url,
            duration: duration
        )
    }

    private static func metadataString(_ metadata: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        for item in metadata {
            if item.commonKey?.rawValue == key.rawValue {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func genreString(_ metadata: [AVMetadataItem]) async -> String? {
        let identifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataUserGenre,
            .iTunesMetadataPredefinedGenre,
            .iTunesMetadataGenreID,
            .quickTimeMetadataGenre,
            .quickTimeUserDataGenre
        ]

        for identifier in identifiers {
            if let item = metadata.first(where: { $0.identifier == identifier }) {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }

        if let item = metadata.first(where: { $0.commonKey?.rawValue == "genre" }) {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
