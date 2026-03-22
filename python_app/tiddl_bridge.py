"""
iOS bridge for tiddl v3.
Called from Swift PythonBridge via PyRun_SimpleString.

Provides functions for:
- Authentication (device code flow)
- Track info lookup
- Track downloading
"""

import os
import sys
import json
import logging
import traceback
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tiddl_bridge")

_PROGRESS_LOOKUP = 0
_PROGRESS_STREAM = 5
_PROGRESS_DOWNLOAD_START = 10
_PROGRESS_DOWNLOAD_RANGE = 80
_PROGRESS_METADATA = 92
_PROGRESS_DONE = 100

# Diagnostic: log sys.path and verify critical imports at load time
logger.info(f"Python {sys.version}")
logger.info(f"sys.path = {sys.path}")

# Test critical imports eagerly so we catch issues at startup
for _mod in ["tiddl", "tiddl.core.auth", "tiddl.core.api", "tiddl.core.utils", "requests", "pydantic"]:
    try:
        __import__(_mod)
        logger.info(f"  ✓ import {_mod}")
    except Exception as _e:
        logger.error(f"  ✗ import {_mod}: {_e}")

# iOS Documents directory for persistent storage
DOCUMENTS_DIR = None


def set_documents_dir(path):
    """Set the iOS Documents directory path (called from Swift)."""
    global DOCUMENTS_DIR
    DOCUMENTS_DIR = path
    os.makedirs(path, exist_ok=True)


def _get_config_path():
    if DOCUMENTS_DIR:
        return os.path.join(DOCUMENTS_DIR, "tiddl.json")
    return None


def _result(success, data=None, error=None):
    """Return JSON result string for Swift bridge."""
    return json.dumps({
        "success": success,
        "data": data,
        "error": error,
    })


def start_device_auth():
    """Start Tidal device code authentication flow.
    Returns JSON with deviceCode, userCode, verificationUri."""
    try:
        from tiddl.core.auth import AuthAPI
        auth_api = AuthAPI()
        resp = auth_api.get_device_auth()
        return _result(True, {
            "deviceCode": resp.deviceCode,
            "userCode": resp.userCode,
            "verificationUri": resp.verificationUri,
            "verificationUriComplete": resp.verificationUriComplete,
            "expiresIn": resp.expiresIn,
            "interval": resp.interval,
        })
    except Exception as e:
        logger.error(f"Auth error: {e}")
        return _result(False, error=str(e))


def check_auth_token(device_code):
    """Poll for auth token after user authorizes.
    Returns JSON with token info or pending status."""
    try:
        from tiddl.core.auth import AuthAPI
        auth_api = AuthAPI()
        resp = auth_api.get_auth(device_code)
        config_data = {
            "auth": {
                "token": resp.access_token,
                "refresh_token": resp.refresh_token,
                "expires": resp.expires_in,
                "user_id": str(resp.user_id),
                "country_code": resp.user.countryCode if hasattr(resp, 'user') else "",
            }
        }
        config_path = _get_config_path()
        if config_path:
            tmp = config_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(config_data, f, indent=2)
            os.replace(tmp, config_path)

        return _result(True, {
            "token": resp.access_token,
            "refreshToken": resp.refresh_token,
            "userId": str(resp.user_id),
            "countryCode": resp.user.countryCode if hasattr(resp, 'user') else "",
        })
    except Exception as e:
        error_str = str(e)
        if "authorization_pending" in error_str.lower():
            return _result(False, error="pending")
        logger.error(f"Token error: {e}")
        return _result(False, error=error_str)


def refresh_auth():
    try:
        config_path = _get_config_path()
        if not config_path or not os.path.exists(config_path):
            return _result(False, error="No config file")

        with open(config_path) as f:
            config = json.load(f)

        refresh_token_val = config.get("auth", {}).get("refresh_token", "")
        if not refresh_token_val:
            return _result(False, error="No refresh token")

        from tiddl.core.auth import AuthAPI
        auth_api = AuthAPI()
        resp = auth_api.refresh_token(refresh_token_val)

        config["auth"]["token"] = resp.access_token
        config["auth"]["expires"] = resp.expires_in

        with open(config_path, "w") as f:
            json.dump(config, f, indent=2)

        return _result(True, {"token": resp.access_token})
    except Exception as e:
        logger.error(f"Refresh error: {e}")
        return _result(False, error=str(e))


def logout():
    try:
        config_path = _get_config_path()
        if config_path and os.path.exists(config_path):
            os.remove(config_path)
        cache_dir = os.path.join(DOCUMENTS_DIR, "cache") if DOCUMENTS_DIR else None
        if cache_dir and os.path.exists(cache_dir):
            import shutil
            shutil.rmtree(cache_dir, ignore_errors=True)
        return _result(True, {"loggedOut": True})
    except Exception as e:
        logger.error(f"Logout error: {e}")
        return _result(False, error=str(e))


