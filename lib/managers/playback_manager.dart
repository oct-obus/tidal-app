import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/channels.dart';

class PlaybackManager extends ChangeNotifier {
  final positionNotifier = ValueNotifier<double>(0);
  final durationNotifier = ValueNotifier<double>(0);

  bool isPlaying = false;
  bool isSeeking = false;
  String? currentFilePath;
  String? trackTitle;
  String? trackArtist;
  String? trackAlbum;
  double playbackSpeed = 1.0;
  String? lastError;

  Timer? _playerStateTimer;
  bool _isDisposed = false;

  void setupAudioCallbacks() {
    audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPlaybackComplete') {
        isPlaying = false;
        notifyListeners();
      } else if (call.method == 'onPlaybackError') {
        final args = call.arguments as Map?;
        final error = args?['error']?.toString() ?? 'Unknown playback error';
        debugPrint('PlaybackManager: Error from AudioBridge: $error');
        stopPlayerStatePolling();
        isPlaying = false;
        if (lastError == null) {
          lastError = error;
        }
        notifyListeners();
      }
    });
  }

  void startPlayerStatePolling() {
    _playerStateTimer?.cancel();
    _playerStateTimer = Timer.periodic(kPlayerPollInterval, (_) async {
      try {
        final state =
            await audioChannel.invokeMapMethod<String, dynamic>('getState');
        if (state != null && !_isDisposed) {
          final newPos = (state['position'] as num?)?.toDouble() ?? 0;
          final newDur = (state['duration'] as num?)?.toDouble() ?? 0;
          final newPlaying = state['isPlaying'] == true;
          final error = state['error'] as String?;

          if (!isSeeking) positionNotifier.value = newPos;
          durationNotifier.value = newDur;

          if (error != null && lastError == null) {
            lastError = error;
            isPlaying = false;
            stopPlayerStatePolling();
            notifyListeners();
            return;
          }

          if (newPlaying != isPlaying) {
            isPlaying = newPlaying;
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('Error in playerStatePolling: $e');
      }
    });
  }

  void stopPlayerStatePolling() {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
  }

  Future<void> playSong(String filePath,
      {String? title, String? artist, String? album}) async {
    lastError = null;
    await audioChannel.invokeMethod('play', {
      'filePath': filePath,
      'speed': playbackSpeed,
      'title': title ?? parseFileName(filePath),
      'artist': artist ?? '',
      'album': album ?? '',
    });
    currentFilePath = filePath;
    trackTitle = title ?? parseFileName(filePath);
    trackArtist = artist;
    trackAlbum = album;
    isPlaying = true;
    notifyListeners();
    startPlayerStatePolling();
  }

  Future<void> togglePlayback() async {
    if (isPlaying) {
      await audioChannel.invokeMethod('pause');
      isPlaying = false;
      notifyListeners();
    } else if (currentFilePath != null) {
      await audioChannel.invokeMethod('resume');
      isPlaying = true;
      notifyListeners();
      startPlayerStatePolling();
    }
  }

  Future<void> setSpeed(double speed, double speedMin, double speedMax) async {
    final clamped = speed.clamp(speedMin, speedMax);
    try {
      await audioChannel.invokeMethod('setSpeed', {'speed': clamped});
      playbackSpeed = clamped;
      notifyListeners();
    } catch (e) {
      debugPrint('Error in setSpeed: $e');
    }
  }

  Future<void> seekTo(double seconds) async {
    try {
      await audioChannel.invokeMethod('seek', {'position': seconds});
    } catch (e) {
      debugPrint('Error in seekTo: $e');
    }
  }

  Future<void> skipForward(double seconds) async {
    final newPos = (positionNotifier.value + seconds)
        .clamp(0.0, durationNotifier.value);
    await seekTo(newPos);
  }

  Future<void> skipBackward(double seconds) async {
    final newPos = (positionNotifier.value - seconds)
        .clamp(0.0, durationNotifier.value);
    await seekTo(newPos);
  }

  Future<void> setSkipIntervals(double seconds) async {
    try {
      await audioChannel.invokeMethod('setSkipIntervals', {'interval': seconds});
    } catch (e) {
      debugPrint('Error in setSkipIntervals: $e');
    }
  }

  Future<void> stop() async {
    try {
      await audioChannel.invokeMethod('stop');
    } catch (e) {
      debugPrint('Error in stop: $e');
    }
    stopPlayerStatePolling();
    isPlaying = false;
    currentFilePath = null;
    trackTitle = null;
    trackArtist = null;
    trackAlbum = null;
    notifyListeners();
  }

  static String parseFileName(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playerStateTimer?.cancel();
    positionNotifier.dispose();
    durationNotifier.dispose();
    super.dispose();
  }
}
