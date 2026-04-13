# Tidal App - Dev Notes

Working notes for picking up development. Not for GitHub publication - just internal reference.

## Directory Structure

```
tidal-app/
├── lib/                              Dart/Flutter UI source
│   ├── main.dart                     App entry + HomePage scaffold (all routing logic)
│   ├── services/
│   │   ├── channels.dart             MethodChannel constants + poll intervals
│   │   └── link_resolver.dart        Spotify/YouTube URL → title+artist (oEmbed)
│   ├── managers/
│   │   ├── auth_manager.dart         Tidal device-code auth flow + token refresh
│   │   ├── library_manager.dart      Download/delete/import + cookies + sort/group
│   │   ├── playback_manager.dart     AVPlayer control + seek/speed/polling
│   │   ├── playlist_manager.dart     Tidal playlist fetch/save/refresh
│   │   ├── search_manager.dart       Tidal catalog search + pagination
│   │   └── settings_manager.dart     Persistent settings (quality, speed, sort)
│   ├── widgets/
│   │   ├── auth_content.dart         Login screen (device code display)
│   │   ├── auth_webview.dart         WKWebView for in-app Tidal login
│   │   ├── cover_thumbnail.dart      Album art with source badge (YT/SC/Tidal)
│   │   ├── library_tab.dart          Song list with sort/group/swipe-delete
│   │   ├── now_playing_bar.dart      Seek bar + play/pause + speed chip
│   │   ├── playlists_tab.dart        Saved playlists list + detail view
│   │   ├── search_tab.dart           Search field + results (tracks/albums/playlists)
│   │   ├── settings_sheet.dart       Quality, speed, cookies, JS runtime
│   │   ├── song_info_sheet.dart      Codec/quality/bitrate metadata display
│   │   ├── sort_sheet.dart           Sort/group/display attribute picker
│   │   └── speed_sheet.dart          Speed slider + presets
│   └── utils/
│       └── formatters.dart           Duration, file size, date helpers
│
├── python_app/
│   ├── tiddl_bridge.py               Tidal auth + download + library + playlists + search
│   └── ytdl_bridge.py                YouTube/SoundCloud/HLS download via yt-dlp
│
├── python_packages/                  Bundled shims (pydantic, ffmpeg_asyncio)
│
├── scripts/
│   ├── PythonBridge.swift            Flutter plugin: CPython init + method dispatch
│   ├── AudioBridge.swift             Flutter plugin: AVPlayer + lock screen
│   ├── post_build.sh                 Post-build: bundles python runtime
│   └── setup_python.rb               Xcode Python setup helper
│
└── .github/workflows/
    ├── build-ipa.yml                 CI: simulator test + unsigned IPA
    └── update-source.yml             CI: triggers app-source update on release
```

No `ios/` Xcode project in repo. Swift bridge files live in `scripts/` and are injected during CI build.

## Architecture

```
Flutter (Dart UI) — 6 managers (auth/library/playback/playlist/search/settings)
    |
    |— MethodChannel: python  →  PythonBridge.swift  →  CPython 3.13
    |                                                      ├── tiddl_bridge.py (Tidal API)
    |                                                      └── ytdl_bridge.py (yt-dlp)
    |
    └— MethodChannel: audio   →  AudioBridge.swift   →  AVPlayer (.varispeed)
```

Key design decisions:
- **Progress + cancel bypass Python queue**: `downloadProgress` and `cancelDownload` are handled entirely in Swift via direct file I/O to avoid blocking the serial Python dispatch queue during downloads.
- **Settings I/O also in Swift**: atomic write to `.tmp` → `moveItem` for crash safety.
- **Single serial DispatchQueue for Python**: all Python calls go through one queue with GIL acquire/release. Result returned via temp file to avoid GIL contention.

## What's Been Built (Chronological)

### Original (pre-YouTube)
- Tidal device-code auth
- Track download with quality selection
- Library browse/play/delete
- Varispeed playback with AVPlayer
- Configurable speed range
- Lock screen controls
- Search with pagination
- Album art thumbnails
- Playlists (fetch/save/browse/download)
- Local file import
- Song info sheet
- Sort/group/display attributes

### Phase 1+2: YouTube & SoundCloud (commit `bff4739`)
- `ytdl_bridge.py` — yt-dlp integration for YouTube/SoundCloud
- URL detection in search bar (regex patterns)
- Preview modal: album art, title, artist, duration, quality, source badge
- Direct HTTP chunked download with progress
- Metadata tagging + cover art embedding via mutagen

