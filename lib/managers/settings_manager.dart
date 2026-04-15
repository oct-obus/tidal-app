import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/channels.dart';

enum SortField { downloadDate, title, artist, fileSize, duration }
enum GroupBy { none, downloadDate, artist }
enum DisplayAttribute { artist, duration, fileSize, audioQuality, downloadDate, album }
enum SkipLayout { split, left, right }

class SettingsManager extends ChangeNotifier {
  String audioQuality = 'LOSSLESS';
  double speedMin = 0.70;
  double speedMax = 1.40;
  double speedStep = 0.05;
  double lastSpeed = 1.0;
  SortField sortField = SortField.downloadDate;
  bool sortAscending = false;
  GroupBy groupBy = GroupBy.none;
  double skipDuration = 10.0;
  SkipLayout skipLayout = SkipLayout.split;
  Set<DisplayAttribute> displayAttributes = {
    DisplayAttribute.artist,
    DisplayAttribute.duration,
  };

  static const displayAttributeLabels = {
    DisplayAttribute.artist: 'Artist',
    DisplayAttribute.duration: 'Duration',
    DisplayAttribute.fileSize: 'File Size',
    DisplayAttribute.audioQuality: 'Audio Quality',
    DisplayAttribute.downloadDate: 'Download Date',
    DisplayAttribute.album: 'Album',
  };

  static const qualityOptions = ['LOW', 'HIGH', 'LOSSLESS', 'HI_RES_LOSSLESS'];
  static const stepOptions = [0.025, 0.05, 0.10, 0.15];
  static const skipDurationOptions = [5.0, 10.0, 15.0, 30.0];

  Future<void> loadSettings() async {
    try {
      final json = await pythonChannel.invokeMethod<String>('loadSettings');
      if (json != null) {
        final data = jsonDecode(json);
        audioQuality = data['audioQuality'] as String? ?? 'LOSSLESS';
        speedMin = (data['speedMin'] as num?)?.toDouble() ?? 0.70;
        speedMax = (data['speedMax'] as num?)?.toDouble() ?? 1.40;
        speedStep = (data['speedStep'] as num?)?.toDouble() ?? 0.05;
        lastSpeed = (data['lastSpeed'] as num?)?.toDouble() ?? 1.0;
        sortField = SortField.values.asNameMap()[data['sortField'] as String? ?? ''] ?? SortField.downloadDate;
        sortAscending = data['sortAscending'] as bool? ?? false;
        groupBy = GroupBy.values.asNameMap()[data['groupBy'] as String? ?? ''] ?? GroupBy.none;
        skipDuration = (data['skipDuration'] as num?)?.toDouble() ?? 10.0;
        skipLayout = SkipLayout.values.asNameMap()[data['skipLayout'] as String? ?? ''] ?? SkipLayout.split;
        final savedAttrs = data['displayAttributes'] as List<dynamic>?;
        if (savedAttrs != null) {
          displayAttributes = savedAttrs
              .map((e) => DisplayAttribute.values.asNameMap()[e as String])
              .whereType<DisplayAttribute>()
              .toSet();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in loadSettings: $e');
    }
  }

  Future<void> saveSettings({required double currentSpeed}) async {
    try {
      final json = jsonEncode({
        'audioQuality': audioQuality,
        'speedMin': speedMin,
        'speedMax': speedMax,
        'speedStep': speedStep,
        'lastSpeed': currentSpeed,
        'sortField': sortField.name,
        'sortAscending': sortAscending,
        'groupBy': groupBy.name,
        'skipDuration': skipDuration,
        'skipLayout': skipLayout.name,
        'displayAttributes': displayAttributes.map((a) => a.name).toList(),
      });
      await pythonChannel.invokeMethod('saveSettings', {'json': json});
    } catch (e) {
      debugPrint('Error in saveSettings: $e');
    }
  }
}
