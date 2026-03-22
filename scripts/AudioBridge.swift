import Flutter
import UIKit
import AVFoundation
import MediaPlayer

class AudioBridgePlugin: NSObject, FlutterPlugin {
    static let shared = AudioBridgePlugin()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stateChannel: FlutterMethodChannel?

    private var currentFilePath: String?
    private var currentTitle: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var playbackSpeed: Float = 1.0
    private var isPlaying = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.obus.tidal_app/audio",
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioBridgePlugin.shared
        instance.stateChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.setupAudioSession()
        instance.setupRemoteCommands()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            NSLog("AudioBridge: Failed to configure audio session: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resumePlayback()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pausePlayback()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true {
                self?.pausePlayback()
            } else {
                self?.resumePlayback()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seekTo(seconds: event.positionTime)
            }
            return .success
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "play":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing filePath", details: nil))
                return
            }
            let speed = Float(args["speed"] as? Double ?? 1.0)
            currentTitle = args["title"] as? String
            currentArtist = args["artist"] as? String
            currentAlbum = args["album"] as? String
            playFile(filePath, speed: speed)
            result(true)

        case "pause":
            pausePlayback()
            result(true)

        case "resume":
            resumePlayback()
            result(true)

        case "stop":
            stopPlayback()
            result(true)

        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing speed", details: nil))
                return
            }
            setSpeed(Float(speed))
            result(true)

        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing position", details: nil))
                return
            }
            seekTo(seconds: position)
            result(true)

        case "getState":
            result(getState())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func playFile(_ filePath: String, speed: Float) {
        // Clean up previous player
        cleanupObservers()

        let url = URL(fileURLWithPath: filePath)
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .varispeed

        player = AVPlayer(playerItem: item)
        currentFilePath = filePath
        playbackSpeed = speed
        isPlaying = true
        player?.rate = speed

        // Observe when track ends
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.updateNowPlayingInfo()
            self?.stateChannel?.invokeMethod("onPlaybackComplete", arguments: nil)
        }

        // Periodic time observer for now playing info updates
        let interval = CMTime(seconds: 1.0, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }

        updateNowPlayingInfo()
    }

    private func pausePlayback() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    private func resumePlayback() {
        guard player != nil else { return }
        player?.currentItem?.audioTimePitchAlgorithm = .varispeed
        player?.rate = playbackSpeed
        isPlaying = true
        updateNowPlayingInfo()
    }

    private func stopPlayback() {
        cleanupObservers()
        player?.pause()
        player = nil
        isPlaying = false
        currentFilePath = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.currentItem?.audioTimePitchAlgorithm = .varispeed
        if isPlaying {
            player?.rate = speed
        }
        updateNowPlayingInfo()
    }

    private func seekTo(seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        player?.seek(to: time) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func getState() -> [String: Any] {
        let position = player?.currentTime().seconds ?? 0
        let duration = player?.currentItem?.duration.seconds ?? 0
        return [
            "isPlaying": isPlaying,
            "position": position.isNaN ? 0.0 : position,
            "duration": duration.isNaN ? 0.0 : duration,
            "speed": Double(playbackSpeed),
        ]
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle ?? "Unknown"
        info[MPMediaItemPropertyArtist] = currentArtist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = currentAlbum ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? NSNumber(value: playbackSpeed) : NSNumber(value: 0)
        let position = player?.currentTime().seconds ?? 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.isNaN ? 0 : position
        let duration = player?.currentItem?.duration.seconds ?? 0
        info[MPMediaItemPropertyPlaybackDuration] = duration.isNaN ? 0 : duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func cleanupObservers() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
    }
}
