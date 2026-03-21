"""
tiddl_bridge.py — iOS bridge for tiddl v3 (Tidal downloader).
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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("tiddl_bridge")

# Diagnostic: log sys.path and verify critical imports at load time
logger.info(f"Python {sys.version}")
logger.info(f"sys.path = {sys.path}")

# Test critical imports eagerly so we catch issues at startup
_import_errors = []
for _mod in ["tiddl", "tiddl.core.auth", "tiddl.core.api", "tiddl.core.utils", "requests", "pydantic"]:
    try:
        __import__(_mod)
        logger.info(f"  ✓ import {_mod}")
    except Exception as _e:
        logger.error(f"  ✗ import {_mod}: {_e}")
        _import_errors.append((_mod, str(_e)))

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
            with open(config_path, "w") as f:
                json.dump(config_data, f, indent=2)

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
    """Refresh the auth token using saved refresh token."""
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
    """Clear saved auth credentials."""
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
    """Check if we have saved auth credentials."""
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
    """Get track info from Tidal URL or ID."""
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


def download_track(url_or_id, quality="LOSSLESS"):
    """Download a track from Tidal."""
    try:
        from tiddl.cli.utils.resource import TidalResource
        from tiddl.core.utils.download import get_track_stream_data
        from tiddl.core.metadata import add_track_metadata, Cover

        api = _get_tidal_api()
        resource = TidalResource.from_string(url_or_id)
        if resource.type != "track":
            return _result(False, error=f"Only track URLs supported, got: {resource.type}")

        track = api.get_track(resource.id)
        stream = api.get_track_stream(resource.id, quality)
        stream_data, file_ext = get_track_stream_data(stream)

        download_dir = os.path.join(DOCUMENTS_DIR, "downloads")
        os.makedirs(download_dir, exist_ok=True)

        artist_name = track.artist.name if track.artist else "Unknown"
        safe_name = "".join(c for c in f"{artist_name} - {track.title}" if c.isalnum() or c in " -_.")
        file_path = os.path.join(download_dir, f"{safe_name}{file_ext}")

        with open(file_path, "wb") as f:
            f.write(stream_data)

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

        return _result(True, {
            "filePath": file_path,
            "title": track.title,
            "artist": artist_name,
            "album": track.album.title,
            "quality": stream.audioQuality,
            "fileExtension": file_ext,
        })
    except Exception as e:
        logger.error(f"Download error: {e}\n{traceback.format_exc()}")
        return _result(False, error=str(e))


if __name__ == "__main__":
    print("tiddl_bridge loaded successfully")
    print(f"Python {sys.version}")
