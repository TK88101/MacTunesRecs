import Foundation

final class SpotifyClient {
    struct Config: Equatable {
        let clientId: String
        let clientSecret: String
    }

    private let config: Config
    private var token: Token?
    private var cachedGenres: [String]?
    private var cachedArtistIds: [String: String] = [:]
    private var cachedArtistGenres: [String: [String]] = [:]
    private var nextNetworkAttemptAt: Date = .distantPast
    private static let fallbackGenreSeeds: [String] = [
        "alternative", "black-metal", "blues", "classical", "country", "dance",
        "edm", "electro", "electronic", "folk", "hard-rock", "heavy-metal",
        "hip-hop", "indie", "jazz", "metal", "pop", "punk", "rock", "soul"
    ]

    init(config: Config) {
        self.config = config
    }

    func recommendAlbumsNotInLibrary(
        libraryIndex: LibraryIndex,
        focusGenre: String?,
        limit: Int,
        avoidAlbumIDs: Set<String>
    ) async throws -> [Recommendation] {
        let accessToken = try await ensureToken()
        let availableGenres = try await fetchAvailableGenres(token: accessToken)

        let focusSeed = focusGenre.flatMap { Self.matchGenre(localGenre: $0, availableGenres: availableGenres) }
        let matchedGenres = libraryIndex.topGenres.compactMap { Self.matchGenre(localGenre: $0, availableGenres: availableGenres) }
        let artistIds = try await resolveArtistIds(token: accessToken, names: libraryIndex.topArtists, max: 8)
        let artistNames = focusSeed == nil ? Array(libraryIndex.topArtists.prefix(8)) : []

        var recommendations: [Recommendation] = []
        var seenAlbumIds = Set<String>()
        var attempts = 0
        var recommendationsEndpointUnavailable = false

        while recommendations.count < limit && attempts < 4 {
            attempts += 1
            let seeds = selectSeeds(focus: focusSeed, genres: matchedGenres, artistIds: artistIds)
            let tracks: [SpotifyTrack]
            if recommendationsEndpointUnavailable {
                tracks = try await searchAlbumCandidates(
                    token: accessToken,
                    focusSeed: focusSeed,
                    genreHints: seeds.genres,
                    artistHints: artistNames,
                    limit: max(limit * 3, 20)
                )
            } else {
                do {
                    tracks = try await fetchRecommendations(
                        token: accessToken,
                        seedGenres: seeds.genres,
                        seedArtists: seeds.artists,
                        limit: max(limit * 3, 20)
                    )
                } catch SpotifyError.recommendationsUnavailable {
                    recommendationsEndpointUnavailable = true
                    tracks = try await searchAlbumCandidates(
                        token: accessToken,
                        focusSeed: focusSeed,
                        genreHints: seeds.genres,
                        artistHints: artistNames,
                        limit: max(limit * 3, 20)
                    )
                }
            }

            for track in tracks {
                if let focusSeed, !(await passesFocusFilter(track: track, token: accessToken, focusSeed: focusSeed)) {
                    continue
                }

                let album = track.album
                guard !seenAlbumIds.contains(album.id) else { continue }
                guard !avoidAlbumIDs.contains(album.id) else { continue }

                let albumArtist = album.artists.first?.name ?? track.artists.first?.name ?? "Unknown Artist"
                let albumKey = RecommendationEngine.albumKey(artist: albumArtist, album: album.name)
                guard !libraryIndex.albumKeys.contains(albumKey) else { continue }

                seenAlbumIds.insert(album.id)

                let imageURL = album.images.first.flatMap { URL(string: $0.url) }
                let spotifyURL = album.externalUrls.spotify.flatMap { URL(string: $0) }

                recommendations.append(Recommendation(
                    id: UUID(),
                    sourceId: album.id,
                    title: album.name,
                    subtitle: albumArtist,
                    genre: focusGenre ?? matchedGenres.first ?? "",
                    spotifyURL: spotifyURL,
                    artworkURL: imageURL,
                    artworkData: nil,
                    source: .spotify
                ))

                if recommendations.count >= limit {
                    break
                }
            }
        }

        if recommendations.count > limit {
            return Array(recommendations.shuffled().prefix(limit))
        }
        return recommendations.shuffled()
    }

