import Foundation

actor OnlineGenreResolver {
    private let cacheKey = "online_album_genre_cache_v2"
    private let noResultMarker = "__NONE__"

    private struct CacheEntry: Codable {
        let genre: String   // "__NONE__" for negative cache entries
        let storedAt: Date
    }

    private var cache: [String: CacheEntry]
    private let session: URLSession
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: configuration)

        if let data = defaults.data(forKey: "online_album_genre_cache_v2"),
           let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    func resolveGenres(for albums: [(key: String, artist: String, album: String)]) async throws -> [String: String] {
        guard !albums.isEmpty else { return [:] }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var resolved: [String: String] = [:]
        var pending: [(key: String, artist: String, album: String)] = []
        pending.reserveCapacity(albums.count)

        for album in albums {
            if let entry = cache[album.key] {
                // Check TTL - treat entries older than 30 days as cache miss
                if entry.storedAt > thirtyDaysAgo {
                    if entry.genre != noResultMarker {
                        resolved[album.key] = entry.genre
                    }
                } else {
                    // Expired entry - treat as miss
                    pending.append(album)
                }
            } else {
                pending.append(album)
            }
        }

        guard !pending.isEmpty else { return resolved }
        try await preflightNetwork()

        var processed = 0
        for album in pending {
            if let genre = try await fetchGenre(for: album) {
                resolved[album.key] = genre
                cache[album.key] = CacheEntry(genre: genre, storedAt: Date())
            } else {
                cache[album.key] = CacheEntry(genre: noResultMarker, storedAt: Date())
            }

            processed += 1
            if processed % 30 == 0 {
                persistCache()
            }
        }

        persistCache()
        return resolved
    }

    private func trimCache(maxEntries: Int = 5000) {
        guard cache.count > maxEntries else { return }
        let sorted = cache.sorted { $0.value.storedAt < $1.value.storedAt }
        let toRemove = cache.count - maxEntries
        for (index, pair) in sorted.enumerated() {
            if index >= toRemove { break }
            cache.removeValue(forKey: pair.key)
        }
    }

    private func preflightNetwork() async throws {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "test"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "1")
        ]

        do {
            let (_, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw OnlineGenreError.remoteUnavailable
            }
        } catch {
            throw mapNetworkError(error)
        }
    }

    private func fetchGenre(for album: (key: String, artist: String, album: String)) async throws -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(album.artist) \(album.album)"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "8")
        ]

        let data: Data
        do {
            let result = try await session.data(from: components.url!)
            data = result.0
        } catch {
            throw mapNetworkError(error)
        }

        guard let decoded = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else {
            return nil
        }

        guard let matched = bestMatch(from: decoded.results, query: album) else {
            return nil
        }

        let trimmed = matched.primaryGenreName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func bestMatch(
        from candidates: [ITunesAlbumResult],
        query: (key: String, artist: String, album: String)
    ) -> ITunesAlbumResult? {
        let targetAlbum = normalize(query.album)
        let targetArtist = normalize(query.artist)

        var winner: ITunesAlbumResult?
        var bestScore = Int.min

        for item in candidates {
            let itemAlbum = normalize(item.collectionName ?? "")
            let itemArtist = normalize(item.artistName ?? "")
            var score = 0

            if !targetAlbum.isEmpty && !itemAlbum.isEmpty {
                if itemAlbum == targetAlbum {
                    score += 7
                } else if itemAlbum.contains(targetAlbum) || targetAlbum.contains(itemAlbum) {
                    score += 4
                }
            }

            if !targetArtist.isEmpty && !itemArtist.isEmpty {
                if itemArtist == targetArtist {
                    score += 6
                } else if itemArtist.contains(targetArtist) || targetArtist.contains(itemArtist) {
                    score += 3
                }
            }

            if let genre = item.primaryGenreName, !genre.isEmpty {
                score += 1
            }

            if score > bestScore {
                bestScore = score
                winner = item
            }
        }

        guard bestScore >= 7 else { return nil }
        return winner
    }

    private func mapNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return OnlineGenreError.requestFailed
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return OnlineGenreError.networkBlocked
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            return OnlineGenreError.networkUnavailable
        default:
            return OnlineGenreError.requestFailed
        }
    }

    private func persistCache() {
        trimCache()
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private func normalize(_ value: String) -> String {
        let lower = value.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let allowed = lower.filter { $0.isLetter || $0.isNumber }
        return allowed
    }
}

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesAlbumResult]
}

private struct ITunesAlbumResult: Decodable {
    let artistName: String?
    let collectionName: String?
    let primaryGenreName: String?
}

enum OnlineGenreError: Error {
    case networkBlocked
    case networkUnavailable
    case remoteUnavailable
    case requestFailed
}

extension OnlineGenreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .networkBlocked:
            return "Cannot reach online genre service. Enable App Sandbox -> Network -> Outgoing Connections (Client)."
        case .networkUnavailable:
            return "Network unavailable while matching album genres online."
        case .remoteUnavailable:
            return "Online genre service returned an invalid response."
        case .requestFailed:
            return "Failed to query online genre service."
        }
    }
}
