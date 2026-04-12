import 'package:flutter/material.dart';
import '../managers/settings_manager.dart';
import '../managers/auth_manager.dart';
import '../managers/playback_manager.dart';

void showSettingsSheet(
  BuildContext context,
  ThemeData theme,
  SettingsManager settings,
  AuthManager auth,
  PlaybackManager playback,
  VoidCallback onChanged,
) {
  final minCtrl = TextEditingController(
      text: (settings.speedMin * 100).round().toString());
  final maxCtrl = TextEditingController(
      text: (settings.speedMax * 100).round().toString());
  final stepCtrl = TextEditingController(
      text: (settings.speedStep * 100).toStringAsFixed(1));

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            Text('Download Quality',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Tidal',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SettingsManager.qualityOptions.map((q) {
                final label = {
                      'LOW': 'Low (96)',
                      'HIGH': 'High (320)',
                      'LOSSLESS': 'Lossless',
                      'HI_RES_LOSSLESS': 'Hi-Res',
                    }[q] ??
                    q;
                return ChoiceChip(
                  label: Text(label),
                  selected: settings.audioQuality == q,
                  onSelected: (_) {
                    settings.audioQuality = q;
                    onChanged();
                    setSheetState(() {});
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.play_arrow, size: 14, color: const Color(0xFFFF0000)),
                const SizedBox(width: 4),
                Text('YouTube',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 8),
                Text('Best available audio (AAC ~128kbps)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline.withOpacity(0.7))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.cloud, size: 14, color: const Color(0xFFFF5500)),
                const SizedBox(width: 4),
                Text('SoundCloud',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 8),
                Text('MP3 128kbps',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline.withOpacity(0.7))),
              ],
            ),
            const Divider(height: 32),
            Text('Speed Range', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Min %',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final val = double.tryParse(v);
                      if (val != null &&
                          val >= 10 &&
                          val < settings.speedMax * 100) {
                        settings.speedMin = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
                        setSheetState(() {});
                      }
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('-'),
                ),
                Expanded(
                  child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max %',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final val = double.tryParse(v);
                      if (val != null &&
                          val > settings.speedMin * 100 &&
                          val <= 300) {
                        settings.speedMax = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
                        setSheetState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Speed Step', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...SettingsManager.stepOptions.map((step) {
                  return ChoiceChip(
                    label:
                        Text('${(step * 100).toStringAsFixed(1)}%'),
                    selected:
                        (settings.speedStep - step).abs() < 0.001,
                    onSelected: (_) {
                      settings.speedStep = step;
                      stepCtrl.text =
                          (step * 100).toStringAsFixed(1);
                      onChanged();
                      settings.saveSettings(
                          currentSpeed: playback.playbackSpeed);
                      setSheetState(() {});
                    },
                  );
                }),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: stepCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom',
                      suffixText: '%',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0 && val <= 50) {
                        settings.speedStep = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
                        setSheetState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Tidal quality affects new Tidal downloads only. '
              'Hi-Res requires Tidal HiFi Plus. '
              'YouTube & SoundCloud use best available quality.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (auth.pythonVersion != null) ...[
              const SizedBox(height: 4),
              Text('Python ${auth.pythonVersion}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