    private func searchAlbumCandidates(
        token: String,
        focusSeed: String?,
        genreHints: [String],
        artistHints: [String],
        limit: Int
    ) async throws -> [SpotifyTrack] {
        try guardNetworkBackoff()

        // Strict fallback when recommendations endpoint is unavailable:
        // anchor on genre -> find artists -> collect their albums.
        if let focusSeed, !focusSeed.isEmpty {
            let artists = try await searchArtistsByGenre(token: token, genreSeed: focusSeed, limit: 40)
            var strictAlbumsById: [String: SpotifyAlbum] = [:]
            for artist in artists {
                if let genres = artist.genres {
                    cachedArtistGenres[artist.id] = genres
                }

                let albums = try await fetchAlbumsForArtist(
                    token: token,
                    artistId: artist.id,
                    limit: max(12, min(40, limit))
                )
                for album in albums {
                    strictAlbumsById[album.id] = album
                }
                if strictAlbumsById.count >= max(limit * 3, 40) {
                    break
                }
            }
            if !strictAlbumsById.isEmpty {
                return strictAlbumsById.values.shuffled().map { album in
                    SpotifyTrack(name: album.name, album: album, artists: album.artists)
                }
            }
        }

        var queries: [String] = []
        for genre in genreHints.shuffled().prefix(3) {
            let normalized = genre.replacingOccurrences(of: "-", with: " ")
            if !normalized.isEmpty {
                queries.append(normalized)
            }
        }
        for artist in artistHints.shuffled().prefix(4) {
            let trimmed = artist.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                queries.append(trimmed)
            }
        }
        if queries.isEmpty {
            queries = ["rock", "pop", "metal"]
        }

        var albumsById: [String: SpotifyAlbum] = [:]
        let queryLimit = max(10, min(30, limit))

