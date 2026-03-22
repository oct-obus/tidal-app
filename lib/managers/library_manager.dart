import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/channels.dart';

class LibraryManager extends ChangeNotifier {
  List<Map<String, dynamic>> library = [];
  bool isDownloading = false;
  String downloadStep = '';
  double downloadProgress = 0;
  String status = '';

  Timer? _progressTimer;
  bool _isDisposed = false;

  void startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(kDownloadPollInterval, (_) async {
      try {
        final response =
            await pythonChannel.invokeMethod<String>('downloadProgress');
        if (response == null || _isDisposed) return;
        final data = jsonDecode(response);
        if (data['success'] == true) {
          final p = data['data'];
          final pct = (p['pct'] as num?)?.toDouble() ?? 0;
          final detail = p['detail'] as String? ?? '';
          downloadProgress = pct / 100.0;
          if (detail.isNotEmpty) downloadStep = detail;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Error in downloadProgressPolling: $e');
      }
    });
  }

  void stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> loadLibrary() async {
    try {
      final response =
          await pythonChannel.invokeMethod<String>('listDownloads');
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        final songs =
            (data['data']['songs'] as List).cast<Map<String, dynamic>>();
        library = songs;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in loadLibrary: $e');
    }
  }

  /// Downloads a track. Returns the result data map on success, null on failure.
  Future<Map<String, dynamic>?> download(String url, String quality) async {
    isDownloading = true;
    downloadStep = 'Starting...';
    downloadProgress = 0;
    notifyListeners();
    startProgressPolling();

    try {
      final response = await pythonChannel
          .invokeMethod<String>('download', {'url': url, 'quality': quality});
      if (response == null) {
        status = 'Download failed: no response';
        notifyListeners();
        return null;
      }
      final data = jsonDecode(response);
      if (data['success'] == true) {
        downloadProgress = 1.0;
        notifyListeners();
        await loadLibrary();
        return data['data'] as Map<String, dynamic>;
      } else {
        status = 'Error: ${data["error"]}';
        notifyListeners();
        return null;
      }
    } on PlatformException catch (e) {
      status = 'Error: ${e.message}';
      notifyListeners();
      return null;
    } on MissingPluginException {
      status = 'Python bridge not available';
      notifyListeners();
      return null;
    } finally {
      stopProgressPolling();
      isDownloading = false;
      downloadStep = '';
      notifyListeners();
    }
  }

  Future<void> deleteSong(String filePath) async {
    try {
      await pythonChannel
          .invokeMethod<String>('deleteDownload', {'filePath': filePath});
      await loadLibrary();
    } catch (e) {
      debugPrint('Error in deleteSong: $e');
    }
  }

  void clearLibrary() {
    library = [];
    notifyListeners();
  }

  static String displayName(String fileName) {
    var name = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final bracketIdx = name.lastIndexOf(' [');
    if (bracketIdx > 0 && name.endsWith(']')) {
      name = name.substring(0, bracketIdx);
    }
    return name;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _progressTimer?.cancel();
    super.dispose();
  }
}
