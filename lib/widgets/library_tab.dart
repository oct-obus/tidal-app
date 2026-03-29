import 'package:flutter/material.dart';
import '../managers/library_manager.dart';
import '../managers/settings_manager.dart';
import '../managers/playback_manager.dart';
import '../utils/formatters.dart';
import 'cover_thumbnail.dart';

class LibraryTab extends StatelessWidget {
  final LibraryManager library;
  final SettingsManager settings;
  final PlaybackManager playback;
  final void Function(String filePath,
      {String? title, String? artist, String? album}) onPlay;
  final void Function(String filePath) onDelete;
  final void Function(Map<String, dynamic> song) onShowInfo;

  const LibraryTab({
    super.key,
    required this.library,
    required this.settings,
    required this.playback,
    required this.onPlay,
    required this.onDelete,
    required this.onShowInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (library.library.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music,
                size: 64,
                color: theme.colorScheme.outline.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('No songs yet',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.outline)),
            Text('Use the Search tab to find and download music',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    final groups = library.groupedLibrary(
      settings.sortField,
      settings.sortAscending,
      settings.groupBy,
    );
    final showHeaders = settings.groupBy != GroupBy.none;

    return ListView.builder(
      itemCount: groups.fold<int>(
          0, (sum, g) => sum + g.songs.length + (showHeaders ? 1 : 0)),
      itemBuilder: (ctx, index) {
        var cursor = 0;
        for (final group in groups) {
          if (showHeaders) {
            if (index == cursor) {
              return _buildGroupHeader(theme, group.label);
            }
            cursor++;
          }
          if (index < cursor + group.songs.length) {
            return _buildSongTile(ctx, theme, group.songs[index - cursor]);
          }
          cursor += group.songs.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildGroupHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSongTile(
      BuildContext context, ThemeData theme, Map<String, dynamic> song) {
    final filePath = song['filePath'] as String;
    final fileName = song['fileName'] as String;
    final meta = song['meta'] as Map<String, dynamic>?;
    final sizeMB = song['sizeMB'] as num;
    final isActive = playback.currentFilePath == filePath;
    final name =
        meta?['title'] as String? ?? LibraryManager.displayName(fileName);

    final subtitle = _buildSongSubtitle(meta, sizeMB);

    return Dismissible(
      key: Key(filePath),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete song?'),
            content: Text('Delete "$name"?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Delete')),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(filePath),
      child: ListTile(
        leading: CoverThumbnail(
          coverUrl: meta?['coverUrl'] as String?,
          fallbackIcon: isActive && playback.isPlaying ? Icons.equalizer : Icons.music_note,
        ),
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isActive
                ? TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold)
                : null),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 22),
              tooltip: 'Play',
              onPressed: () => onPlay(filePath, title: name),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 22),
              tooltip: 'Song info',
              onPressed: () => onShowInfo(song),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: () => onPlay(filePath, title: name),
        dense: true,
      ),
    );
  }

  String _buildSongSubtitle(Map<String, dynamic>? meta, num sizeMB) {
    final attrs = settings.displayAttributes;
    if (attrs.isEmpty) return '${sizeMB.toStringAsFixed(1)} MB';

    final parts = <String>[];
    for (final attr in DisplayAttribute.values) {
      if (!attrs.contains(attr)) continue;
      switch (attr) {
        case DisplayAttribute.artist:
          if (settings.groupBy == GroupBy.artist) continue;
          final v = meta?['artist'] as String?;
          if (v != null) parts.add(v);
        case DisplayAttribute.duration:
          final v = meta?['duration'];
          if (v != null) parts.add(formatTrackDuration(v));
        case DisplayAttribute.fileSize:
          final bytes = meta?['fileSize'];
          if (bytes != null) {
            parts.add(formatFileSize(bytes));
          } else {
            parts.add('${sizeMB.toStringAsFixed(1)} MB');
          }
        case DisplayAttribute.audioQuality:
          final v = meta?['servedQuality'] as String?;
          if (v != null) parts.add(v);
        case DisplayAttribute.downloadDate:
          final v = meta?['downloadDate'] as String?;
          if (v != null) parts.add(formatRelativeDate(v));
        case DisplayAttribute.album:
          final v = meta?['album'] as String?;
          if (v != null) parts.add(v);
      }
    }

    if (parts.isEmpty) return '${sizeMB.toStringAsFixed(1)} MB';
    return parts.join(' \u00b7 ');
  }
}
