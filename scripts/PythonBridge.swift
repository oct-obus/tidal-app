import Flutter
import UIKit
import WebKit

// Python C API
@_silgen_name("Py_Initialize")
func Py_Initialize()

@_silgen_name("Py_IsInitialized")
func Py_IsInitialized() -> Int32

@_silgen_name("PyRun_SimpleString")
func PyRun_SimpleString(_ command: UnsafePointer<CChar>) -> Int32

@_silgen_name("Py_FinalizeEx")
func Py_FinalizeEx() -> Int32

@_silgen_name("setenv")
func c_setenv(_ name: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>, _ overwrite: Int32) -> Int32

@_silgen_name("PyGILState_Ensure")
func PyGILState_Ensure() -> Int32

@_silgen_name("PyGILState_Release")
func PyGILState_Release(_ state: Int32)

@_silgen_name("PyEval_SaveThread")
func PyEval_SaveThread() -> OpaquePointer?

class PythonBridge: NSObject {
    static let shared = PythonBridge()
    private var isInitialized = false
    private let queue = DispatchQueue(label: "com.obus.python", qos: .userInitiated)

    lazy var documentsPath: String = {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            NSLog("PythonBridge: Failed to get documents directory")
            return NSTemporaryDirectory()
        }
        return path
    }()

    func initialize() {
        guard !isInitialized else { return }

        guard let resourcePath = Bundle.main.resourcePath else {
            NSLog("PythonBridge: Failed to get bundle resource path")
            return
        }
        let pythonHome = "\(resourcePath)/python"
        let libPath = "\(resourcePath)/python/lib/python3.13"
        let dynloadPath = "\(libPath)/lib-dynload"
        let appPath = "\(resourcePath)/python/app"
        let appPackages = "\(resourcePath)/python/app_packages"
        let pythonPath = "\(libPath):\(dynloadPath):\(appPath):\(appPackages)"

        NSLog("PythonBridge: PYTHONHOME = %@", pythonHome)
        NSLog("PythonBridge: PYTHONPATH = %@", pythonPath)

        _ = c_setenv("PYTHONHOME", pythonHome, 1)
        _ = c_setenv("PYTHONPATH", pythonPath, 1)
        _ = c_setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        _ = c_setenv("PYTHONUNBUFFERED", "1", 1)
        _ = c_setenv("SSL_CERT_FILE", "\(resourcePath)/python/lib/python3.13/certifi/cacert.pem", 1)

        let docs = self.documentsPath
        _ = c_setenv("TIDDL_PATH", docs, 1)

        Py_Initialize()
        isInitialized = Py_IsInitialized() != 0

        if isInitialized {
            NSLog("PythonBridge: Python initialized successfully")
            let initCode = """
            import sys
            sys.path.insert(0, '\(appPackages)')
            sys.path.insert(0, '\(appPath)')
            try:
                import tiddl_bridge
                tiddl_bridge.set_documents_dir('\(docs)')
                print('tiddl_bridge loaded')
            except Exception as e:
                print(f'Failed to load tiddl_bridge: {e}')
                import traceback
                traceback.print_exc()
            try:
                import ytdl_bridge
                ytdl_bridge.set_documents_dir('\(docs)')
                _cookies = '\(docs)/cookies.txt'
                import os as _os
                if _os.path.isfile(_cookies):
                    ytdl_bridge.set_cookies_path(_cookies)
                print('ytdl_bridge loaded')
            except Exception as e:
                print(f'Failed to load ytdl_bridge: {e}')
                import traceback
                traceback.print_exc()
            """
            PyRun_SimpleString(initCode)

            // Release the GIL so background threads can acquire it
            _ = PyEval_SaveThread()
        } else {
            NSLog("PythonBridge: Failed to initialize Python")
        }
    }

    func run(_ code: String) -> Bool {
        guard isInitialized else { return false }
        let result = PyRun_SimpleString(code)
        return result == 0
    }

    /// Escape a string for safe inclusion in Python string literals
    func pythonEscape(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// Run Python code that stores its result in `_bridge_result` and return it
    func runWithResult(_ code: String, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.isInitialized else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let gilState = PyGILState_Ensure()
            defer { PyGILState_Release(gilState) }

            let wrappedCode = """
            import json as _json
            _bridge_result = None
            try:
                _bridge_result = (lambda: (\(code)))()
            except Exception as _e:
                _bridge_result = _json.dumps({"success": False, "error": str(_e)})
            """

            let success = PyRun_SimpleString(wrappedCode)
            guard success == 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Use unique temp file to avoid race conditions
            let tmpPath = NSTemporaryDirectory() + "bridge_result_\(UUID().uuidString).txt"
            let fileCode = """
            with open('\(tmpPath)', 'w') as _f:
                _f.write(str(_bridge_result) if _bridge_result else '')
            """
            PyRun_SimpleString(fileCode)

            let result = try? String(contentsOfFile: tmpPath, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: tmpPath)
            DispatchQueue.main.async { completion(result) }
        }
    }
}