def get_auth_status():
    try:
        config_path = _get_config_path()
        if not config_path or not os.path.exists(config_path):
            return _result(True, {"authenticated": False})

        with open(config_path) as f:
            config = json.load(f)

        token = config.get("auth", {}).get("token", "")
        return _result(True, {"authenticated": bool(token)})
    except Exception as e:
        return _result(False, error=str(e))


def _get_tidal_api():
    """Create a TidalAPI instance from saved config."""
    config_path = _get_config_path()
    if not config_path or not os.path.exists(config_path):
        raise RuntimeError("Not authenticated")

    with open(config_path) as f:
        config = json.load(f)

    auth = config.get("auth", {})
    from tiddl.core.api import TidalAPI, TidalClient

    cache_dir = os.path.join(DOCUMENTS_DIR, "cache") if DOCUMENTS_DIR else "/tmp"
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, "tidal_cache")

    client = TidalClient(
        token=auth["token"],
        cache_name=cache_path,
    )
    return TidalAPI(
        client=client,
        user_id=str(auth["user_id"]),
        country_code=auth.get("country_code", "US"),
    )


def get_track_info(url_or_id):
    try:
        from tiddl.cli.utils.resource import TidalResource

        api = _get_tidal_api()
        resource = TidalResource.from_string(url_or_id)
        if resource.type != "track":
            return _result(False, error=f"Only track URLs supported, got: {resource.type}")

        track = api.get_track(resource.id)
        return _result(True, {
            "id": track.id,
            "title": track.title,
            "artist": track.artist.name if track.artist else "Unknown",
            "album": track.album.title,
            "duration": track.duration,
            "quality": track.audioQuality,
        })
    except Exception as e:
        logger.error(f"Track info error: {e}\n{traceback.format_exc()}")
        return _result(False, error=str(e))


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


def get_download_progress():
    try:
        if not DOCUMENTS_DIR:
            return _result(True, {"step": "idle", "pct": 0, "detail": ""})
        progress_path = os.path.join(DOCUMENTS_DIR, ".download_progress.json")
        if not os.path.exists(progress_path):
            return _result(True, {"step": "idle", "pct": 0, "detail": ""})
        with open(progress_path) as f:
            data = json.load(f)
        return _result(True, data)
    except Exception as e:
        return _result(False, error=str(e))


