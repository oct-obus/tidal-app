import Foundation
import AVFoundation
import AudioToolbox
import FFmpegSupport

enum FFmpegBridge {
    private static let convertibleExtensions = Set([".webm", ".opus", ".ogg"])

    static func convertDownloadResponseIfNeeded(_ response: String, documentsPath: String) -> String {
        guard let data = response.data(using: .utf8),
              var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              payload["success"] as? Bool == true,
              var item = payload["data"] as? [String: Any],
              let filePath = item["filePath"] as? String else {
            return response
        }

        let inputURL = URL(fileURLWithPath: filePath)
        let inputExt = "." + inputURL.pathExtension.lowercased()
        guard convertibleExtensions.contains(inputExt) else {
            return response
        }

        do {
            writeProgress(documentsPath: documentsPath, step: "converting", pct: 94,
                          detail: "Converting Opus/WebM for iOS playback...")
            let outputPath = try convertToM4A(inputPath: filePath)
            item["filePath"] = outputPath
            item["fileExtension"] = ".m4a"
            item["quality"] = item["quality"] ?? "Converted AAC"

            if var stats = item["downloadStats"] as? [String: Any] {
                stats["conversion"] = "ffmpeg-aac-m4a"
                item["downloadStats"] = stats
            } else {
                item["downloadStats"] = ["conversion": "ffmpeg-aac-m4a"]
            }

            payload["data"] = item
            updateMetadataSidecar(inputPath: filePath, outputPath: outputPath)
            try? FileManager.default.removeItem(atPath: filePath)
            try? FileManager.default.removeItem(atPath: filePath + ".meta.json")
            writeProgress(documentsPath: documentsPath, step: "done", pct: 100,
                          detail: item["title"] as? String ?? "Done")

            guard let outData = try? JSONSerialization.data(withJSONObject: payload),
                  let outString = String(data: outData, encoding: .utf8) else {
                return response
            }
            return outString
        } catch {
            try? FileManager.default.removeItem(atPath: filePath)
            try? FileManager.default.removeItem(atPath: filePath + ".meta.json")
            writeProgress(documentsPath: documentsPath, step: "error", pct: 0,
                          detail: error.localizedDescription)
            return failureResponse("FFmpeg conversion failed: \(error.localizedDescription)")
        }
    }

    private static func convertToM4A(inputPath: String) throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let baseURL = inputURL.deletingPathExtension()
        let outputURL = uniqueOutputURL(baseURL.appendingPathExtension("m4a"))
        let tmpURL = URL(fileURLWithPath: outputURL.path + ".tmp.m4a")
        try? FileManager.default.removeItem(at: tmpURL)

        let ret = ffmpeg([
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputPath,
            "-vn",
            "-map", "0:a:0",
            "-c:a", "aac",
            "-b:a", "160k",
            "-movflags", "+faststart",
            tmpURL.path,
        ])

