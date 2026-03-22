# Tidal Downloader

[![Build](https://github.com/obus-schmobus/tidal-app/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/obus-schmobus/tidal-app/actions/workflows/build-ipa.yml)

Flutter iOS app for downloading and playing Tidal tracks with variable-speed pitch-shifting playback. Powered by [tiddl](https://github.com/oskvr37/tiddl) running in embedded CPython.

**[Download latest IPA](https://github.com/obus-schmobus/tidal-app/actions/workflows/build-ipa.yml)** - grab the artifact from the most recent green build.

## Features

- **Tidal authentication** via device code flow (no password entry)
- **Track downloading** from Tidal URLs with real-time progress (MB downloaded / total)
- **Quality selection** - LOW (AAC 96k), HIGH (AAC 320k), LOSSLESS (FLAC 16-bit), HI_RES_LOSSLESS (FLAC 24-bit)
- **Varispeed playback** - native AVPlayer with `.varispeed` algorithm for turntable-style speed+pitch shifting
- **Configurable speed range** - adjustable min/max/step, persisted across sessions
- **Song library** - browse, play, swipe-to-delete downloaded tracks
- **Song info** - tap to see served quality, codec, bit depth, sample rate, file size
- **Lock screen controls** - play/pause/seek via MPNowPlayingInfoCenter and MPRemoteCommandCenter
- **Seek bar** - drag to seek with position/duration display

## Architecture

```
Flutter (Dart UI)
  |
  |- MethodChannel: com.obus.tidal_app/audio  -->  AudioBridge.swift (AVPlayer + varispeed)
  |
  |- MethodChannel: com.obus.tidal_app/python  -->  PythonBridge.swift (GIL-safe Python calls)
                                                        |
                                                        v
                                                    tiddl_bridge.py (tiddl v3 API)
```

- **Dart** - UI split into managers (auth, playback, library, settings) + main widget
- **AudioBridge.swift** - Native AVPlayer with `.varispeed` pitch algorithm, lock screen integration
- **PythonBridge.swift** - Serial dispatch queue with GIL protection, direct file I/O for progress/settings
- **tiddl_bridge.py** - Tidal auth, track lookup, segment downloads with atomic writes
- **CPython 3.13+** - Embedded via python-apple-support XCFramework, pydantic v2 shim included

## Build

Every push to `main` triggers CI:
1. **Simulator smoke test** - boots iOS sim, installs app, verifies Python initializes
2. **Device IPA build** - produces unsigned IPA artifact for sideloading

To build manually: Actions > Build iOS IPA > Run workflow

Requires no local Xcode/Flutter setup - everything runs on GitHub Actions macOS runners.

## Sideloading

The app produces an unsigned IPA. Install via [LiveContainer](https://github.com/khanhduytran0/LiveContainer) on a jailbroken/sideloaded iOS device.
