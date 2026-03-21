# Tidal Downloader

Flutter iOS app for downloading and playing Tidal tracks, powered by [tiddl](https://github.com/oskvr37/tiddl) running in embedded CPython.

## Architecture

- **Flutter/Dart** — UI and audio playback
- **Swift** — Platform channel bridge to embedded CPython
- **Python (embedded)** — tiddl for Tidal API interaction and downloads
- **GitHub Actions** — Builds unsigned IPA on macOS runner

## Build

Push to `main` triggers a GitHub Actions build. Download the IPA from the workflow artifacts.

To trigger manually: Actions → Build iOS IPA → Run workflow

## Development Phases

1. ✅ Flutter UI scaffold + CI pipeline
2. 🔲 Embed CPython (python-apple-support XCFramework)
3. 🔲 Bundle tiddl + dependencies
4. 🔲 Audio playback + Tidal auth flow
