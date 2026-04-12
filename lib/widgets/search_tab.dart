import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../managers/search_manager.dart';
import '../managers/library_manager.dart';
import '../utils/formatters.dart';
import 'cover_thumbnail.dart';

class SearchTab extends StatefulWidget {
  final SearchManager search;
  final LibraryManager library;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final void Function(Map<String, dynamic> track) onDownloadTrack;
  final Future<void> Function(String uuid) onOpenPlaylist;
  final Set<int> downloadedIds;
  final VoidCallback onTextChanged;
  final Future<void> Function(String type) onLoadMore;

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
    required this.onLoadMore,
  });

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final Map<String, bool> _collapsed = {
    'tracks': false,
    'albums': false,
    'playlists': false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = widget.search;
    final library = widget.library;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: widget.searchController,
            enabled: !search.isSearching && !library.isDownloading,
            decoration: InputDecoration(
              hintText: 'Search tracks, albums, playlists or paste URL...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        widget.searchController.clear();
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
                              widget.searchController.text = data!.text!;
                            }
                          },
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => widget.onSearch(),
            onChanged: (_) => widget.onTextChanged(),
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
                  Text('Search or paste URL',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline)),
                  Text('Tidal search, or paste YouTube / SoundCloud URL',
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
    final search = widget.search;
    return ListView(
      children: [
        if (search.tracks.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Tracks', 'tracks', search.tracks.length,
              total: search.totalTracks),
          if (!(_collapsed['tracks'] ?? false)) ...[
            ...search.tracks
                .map((track) => _buildSearchTrackTile(theme, track)),
            if (search.hasMoreTracks)
              _buildLoadMoreButton(
                  type: 'tracks', isLoading: search.isLoadingType('tracks')),
          ],
        ],
        if (search.albums.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Albums', 'albums', search.albums.length,
              total: search.totalAlbums),
          if (!(_collapsed['albums'] ?? false)) ...[
            ...search.albums
                .map((album) => _buildSearchAlbumTile(theme, album)),
            if (search.hasMoreAlbums)
              _buildLoadMoreButton(
                  type: 'albums', isLoading: search.isLoadingType('albums')),
          ],
        ],
        if (search.playlists.isNotEmpty) ...[
          _buildSectionHeader(theme, 'Playlists', 'playlists', search.playlists.length,
              total: search.totalPlaylists),
          if (!(_collapsed['playlists'] ?? false)) ...[
            ...search.playlists
                .map((pl) => _buildSearchPlaylistTile(theme, pl)),
            if (search.hasMorePlaylists)
              _buildLoadMoreButton(
                  type: 'playlists',
                  isLoading: search.isLoadingType('playlists')),
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLoadMoreButton({
    required String type,
    required bool isLoading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: () => widget.onLoadMore(type),
                child: Text('Load more $type'),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, String key, int count,
      {int? total}) {
    final isCollapsed = _collapsed[key] ?? false;
    final label = (total != null && total > count)
        ? '$title ($count of $total)'
        : '$title ($count)';
    return InkWell(
      onTap: () => setState(() => _collapsed[key] = !isCollapsed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Icon(
              isCollapsed ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTrackTile(
      ThemeData theme, Map<String, dynamic> track) {
    final title = track['title'] as String? ?? 'Unknown';
    final artist = track['artist'] as String? ?? 'Unknown';
    final duration = track['duration'];
    final trackId = (track['trackId'] as num?)?.toInt() ?? 0;
    final isExplicit = track['explicit'] == true;
    final isDownloaded = widget.downloadedIds.contains(trackId);

    return ListTile(
      leading: CoverThumbnail(coverUrl: track['coverUrl'] as String?),
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
              onPressed: widget.library.isDownloading
                  ? null
                  : () => widget.onDownloadTrack(track),
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
      leading: CoverThumbnail(coverUrl: album['coverUrl'] as String?, fallbackIcon: Icons.album),
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
      leading: CoverThumbnail(coverUrl: pl['coverUrl'] as String?, fallbackIcon: Icons.queue_music),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '$trackCount tracks · ${formatTrackDuration(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final uuid = pl['uuid'] as String? ?? '';
        if (uuid.isNotEmpty) {
          widget.onOpenPlaylist(uuid);
        }
      },
      dense: true,
    );
  }
}
