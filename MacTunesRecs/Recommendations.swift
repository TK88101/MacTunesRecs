import Foundation

/// Pure-logic namespace for all recommendation and library-analysis algorithms.
enum RecommendationEngine {
    /// Computes pie-chart slices from the track list, rolling small genres into an "Other" bucket.
    /// Returns the slices and the list of major genre names (excludes "Other").
    static func genreSlices(from tracks: [TrackInfo], maxSlices: Int) -> (slices: [GenreSlice], majorGenres: [String]) {
        let albums = albumInfos(from: tracks)
        var counts: [String: Int] = [:]
        for album in albums {
            let key = normalizedGenre(album.genre)
            counts[key, default: 0] += 1
        }
        guard !counts.isEmpty else { return ([], []) }

        // Keep "Other" as a single final bucket; do not let it appear in top slices.
        let explicitOther = counts["Other"] ?? 0
        let sortedNonOther = counts
            .filter { $0.key != "Other" }
            .sorted { $0.value > $1.value }

        let maxMain = max(1, maxSlices - 1)
        var slices: [GenreSlice] = []
        var majorGenres: [String] = []
        var rolledUpOther = explicitOther

        for (index, entry) in sortedNonOther.enumerated() {
            if index < maxMain {
                let slice = GenreSlice(id: UUID(), name: entry.key, count: entry.value, colorIndex: index)
                slices.append(slice)
                majorGenres.append(entry.key)
            } else {
                rolledUpOther += entry.value
            }
        }

        // If everything is "Other", still show one slice.
        if slices.isEmpty && rolledUpOther == 0 {
            rolledUpOther = counts.values.reduce(0, +)
        }

        if rolledUpOther > 0 {
            slices.append(GenreSlice(id: UUID(), name: "Other", count: rolledUpOther, colorIndex: slices.count))
        }
        return (slices, majorGenres)
    }

    /// Builds a `LibraryIndex` containing deduplication keys, top genres, and top artists up to `topLimit` entries each.
    static func buildLibraryIndex(from tracks: [TrackInfo], topLimit: Int) -> LibraryIndex {
        let albums = albumInfos(from: tracks)
        var albumKeys = Set<String>()
        albumKeys.reserveCapacity(albums.count)
        for album in albums {
            albumKeys.insert(albumKey(artist: album.artist, album: album.album))
        }

        var genreCounts: [String: Int] = [:]
        for album in albums {
            let key = normalizedGenre(album.genre)
            genreCounts[key, default: 0] += 1
        }
        let topGenres = genreCounts
            .filter { $0.key != "Unknown Genre" && $0.key != "Other" }
            .sorted { $0.value > $1.value }
            .map { $0.key }
            .prefix(topLimit)

        var artistCounts: [String: Int] = [:]
        for track in tracks {
            let artist = normalizedArtist(track.artist)
            artistCounts[artist, default: 0] += 1
        }
        let topArtists = artistCounts
            .filter { !$0.key.isEmpty }
            .sorted { $0.value > $1.value }
            .map { $0.key }
            .prefix(topLimit)

        return LibraryIndex(
            albumKeys: albumKeys,
            topGenres: Array(topGenres),
            topArtists: Array(topArtists)
        )
    }

    static func makeLocalRecommendations(genre: String, tracks: [TrackInfo], majorGenres: [String], limit: Int) async -> [Recommendation] {
        let filtered: [TrackInfo]
        if genre == "Other" {
            filtered = tracks.filter { !majorGenres.contains(normalizedGenre($0.genre)) }
        } else {
            filtered = tracks.filter { normalizedGenre($0.genre) == normalizedGenre(genre) }
        }

        let albums = albumInfos(from: filtered)
        let shuffled = albums.shuffled()
        let selected = shuffled.prefix(limit)

        var recommendations: [Recommendation] = []
        recommendations.reserveCapacity(selected.count)
        for album in selected {
            let artworkData: Data?
            if let fileURL = album.artworkFileURL {
                artworkData = await ArtworkLoader.loadArtworkData(from: fileURL)
            } else {
                artworkData = nil
            }
            recommendations.append(Recommendation(
                id: UUID(),
                sourceId: nil,
                title: album.album,
                subtitle: album.artist,
                genre: album.genre,
                spotifyURL: nil,
                artworkURL: nil,
                artworkData: artworkData,
                source: .library
            ))
        }
        return recommendations
    }

    /// Returns a stable, case-folded deduplication key in the form `"normalizedArtist||normalizedAlbum"`.
    static func albumKey(artist: String, album: String) -> String {
        "\(normalizeKey(artist))||\(normalizeKey(album))"
    }

