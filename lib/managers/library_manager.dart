import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/channels.dart';
import 'settings_manager.dart';

class LibraryGroup {
  final String label;
  final List<Map<String, dynamic>> songs;
  LibraryGroup(this.label, this.songs);
}

class LibraryManager extends ChangeNotifier {
  List<Map<String, dynamic>> library = [];
  bool isDownloading = false;
  String downloadStep = '';
  double downloadProgress = 0;
  String status = '';

  Timer? _progressTimer;
  bool _isDisposed = false;

  List<Map<String, dynamic>> sortedLibrary(SortField field, bool ascending) {
    final sorted = List<Map<String, dynamic>>.from(library);
    sorted.sort((a, b) {
      final cmp = _compareBy(field, a, b);
      return ascending ? cmp : -cmp;
    });
    return sorted;
  }

  List<LibraryGroup> groupedLibrary(SortField sortField, bool ascending, GroupBy groupBy) {
    final sorted = sortedLibrary(sortField, ascending);
    if (groupBy == GroupBy.none) {
      return [LibraryGroup('', sorted)];
    }

    final groups = <String, List<Map<String, dynamic>>>{};
    final groupOrder = <String>[];

    for (final song in sorted) {
      final key = _groupKey(groupBy, song);
      if (!groups.containsKey(key)) {
        groups[key] = [];
        groupOrder.add(key);
      }
      groups[key]!.add(song);
    }

    return groupOrder.map((k) => LibraryGroup(k, groups[k]!)).toList();
  }

  int _compareBy(SortField field, Map<String, dynamic> a, Map<String, dynamic> b) {
    final metaA = a['meta'] as Map<String, dynamic>?;
    final metaB = b['meta'] as Map<String, dynamic>?;

    switch (field) {
      case SortField.downloadDate:
        final da = _parseDate(metaA?['downloadDate']);
        final db = _parseDate(metaB?['downloadDate']);
        return da.compareTo(db);
      case SortField.title:
        final ta = (metaA?['title'] as String?) ?? displayName(a['fileName'] as String);
        final tb = (metaB?['title'] as String?) ?? displayName(b['fileName'] as String);
        return ta.toLowerCase().compareTo(tb.toLowerCase());
      case SortField.artist:
        final aa = (metaA?['artist'] as String?)?.toLowerCase() ?? '\uffff';
        final ab = (metaB?['artist'] as String?)?.toLowerCase() ?? '\uffff';
        return aa.compareTo(ab);
      case SortField.fileSize:
        final sa = (metaA?['fileSize'] as num?) ?? (a['sizeMB'] as num? ?? 0) * 1048576;
        final sb = (metaB?['fileSize'] as num?) ?? (b['sizeMB'] as num? ?? 0) * 1048576;
        return sa.compareTo(sb);
      case SortField.duration:
        final da = (metaA?['duration'] as num?) ?? 0;
        final db = (metaB?['duration'] as num?) ?? 0;
        return da.compareTo(db);
    }
  }

  DateTime _parseDate(dynamic dateStr) {
    if (dateStr == null) return DateTime(1970);
    try {
      return DateTime.parse(dateStr as String);
    } catch (_) {
      return DateTime(1970);
    }
  }

  String _groupKey(GroupBy groupBy, Map<String, dynamic> song) {
    final meta = song['meta'] as Map<String, dynamic>?;
    switch (groupBy) {
      case GroupBy.none:
        return '';
      case GroupBy.artist:
        return (meta?['artist'] as String?) ?? 'Unknown Artist';
      case GroupBy.downloadDate:
        return _dateBucket(_parseDate(meta?['downloadDate']));
    }
  }

  String _dateBucket(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final songDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(songDay).inDays;
    if (dt.year == 1970) return 'Unknown Date';
    if (diff == 0) return 'Today';
    if (diff < 7) return 'This Week';
    if (diff < 30) return 'This Month';
    return 'Older';
  }

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
