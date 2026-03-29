import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../managers/search_manager.dart';
import '../managers/library_manager.dart';
import '../utils/formatters.dart';

class SearchTab extends StatelessWidget {
  final SearchManager search;
  final LibraryManager library;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final void Function(Map<String, dynamic> track) onDownloadTrack;
  final Future<void> Function(String uuid) onOpenPlaylist;
  final Set<int> downloadedIds;
  final VoidCallback onTextChanged;

  const SearchTab({
    super.key,
    required this.search,
    required this.library,
    required this.searchController,
    required this.onSearch,
    required this.onDownloadTrack,
    required this.onOpenPlaylist,
    required this.downloadedIds,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: searchController,
            enabled: !search.isSearching && !library.isDownloading,
            decoration: InputDecoration(
              hintText: 'Search tracks, albums, playlists or paste URL...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        searchController.clear();
                        search.clear();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 20),
                    onPressed: (search.isSearching || library.isDownloading)
                        ? null
                        : () async {
                            final data =
                                await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              searchController.text = data!.text!;
                            }
                          },
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => onSearch(),
            onChanged: (_) => onTextChanged(),
          ),
        ),
        const SizedBox(height: 8),
        if (search.isSearching)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          )
        else if (search.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(search.error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
          )
        else if (search.hasResults)
          Expanded(child: _buildSearchResults(theme))
        else if (search.lastQuery.isNotEmpty)
          Expanded(
            child: Center(
              child: Text('No results for "${search.lastQuery}"',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search,
                      size: 64,
                      color: theme.colorScheme.outline.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text('Search Tidal',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline)),
                  Text('Find tracks, albums, and playlists',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    return ListView(
      children: [
        if (search.tracks.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Tracks', search.tracks.length,
              total: search.totalTracks),
          ...search.tracks
              .map((track) => _buildSearchTrackTile(theme, track)),
        ],
        if (search.albums.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Albums', search.albums.length,
              total: search.totalAlbums),
          ...search.albums
              .map((album) => _buildSearchAlbumTile(theme, album)),
        ],
        if (search.playlists.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Playlists', search.playlists.length,
              total: search.totalPlaylists),
          ...search.playlists
              .map((pl) => _buildSearchPlaylistTile(theme, pl)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, int count,
      {int? total}) {
    final label = (total != null && total > count)
        ? '$title (showing $count of $total)'
        : '$title ($count)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  Widget _buildSearchTrackTile(
      ThemeData theme, Map<String, dynamic> track) {
    final title = track['title'] as String? ?? 'Unknown';
    final artist = track['artist'] as String? ?? 'Unknown';
    final duration = track['duration'];
    final trackId = (track['trackId'] as num?)?.toInt() ?? 0;
    final isExplicit = track['explicit'] == true;
    final isDownloaded = downloadedIds.contains(trackId);

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child:
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (isExplicit)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.explicit,
                  size: 16, color: theme.colorScheme.outline),
            ),
        ],
      ),
      subtitle: Text('$artist · ${formatTrackDuration(duration)}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isDownloaded
          ? Icon(Icons.check_circle,
              color: theme.colorScheme.primary, size: 22)
          : IconButton(
              icon: const Icon(Icons.download, size: 22),
              onPressed: library.isDownloading
                  ? null
                  : () => onDownloadTrack(track),
              tooltip: 'Download',
              visualDensity: VisualDensity.compact,
            ),
      dense: true,
    );
  }

  Widget _buildSearchAlbumTile(
      ThemeData theme, Map<String, dynamic> album) {
    final title = album['title'] as String? ?? 'Unknown';
    final artist = album['artist'] as String? ?? 'Unknown';
    final trackCount = album['numberOfTracks'] as int? ?? 0;

    return ListTile(
      leading: const Icon(Icons.album, size: 22),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$artist · $trackCount tracks',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      dense: true,
    );
  }

  Widget _buildSearchPlaylistTile(
      ThemeData theme, Map<String, dynamic> pl) {
    final title = pl['title'] as String? ?? 'Untitled';
    final trackCount = pl['numberOfTracks'] as int? ?? 0;
    final duration = pl['duration'];

    return ListTile(
      leading: const Icon(Icons.queue_music, size: 22),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '$trackCount tracks · ${formatTrackDuration(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final uuid = pl['uuid'] as String? ?? '';
        if (uuid.isNotEmpty) {
          onOpenPlaylist(uuid);
        }
      },
      dense: true,
    );
  }
}