    static func uniqueAlbums(from tracks: [TrackInfo]) -> [(key: String, artist: String, album: String)] {
        var seen = Set<String>()
        var albums: [(key: String, artist: String, album: String)] = []
        albums.reserveCapacity(tracks.count / 5)
        for track in tracks {
            let key = albumKey(artist: track.artist, album: track.album)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            albums.append((key: key, artist: track.artist, album: track.album))
        }
        return albums
    }

    private static func albumInfos(from tracks: [TrackInfo]) -> [AlbumInfo] {
        var grouped: [String: [TrackInfo]] = [:]
        for track in tracks {
            let key = albumKey(artist: track.artist, album: track.album)
            grouped[key, default: []].append(track)
        }
        return grouped.values.map { group in
            let first = group[0]
            let dominant = dominantGenre(from: group)
            return AlbumInfo(
                id: UUID(),
                artist: first.artist,
                album: first.album,
                genre: dominant,
                trackCount: group.count,
                artworkFileURL: first.fileURL
            )
        }
    }

    private static func dominantGenre(from tracks: [TrackInfo]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for track in tracks {
            let genre = normalizedGenre(track.genre)
            if counts[genre] == nil {
                order.append(genre)
            }
            counts[genre, default: 0] += 1
        }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                let leftIndex = order.firstIndex(of: lhs.key) ?? 0
                let rightIndex = order.firstIndex(of: rhs.key) ?? 0
                return leftIndex < rightIndex
            }
            return lhs.value > rhs.value
        }
        return sorted.first?.key ?? "Unknown Genre"
    }

    private static func normalizedGenre(_ genre: String) -> String {
        let trimmed = genre.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Genre" }

        let key = canonicalLookupKey(trimmed)
        if let mapped = canonicalGenreMap[key] {
            return mapped
        }

        // Keep English-like genre names readable, fallback to Other for non-Latin unmatched labels.
        if isMostlyLatin(trimmed) {
            return prettifyGenre(trimmed)
        }
        return "Other"
    }

    private static func normalizedArtist(_ artist: String) -> String {
        artist.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private static func normalizeKey(_ value: String) -> String {
        let lower = value.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let allowed = lower.filter { $0.isLetter || $0.isNumber }
        return allowed
    }

    private static func canonicalLookupKey(_ value: String) -> String {
        let base = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let latin = base.applyingTransform(.toLatin, reverse: false) ?? base
        let folded = latin.folding(
            options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return normalizeKey(folded)
    }

    private static func isMostlyLatin(_ value: String) -> Bool {
        var total = 0
        var latin = 0
        for scalar in value.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                total += 1
                if scalar.isASCII {
                    latin += 1
                }
            }
        }
        if total == 0 { return true }
        return Double(latin) / Double(total) >= 0.7
    }

    private static func prettifyGenre(_ value: String) -> String {
        let lowered = value.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let words = lowered.split(separator: " ").map { token -> String in
            switch token {
            case "rnb":
                return "R&B"
            case "edm":
                return "EDM"
            case "hiphop":
                return "Hip-Hop"
            default:
                return token.prefix(1).uppercased() + token.dropFirst()
            }
        }
        let joined = words.joined(separator: " ")
        return joined.isEmpty ? "Unknown Genre" : joined
    }

    private static let canonicalGenreMap: [String: String] = [
        "metal": "Metal",
        "metaru": "Metal",
        "heavymetal": "Metal",
        "hardrock": "Hard Rock",
        "rock": "Rock",
        "rokku": "Rock",
        "alternativerock": "Alternative",
        "alternative": "Alternative",
        "indierock": "Indie Rock",
        "indie": "Indie Rock",
        "blackmetal": "Black Metal",
        "deathmetal": "Death Metal",
        "thrashmetal": "Thrash Metal",
        "doommetal": "Doom Metal",
        "powermetal": "Power Metal",
        "progressivemetal": "Progressive Metal",
        "metalcore": "Metalcore",
        "deathcore": "Deathcore",
        "pop": "Pop",
        "poppu": "Pop",
        "jpop": "J-Pop",
        "kpop": "K-Pop",
        "hiphop": "Hip-Hop",
        "rap": "Hip-Hop",
        "rnb": "R&B",
        "randb": "R&B",
        "electronic": "Electronic",
        "electronica": "Electronic",
        "edm": "EDM",
        "house": "House",
        "techno": "Techno",
        "trance": "Trance",
        "dubstep": "Dubstep",
        "drumnbass": "Drum & Bass",
        "dnb": "Drum & Bass",
        "classical": "Classical",
        "jazz": "Jazz",
        "blues": "Blues",
        "country": "Country",
        "folk": "Folk",
        "punk": "Punk",
        "postrock": "Post-Rock",
        "shoegaze": "Shoegaze",
        "ambient": "Ambient",
        "soundtrack": "Soundtrack",
        "orchestral": "Orchestral"
    ]
}