public class PythonBridgePlugin: NSObject, FlutterPlugin {
    private let bridge = PythonBridge.shared

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.obus.tidal_app/python",
            binaryMessenger: registrar.messenger()
        )
        let instance = PythonBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Initialize Python early
        instance.bridge.initialize()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "runPython":
            guard let args = call.arguments as? [String: Any],
                  let code = args["code"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'code' argument", details: nil))
                return
            }
            let success = bridge.run(code)
            result(success)

        case "pythonVersion":
            bridge.runWithResult("__import__('sys').version") { version in
                result(version ?? "Unknown")
            }

        case "authStatus":
            bridge.runWithResult("tiddl_bridge.get_auth_status()") { response in
                result(response)
            }

        case "startAuth":
            bridge.runWithResult("tiddl_bridge.start_device_auth()") { response in
                result(response)
            }

        case "checkAuth":
            guard let args = call.arguments as? [String: Any],
                  let deviceCode = args["deviceCode"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'deviceCode'", details: nil))
                return
            }
            let safeCode = bridge.pythonEscape(deviceCode)
            bridge.runWithResult("tiddl_bridge.check_auth_token('\(safeCode)')") { response in
                result(response)
            }

        case "logout":
            bridge.runWithResult("tiddl_bridge.logout()") { response in
                result(response)
            }

        case "downloadProgress":
            // Read progress file directly from Swift, not via Python queue
            // (the Python queue is blocked by the running download)
            let docs = bridge.documentsPath
            let progressPath = "\(docs)/.download_progress.json"
            if let data = FileManager.default.contents(atPath: progressPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let wrapped: [String: Any] = ["success": true, "data": json]
                if let jsonData = try? JSONSerialization.data(withJSONObject: wrapped),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    result(jsonStr)
                    return
                }
            }
            result("{\"success\":true,\"data\":{\"step\":\"idle\",\"pct\":0,\"detail\":\"\"}}")

        case "cancelDownload":
            // Write cancel flag directly from Swift (bypasses blocked Python queue)
            let docs = bridge.documentsPath
            let cancelPath = "\(docs)/.download_cancel"
            FileManager.default.createFile(atPath: cancelPath, contents: "cancel".data(using: .utf8))
            result("{\"success\":true}")

        case "listDownloads":
            bridge.runWithResult("tiddl_bridge.list_downloads()") { response in
                result(response)
            }

        case "deleteDownload":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'filePath'", details: nil))
                return
            }
            let safePath = bridge.pythonEscape(filePath)
            bridge.runWithResult("tiddl_bridge.delete_download('\(safePath)')") { response in
                result(response)
            }

        case "refreshAuth":
            bridge.runWithResult("tiddl_bridge.refresh_auth()") { response in
                result(response)
            }

        case "getPlaylistInfo":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url'", details: nil))
                return
            }
            let safeUrl = bridge.pythonEscape(url)
            bridge.runWithResult("tiddl_bridge.get_playlist_info('\(safeUrl)')") { response in
                result(response)
            }

        case "listPlaylists":
            bridge.runWithResult("tiddl_bridge.list_playlists()") { response in
                result(response)
            }

        case "savePlaylist":
            guard let args = call.arguments as? [String: Any],
                  let jsonStr = args["json"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'json'", details: nil))
                return
            }
            let safeJson = bridge.pythonEscape(jsonStr)
            bridge.runWithResult("tiddl_bridge.save_playlist('\(safeJson)')") { response in
                result(response)
            }

        case "removePlaylist":
            guard let args = call.arguments as? [String: Any],
                  let uuid = args["uuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'uuid'", details: nil))
                return
            }
            let safeUuid = bridge.pythonEscape(uuid)
            bridge.runWithResult("tiddl_bridge.remove_playlist('\(safeUuid)')") { response in
                result(response)
            }

        case "searchTidal":
            guard let args = call.arguments as? [String: Any],
                  let query = args["query"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'query'", details: nil))
                return
            }
            let safeQuery = bridge.pythonEscape(query)
            let limit = args["limit"] as? Int ?? 25
            let offset = args["offset"] as? Int ?? 0
            bridge.runWithResult("tiddl_bridge.search_tidal('\(safeQuery)', limit=\(limit), offset=\(offset))") { response in
                result(response)
            }

        case "getTrackInfo":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url'", details: nil))
                return
            }
            let safeUrl = bridge.pythonEscape(url)
            bridge.runWithResult("tiddl_bridge.get_track_info('\(safeUrl)')") { response in
                result(response)
            }

        case "download":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url'", details: nil))
                return
            }
            let quality = (args["quality"] as? String) ?? "LOSSLESS"
            let safeUrl = bridge.pythonEscape(url)
            let safeQuality = bridge.pythonEscape(quality)
            bridge.runWithResult("tiddl_bridge.download_track('\(safeUrl)', '\(safeQuality)')") { response in
                result(response)
            }

        case "importFiles":
            guard let args = call.arguments as? [String: Any],
                  let filePaths = args["filePaths"] as? [String] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'filePaths'", details: nil))
                return
            }
            // Serialize paths as JSON and pass to Python
            guard let jsonData = try? JSONSerialization.data(withJSONObject: filePaths),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                result(FlutterError(code: "JSON_ERROR", message: "Failed to encode paths", details: nil))
                return
            }
            let safeJson = bridge.pythonEscape(jsonStr)
            bridge.runWithResult("tiddl_bridge.import_files('\(safeJson)')") { response in
                result(response)
            }

        case "saveSettings":
            guard let args = call.arguments as? [String: Any],
                  let jsonStr = args["json"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'json'", details: nil))
                return
            }
            let docs = bridge.documentsPath
            let path = "\(docs)/settings.json"
            let tmp = "\(path).tmp"
            do {
                try jsonStr.write(toFile: tmp, atomically: false, encoding: .utf8)
                try FileManager.default.moveItem(atPath: tmp, toPath: path)
            } catch {
                // moveItem fails if dest exists; replace manually
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.moveItem(atPath: tmp, toPath: path)
            }
            result(true)

        case "loadSettings":
            let docs = bridge.documentsPath
            let path = "\(docs)/settings.json"
            if let data = FileManager.default.contents(atPath: path),
               let str = String(data: data, encoding: .utf8) {
                result(str)
            } else {
                result(nil)
            }

        // MARK: - yt-dlp bridge (YouTube / SoundCloud)

        case "checkYtdlp":
            bridge.runWithResult("ytdl_bridge.check_ytdlp()") { response in
                result(response)
            }

        case "checkJsRuntime":
            bridge.runWithResult("ytdl_bridge.check_js_runtime()") { response in
                result(response)
            }

        case "getUrlInfo":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url'", details: nil))
                return
            }
            let safeUrl = bridge.pythonEscape(url)
            bridge.runWithResult("ytdl_bridge.get_url_info('\(safeUrl)')") { response in
                result(response)
            }

        case "downloadUrl":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url'", details: nil))
                return
            }
            let quality = (args["quality"] as? String) ?? "best"
            let safeUrl = bridge.pythonEscape(url)
            let safeQuality = bridge.pythonEscape(quality)
            bridge.runWithResult("ytdl_bridge.download_url('\(safeUrl)', '\(safeQuality)')") { response in
                result(response)
            }

        case "setCookiesPath":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path'", details: nil))
                return
            }
            let safePath = bridge.pythonEscape(path)
            bridge.runWithResult("ytdl_bridge.set_cookies_path('\(safePath)') or 'ok'") { _ in
                result(nil)
            }

        case "clearCookies":
            bridge.runWithResult("ytdl_bridge.clear_cookies() or 'ok'") { _ in
                result(nil)
            }

        case "getCookiesStatus":
            bridge.runWithResult("ytdl_bridge.get_cookies_status()") { response in
                result(response)
            }

        case "importCookies":
            // Copy the user-selected file to a stable location in Documents
            guard let args = call.arguments as? [String: Any],
                  let sourcePath = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'path'", details: nil))
                return
            }
            let docs = bridge.documentsPath
            let destPath = "\(docs)/cookies.txt"
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.copyItem(atPath: sourcePath, toPath: destPath)
                let safeDest = bridge.pythonEscape(destPath)
                bridge.runWithResult("ytdl_bridge.set_cookies_path('\(safeDest)') or 'ok'") { _ in
                    result(destPath)
                }
            } catch {
                result(FlutterError(code: "COPY_ERROR",
                                    message: "Failed to import cookies: \(error.localizedDescription)",
                                    details: nil))
            }

        case "extractYouTubeCookies":
            // Extract YouTube/Google cookies from WKWebView's default data store
            // and save as Netscape cookies.txt for yt-dlp
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self = self else {
                    result(FlutterError(code: "ERROR", message: "Plugin deallocated", details: nil))
                    return
                }

                let ytCookies = cookies.filter { cookie in
                    cookie.domain.contains("youtube") ||
                    cookie.domain.contains("google") ||
                    cookie.domain.contains("googlevideo")
                }

                if ytCookies.isEmpty {
                    result("{\"success\":true,\"data\":{\"count\":0}}")
                    return
                }

                // Build Netscape cookies.txt
                var lines = [
                    "# Netscape HTTP Cookie File",
                    "# Extracted from WKWebView by Tidal App",
                    ""
                ]

                for cookie in ytCookies {
                    let domain = cookie.domain.hasPrefix(".") ? cookie.domain : ".\(cookie.domain)"
                    let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
                    let secure = cookie.isSecure ? "TRUE" : "FALSE"
                    let expiry: String
                    if let expiresDate = cookie.expiresDate {
                        expiry = String(Int(expiresDate.timeIntervalSince1970))
                    } else {
                        expiry = "0"
                    }
                    lines.append("\(domain)\t\(includeSubdomains)\t\(cookie.path)\t\(secure)\t\(expiry)\t\(cookie.name)\t\(cookie.value)")
                }

                let content = lines.joined(separator: "\n") + "\n"
                let docs = self.bridge.documentsPath
                let destPath = "\(docs)/cookies.txt"

                do {
                    try content.write(toFile: destPath, atomically: true, encoding: .utf8)
                    let safeDest = self.bridge.pythonEscape(destPath)
                    self.bridge.runWithResult("ytdl_bridge.set_cookies_path('\(safeDest)') or 'ok'") { _ in
                        let response = "{\"success\":true,\"data\":{\"count\":\(ytCookies.count),\"path\":\"\(destPath)\"}}"
                        result(response)
                    }
                } catch {
                    result(FlutterError(code: "WRITE_ERROR",
                                        message: "Failed to write cookies: \(error.localizedDescription)",
                                        details: nil))
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
