import 'package:flutter/material.dart';
import '../managers/playback_manager.dart';
import '../utils/formatters.dart';

class NowPlayingBar extends StatelessWidget {
  final PlaybackManager playback;
  final VoidCallback onShowSpeedSheet;

  const NowPlayingBar({
    super.key,
    required this.playback,
    required this.onShowSpeedSheet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(blurRadius: 8, color: Colors.black.withOpacity(0.3))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: playback.durationNotifier,
              builder: (_, dur, __) => ValueListenableBuilder<double>(
                valueListenable: playback.positionNotifier,
                builder: (_, pos, __) => SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2,
                    thumbShape:
                        RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: dur > 0 ? pos.clamp(0, dur) : 0,
                    max: dur > 0 ? dur : 1,
                    onChangeStart: dur > 0
                        ? (_) => playback.isSeeking = true
                        : null,
                    onChanged: dur > 0
                        ? (v) => playback.positionNotifier.value = v
                        : null,
                    onChangeEnd: dur > 0
                        ? (v) {
                            playback.seekTo(v);
                            playback.isSeeking = false;
                          }
                        : null,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<double>(
                valueListenable: playback.durationNotifier,
                builder: (_, dur, __) => ValueListenableBuilder<double>(
                  valueListenable: playback.positionNotifier,
                  builder: (_, pos, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(pos),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                      Text(formatDuration(dur),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(playback.trackTitle ?? 'Unknown',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (playback.trackArtist != null &&
                            playback.trackArtist!.isNotEmpty)
                          Text(playback.trackArtist!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 40),
                    onPressed: playback.togglePlayback,
                  ),
                  GestureDetector(
                    onTap: onShowSpeedSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                          '${(playback.playbackSpeed * 100).round()}%',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
