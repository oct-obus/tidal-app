"""
iOS bridge for yt-dlp (YouTube, SoundCloud, and other platforms).
Called from Swift PythonBridge via PyRun_SimpleString.

Uses yt-dlp for URL info extraction, then downloads audio streams
directly using chunked HTTP or HLS segment downloading (via m3u8).

Phase 1: SoundCloud (pure Python extractor, no JS needed)
Phase 1.5: SoundCloud HLS upgrade (AAC 160kbps via m3u8 + fMP4 concat)
Phase 2: YouTube degraded (limited formats without JS runtime)
Phase 3: YouTube full (requires ctypes + apple-webkit-jsi plugin)
"""

import os
import sys
import json
import logging
import traceback
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ytdl_bridge")

# Progress constants (same scale as tiddl_bridge)
_PROGRESS_EXTRACT = 0
_PROGRESS_FORMAT = 5
_PROGRESS_DOWNLOAD_START = 10
_PROGRESS_DOWNLOAD_RANGE = 80
_PROGRESS_METADATA = 92
_PROGRESS_DONE = 100

DOCUMENTS_DIR = None
_COOKIES_PATH = None  # Path to Netscape cookies.txt for YouTube Premium

# Test critical import eagerly at load time
try:
    import yt_dlp
    logger.info(f"  ✓ import yt_dlp ({yt_dlp.version.__version__})")
except Exception as _e:
    logger.error(f"  ✗ import yt_dlp: {_e}")


def set_documents_dir(path):
    global DOCUMENTS_DIR
    DOCUMENTS_DIR = path


def set_cookies_path(path):
    """Set the path to a Netscape cookies.txt file for YouTube Premium."""
    global _COOKIES_PATH
    if path and os.path.isfile(path):
        _COOKIES_PATH = path
        logger.info(f"Cookies file set: {path}")
    else:
        _COOKIES_PATH = None
        if path:
            logger.warning(f"Cookies file not found: {path}")


def clear_cookies():
    """Remove the cookies file and clear the path."""
    global _COOKIES_PATH
    if _COOKIES_PATH and os.path.isfile(_COOKIES_PATH):
        try:
            os.remove(_COOKIES_PATH)
        except OSError as e:
            logger.warning(f"Could not delete cookies file: {e}")
    _COOKIES_PATH = None
    logger.info("Cookies cleared")


def get_cookies_status():
    """Check cookies file status. Returns JSON."""
    if not _COOKIES_PATH or not os.path.isfile(_COOKIES_PATH):
        return _result(True, {"hasCookies": False})
    try:
        stat = os.stat(_COOKIES_PATH)
        return _result(True, {
            "hasCookies": True,
            "path": _COOKIES_PATH,
            "sizeBytes": stat.st_size,
            "modifiedAt": datetime.fromtimestamp(stat.st_mtime).isoformat(),
        })
    except OSError as e:
        return _result(True, {"hasCookies": False, "error": str(e)})


# ---------------------------------------------------------------------------
# Helpers (mirror tiddl_bridge patterns exactly)
# ---------------------------------------------------------------------------

def _result(success, data=None, error=None):
    return json.dumps({
        "success": success,
        "data": data,
        "error": error,
    })


def _write_progress(step, pct=0, detail=""):
    """Write download progress atomically for Dart to poll."""
    try:
        if not DOCUMENTS_DIR:
            return
        progress_path = os.path.join(DOCUMENTS_DIR, ".download_progress.json")
        tmp_path = progress_path + ".tmp"
        with open(tmp_path, "w") as f:
            json.dump({"step": step, "pct": pct, "detail": detail}, f)
        os.replace(tmp_path, progress_path)
    except Exception:
        pass


def _check_cancelled():
    if not DOCUMENTS_DIR:
        return False
    return os.path.exists(os.path.join(DOCUMENTS_DIR, ".download_cancel"))


def _clear_cancel_flag():
    if not DOCUMENTS_DIR:
        return
    flag = os.path.join(DOCUMENTS_DIR, ".download_cancel")
    try:
        os.remove(flag)
    except OSError:
        pass


