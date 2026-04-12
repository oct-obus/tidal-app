import 'package:flutter/material.dart';
import '../managers/library_manager.dart';
import '../utils/formatters.dart';

void showSongInfoSheet(
    BuildContext context, ThemeData theme, Map<String, dynamic> song) {
  final meta = song['meta'] as Map<String, dynamic>?;
  final fileName = song['fileName'] as String;
  final displayTitle = LibraryManager.displayName(fileName);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: meta == null
            ? ListView(
                controller: scrollController,
                children: [
                  Text('Song Info', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Icon(Icons.info_outline,
                      size: 48,
                      color:
                          theme.colorScheme.outline.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text(displayTitle,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text('No metadata available',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                      'Re-downloading this song will capture full metadata.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      textAlign: TextAlign.center),
                ],
              )
            : ListView(
                controller: scrollController,
                children: _buildInfoContent(theme, meta),
              ),
      ),
    ),
  );
}

List<Widget> _buildInfoContent(ThemeData theme, Map<String, dynamic> meta) {
  final source = meta['source'] as String?;
  final isTidal = source == null || source == 'tidal';

  final widgets = <Widget>[
    Text('Song Info', style: theme.textTheme.titleMedium),
    const Divider(),
    _infoRow(theme, 'Title', meta['title']),
    _infoRow(theme, 'Artist', meta['artist']),
    _infoRow(theme, 'Album', meta['album']),
  ];

  if (!isTidal) {
    widgets.add(_sourceRow(theme, source!));
    if (meta['sourceUrl'] != null) {
      _addInfoRow(widgets, theme, 'Source URL', meta['sourceUrl']);
    }
  }

  widgets.addAll([
    const SizedBox(height: 12),
    Text('Quality', style: theme.textTheme.titleSmall),
    const Divider(),
  ]);

  if (isTidal) {
    widgets.addAll([
      _infoRow(theme, 'Requested', meta['requestedQuality']),
      _infoRow(theme, 'Served', meta['servedQuality']),
      _infoRow(theme, 'Codec', meta['codec']),
      _infoRow(theme, 'Bit Depth',
          meta['bitDepth'] != null ? '${meta['bitDepth']}-bit' : null),
      _infoRow(theme, 'Sample Rate', formatSampleRate(meta['sampleRate'])),
      _infoRow(theme, 'Audio Mode', meta['audioMode']),
    ]);
  } else {
    widgets.addAll([
      _infoRow(theme, 'Quality', meta['servedQuality']),
      _infoRow(theme, 'Codec', meta['codec']),
    ]);
  }

  widgets.addAll([
    const SizedBox(height: 12),
    Text('File', style: theme.textTheme.titleSmall),
    const Divider(),
    _infoRow(theme, 'Size', formatFileSize(meta['fileSize'])),
    _infoRow(theme, 'Duration', formatTrackDuration(meta['duration'])),
    _infoRow(theme, 'Extension', meta['fileExtension']),
    _infoRow(theme, 'Downloaded', formatDownloadDate(meta['downloadDate'])),
  ]);

  return widgets;
}

Widget _sourceRow(ThemeData theme, String source) {
  final Color badgeColor;
  final IconData icon;
  final String label;

  switch (source) {
    case 'youtube':
      badgeColor = const Color(0xFFFF0000);
      icon = Icons.play_arrow;
      label = 'YouTube';
    case 'soundcloud':
      badgeColor = const Color(0xFFFF5500);
      icon = Icons.cloud;
      label = 'SoundCloud';
    default:
      badgeColor = theme.colorScheme.primary;
      icon = Icons.music_note;
      label = source;
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text('Source',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        Icon(icon, size: 16, color: badgeColor),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}

void _addInfoRow(List<Widget> list, ThemeData theme, String label, dynamic value) {
  list.add(_infoRow(theme, label, value));
}

Widget _infoRow(ThemeData theme, String label, dynamic value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(
          child: Text(value?.toString() ?? '-',
              style: theme.textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