### Phase 1.5: SoundCloud HLS (commit `c185fc3`)
- `_download_hls_stream()` in ytdl_bridge.py
- fMP4 HLS: init segment + media segments concatenated to valid .m4a
- Upgraded SoundCloud from ~64kbps to 160kbps AAC

### Phase 2.5: YouTube Premium Cookies (commit `2828aa7`)
- `cookies.txt` import via file picker
- Unlocks 256kbps AAC on YouTube
- Settings UI: loaded status, age display, replace/clear buttons

### Phase 3: WebKit JSI Anti-Throttle (commit `ece29f3`)
- `yt-dlp-apple-webkit-jsi` plugin support
- Bypasses YouTube n-parameter throttling without ffmpeg
- Runs JS challenge natively in WKWebView
- Settings diagnostic panel

### Phase 4 (current): Spotify/YouTube → Tidal Search
- `link_resolver.dart` — pure Dart HTTP resolver
- Spotify: oEmbed + og:description scraping (parallel fetch)
- YouTube: oEmbed + title cleanup (14 regex patterns)
- Spotify URL detection → preview modal → "Search on Tidal"
- YouTube/SoundCloud: added "Search on Tidal" button alongside "Download"
- `_searchTidalForTrack()` — populates search bar + fires Tidal search

## What Worked / What Didn't

### Worked Well
- **Spotify oEmbed**: No auth needed, instant, reliable. Returns title + thumbnail. Pair with og:description scrape for artist.
- **YouTube oEmbed**: No auth needed, returns full video title + author. "Artist - Title" parsing works for ~90% of music videos.
- **HLS segment download**: Manual m3u8 parsing + segment concatenation works perfectly for SoundCloud's fMP4 streams.
- **Swift file I/O bypass**: Reading progress/cancel from files instead of going through Python queue was essential — Python queue blocks during long downloads.
- **WebKit JSI**: Works great when available. The ctypes check + version detection is reliable.

### Gotchas / Known Issues
- **Spotify oEmbed has no artist field**: Must scrape the HTML page. `og:description` format is `"Artist · Album · Song · Year"` — split on `·` and take first part. Fallback: parse `<title>` tag.
- **Spotify oEmbed only works for tracks**: Returns 404 for albums/playlists. Pattern restricted to `/track/` only.
- **YouTube title cleanup is heuristic**: Handles common patterns but won't catch everything. Edge cases: non-standard title formats, live recordings, fan uploads.
- **yt-dlp artist field**: Sometimes returns the actual artist metadata, sometimes returns channel name. Quality varies by video.
- **SoundCloud HLS**: Some tracks serve HLS, others serve direct HTTP. Must try non-HLS first, fall back to HLS.
- **Cookie expiry**: YouTube cookies expire. No automatic detection — user has to notice quality degradation and re-import.
- **No `dart:io` HttpClient on Flutter Web**: Not relevant (iOS only), but worth noting if the app ever targets web.
- **CPython GIL**: All Python calls are serialized. Long downloads block search/auth until complete (progress/cancel bypass mitigates this).
- **`response.drain()` required**: HTTP responses with `dart:io` HttpClient must be fully read or drained, otherwise connections leak from the keep-alive pool.

## Python Bridge Methods

### PythonBridge.swift (python channel)
| Method | Handler |
|---|---|
| `pythonVersion` | `sys.version` |
| `authStatus` / `startAuth` / `checkAuth` / `refreshAuth` / `logout` | tiddl_bridge auth |
| `download` | `tiddl_bridge.download_track(url, quality)` |
| `downloadProgress` | **Swift-only** — reads `.download_progress.json` |
| `cancelDownload` | **Swift-only** — creates `.download_cancel` flag |
| `listDownloads` / `deleteDownload` | tiddl_bridge library |
| `importFiles` | `tiddl_bridge.import_files(jsonPaths)` |
| `searchTidal` | `tiddl_bridge.search_tidal(query, limit, offset)` |
| `getPlaylistInfo` / `listPlaylists` / `savePlaylist` / `removePlaylist` | tiddl_bridge playlists |
| `saveSettings` / `loadSettings` | **Swift-only** — atomic JSON I/O |
| `getUrlInfo` / `downloadUrl` | ytdl_bridge (yt-dlp) |
| `checkYtdlp` / `checkJsRuntime` | ytdl_bridge diagnostics |
| `setCookiesPath` / `clearCookies` / `getCookiesStatus` / `importCookies` | ytdl_bridge cookies |

### AudioBridge.swift (audio channel)
`play` / `pause` / `resume` / `stop` / `setSpeed` / `seek` / `getState`
Callbacks: `onPlaybackComplete` / `onPlaybackError`