def _detect_platform(url):
    """Detect which platform a URL belongs to."""
    url_lower = url.lower()
    if any(d in url_lower for d in ("youtube.com", "youtu.be", "music.youtube.com")):
        return "youtube"
    if "soundcloud.com" in url_lower:
        return "soundcloud"
    return "other"


def _safe_filename(name):
    """Create a filesystem-safe name."""
    return "".join(c for c in name if c.isalnum() or c in " -_.").strip()


def _platform_prefix(platform):
    return {"youtube": "yt", "soundcloud": "sc"}.get(platform, "dl")


def _ydl_opts_base():
    """Common yt-dlp options for iOS."""
    opts = {
        "quiet": True,
        "no_warnings": True,
        "no_color": True,
        "noprogress": True,
        "socket_timeout": 30,
        "nocheckcertificate": False,
        # Disable all post-processors (no ffmpeg on iOS)
        "postprocessors": [],
    }
    # Use Documents/cache for yt-dlp cache
    if DOCUMENTS_DIR:
        cache_dir = os.path.join(DOCUMENTS_DIR, "cache", "ytdl")
        os.makedirs(cache_dir, exist_ok=True)
        opts["cachedir"] = cache_dir
    # Inject cookies for YouTube Premium (unlocks 256kbps AAC)
    if _COOKIES_PATH and os.path.isfile(_COOKIES_PATH):
        opts["cookiefile"] = _COOKIES_PATH
    return opts


# ---------------------------------------------------------------------------
# Format selection helpers
# ---------------------------------------------------------------------------