        for query in queries {
            var components = URLComponents(string: "https://api.spotify.com/v1/search")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "album"),
                URLQueryItem(name: "limit", value: String(queryLimit))
            ]

            var request = URLRequest(url: components.url!)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw mapNetworkError(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                    throw SpotifyError.invalidCredentials
                }
                continue
            }

            guard let decoded = try? JSONDecoder().decode(AlbumSearchResponse.self, from: data) else {
                continue
            }
            for album in decoded.albums.items {
                albumsById[album.id] = album
            }
            if albumsById.count >= max(limit * 2, 24) {
                break
            }
        }

        return albumsById.values.shuffled().map { album in
            SpotifyTrack(name: album.name, album: album, artists: album.artists)
        }
    }

    private func searchArtistsByGenre(
        token: String,
        genreSeed: String,
        limit: Int
    ) async throws -> [ArtistSearchItem] {
        let genrePhrase = genreSeed.replacingOccurrences(of: "-", with: " ")
        let queries = [
            "genre:\"\(genrePhrase)\"",
            genrePhrase
        ]

        var merged: [String: ArtistSearchItem] = [:]
        for query in queries {
            var components = URLComponents(string: "https://api.spotify.com/v1/search")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "artist"),
                URLQueryItem(name: "limit", value: String(max(1, min(50, limit))))
            ]

            var request = URLRequest(url: components.url!)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw mapNetworkError(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                    throw SpotifyError.invalidCredentials
                }
                continue
            }

            guard let decoded = try? JSONDecoder().decode(ArtistSearchResponse.self, from: data) else {
                continue
            }
            for item in decoded.artists.items {
                merged[item.id] = item
            }
        }

        let normalizedFocus = Self.normalize(genreSeed)
        let ranked = merged.values.sorted { lhs, rhs in
            let leftScore = genreScore(genres: lhs.genres ?? [], normalizedFocus: normalizedFocus)
            let rightScore = genreScore(genres: rhs.genres ?? [], normalizedFocus: normalizedFocus)
            if leftScore == rightScore {
                return lhs.name < rhs.name
            }
            return leftScore > rightScore
        }
        let strongMatches = ranked.filter { genreScore(genres: $0.genres ?? [], normalizedFocus: normalizedFocus) >= 3 }
        if !strongMatches.isEmpty {
            return Array(strongMatches.prefix(limit))
        }
        return Array(ranked.prefix(limit))
    }

    private func fetchAlbumsForArtist(
        token: String,
        artistId: String,
        limit: Int
    ) async throws -> [SpotifyAlbum] {
        var components = URLComponents(string: "https://api.spotify.com/v1/artists/\(artistId)/albums")!
        components.queryItems = [
            URLQueryItem(name: "include_groups", value: "album,single"),
            URLQueryItem(name: "limit", value: String(max(1, min(50, limit)))),
            URLQueryItem(name: "market", value: "US")
        ]

        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return []
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw SpotifyError.invalidCredentials
            }
            return []
        }

        let decoded = try JSONDecoder().decode(ArtistAlbumsResponse.self, from: data)
        return decoded.items
    }

    private func selectSeeds(
        focus: String?,
        genres: [String],
        artistIds: [String]
    ) -> (genres: [String], artists: [String]) {
        // If user picked a genre, keep recommendations anchored to that genre.
        if let focus, !focus.isEmpty {
            return ([focus], [])
        }

        var seedGenres: [String] = []
        var shuffledGenres = genres.shuffled()
        shuffledGenres.removeAll { seedGenres.contains($0) }
        for genre in shuffledGenres {
            if seedGenres.count >= 3 { break }
            seedGenres.append(genre)
        }

        var seedArtists: [String] = []
        var shuffledArtists = artistIds.shuffled()
        while seedGenres.count + seedArtists.count < 5, let next = shuffledArtists.first {
            seedArtists.append(next)
            shuffledArtists.removeFirst()
        }

        if seedGenres.isEmpty && seedArtists.isEmpty {
            seedGenres = ["pop"]
        }

        return (seedGenres, seedArtists)
    }

    private func passesFocusFilter(track: SpotifyTrack, token: String, focusSeed: String) async -> Bool {
        let normalizedFocus = Self.normalize(focusSeed)
        if normalizedFocus.isEmpty {
            return true
        }

        var checkedAnyGenres = false
        let candidates = track.album.artists + track.artists
        var seenArtistIds = Set<String>()
        for artist in candidates {
            guard let artistId = artist.id, !artistId.isEmpty else { continue }
            guard !seenArtistIds.contains(artistId) else { continue }
            seenArtistIds.insert(artistId)

            guard let genres = await fetchArtistGenres(token: token, artistId: artistId) else { continue }
            if genres.isEmpty { continue }

            checkedAnyGenres = true
            for genre in genres {
                let normalizedGenre = Self.normalize(genre)
                if normalizedGenre.contains(normalizedFocus) || normalizedFocus.contains(normalizedGenre) {
                    return true
                }
            }
        }

        if checkedAnyGenres {
            return false
        }

        // If genre evidence is unavailable from Spotify artist profiles, do not hard-block the item.
        return true
    }

    private func fetchArtistGenres(token: String, artistId: String) async -> [String]? {
        if let cached = cachedArtistGenres[artistId] {
            return cached
        }

        guard let url = URL(string: "https://api.spotify.com/v1/artists/\(artistId)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(ArtistDetailResponse.self, from: data) else {
            return nil
        }

        cachedArtistGenres[artistId] = decoded.genres
        return decoded.genres
    }

    private func resolveArtistIds(token: String, names: [String], max: Int) async throws -> [String] {
        var results: [String] = []
        for name in names {
            if results.count >= max { break }
            let key = Self.normalize(name)
            if let cached = cachedArtistIds[key] {
                results.append(cached)
                continue
            }
            if let id = try await searchArtistId(token: token, name: name) {
                cachedArtistIds[key] = id
                results.append(id)
            }
        }
        return results
    }

    private func searchArtistId(token: String, name: String) async throws -> String? {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let decoded = try JSONDecoder().decode(ArtistSearchResponse.self, from: data)
        return decoded.artists.items.first?.id
    }

    private func ensureToken() async throws -> String {
        try guardNetworkBackoff()

        if let token = token, token.expiresAt > Date().addingTimeInterval(60) {
            return token.value
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let authString = "\(config.clientId):\(config.clientSecret)"
        let authData = authString.data(using: .utf8) ?? Data()
        let authHeader = authData.base64EncodedString()
        request.addValue("Basic \(authHeader)", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.tokenFailed
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw SpotifyError.invalidCredentials
            }
            throw SpotifyError.httpStatus(endpoint: "token", code: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newToken = Token(value: decoded.accessToken, expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn)))
        token = newToken
        return newToken.value
    }

    private func fetchAvailableGenres(token: String) async throws -> [String] {
        if let cachedGenres = cachedGenres {
            return cachedGenres
        }
        try guardNetworkBackoff()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/recommendations/available-genre-seeds")!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.genresFailed
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                // Some apps/accounts cannot access this endpoint anymore.
                cachedGenres = Self.fallbackGenreSeeds
                return Self.fallbackGenreSeeds
            }
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw SpotifyError.invalidCredentials
            }
            throw SpotifyError.httpStatus(endpoint: "available-genre-seeds", code: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GenreSeedsResponse.self, from: data)
        if decoded.genres.isEmpty {
            cachedGenres = Self.fallbackGenreSeeds
            return Self.fallbackGenreSeeds
        }
        cachedGenres = decoded.genres
        return decoded.genres
    }

    private func fetchRecommendations(token: String, seedGenres: [String], seedArtists: [String], limit: Int) async throws -> [SpotifyTrack] {
        try guardNetworkBackoff()
        var components = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if !seedGenres.isEmpty {
            items.append(URLQueryItem(name: "seed_genres", value: seedGenres.joined(separator: ",")))
        }
        if !seedArtists.isEmpty {
            items.append(URLQueryItem(name: "seed_artists", value: seedArtists.joined(separator: ",")))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw mapNetworkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.recommendationsFailed
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw SpotifyError.recommendationsUnavailable
            }
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw SpotifyError.invalidCredentials
            }
            throw SpotifyError.httpStatus(endpoint: "recommendations", code: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(RecommendationsResponse.self, from: data)
        return decoded.tracks
    }

    private static func matchGenre(localGenre: String, availableGenres: [String]) -> String? {
        let normalized = normalize(localGenre)
        guard !normalized.isEmpty else {
            return nil
        }

        var best: (genre: String, score: Int)?
        for candidate in availableGenres {
            let normalizedCandidate = normalize(candidate)
            if normalizedCandidate.isEmpty { continue }

            let score: Int
            if normalizedCandidate == normalized {
                score = 10_000
            } else if normalizedCandidate.contains(normalized) || normalized.contains(normalizedCandidate) {
                // Prefer specific sub-genres (e.g. black-metal) over broad genre (metal).
                score = 1_000 + normalizedCandidate.count
            } else {
                continue
            }

            if let current = best {
                if score > current.score {
                    best = (candidate, score)
                }
            } else {
                best = (candidate, score)
            }
        }

        return best?.genre
    }

    private static func normalize(_ value: String) -> String {
        let lower = value.lowercased()
        let allowed = lower.filter { $0.isLetter || $0.isNumber }
        return allowed
    }

    private func guardNetworkBackoff() throws {
        if Date() < nextNetworkAttemptAt {
            throw SpotifyError.networkBackoff
        }
    }

    private func mapNetworkError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            // Avoid spamming resolver failures when sandbox/network is misconfigured.
            nextNetworkAttemptAt = Date().addingTimeInterval(20)
            return SpotifyError.cannotResolveHost
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
            nextNetworkAttemptAt = Date().addingTimeInterval(12)
            return SpotifyError.networkUnavailable
        default:
            return error
        }
    }

    private func genreScore(genres: [String], normalizedFocus: String) -> Int {
        var best = 0
        for genre in genres {
            let normalizedGenre = Self.normalize(genre)
            if normalizedGenre == normalizedFocus {
                return 5
            }
            if normalizedGenre.contains(normalizedFocus) || normalizedFocus.contains(normalizedGenre) {
                best = max(best, 3)
            } else if !normalizedFocus.isEmpty && !normalizedGenre.isEmpty {
                // keep as weak signal if genre list exists but not exact.
                best = max(best, 1)
            }
        }
        return best
    }
}

