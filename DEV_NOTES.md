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

### Phase 4: Spotify/YouTube → Tidal Search
- `link_resolver.dart` — pure Dart HTTP resolver
- Spotify: oEmbed + og:description scraping (parallel fetch)
- YouTube: oEmbed + title cleanup (14 regex patterns)
- Spotify URL detection → preview modal → "Search on Tidal"
- YouTube/SoundCloud: added "Search on Tidal" button alongside "Download"
- `_searchTidalForTrack()` — populates search bar + fires Tidal search

### Phase 5: Error Propagation + Debug Logging + Skip Controls (v1.5.0)
- **Error propagation**: yt-dlp errors now surface in snackbar (not silent failures)
- **Debug logging**: File-based log system with View/Copy/Share/Clear in Settings
- **Skip forward/backward**: Configurable duration (5/10/15/30s) and layout (inside/outside play button)
- **Lock screen controls**: MPRemoteCommandCenter skip forward/backward working
- **Cookie domain fix**: MozillaCookieJar assertion crash — domain flag must be `TRUE` when domain has leading `.`

### Phase 6: YouTube SABR Fix (v1.5.3)

**Problem**: YouTube playback broken — "Requested format is not available" for all YouTube URLs when cookies are loaded.

**Root Cause Investigation** (5 failed attempts before finding the real issue):

The problem was a three-layer interaction between YouTube's SABR protocol, yt-dlp's cookie-based client filtering, and our explicit `player_client` override:

1. **Layer 1 — SUPPORTS_COOKIES filtering** (`yt_dlp/extractor/youtube/_video.py` lines 3014-3023):
   When cookies are loaded, yt-dlp sets `is_authenticated=True` and **removes** any player client that lacks `SUPPORTS_COOKIES=True`:
   ```python
   if self.is_authenticated:
       unsupported_clients = [
           client for client in requested_clients
           if not INNERTUBE_CLIENTS[client]['SUPPORTS_COOKIES']
       ]
       for client in unsupported_clients:
           self.report_warning(f'Skipping client "{client}" since it does not support cookies')
           requested_clients.remove(client)
   ```
   Clients WITH `SUPPORTS_COOKIES`: web, web_safari, web_embedded, web_music, web_creator, mweb, tv, tv_downgraded.
   Clients WITHOUT (defaults to False): android, android_vr, ios, tv_simply.

2. **Layer 2 — SABR (Server ABR)**: YouTube's web clients now return SABR-only streams — format entries have no `url` field, only internal SABR routing. yt-dlp skips these at line 3535: `if not all((sc, fmt_url, ...)): continue`. TV clients (`tv_downgraded`) and old mobile clients (`android_vr` v1.65) still return direct URLs.

3. **Layer 3 — Our explicit `player_client` override**: We had set `player_client: ["android_vr", "ios", "mweb"]`. With cookies loaded, ALL THREE were filtered out: `android_vr` and `ios` lack `SUPPORTS_COOKIES`, and `mweb` survived but returned SABR-only streams → no playable formats.

**What we tried and why each failed:**

| Attempt | Change | Why it failed |
|---------|--------|---------------|
| v1.5.0 | Removed `format: "bestaudio/best"` | yt-dlp default format `bestvideo*+bestaudio/best` is even MORE restrictive |
| v1.5.1 | `format: "ba/b/w"` + removed `ios` client | `android_vr` and `mweb` still removed by SUPPORTS_COOKIES filter |
| v1.5.2 | Added `player_client: [android_vr, ios, mweb]` + `formats: [missing_pot]` | Same issue — all three removed or SABR'd when cookies loaded |
| v1.5.3 (first) | Two-pass: with cookies then without | Correct direction but still used explicit client override |
| v1.5.3 (final) | **Removed `player_client` override entirely** | ✅ Works — yt-dlp defaults are already correct |

**The fix**: Don't override `player_client`. yt-dlp's built-in defaults handle this correctly:
- **Authenticated** (cookies loaded): defaults to `('tv_downgraded', 'web_safari')` — `tv_downgraded` has `SUPPORTS_COOKIES=True`, is a TVHTML5 client (avoids SABR), and `REQUIRE_AUTH=True` (needs cookies, which we have).
- **Not authenticated**: defaults to `('android_vr', 'web_safari')` — `android_vr` uses client version 1.65 (below SABR threshold), doesn't need cookies.

Evidence that `tv_downgraded` avoids SABR: it's one of two `_DEFAULT_AUTHED_CLIENTS`. The other (`web_safari`) IS confirmed SABR'd (hardcoded at line 3539). If both were SABR'd, no authenticated yt-dlp user could download anything.

**Safety net**: Two-pass fallback retained. If pass 1 (with cookies → `tv_downgraded`) returns no audio formats, pass 2 runs without cookies (→ `android_vr`). `ignore_no_formats_error=True` prevents crashes. Format logging in both passes for diagnostics.

**Key `is_authenticated` check** (`_base.py` line 771-780):
```python
@property
def is_authenticated(self):
    return self._has_auth_cookies  # checks for LOGIN_INFO + SAPISID cookies
```
Simply not setting `cookiefile` in opts → `is_authenticated=False` → no client filtering.

**Key yt-dlp defaults** (`_video.py` lines 143-147):
```python
_DEFAULT_CLIENTS = ('android_vr', 'web_safari')         # no auth
_DEFAULT_JSLESS_CLIENTS = ('android_vr',)                # no auth, no JS
_DEFAULT_AUTHED_CLIENTS = ('tv_downgraded', 'web_safari')  # with cookies
_DEFAULT_PREMIUM_CLIENTS = ('tv_downgraded', 'web_creator') # Premium subscriber
```

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
| `extractYouTubeCookies` | **Swift-only** — WKHTTPCookieStore → Netscape cookies.txt |
| `getDebugLog` / `clearDebugLog` / `getDebugLogPath` | **Swift-only** — debug log file I/O |
| `shareFile` | **Swift-only** — UIActivityViewController for file export |

### AudioBridge.swift (audio channel)
`play` / `pause` / `resume` / `stop` / `setSpeed` / `seek` / `getState` / `skipForward` / `skipBackward`
Callbacks: `onPlaybackComplete` / `onPlaybackError`
