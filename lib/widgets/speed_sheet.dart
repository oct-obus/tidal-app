import 'package:flutter/material.dart';
import '../managers/playback_manager.dart';
import '../managers/settings_manager.dart';

void showSpeedSheet(
  BuildContext context,
  ThemeData theme,
  PlaybackManager playback,
  SettingsManager settings,
  Future<void> Function(double) onSetSpeed,
) {
  final customController = TextEditingController(
      text: (playback.playbackSpeed * 100).round().toString());

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final presets = <double>[];
          for (var s = settings.speedMin;
              s <= settings.speedMax + 0.001;
              s += settings.speedStep) {
            presets.add(double.parse(s.toStringAsFixed(3)));
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Playback Speed',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${(playback.playbackSpeed * 100).round()}%',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Speed changes pitch (turntable style)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 12),
              Slider(
                value: playback.playbackSpeed
                    .clamp(settings.speedMin, settings.speedMax),
                min: settings.speedMin,
                max: settings.speedMax,
                divisions: ((settings.speedMax - settings.speedMin) /
                        settings.speedStep)
                    .round()
                    .clamp(1, 100),
                label: '${(playback.playbackSpeed * 100).round()}%',
                onChanged: (v) {
                  onSetSpeed(v);
                  setSheetState(() {});
                  customController.text = (v * 100).round().toString();
                },
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: customController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (val) {
                        final pct = double.tryParse(val);
                        if (pct != null) {
                          onSetSpeed(pct / 100);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (presets.length <= 20)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: presets.map((speed) {
                    final isActive =
                        (playback.playbackSpeed - speed).abs() < 0.001;
                    return FilterChip(
                      label: Text('${(speed * 100).round()}%',
                          style: const TextStyle(fontSize: 12)),
                      selected: isActive,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        onSetSpeed(speed);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    ),
  );
}