def _select_audio_format(formats, quality="best"):
    """Pick the best audio-only format from a list of yt-dlp format dicts.

    Returns a tuple ``(format_dict, is_hls)`` where ``is_hls`` indicates the
    format requires HLS segment downloading rather than plain HTTP.
    Prefers HLS AAC over HTTP MP3 when higher quality, since we can
    download fMP4 segments with the m3u8 library.
    """
    audio_fmts = [
        f for f in formats
        if f.get("acodec", "none") != "none"
        and f.get("url")
    ]
    # Prefer audio-only (no video track)
    audio_only = [f for f in audio_fmts if f.get("vcodec") in ("none", None)]
    pool = audio_only if audio_only else audio_fmts

    if not pool:
        return None, False

    # Partition into direct-HTTP vs HLS
    http_pool = [f for f in pool
                 if f.get("protocol", "http") in ("http", "https")]
    hls_pool = [f for f in pool
                if f.get("protocol") in ("m3u8", "m3u8_native")]

    # Sort both pools by bitrate (descending)
    http_pool.sort(
        key=lambda f: f.get("abr") or f.get("tbr") or 0, reverse=True)
    hls_pool.sort(
        key=lambda f: f.get("abr") or f.get("tbr") or 0, reverse=True)

    best_http = http_pool[0] if http_pool else None
    best_hls = hls_pool[0] if hls_pool else None

    if quality == "low":
        if http_pool:
            return http_pool[-1], False
        if hls_pool:
            return hls_pool[-1], True
        return None, False

    if quality == "medium":
        if http_pool and len(http_pool) > 1:
            return http_pool[len(http_pool) // 2], False
        if http_pool:
            return http_pool[0], False
        if hls_pool:
            return hls_pool[len(hls_pool) // 2] if len(hls_pool) > 1 else hls_pool[0], True
        return None, False

    # "best" / "high" — prefer higher quality even if HLS
    if best_http and best_hls:
        http_br = best_http.get("abr") or best_http.get("tbr") or 0
        hls_br = best_hls.get("abr") or best_hls.get("tbr") or 0
        if hls_br > http_br:
            return best_hls, True
        return best_http, False

    if best_http:
        return best_http, False
    if best_hls:
        return best_hls, True
    return None, False


def _download_hls_stream(hls_url, http_headers=None):
    """Download an HLS stream by fetching init + media segments.

    SoundCloud serves HLS AAC as fMP4 (fragmented MP4):
    init.mp4 (ftyp+moov) + data000.m4s + data001.m4s + ...
    Simple concatenation produces a valid .m4a file.

    Returns ``(bytes_data, total_bytes)`` or raises on failure.
    """
    import m3u8
    from requests import Session as ReqSession

    playlist = m3u8.load(hls_url, headers=http_headers or {})
    if not playlist.segments:
        raise ValueError("HLS playlist has no segments")

    total_segments = len(playlist.segments)
    chunks = []
    total_bytes = 0

    with ReqSession() as sess:
        if http_headers:
            sess.headers.update(http_headers)

        # Download initialization segment (contains codec metadata)
        if playlist.segment_map and playlist.segment_map[0] is not None:
            init_uri = playlist.segment_map[0].absolute_uri
            resp = sess.get(init_uri, timeout=30)
            resp.raise_for_status()
            chunks.append(resp.content)
            total_bytes += len(resp.content)

        # Download media segments with progress
        for i, seg in enumerate(playlist.segments):
            if _check_cancelled():
                raise InterruptedError("cancelled")

            resp = sess.get(seg.absolute_uri, timeout=30)
            resp.raise_for_status()
            chunks.append(resp.content)
            total_bytes += len(resp.content)

            frac = (i + 1) / total_segments
            pct = _PROGRESS_DOWNLOAD_START + int(
                _PROGRESS_DOWNLOAD_RANGE * frac)
            mb_done = total_bytes / (1024 * 1024)
            _write_progress(
                "downloading",
                min(pct, _PROGRESS_DOWNLOAD_START + _PROGRESS_DOWNLOAD_RANGE),
                f"{mb_done:.1f} MB ({i+1}/{total_segments} segments)",
            )

    return b"".join(chunks), total_bytes


# ---------------------------------------------------------------------------
# Public API — called from Swift via method channel
# ---------------------------------------------------------------------------

def check_ytdlp():
    """Check if yt-dlp is available and return version info."""
    try:
        import yt_dlp as _yt
        return _result(True, {
            "version": _yt.version.__version__,
            "available": True,
        })
    except ImportError as e:
        return _result(True, {
            "version": None,
            "available": False,
            "error": str(e),
        })


def check_js_runtime():
    """Diagnose JS runtime availability for YouTube anti-throttle.

    Checks:
      1. ctypes C extension importable
      2. yt-dlp-apple-webkit-jsi plugin installed
      3. Plugin reports as available (Darwin + WKWebView)
    """
    diagnostics = {
        "ctypes": False,
        "ctypesError": None,
        "pluginInstalled": False,
        "pluginVersion": None,
        "pluginAvailable": False,
        "pluginError": None,
    }

    # 1. Check ctypes
    try:
        import ctypes  # noqa: F401
        diagnostics["ctypes"] = True
    except ImportError as e:
        diagnostics["ctypesError"] = str(e)

    # 2. Check plugin installed
    try:
        from yt_dlp_plugins.extractor.webkit_jsi import __version__ as wk_ver
        diagnostics["pluginInstalled"] = True
        diagnostics["pluginVersion"] = wk_ver
    except ImportError as e:
        diagnostics["pluginError"] = str(e)
        return _result(True, diagnostics)

    # 3. Check plugin availability using its own logic
    try:
        from yt_dlp_plugins.extractor.webkit_jsi import AppleWebKitMixin
        from yt_dlp_plugins.webkit_jsi.lib.api import DarwinMinVer
        from yt_dlp.utils import version_tuple

        ures = os.uname()
        diagnostics["platform"] = ures.sysname
        is_avail = (AppleWebKitMixin.IS_AVAIL
                    and ures.sysname == "Darwin"
                    and version_tuple(ures.release) >= DarwinMinVer)
        diagnostics["pluginAvailable"] = is_avail
        if not is_avail:
            if not AppleWebKitMixin.IS_AVAIL:
                diagnostics["pluginError"] = (
                    "Plugin disabled (prior WKWebView failure)")
            elif ures.sysname != "Darwin":
                diagnostics["pluginError"] = (
                    f"Not on Darwin (sysname={ures.sysname})")
            else:
                diagnostics["pluginError"] = (
                    f"Darwin version too old ({ures.release})")
    except Exception as e:
        diagnostics["platform"] = os.uname().sysname
        diagnostics["pluginError"] = str(e)

    return _result(True, diagnostics)


def get_url_info(url):
    """Extract metadata about a URL without downloading.

    Returns track or playlist info: title, artist, duration, thumbnail, etc.
    """
    try:
        import yt_dlp

        platform = _detect_platform(url)
        opts = _ydl_opts_base()
        opts["format"] = "bestaudio/best"

        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)

        if not info:
            return _result(False, error="Could not extract info from URL")

        # --- playlist ---
        if info.get("_type") == "playlist":
            entries = info.get("entries", [])
            tracks = []
            for entry in entries:
                if not entry:
                    continue
                tracks.append({
                    "trackId": entry.get("id", ""),
                    "title": entry.get("title", "Unknown"),
                    "artist": (entry.get("uploader")
                               or entry.get("creator")
                               or entry.get("channel")
                               or "Unknown"),
                    "duration": entry.get("duration"),
                    "coverUrl": entry.get("thumbnail"),
                    "url": entry.get("webpage_url") or entry.get("url", ""),
                })

            return _result(True, {
                "type": "playlist",
                "platform": platform,
                "title": info.get("title", "Unknown Playlist"),
                "uploader": (info.get("uploader")
                             or info.get("channel") or ""),
                "trackCount": len(tracks),
                "tracks": tracks,
                "thumbnailUrl": info.get("thumbnail"),
            })

        # --- single track ---
        formats = info.get("formats", [])
        audio_formats = []
        for f in formats:
            if f.get("acodec", "none") != "none":
                audio_formats.append({
                    "formatId": f.get("format_id"),
                    "ext": f.get("ext"),
                    "abr": f.get("abr"),
                    "asr": f.get("asr"),
                    "acodec": f.get("acodec"),
                    "filesize": f.get("filesize") or f.get("filesize_approx"),
                })

        return _result(True, {
            "type": "track",
            "platform": platform,
            "id": info.get("id", ""),
            "title": info.get("title", "Unknown"),
            "artist": (info.get("uploader")
                       or info.get("creator")
                       or info.get("channel")
                       or "Unknown"),
            "album": info.get("album") or "",
            "duration": info.get("duration"),
            "thumbnailUrl": info.get("thumbnail"),
            "url": info.get("webpage_url", url),
            "audioFormats": audio_formats,
        })
    except Exception as e:
        logger.error(f"URL info error: {e}\n{traceback.format_exc()}")
        return _result(False, error=str(e))


def download_url(url, quality="best"):
    """Download audio from a YouTube / SoundCloud / other URL.

    Uses yt-dlp to resolve the direct stream URL then downloads the audio
    stream ourselves with chunked HTTP progress — identical pattern to
    ``tiddl_bridge.download_track``.

    Args:
        url: web page URL to download from.
        quality: "best" | "high" | "medium" | "low".

    Returns:
        JSON ``{success, data:{filePath, title, artist, album, quality,
        fileExtension, source}, error}``.
    """
    try:
        _clear_cancel_flag()

        if not DOCUMENTS_DIR:
            return _result(False, error="Documents directory not set")

        import yt_dlp
        from requests import Session as ReqSession

        platform = _detect_platform(url)
        _write_progress("extract", _PROGRESS_EXTRACT, "Extracting info...")

        # --- 1. Extract info (no download) ---
        opts = _ydl_opts_base()
        opts["format"] = "bestaudio/best"

        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)

        if not info:
            return _result(False, error="Could not extract info from URL")

        # Unwrap playlist → first track
        if info.get("_type") == "playlist":
            first = next((e for e in info.get("entries", []) if e), None)
            if first is None:
                return _result(False, error="Playlist is empty or unresolvable")
            info = first

        title = info.get("title", "Unknown")
        artist = (info.get("uploader")
                  or info.get("creator")
                  or info.get("channel")
                  or "Unknown")
        album = info.get("album") or ""
        duration = info.get("duration")
        track_id = info.get("id", "")
        thumbnail_url = info.get("thumbnail")

        _write_progress("format", _PROGRESS_FORMAT, f"{artist} - {title}")

        if _check_cancelled():
            _write_progress("cancelled", 0, "Download cancelled")
            _clear_cancel_flag()
            return _result(False, error="cancelled")

        # --- 2. Resolve stream URL ---
        selected, is_hls = _select_audio_format(
            info.get("formats", []), quality)

        if selected is not None:
            stream_url = selected["url"]
            file_ext = "." + (selected.get("ext") or "m4a")
            # HLS fMP4 segments produce .m4a regardless of listed ext
            if is_hls:
                file_ext = ".m4a"
            abr = selected.get("abr") or selected.get("tbr")
            asr = selected.get("asr")
            acodec = selected.get("acodec")
            http_headers = (selected.get("http_headers")
                            or info.get("http_headers") or {})
        elif info.get("url"):
            is_hls = False
            stream_url = info["url"]
            file_ext = "." + (info.get("ext") or "m4a")
            abr = info.get("abr") or info.get("tbr")
            asr = info.get("asr")
            acodec = info.get("acodec")
            http_headers = info.get("http_headers") or {}
        else:
            return _result(
                False,
                error="No downloadable audio formats found"
                      " (streams may require ffmpeg)")

        # --- 3. Download the stream ---
        _write_progress("downloading", _PROGRESS_DOWNLOAD_START,
                        "Starting download...")

        if is_hls:
            # HLS: download init + media segments via m3u8 parser
            try:
                stream_data, total_bytes = _download_hls_stream(
                    stream_url, http_headers)
            except InterruptedError:
                _write_progress("cancelled", 0, "Download cancelled")
                _clear_cancel_flag()
                return _result(False, error="cancelled")
        else:
            # Direct HTTP: chunked download with progress
            total_bytes = 0
            with ReqSession() as sess:
                resp = sess.get(stream_url, timeout=60, stream=True,
                                headers=http_headers)
                resp.raise_for_status()
                content_length = int(resp.headers.get("Content-Length", 0))
                chunks = []

                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if _check_cancelled():
                        resp.close()
                        _write_progress("cancelled", 0, "Download cancelled")
                        _clear_cancel_flag()
                        return _result(False, error="cancelled")

                    chunks.append(chunk)
                    total_bytes += len(chunk)
                    mb_done = total_bytes / (1024 * 1024)

                    if content_length > 0:
                        frac = total_bytes / content_length
                        pct = _PROGRESS_DOWNLOAD_START + int(
                            _PROGRESS_DOWNLOAD_RANGE * frac)
                        mb_total = content_length / (1024 * 1024)
                        detail = f"{mb_done:.1f} / {mb_total:.1f} MB"
                    else:
                        pct = _PROGRESS_DOWNLOAD_START
                        detail = f"{mb_done:.1f} MB"

                    _write_progress(
                        "downloading",
                        min(pct,
                            _PROGRESS_DOWNLOAD_START + _PROGRESS_DOWNLOAD_RANGE),
                        detail,
                    )

                stream_data = b"".join(chunks)

                if content_length > 0 and total_bytes != content_length:
                    raise IOError(
                        f"Incomplete download: got {total_bytes}"
                        f" of {content_length} bytes")

        # --- 4. Write file atomically ---
        _write_progress("metadata", _PROGRESS_METADATA, "Adding metadata...")

        download_dir = os.path.join(DOCUMENTS_DIR, "downloads")
        os.makedirs(download_dir, exist_ok=True)

        prefix = _platform_prefix(platform)
        safe_name = _safe_filename(f"{artist} - {title}")
        if not safe_name:
            safe_name = _safe_filename(title) or "download"
        file_path = os.path.join(
            download_dir, f"{safe_name} [{prefix}-{track_id}]{file_ext}")

        tmp_path = file_path + ".tmp"
        try:
            with open(tmp_path, "wb") as f:
                f.write(stream_data)
            os.replace(tmp_path, file_path)
        except Exception:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            raise

        # --- 5. Metadata tags (non-fatal) ---
        try:
            _tag_audio_file(file_path, file_ext, title, artist, album,
                            thumbnail_url)
        except Exception as e:
            logger.warning(f"Metadata tagging error (non-fatal): {e}")

        # --- 6. Write .meta.json sidecar ---
        served_quality = f"{int(abr)}kbps" if abr else None
        try:
            codec_map = {
                ".m4a": "AAC", ".mp3": "MP3", ".opus": "Opus",
                ".ogg": "OGG", ".webm": "WebM", ".flac": "FLAC",
                ".wav": "WAV", ".mp4": "AAC",
            }
            meta = {
                "title": title,
                "artist": artist,
                "album": album,
                "trackId": None,
                "duration": duration,
                "requestedQuality": quality,
                "servedQuality": served_quality,
                "audioMode": None,
                "bitDepth": None,
                "sampleRate": asr,
                "codec": codec_map.get(file_ext,
                                       acodec or file_ext.lstrip(".")),
                "fileExtension": file_ext,
                "fileSize": os.path.getsize(file_path),
                "downloadDate": datetime.now().isoformat(),
                "coverUrl": thumbnail_url,
                "source": platform,
                "sourceUrl": info.get("webpage_url", url),
                "sourceId": track_id,
            }
            meta_path = file_path + ".meta.json"
            meta_tmp = meta_path + ".tmp"
            with open(meta_tmp, "w") as f:
                json.dump(meta, f, indent=2)
            os.replace(meta_tmp, meta_path)
        except Exception as e:
            logger.warning(f"Meta write error (non-fatal): {e}")

        _write_progress("done", _PROGRESS_DONE, title)

        return _result(True, {
            "filePath": file_path,
            "title": title,
            "artist": artist,
            "album": album,
            "quality": served_quality or quality,
            "fileExtension": file_ext,
            "source": platform,
        })
    except Exception as e:
        _write_progress("error", 0, str(e))
        logger.error(f"Download error: {e}\n{traceback.format_exc()}")
        return _result(False, error=str(e))