def download_track(url_or_id, quality="LOSSLESS"):
    try:
        from tiddl.cli.utils.resource import TidalResource
        from tiddl.core.metadata import add_track_metadata, Cover

        if not DOCUMENTS_DIR:
            return _result(False, error="Documents directory not set")

        _write_progress("lookup", _PROGRESS_LOOKUP, "Looking up track...")

        api = _get_tidal_api()
        resource = TidalResource.from_string(url_or_id)
        if resource.type != "track":
            return _result(False, error=f"Only track URLs supported, got: {resource.type}")

        track = api.get_track(resource.id)
        artist_name = track.artist.name if track.artist else "Unknown"
        _write_progress("stream", _PROGRESS_STREAM, f"{artist_name} - {track.title}")

        stream = api.get_track_stream(resource.id, quality)

        # Use parse_track_stream for segment-level progress
        try:
            from tiddl.core.utils.parse import parse_track_stream
            from requests import Session as ReqSession

            urls, file_ext = parse_track_stream(stream)
            _write_progress("downloading", _PROGRESS_DOWNLOAD_START, "Starting download...")

            # Estimate total size from first segment's Content-Length
            est_total = 0
            stream_data = b""
            total_bytes = 0
            with ReqSession() as s:
                for i, url in enumerate(urls):
                    resp = s.get(url, timeout=30)
                    resp.raise_for_status()
                    chunk = resp.content
                    stream_data += chunk
                    total_bytes += len(chunk)
                    if i == 0 and len(urls) > 1:
                        est_total = len(chunk) * len(urls)
                    pct = _PROGRESS_DOWNLOAD_START + int(_PROGRESS_DOWNLOAD_RANGE * (i + 1) / len(urls))
                    mb_done = total_bytes / (1024 * 1024)
                    if est_total > 0:
                        mb_total = est_total / (1024 * 1024)
                        detail = f"{mb_done:.1f} / {mb_total:.0f} MB"
                    else:
                        detail = f"{mb_done:.1f} MB"
                    _write_progress("downloading", pct, detail)
        except ImportError:
            # Fallback: use get_track_stream_data if parse not available
            from tiddl.core.utils.download import get_track_stream_data
            _write_progress("downloading", _PROGRESS_DOWNLOAD_START, "Downloading...")
            stream_data, file_ext = get_track_stream_data(stream)

        _write_progress("metadata", _PROGRESS_METADATA, "Adding metadata...")

        download_dir = os.path.join(DOCUMENTS_DIR, "downloads")
        os.makedirs(download_dir, exist_ok=True)

        # Include track ID in filename to prevent collisions
        safe_name = "".join(c for c in f"{artist_name} - {track.title}" if c.isalnum() or c in " -_.")
        file_path = os.path.join(download_dir, f"{safe_name} [{resource.id}]{file_ext}")

        # Atomic write: temp file + rename
        tmp_path = file_path + ".tmp"
        try:
            with open(tmp_path, "wb") as f:
                f.write(stream_data)
            os.replace(tmp_path, file_path)
        except Exception:
            # Clean up partial temp file on failure
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            raise

        try:
            from pathlib import Path
            track_path = Path(file_path)
            cover_data = None
            if track.album.cover:
                try:
                    cover = Cover(track.album.cover)
                    cover_data = cover.fetch_data()
                except Exception:
                    pass
            add_track_metadata(track_path, track, cover_data=cover_data)
        except Exception as e:
            logger.warning(f"Metadata error (non-fatal): {e}")

        # Write .meta.json sidecar atomically
        try:
            codec_map = {".flac": "FLAC", ".m4a": "AAC", ".mp4": "AAC"}
            meta = {
                "title": track.title,
                "artist": artist_name,
                "album": track.album.title,
                "trackId": track.id,
                "duration": track.duration,
                "requestedQuality": quality,
                "servedQuality": stream.audioQuality,
                "audioMode": getattr(stream, "audioMode", None),
                "bitDepth": getattr(stream, "bitDepth", None),
                "sampleRate": getattr(stream, "sampleRate", None),
                "codec": codec_map.get(file_ext, file_ext.lstrip(".")),
                "fileExtension": file_ext,
                "fileSize": os.path.getsize(file_path),
                "downloadDate": datetime.now().isoformat(),
            }
            meta_path = file_path + ".meta.json"
            meta_tmp = meta_path + ".tmp"
            with open(meta_tmp, "w") as f:
                json.dump(meta, f, indent=2)
            os.replace(meta_tmp, meta_path)
        except Exception as e:
            logger.warning(f"Meta write error (non-fatal): {e}")

        _write_progress("done", _PROGRESS_DONE, track.title)

        return _result(True, {
            "filePath": file_path,
            "title": track.title,
            "artist": artist_name,
            "album": track.album.title,
            "quality": stream.audioQuality,
            "fileExtension": file_ext,
        })
    except Exception as e:
        _write_progress("error", 0, str(e))
        logger.error(f"Download error: {e}\n{traceback.format_exc()}")
        return _result(False, error=str(e))


def list_downloads():
    try:
        if not DOCUMENTS_DIR:
            return _result(True, {"songs": []})
        download_dir = os.path.join(DOCUMENTS_DIR, "downloads")
        if not os.path.exists(download_dir):
            return _result(True, {"songs": []})
        songs = []
        for fname in sorted(os.listdir(download_dir)):
            fpath = os.path.join(download_dir, fname)
            if os.path.isfile(fpath) and not fname.startswith('.') and not fname.endswith('.tmp') and not fname.endswith('.meta.json'):
                size_mb = os.path.getsize(fpath) / (1024 * 1024)
                meta = None
                meta_path = fpath + ".meta.json"
                try:
                    if os.path.exists(meta_path):
                        with open(meta_path) as f:
                            meta = json.load(f)
                except Exception as e:
                    logger.warning(f"Failed to read meta for {fname}: {e}")
                songs.append({
                    "fileName": fname,
                    "filePath": fpath,
                    "sizeMB": round(size_mb, 1),
                    "meta": meta,
                })
        return _result(True, {"songs": songs})
    except Exception as e:
        logger.error(f"List downloads error: {e}")
        return _result(False, error=str(e))


def delete_download(file_path):
    """Delete a downloaded song and its .meta.json sidecar (path must be within downloads dir)."""
    try:
        if not DOCUMENTS_DIR:
            return _result(False, error="Documents directory not set")
        download_dir = os.path.realpath(os.path.join(DOCUMENTS_DIR, "downloads"))
        resolved = os.path.realpath(file_path)
        if not resolved.startswith(download_dir + os.sep):
            return _result(False, error="Invalid file path")
        if os.path.exists(resolved):
            os.remove(resolved)
        meta_path = resolved + ".meta.json"
        try:
            if os.path.exists(meta_path):
                os.remove(meta_path)
        except Exception as e:
            logger.warning(f"Failed to delete meta file: {e}")
        return _result(True, {"deleted": True})
    except Exception as e:
        logger.error(f"Delete error: {e}")
        return _result(False, error=str(e))


if __name__ == "__main__":
    print("tiddl_bridge loaded successfully")
    print(f"Python {sys.version}")
