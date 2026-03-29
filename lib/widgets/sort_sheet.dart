import 'package:flutter/material.dart';
import '../managers/settings_manager.dart';
import '../managers/playback_manager.dart';

void showSortGroupSheet(
  BuildContext context,
  ThemeData theme,
  SettingsManager settings,
  PlaybackManager playback,
  VoidCallback onChanged,
) {
  const sortLabels = {
    SortField.downloadDate: 'Date Downloaded',
    SortField.title: 'Title',
    SortField.artist: 'Artist',
    SortField.fileSize: 'File Size',
    SortField.duration: 'Duration',
  };
  const groupLabels = {
    GroupBy.none: 'None',
    GroupBy.downloadDate: 'Date Downloaded',
    GroupBy.artist: 'Artist',
  };

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Row(
              children: [
                Text('Library View', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setSheetState(() {
                      settings.sortField = SortField.downloadDate;
                      settings.sortAscending = false;
                      settings.groupBy = GroupBy.none;
                      settings.displayAttributes = {
                        DisplayAttribute.artist,
                        DisplayAttribute.duration,
                      };
                    });
                    onChanged();
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Sort by', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: SortField.values.map((f) {
                final selected = settings.sortField == f;
                return ChoiceChip(
                  label: Text(sortLabels[f]!),
                  selected: selected,
                  onSelected: (_) {
                    setSheetState(() => settings.sortField = f);
                    onChanged();
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Direction', style: theme.textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: true,
                        label: Text(_ascLabel(settings.sortField))),
                    ButtonSegment(
                        value: false,
                        label: Text(_descLabel(settings.sortField))),
                  ],
                  selected: {settings.sortAscending},
                  onSelectionChanged: (v) {
                    setSheetState(() => settings.sortAscending = v.first);
                    onChanged();
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Group by', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: GroupBy.values.map((g) {
                final selected = settings.groupBy == g;
                return ChoiceChip(
                  label: Text(groupLabels[g]!),
                  selected: selected,
                  onSelected: (_) {
                    setSheetState(() => settings.groupBy = g);
                    onChanged();
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('Display', style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text('Shown below each song in the library',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            ...DisplayAttribute.values.map((attr) {
              final enabled = settings.displayAttributes.contains(attr);
              return SwitchListTile(
                title:
                    Text(SettingsManager.displayAttributeLabels[attr]!),
                value: enabled,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setSheetState(() {
                    if (val) {
                      settings.displayAttributes.add(attr);
                    } else {
                      settings.displayAttributes.remove(attr);
                    }
                  });
                  onChanged();
                  settings.saveSettings(
                      currentSpeed: playback.playbackSpeed);
                },
              );
            }),
            if (settings.displayAttributes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Preview: ${_buildSongSubtitlePreview(settings)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

String _ascLabel(SortField field) {
  switch (field) {
    case SortField.title:
    case SortField.artist:
      return 'A-Z';
    case SortField.downloadDate:
      return 'Oldest';
    case SortField.fileSize:
      return 'Smallest';
    case SortField.duration:
      return 'Shortest';
  }
}

String _descLabel(SortField field) {
  switch (field) {
    case SortField.title:
    case SortField.artist:
      return 'Z-A';
    case SortField.downloadDate:
      return 'Newest';
    case SortField.fileSize:
      return 'Largest';
    case SortField.duration:
      return 'Longest';
  }
}

String _buildSongSubtitlePreview(SettingsManager settings) {
  final attrs = settings.displayAttributes;
  final parts = <String>[];
  for (final attr in DisplayAttribute.values) {
    if (!attrs.contains(attr)) continue;
    switch (attr) {
      case DisplayAttribute.artist:
        if (settings.groupBy == GroupBy.artist) continue;
        parts.add('Artist Name');
      case DisplayAttribute.duration:
        parts.add('3:45');
      case DisplayAttribute.fileSize:
        parts.add('8.5 MB');
      case DisplayAttribute.audioQuality:
        parts.add('LOSSLESS');
      case DisplayAttribute.downloadDate:
        parts.add('2 days ago');
      case DisplayAttribute.album:
        parts.add('Album Name');
    }
  }
  return parts.isEmpty ? '(nothing)' : parts.join(' \u00b7 ');
}