# ---------------------------------------------------------------------------
# Metadata tagging via mutagen
# ---------------------------------------------------------------------------

def _tag_audio_file(file_path, file_ext, title, artist, album,
                    thumbnail_url):
    """Add metadata tags to an audio file using mutagen."""
    from mutagen import File as MutagenFile

    audio = MutagenFile(file_path, easy=True)
    if audio is None:
        return

    audio["title"] = title
    audio["artist"] = artist
    if album:
        audio["album"] = album
    audio.save()

    if thumbnail_url:
        _embed_cover_art(file_path, file_ext, thumbnail_url)


def _embed_cover_art(file_path, file_ext, thumbnail_url):
    """Download and embed cover art into the audio file."""
    try:
        from requests import get as http_get

        resp = http_get(thumbnail_url, timeout=10)
        if resp.status_code != 200:
            return

        cover_data = resp.content
        mime_type = resp.headers.get("content-type", "image/jpeg")

        if file_ext == ".mp3":
            from mutagen.mp3 import MP3
            from mutagen.id3 import APIC
            audio = MP3(file_path)
            if audio.tags is None:
                audio.add_tags()
            audio.tags.add(APIC(
                encoding=3, mime=mime_type, type=3,
                desc="Cover", data=cover_data,
            ))
            audio.save()

        elif file_ext in (".m4a", ".mp4"):
            from mutagen.mp4 import MP4, MP4Cover
            audio = MP4(file_path)
            fmt = (MP4Cover.FORMAT_JPEG
                   if "jpeg" in mime_type or "jpg" in mime_type
                   else MP4Cover.FORMAT_PNG)
            audio["covr"] = [MP4Cover(cover_data, imageformat=fmt)]
            audio.save()

        elif file_ext in (".ogg", ".opus"):
            import base64
            from mutagen.flac import Picture
            if file_ext == ".opus":
                from mutagen.oggopus import OggOpus
                audio = OggOpus(file_path)
            else:
                from mutagen.oggvorbis import OggVorbis
                audio = OggVorbis(file_path)
            pic = Picture()
            pic.data = cover_data
            pic.type = 3
            pic.mime = mime_type
            audio["metadata_block_picture"] = [
                base64.b64encode(pic.write()).decode("ascii")]
            audio.save()

        elif file_ext == ".flac":
            from mutagen.flac import FLAC, Picture
            audio = FLAC(file_path)
            pic = Picture()
            pic.data = cover_data
            pic.type = 3
            pic.mime = mime_type
            audio.add_picture(pic)
            audio.save()

    except Exception as e:
        logger.warning(f"Cover art error (non-fatal): {e}")


# ---------------------------------------------------------------------------
# Module self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("ytdl_bridge loaded successfully")
    print(f"Python {sys.version}")
