# Tidal Downloader

[![Build](https://github.com/oct-obus/tidal-app/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/oct-obus/tidal-app/actions/workflows/build-ipa.yml)

Flutter iOS app for downloading music from Tidal, YouTube, and SoundCloud with variable-speed playback. Powered by [tiddl](https://github.com/oskvr37/tiddl) and [yt-dlp](https://github.com/yt-dlp/yt-dlp) running in embedded CPython.

**[Download latest IPA](https://github.com/oct-obus/tidal-app/actions/workflows/build-ipa.yml)** - grab the artifact from the most recent green build.

## Features

### Downloading
- **Tidal** - download tracks by URL or search. Quality: LOW (AAC 96k), HIGH (AAC 320k), LOSSLESS (FLAC 16-bit), HI_RES_LOSSLESS (FLAC 24-bit)
- **YouTube** - download audio from any YouTube/YouTube Music link. Default AAC ~128kbps, or 256kbps with Premium cookies
- **SoundCloud** - download via HLS (AAC 160kbps fMP4) or direct HTTP
- **Spotify link resolution** - paste a Spotify track link to resolve the title/artist, then search and download from Tidal
- **Real-time progress** - MB downloaded/total, cancel button, step descriptions
- **Local file import** - import .mp3, .flac, .m4a, .wav, .ogg, .opus and more from device

### Search & Discovery
- **Tidal catalog search** - tracks, albums, playlists with paginated results
- **Playlist support** - browse playlist tracks, save/unsave playlists, refresh from Tidal
- **Link pasting** - paste Spotify, YouTube, or SoundCloud URLs directly into the search bar
- **Cross-platform lookup** - "Search on Tidal" button when previewing YouTube/SoundCloud links

### Playback
- **Varispeed playback** - AVPlayer with `.varispeed` algorithm (turntable-style speed+pitch shifting)
- **Configurable speed range** - adjustable min/max/step with preset chips
- **Lock screen controls** - play/pause/seek via MPNowPlayingInfoCenter
- **Seek bar** - drag to seek with position/duration display

### Library
- **Sort & group** - by date, title, artist, file size, duration; group by date or artist
- **Configurable display** - toggle subtitle attributes (artist, duration, size, quality, date, album)
- **Song info** - served quality, codec, bit depth, sample rate, file size, source info
- **Album art** - cached thumbnails with source badges (YouTube red, SoundCloud orange)
- **Swipe to delete** with confirmation

### Advanced
- **YouTube Premium cookies** - import `cookies.txt` for 256kbps AAC quality
- **WebKit JSI anti-throttle** - runs YouTube's JS challenge natively via `yt-dlp-apple-webkit-jsi` plugin, bypassing n-parameter throttling without ffmpeg
- **In-app login browser** - WKWebView for Tidal device-code authentication

## Architecture

```
Flutter (Dart UI) - 6 managers + link resolver
  |
  |- MethodChannel: audio   →  AudioBridge.swift    →  AVPlayer + lock screen
  |
  |- MethodChannel: python  →  PythonBridge.swift    →  CPython 3.13
                                                          ├── tiddl_bridge.py (Tidal API via tiddl)
                                                          └── ytdl_bridge.py (YouTube/SC via yt-dlp)
```

- **Dart layer** - UI split into managers (auth, playback, library, search, playlist, settings) + widgets
- **AudioBridge.swift** - AVPlayer with `.varispeed`, `MPRemoteCommandCenter`, KVO observers
- **PythonBridge.swift** - Serial dispatch queue with GIL protection; direct Swift file I/O for progress/cancel/settings (bypasses Python queue)
- **tiddl_bridge.py** - Tidal auth, track download with segment streaming, library CRUD, playlist management, search
- **ytdl_bridge.py** - yt-dlp integration for YouTube/SoundCloud, HLS fMP4 segment download, cookie management, metadata tagging
- **link_resolver.dart** - Pure-Dart HTTP resolver for Spotify (oEmbed + page scraping) and YouTube (oEmbed + title cleanup)

## Build

CI runs on GitHub Actions macOS runners:
1. **Simulator smoke test** - boots iOS sim, installs app, verifies Python initializes
2. **Device IPA build** - produces unsigned IPA artifact for sideloading

To build manually: Actions > Build iOS IPA > Run workflow

Requires no local Xcode/Flutter setup - everything runs on GitHub Actions.

## Sideloading

The app produces an unsigned IPA. Install using any sideloading method:
- [AltStore](https://altstore.io/) - free, re-signs every 7 days
- [LiveContainer](https://github.com/khanhduytran0/LiveContainer) - runs apps inside a container without re-signing
- [TrollStore](https://github.com/opa334/TrollStore) - permanent install, requires compatible iOS version
- Other signing tools (Sideloadly, etc.)

No jailbreak required.
