# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.0.0] - 2026-02-22

### Added
- Initial release: scan iTunes/Music library and custom audio folders
- Genre analysis with donut chart and Genre Galaxy (bubble) visualizations
- Spotify Web API integration for personalized album recommendations
- Fallback to artist/genre search when Spotify recommendations endpoint is unavailable
- Online genre enrichment via iTunes Search API with persistent caching
- Genre normalization to canonical names (e.g., "hip-hop" â "Hip-Hop")
- Album artwork extraction from local audio files (m4a, mp3, aac, flac, wav, aiff)
- Spotify credentials management in Settings panel
- HTTP 429 rate limit handling with Retry-After support
- Exponential backoff for transient Spotify API errors (5xx)
- Cache TTL (30 days) and size eviction (max 5,000 entries) for genre resolver
- Persistent lastSpotifyAlbumIDs to avoid repeating recommendations across launches
- "Test Connection" button in Spotify Settings for immediate credential validation
- Comprehensive unit and integration test suite (47+ test cases)
