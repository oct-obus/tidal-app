import Foundation
import AVFoundation
import FFmpegSupport

enum FFmpegBridge {
    private static let remuxableExtensions = Set([".webm", ".opus", ".ogg"])

    static func remuxDownloadResponseIfNeeded(_ response: String, documentsPath: String) -> String {
        guard let data = response.data(using: .utf8),
              var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              payload["success"] as? Bool == true,
              var item = payload["data"] as? [String: Any],
              let filePath = item["filePath"] as? String else {
            return response
        }

        let inputURL = URL(fileURLWithPath: filePath)
        let inputExt = "." + inputURL.pathExtension.lowercased()
        guard remuxableExtensions.contains(inputExt) else {
            return response
        }

        do {
            writeProgress(documentsPath: documentsPath, step: "remuxing", pct: 94,
                          detail: "Remuxing Opus for iOS playback...")
            let outputPath = try remuxOpusToMP4(inputPath: filePath)
            guard isAVPlayerReady(outputPath) else {
                try? FileManager.default.removeItem(atPath: outputPath)
                throw NSError(domain: "FFmpegBridge", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "remuxed mp4 opus was not playable by AVPlayer"
                ])
            }
            rewriteResult(&payload, item: &item, filePath: filePath,
                          outputPath: outputPath, fileExtension: ".mp4",
                          codec: "Opus", conversion: "ffmpeg-opus-mp4-copy")
            cleanupOriginal(filePath)
            writeProgress(documentsPath: documentsPath, step: "done", pct: 100,
                          detail: item["title"] as? String ?? "Done")
            return serialize(payload) ?? response
        } catch {
            NSLog("FFmpegBridge: Opus remux failed, falling back to AAC: \(error.localizedDescription)")
            do {
                writeProgress(documentsPath: documentsPath, step: "converting", pct: 96,
                              detail: "Remux failed; converting to AAC fallback...")
                let outputPath = try convertToM4A(inputPath: filePath)
                rewriteResult(&payload, item: &item, filePath: filePath,
                              outputPath: outputPath, fileExtension: ".m4a",
                              codec: "AAC", conversion: "ffmpeg-aac-m4a-fallback")
                cleanupOriginal(filePath)
                writeProgress(documentsPath: documentsPath, step: "done", pct: 100,
                              detail: item["title"] as? String ?? "Done")
                return serialize(payload) ?? response
            } catch {
                cleanupOriginal(filePath)
                writeProgress(documentsPath: documentsPath, step: "error", pct: 0,
                              detail: error.localizedDescription)
                return failureResponse("FFmpeg remux/conversion failed: \(error.localizedDescription)")
            }
        }
    }

    private static func remuxOpusToMP4(inputPath: String) throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = uniqueOutputURL(inputURL.deletingPathExtension().appendingPathExtension("mp4"))
        let tmpURL = URL(fileURLWithPath: outputURL.path + ".tmp.mp4")
        try? FileManager.default.removeItem(at: tmpURL)

        let ret = ffmpeg([
            "ffmpeg",
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", inputPath,
            "-vn",
            "-map", "0:a:0",
            "-map_metadata", "0",
            "-c:a", "copy",
            tmpURL.path,
        ])

        guard ret == 0, FileManager.default.fileExists(atPath: tmpURL.path), (fileSize(tmpURL.path) ?? 0) > 0 else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: "FFmpegBridge", code: ret, userInfo: [
                NSLocalizedDescriptionKey: "ffmpeg opus mp4 remux exited with status \(ret)"
            ])
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: tmpURL, to: outputURL)
        return outputURL.path
    }

    private static func convertToM4A(inputPath: String) throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = uniqueOutputURL(inputURL.deletingPathExtension().appendingPathExtension("m4a"))
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
            "-map_metadata", "0",
            "-c:a", "aac",
            "-b:a", "160k",
            "-movflags", "+faststart",
            tmpURL.path,
        ])

        guard ret == 0, FileManager.default.fileExists(atPath: tmpURL.path), (fileSize(tmpURL.path) ?? 0) > 0 else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw NSError(domain: "FFmpegBridge", code: ret, userInfo: [
                NSLocalizedDescriptionKey: "ffmpeg aac fallback exited with status \(ret)"
            ])
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: tmpURL, to: outputURL)
        return outputURL.path
    }

    private static func rewriteResult(_ payload: inout [String: Any], item: inout [String: Any],
                                      filePath: String, outputPath: String,
                                      fileExtension: String, codec: String,
                                      conversion: String) {
        item["filePath"] = outputPath
        item["fileExtension"] = fileExtension
        item["codec"] = codec
        item["fileSize"] = fileSize(outputPath) ?? 0
        if var stats = item["downloadStats"] as? [String: Any] {
            stats["conversion"] = conversion
            item["downloadStats"] = stats
        } else {
            item["downloadStats"] = ["conversion": conversion]
        }
        payload["data"] = item
        updateMetadataSidecar(inputPath: filePath, outputPath: outputPath,
                              fileExtension: fileExtension, codec: codec,
                              conversion: conversion)
    }

    private static func updateMetadataSidecar(inputPath: String, outputPath: String,
                                              fileExtension: String, codec: String,
                                              conversion: String) {
        let inputMeta = inputPath + ".meta.json"
        let outputMeta = outputPath + ".meta.json"
        guard let data = FileManager.default.contents(atPath: inputMeta),
              var meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        meta["codec"] = codec
        meta["fileExtension"] = fileExtension
        meta["fileSize"] = fileSize(outputPath) ?? 0
        meta["conversion"] = conversion
        if let outData = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try? outData.write(to: URL(fileURLWithPath: outputMeta), options: [.atomic])
        }
    }

    private static func cleanupOriginal(_ filePath: String) {
        try? FileManager.default.removeItem(atPath: filePath)
        try? FileManager.default.removeItem(atPath: filePath + ".meta.json")
    }

    private static func isAVPlayerReady(_ path: String) -> Bool {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let keys = ["playable", "tracks"]
        let loadSema = DispatchSemaphore(value: 0)
        asset.loadValuesAsynchronously(forKeys: keys) {
            loadSema.signal()
        }
        guard loadSema.wait(timeout: .now() + 8) == .success else {
            return false
        }

        for key in keys {
            var error: NSError?
            guard asset.statusOfValue(forKey: key, error: &error) == .loaded else {
                return false
            }
        }
        guard asset.isPlayable, !asset.tracks(withMediaType: .audio).isEmpty else {
            return false
        }

        let item = AVPlayerItem(asset: asset)
        if item.status == .readyToPlay {
            return true
        }
        if item.status == .failed {
            return false
        }

        let readySema = DispatchSemaphore(value: 0)
        var isReady = false
        var observation: NSKeyValueObservation?
        observation = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
            switch observedItem.status {
            case .readyToPlay:
                isReady = true
                readySema.signal()
            case .failed:
                readySema.signal()
            default:
                break
            }
        }
        let player = AVPlayer(playerItem: item)
        _ = player.currentItem
        _ = readySema.wait(timeout: .now() + 8)
        observation?.invalidate()
        return isReady
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

    private static func writeProgress(documentsPath: String, step: String, pct: Int, detail: String) {
        let path = URL(fileURLWithPath: documentsPath).appendingPathComponent(".download_progress.json")
        let progress: [String: Any] = ["step": step, "pct": pct, "detail": detail]
        if let data = try? JSONSerialization.data(withJSONObject: progress) {
            try? data.write(to: path, options: [.atomic])
        }
    }

    private static func fileSize(_ path: String) -> Int64? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func serialize(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func failureResponse(_ message: String) -> String {
        let payload: [String: Any] = ["success": false, "error": message]
        return serialize(payload) ?? "{\"success\":false,\"error\":\"FFmpeg remux failed\"}"
    }
}
