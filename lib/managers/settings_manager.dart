import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/channels.dart';

class SettingsManager extends ChangeNotifier {
  String audioQuality = 'LOSSLESS';
  double speedMin = 0.70;
  double speedMax = 1.40;
  double speedStep = 0.05;
  double lastSpeed = 1.0;

  static const qualityOptions = ['LOW', 'HIGH', 'LOSSLESS', 'HI_RES_LOSSLESS'];
  static const stepOptions = [0.025, 0.05, 0.10, 0.15];

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
      });
      await pythonChannel.invokeMethod('saveSettings', {'json': json});
    } catch (e) {
      debugPrint('Error in saveSettings: $e');
    }
  }
}
