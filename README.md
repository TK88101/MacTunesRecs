# MacTunesRecs

A macOS desktop app that analyzes your iTunes/Music library and recommends new albums via Spotify.

## Overview

MacTunesRecs scans your local iTunes/Music library (or any folder of audio files), breaks down your collection by genre using interactive visualizations, and fetches personalized album recommendations from the Spotify Web API. It works entirely on-device except for the optional Spotify and iTunes Search API callsâno cloud sync or account required beyond Spotify developer credentials.

## Features

- Scan your iTunes/Music library via `iTunesLibrary.framework`, or point at any folder of audio files
- Supported formats: m4a, mp3, aac, flac, wav, aiff
- Genre analysis with two interactive visualizations:
  - **Donut Chart** â proportional genre breakdown
  - **Genre Galaxy** â force-directed bubble layout
- Click any genre to focus recommendations on that genre
- Spotify Web API integration: personalized album recommendations seeded by your top genres and artists
- Automatic fallback to artist/genre-anchored album search when the Spotify `/recommendations` endpoint is unavailable
- Online genre enrichment via the iTunes Search API (cached locally, up to 5,000 entries, 30-day TTL)
- Genre normalization to canonical names (e.g. "hip-hop" â "Hip-Hop", "rokku" â "Rock")
- Album artwork extraction directly from local audio files
- HTTP 429 / Retry-After handling and exponential backoff for transient 5xx errors
- Remembers previously shown Spotify albums across launches to avoid repeats
- Pure Swift, zero external package dependencies

## Screenshots

<!-- TODO: Add screenshots of Donut Chart and Genre Galaxy views -->

## Requirements

- macOS 26.1 or later
- Xcode 26 or later (for building from source)
- Spotify Developer Account (free) for recommendations â sign up at [developer.spotify.com](https://developer.spotify.com)

## Installation / Getting Started

**Step 1: Clone the repository**
```bash
git clone https://github.com/your-username/MacTunesRecs.git
```

**Step 2: Open the project in Xcode**
```bash
open MacTunesRecs/MacTunesRecs.xcodeproj
```

**Step 3: Build and Run**

Press `Cmd+R`. There are no Swift Package dependencies to resolveâthe build starts immediately.

**Step 4: Grant Music library permission**

When prompted, allow "Media & Apple Music" access. If the prompt does not appear, open System Settings â Privacy & Security â Media & Apple Music and enable MacTunesRecs.

**Step 5: Configure Spotify credentials (optional, for recommendations)**

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and create a free app.
2. Copy the **Client ID** and **Client Secret** from your app's settings page.
3. In MacTunesRecs, open **Settings** (gear icon) and paste both values, then click **Save**.
4. Use **Test Connection** to confirm the credentials work before scanning.

## Usage

| Action | How |
|--------|-----|
| Scan iTunes/Music library | Click **Scan iTunes Library** |
| Scan a custom folder | Click **Choose Folder** and select any directory |
| Explore genre breakdown | Switch between **Donut Chart** and **Genre Galaxy** tabs |
| Focus on a genre | Click a slice or bubble |
| Get album recommendations | Click **Recommend** |
| Refresh recommendations | Click **Recommend** againâpreviously shown albums are skipped |

## Architecture

```
MacTunesRecs/
âââ MacTunesRecsApp.swift       # App entry point and lifecycle
âââ ContentView.swift           # Main SwiftUI view + SpotifySettingsView
âââ LibraryViewModel.swift      # @MainActor ViewModel, coordinates all operations
âââ Models.swift                # Data types: TrackInfo, AlbumInfo, Recommendation, etc.
âââ LibraryScanner.swift        # iTunes library + folder scanning
âââ Recommendations.swift       # Genre analysis and local recommendation engine
âââ SpotifyClient.swift         # Spotify Web API client
âââ OnlineGenreResolver.swift   # iTunes Search API for genre enrichment (cached)
âââ ArtworkLoader.swift         # Album artwork extraction from audio files
âââ PieChart.swift              # Donut chart SwiftUI view
âââ GenreGalaxy.swift           # Bubble/galaxy genre layout SwiftUI view
```

## App Sandbox Notes

- Network access is limited to outbound connections only (Spotify API, iTunes Search API).
- Music library access uses a read-only entitlementâthe app never modifies your library.
- Spotify credentials are stored in `UserDefaults` (not Keychain). Do not use MacTunesRecs on shared machines where other users could read your defaults database.

## Known Limitations

- Spotify's `/recommendations` endpoint may not be available for all developer app tiers. MacTunesRecs automatically detects this and falls back to a genre/artist-based album search, so recommendations continue to work either way.
- Genre matching between your local library's tags and Spotify's taxonomy is approximate. Unusual or non-English genre tags may be normalized to "Other."

## Running Tests

```bash
xcodebuild test   -project MacTunesRecs.xcodeproj   -scheme MacTunesRecs   -destination "platform=macOS"   CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## License

MIT License â see the [LICENSE](LICENSE) file for details.