private struct Token: Equatable {
    let value: String
    let expiresAt: Date
}

private struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct GenreSeedsResponse: Codable {
    let genres: [String]
}

private struct RecommendationsResponse: Codable {
    let tracks: [SpotifyTrack]
}

private struct SpotifyTrack: Codable {
    let name: String
    let album: SpotifyAlbum
    let artists: [SpotifyArtist]
}

private struct SpotifyArtist: Codable {
    let id: String?
    let name: String
}

private struct SpotifyAlbum: Codable {
    let id: String
    let name: String
    let images: [SpotifyImage]
    let externalUrls: ExternalUrls
    let artists: [SpotifyArtist]

    enum CodingKeys: String, CodingKey {
        case id, name, images, artists
        case externalUrls = "external_urls"
    }
}

private struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

private struct ExternalUrls: Codable {
    let spotify: String?
}

private struct ArtistSearchResponse: Codable {
    let artists: ArtistSearchPage
}

private struct ArtistSearchPage: Codable {
    let items: [ArtistSearchItem]
}

private struct ArtistSearchItem: Codable {
    let id: String
    let name: String
    let genres: [String]?
}

private struct ArtistDetailResponse: Codable {
    let genres: [String]
}

private struct AlbumSearchResponse: Codable {
    let albums: AlbumSearchPage
}

