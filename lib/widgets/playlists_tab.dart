import 'package:flutter/material.dart';
import '../managers/playlist_manager.dart';
import '../managers/library_manager.dart';
import '../utils/formatters.dart';

class PlaylistsTab extends StatelessWidget {
  final PlaylistManager playlist;
  final void Function(Map<String, dynamic> pl) onViewDetail;

  const PlaylistsTab({
    super.key,
    required this.playlist,
    required this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (playlist.savedPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music,
                size: 64,
                color: theme.colorScheme.outline.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('No playlists saved',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.outline)),
            Text('Search for playlists in the Search tab',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: playlist.savedPlaylists.length,
      itemBuilder: (ctx, i) {
        final pl = playlist.savedPlaylists[i];
        final title = pl['title'] as String? ?? 'Untitled';
        final trackCount = pl['numberOfTracks'] as int? ?? 0;
        final totalDuration = pl['duration'] as int? ?? 0;

        return Dismissible(
          key: Key(pl['uuid'] as String),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) async {
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (c) => AlertDialog(
                title: const Text('Remove playlist?'),
                content: Text('Remove "$title" from saved playlists?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove')),
                ],
              ),
            );
            if (confirmed != true) return false;
            await playlist.removePlaylist(pl['uuid'] as String);
            if (playlist.error != null) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(playlist.error!)),
                );
              }
              return false;
            }
            return true;
          },
          child: ListTile(
            leading: const Icon(Icons.queue_music),
            title:
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '$trackCount tracks · ${formatTrackDuration(totalDuration)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onViewDetail(pl),
            dense: true,
          ),
        );
      },
    );
  }
}

class PlaylistDetailView extends StatelessWidget {
  final PlaylistManager playlist;
  final LibraryManager library;
  final Set<int> downloadedIds;
  final void Function(Map<String, dynamic> track) onDownloadTrack;
  final VoidCallback onBack;

  const PlaylistDetailView({
    super.key,
    required this.playlist,
    required this.library,
    required this.downloadedIds,
    required this.onDownloadTrack,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pl = playlist.currentPlaylist;
    if (pl == null) {
      return Center(
        child: playlist.isLoading
            ? const CircularProgressIndicator()
            : Text(playlist.error ?? 'No playlist loaded',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.error)),
      );
    }

    final title = pl['title'] as String? ?? 'Untitled';
    final trackCount = pl['numberOfTracks'] as int? ?? 0;
    final totalDuration = pl['duration'] as int? ?? 0;
    final description = pl['description'] as String?;
    final tracks = (pl['tracks'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final uuid = pl['uuid'] as String;
    final isSaved = playlist.isSaved(uuid);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                        '$trackCount tracks · ${formatTrackDuration(totalDuration)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              IconButton(
                icon: playlist.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed: playlist.isLoading
                    ? null
                    : () => playlist.refreshPlaylist(uuid),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon:
                    Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  if (isSaved) {
                    await playlist.removePlaylist(uuid);
                  } else {
                    await playlist.savePlaylist(pl);
                  }
                },
                tooltip: isSaved ? 'Remove from saved' : 'Save playlist',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        if (playlist.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(playlist.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        const Divider(height: 1),
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Text('No tracks',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline)))
              : ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (ctx, i) {
                    final track = tracks[i];
                    final trackTitle =
                        track['title'] as String? ?? 'Unknown';
                    final artist =
                        track['artist'] as String? ?? 'Unknown';
                    final duration = track['duration'];
                    final trackId =
                        (track['trackId'] as num?)?.toInt() ?? 0;
                    final isExplicit = track['explicit'] == true;
                    final isDownloaded = downloadedIds.contains(trackId);

                    return ListTile(
                      leading: SizedBox(
                        width: 28,
                        child: Center(
                          child: Text('${i + 1}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(trackTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isExplicit)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.explicit,
                                  size: 16,
                                  color: theme.colorScheme.outline),
                            ),
                        ],
                      ),
                      subtitle: Text(
                          '$artist · ${formatTrackDuration(duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: isDownloaded
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary, size: 22)
                          : IconButton(
                              icon:
                                  const Icon(Icons.download, size: 22),
                              onPressed: library.isDownloading
                                  ? null
                                  : () => onDownloadTrack(track),
                              tooltip: 'Download',
                              visualDensity: VisualDensity.compact,
                            ),
                      dense: true,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