        guard ret == 0, FileManager.default.fileExists(atPath: tmpURL.path) else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: "FFmpegBridge", code: ret, userInfo: [
                NSLocalizedDescriptionKey: "ffmpeg exited with status \(ret)"
            ])
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: tmpURL, to: outputURL)
        return outputURL.path
    }

    private static func uniqueOutputURL(_ preferredURL: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }
        let dir = preferredURL.deletingLastPathComponent()
        let base = preferredURL.deletingPathExtension().lastPathComponent
        let ext = preferredURL.pathExtension
        for index in 1..<1000 {
            let candidate = dir.appendingPathComponent("\(base) (\(index))").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return dir.appendingPathComponent("\(base) (\(UUID().uuidString))").appendingPathExtension(ext)
    }

    private static func updateMetadataSidecar(inputPath: String, outputPath: String) {
        let inputMeta = inputPath + ".meta.json"
        let outputMeta = outputPath + ".meta.json"
        guard let data = FileManager.default.contents(atPath: inputMeta),
              var meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        meta["codec"] = "AAC"
        meta["fileExtension"] = ".m4a"
        meta["fileSize"] = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size]) ?? 0
        meta["conversion"] = "ffmpeg-aac-m4a"
        if let outData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try? outData.write(to: URL(fileURLWithPath: outputMeta), options: [.atomic])
        }
    }

    private static func writeProgress(documentsPath: String, step: String, pct: Int, detail: String) {
        let path = URL(fileURLWithPath: documentsPath).appendingPathComponent(".download_progress.json")
        let progress: [String: Any] = ["step": step, "pct": pct, "detail": detail]
        if let data = try? JSONSerialization.data(withJSONObject: progress) {
            try? data.write(to: path, options: [.atomic])
        }
    }

    private static func failureResponse(_ message: String) -> String {
        let payload: [String: Any] = ["success": false, "error": message]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"success\":false,\"error\":\"FFmpeg conversion failed\"}"
        }
        return string
    }

    static func runOpusDiagnostic(_ response: String, documentsPath: String) -> String {
        guard let data = response.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              payload["success"] as? Bool == true,
              let item = payload["data"] as? [String: Any],
              let inputPath = item["filePath"] as? String else {
            return response
        }

        let dir = URL(fileURLWithPath: documentsPath)
            .appendingPathComponent("opus_diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.timestamp()
        let logURL = dir.appendingPathComponent("opus_diagnostic_\(stamp).log")

        var log = [String]()
        func add(_ line: String = "") { log.append(line) }

        add("YouTube Opus iOS diagnostic")
        add("Timestamp: \(Date())")
        add("Input: \(inputPath)")
        add("Title: \(item["title"] as? String ?? "")")
        add("Format: \(item["formatId"] as? String ?? "") ext=\(item["fileExtension"] as? String ?? "") codec=\(item["codec"] as? String ?? "") abr=\(item["abr"] ?? "") asr=\(item["sampleRate"] ?? "")")
        add("Goal: prove whether Opus can be preserved without re-encoding for this app's AVPlayer path.")
        add("")

        add(section("direct-webm", inputPath, remux: nil))

        let candidates: [(String, [String])] = [
            ("caf-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("mov-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("mp4-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("m4a-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("ogg-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("opus-copy", ["-vn", "-map", "0:a:0", "-c:a", "copy"]),
            ("m4a-aac-baseline", ["-vn", "-map", "0:a:0", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]),
        ]

        let extensions = [
            "caf-copy": "caf",
            "mov-copy": "mov",
            "mp4-copy": "mp4",
            "m4a-copy": "m4a",
            "ogg-copy": "ogg",
            "opus-copy": "opus",
            "m4a-aac-baseline": "m4a",
        ]

        for (name, args) in candidates {
            let ext = extensions[name] ?? "bin"
            let output = dir.appendingPathComponent("\(stamp)_\(name).\(ext)").path
            add(section(name, inputPath, remux: (output, args)))
        }

        add("Legend:")
        add("- PASS for Opus preservation requires ffmpeg copy success plus AVPlayer readyToPlay without AAC transcode.")
        add("- The m4a-aac-baseline row is a labeled fallback only; it does not preserve Opus quality.")
        add("- AudioToolbox OSStatus 'typ?' indicates unsupported container/file type.")

        let content = log.joined(separator: "\n") + "\n"
        try? content.write(to: logURL, atomically: true, encoding: .utf8)

        let result: [String: Any] = [
            "success": true,
            "data": [
                "logPath": logURL.path,
                "content": content,
                "inputPath": inputPath,
            ],
        ]
        guard let outData = try? JSONSerialization.data(withJSONObject: result),
              let outString = String(data: outData, encoding: .utf8) else {
            return failureResponse("Could not serialize Opus diagnostic result")
        }
        return outString
    }

    private static func section(_ name: String, _ inputPath: String, remux: (String, [String])?) -> String {
        var lines = ["=== \(name) ==="]
        var testPath = inputPath
        if let remux = remux {
            let outputPath = remux.0
            try? FileManager.default.removeItem(atPath: outputPath)
            let args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", inputPath] + remux.1 + [outputPath]
            let ret = ffmpeg(args)
            lines.append("ffmpeg: \(args.joined(separator: " "))")
            lines.append("ffmpegExit: \(ret)")
            lines.append("outputExists: \(FileManager.default.fileExists(atPath: outputPath))")
            if let size = fileSize(outputPath) {
                lines.append("outputBytes: \(size)")
            }
            if ret != 0 || !FileManager.default.fileExists(atPath: outputPath) {
                lines.append("result: REMUX_FAILED")
                lines.append("")
                return lines.joined(separator: "\n")
            }
            testPath = outputPath
        }

        lines.append(contentsOf: avDiagnostics(testPath))
        lines.append(contentsOf: audioToolboxDiagnostics(testPath))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func avDiagnostics(_ path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        var lines = [String]()
        let keys = ["playable", "tracks", "duration"]
        let loadSema = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: keys) {
            loadSema.signal()
        }
        let loadWait = loadSema.wait(timeout: .now() + 8)
        lines.append("path: \(path)")
        lines.append("bytes: \(fileSize(path).map(String.init) ?? "missing")")
        lines.append("asset.keyLoadWait: \(loadWait == .success ? "completed" : "timedOut")")
        for key in keys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            lines.append("asset.keyStatus.\(key): \(status.rawValue) error=\(error?.localizedDescription ?? "none")")
        }
        lines.append("asset.isPlayable: \(asset.isPlayable)")
        lines.append("asset.duration: \(safeSeconds(asset.duration))")
        lines.append("audioTracks: \(asset.tracks(withMediaType: .audio).count)")
        for (idx, track) in asset.tracks(withMediaType: .audio).enumerated() {
            lines.append("audioTrack[\(idx)].formatDescriptions: \(track.formatDescriptions.count)")
            for desc in track.formatDescriptions {
                let fmt = CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription)
                lines.append("audioTrack[\(idx)].subtype: \(fourCC(fmt))")
            }
        }

        let item = AVPlayerItem(url: url)
        let sema = DispatchSemaphore(value: 0)
        var observed = "unknown"
        let observer = item.observe(\.status, options: [.new]) { observedItem, _ in
            switch observedItem.status {
            case .readyToPlay:
                observed = "readyToPlay"
                sema.signal()
            case .failed:
                observed = "failed"
                sema.signal()
            default:
                break
            }
        }
        let player = AVPlayer(playerItem: item)
        _ = player.currentItem
        let wait = sema.wait(timeout: .now() + 8)
        observer.invalidate()
        lines.append("playerItem.status: \(observed)")
        lines.append("playerItem.waitResult: \(wait == .success ? "completed" : "timedOut")")
        lines.append("playerItem.error: \(item.error?.localizedDescription ?? "none")")
        if let errorLog = item.errorLog() {
            lines.append("playerItem.errorLog.events: \(errorLog.events.count)")
            for event in errorLog.events {
                lines.append("errorLog: status=\(event.errorStatusCode) domain=\(event.errorDomain ?? "") comment=\(event.errorComment ?? "")")
            }
        }
        return lines
    }

    private static func audioToolboxDiagnostics(_ path: String) -> [String] {
        var file: ExtAudioFileRef?
        let status = ExtAudioFileOpenURL(URL(fileURLWithPath: path) as CFURL, &file)
        if let file = file {
            ExtAudioFileDispose(file)
        }
        return [
            "ExtAudioFileOpenURL.status: \(status)",
            "ExtAudioFileOpenURL.fourCC: \(fourCC(UInt32(bitPattern: status)))",
        ]
    }

    private static func fileSize(_ path: String) -> UInt64? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    private static func safeSeconds(_ time: CMTime) -> String {
        let seconds = time.seconds
        if seconds.isNaN || seconds.isInfinite {
            return "invalid"
        }
        return String(format: "%.3f", seconds)
    }

    private static func fourCC(_ value: UInt32) -> String {
        let chars = [
            Character(UnicodeScalar((value >> 24) & 0xff) ?? UnicodeScalar(63)!),
            Character(UnicodeScalar((value >> 16) & 0xff) ?? UnicodeScalar(63)!),
            Character(UnicodeScalar((value >> 8) & 0xff) ?? UnicodeScalar(63)!),
            Character(UnicodeScalar(value & 0xff) ?? UnicodeScalar(63)!),
        ]
        return String(chars)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