private struct AlbumSearchPage: Codable {
    let items: [SpotifyAlbum]
}

private struct ArtistAlbumsResponse: Codable {
    let items: [SpotifyAlbum]
}

enum SpotifyError: Error {
    case tokenFailed
    case genresFailed
    case recommendationsFailed
    case recommendationsUnavailable
    case invalidCredentials
    case httpStatus(endpoint: String, code: Int)
    case cannotResolveHost
    case networkUnavailable
    case networkBackoff
}

extension SpotifyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .tokenFailed:
            return "Spotify token request failed."
        case .genresFailed:
            return "Failed to load Spotify genre seeds."
        case .recommendationsFailed:
            return "Failed to load Spotify recommendations."
        case .recommendationsUnavailable:
            return "Spotify recommendations endpoint unavailable for this app. Using genre-anchored artist/album fallback."
        case .invalidCredentials:
            return "Spotify credentials are invalid. Check Client ID/Client Secret."
        case let .httpStatus(endpoint, code):
            return "Spotify \(endpoint) failed with HTTP \(code)."
        case .cannotResolveHost:
            return "Cannot resolve Spotify host. Enable App Sandbox -> Network -> Outgoing Connections (Client), then try again."
        case .networkUnavailable:
            return "Network unavailable while contacting Spotify."
        case .networkBackoff:
            return "Retrying Spotify in a few seconds to avoid repeated DNS failures."
        }
    }
}
