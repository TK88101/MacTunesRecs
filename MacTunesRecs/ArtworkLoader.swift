import Foundation
import AVFoundation
import AppKit

enum ArtworkLoader {
    static func loadArtworkData(from fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in metadata {
            if item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
                if let data = try? await item.load(.dataValue) {
                    return data
                }
            }
        }
        return nil
    }

    static func loadArtworkImage(from fileURL: URL) async -> NSImage? {
        guard let data = await loadArtworkData(from: fileURL) else { return nil }
        return NSImage(data: data)
    }
}
