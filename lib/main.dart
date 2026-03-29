import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'managers/auth_manager.dart';
import 'managers/playback_manager.dart';
import 'managers/library_manager.dart';
import 'managers/settings_manager.dart';
import 'managers/search_manager.dart';
import 'managers/playlist_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TidalApp());
}

class TidalApp extends StatelessWidget {
  const TidalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tidal Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00FFFF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _auth = AuthManager();
  final _playback = PlaybackManager();
  final _library = LibraryManager();
  final _settings = SettingsManager();
  final _playlist = PlaylistManager();
  final _search = SearchManager();
  final _searchController = TextEditingController();

  int _tabIndex = 0;
  bool _viewingPlaylistDetail = false;

  @override
  void initState() {
    super.initState();
    _auth.onAuthenticated = () {
      _library.loadLibrary();
      _playlist.loadSavedPlaylists();
    };
    _auth.addListener(_onManagerChanged);
    _playback.addListener(_onManagerChanged);
    _library.addListener(_onManagerChanged);
    _settings.addListener(_onManagerChanged);
    _playlist.addListener(_onManagerChanged);
    _search.addListener(_onManagerChanged);
    _playback.setupAudioCallbacks();
    _init();
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _settings.loadSettings();
    _playback.playbackSpeed = _settings.lastSpeed;
    await _auth.initPython();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _auth.removeListener(_onManagerChanged);
    _playback.removeListener(_onManagerChanged);
    _library.removeListener(_onManagerChanged);
    _settings.removeListener(_onManagerChanged);
    _playlist.removeListener(_onManagerChanged);
    _search.removeListener(_onManagerChanged);
    _auth.dispose();
    _playback.dispose();
    _library.dispose();
    _settings.dispose();
    _playlist.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _handleOpenAuthUrl(String url) async {
    final opened = await _auth.openAuthUrl(url);
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open browser. Link copied to clipboard.')),
      );
    }
  }

  Future<void> _startAuth() async {
    await _auth.startAuth();
    if (_auth.authVerifyUrl != null) {
      await _handleOpenAuthUrl(_auth.authVerifyUrl!);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content:
            const Text('This will clear your Tidal credentials. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;

    await _auth.logout();
    await _playback.stop();
    _library.clearLibrary();
  }

  bool _isPlaylistUrl(String url) {
    return url.contains('/playlist/') || url.startsWith('playlist/');
  }

  bool _isDirectUrl(String input) {
    return input.contains('tidal.com') ||
        input.startsWith('track/') ||
        input.startsWith('playlist/');
  }

  Future<void> _handleSearchSubmit() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) return;

    if (_isDirectUrl(input)) {
      if (_isPlaylistUrl(input)) {
        await _playlist.fetchPlaylist(input);
        if (_playlist.currentPlaylist != null) {
          _searchController.clear();
          _tabIndex = 2;
          _viewingPlaylistDetail = true;
          setState(() {});
        }
      } else {
        // Direct track URL — download it
        final result = await _library.download(input, _settings.audioQuality);
        if (result != null) {
          _playback.trackTitle = result['title'] as String?;
          _playback.trackArtist = result['artist'] as String?;
          _playback.trackAlbum = result['album'] as String?;
          _searchController.clear();
        }
      }
    } else {
      await _search.search(input);
    }
  }

  Future<void> _downloadTrackFromPlaylist(Map<String, dynamic> track) async {
    final trackId = track['trackId'];
    final result = await _library.download(
        'track/$trackId', _settings.audioQuality);
    if (result != null) {
      _playback.trackTitle = result['title'] as String?;
      _playback.trackArtist = result['artist'] as String?;
      _playback.trackAlbum = result['album'] as String?;
    }
  }

  Future<void> _playSong(String filePath,
      {String? title, String? artist, String? album}) async {
    try {
      await _playback.playSong(filePath,
          title: title, artist: artist, album: album);
    } catch (e) {
      debugPrint('Error in playSong: $e');
    }
  }

  Future<void> _setSpeed(double speed) async {
    await _playback.setSpeed(speed, _settings.speedMin, _settings.speedMax);
    _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
  }

  Future<void> _deleteSong(String filePath) async {
    if (_playback.currentFilePath == filePath) {
      await _playback.stop();
    }
    await _library.deleteSong(filePath);
  }

  String _formatDuration(double seconds) {
    if (seconds <= 0 || seconds.isInfinite || seconds.isNaN) return '0:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = (seconds % 60).toInt();
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatTrackDuration(dynamic seconds) {
    if (seconds == null) return '-';
    final total = (seconds as num).toInt();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Set<int> _getDownloadedTrackIds() {
    final ids = <int>{};
    for (final song in _library.library) {
      final meta = song['meta'] as Map<String, dynamic>?;
      if (meta != null && meta['trackId'] != null) {
        ids.add((meta['trackId'] as num).toInt());
      }
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Downloader'),
        centerTitle: true,
        actions: [
          if (_auth.isAuthenticated) ...[
            if (_tabIndex == 0 && _library.library.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: () => _showSortGroupSheet(theme),
                tooltip: 'Sort & Group',
              ),
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showSettingsSheet(theme),
                tooltip: 'Settings'),
            IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
                tooltip: 'Log out'),
          ] else
            IconButton(
                icon: const Icon(Icons.login),
                onPressed: _auth.isAuthenticating ? null : _startAuth,
                tooltip: 'Log in'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _auth.isAuthenticated
                ? _buildAuthenticatedContent(theme)
                : _buildAuthContent(theme),
          ),
          if (_playback.currentFilePath != null) _buildNowPlayingBar(theme),
        ],
      ),
      bottomNavigationBar: _auth.isAuthenticated
          ? NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (i) {
                setState(() {
                  _tabIndex = i;
                  if (i != 2) _viewingPlaylistDetail = false;
                });
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.library_music), label: 'Library'),
                NavigationDestination(
                    icon: Icon(Icons.search), label: 'Search'),
                NavigationDestination(
                    icon: Icon(Icons.queue_music), label: 'Playlists'),
              ],
            )
          : null,
    );
  }

  Widget _buildAuthenticatedContent(ThemeData theme) {
    return Column(
      children: [
        if (_library.isDownloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                LinearProgressIndicator(
                    value: _library.downloadProgress > 0
                        ? _library.downloadProgress
                        : null),
                const SizedBox(height: 4),
                Text(_library.downloadStep,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        Expanded(
          child: _tabIndex == 0
              ? _buildLibraryTab(theme)
              : _tabIndex == 1
                  ? _buildSearchTab(theme)
                  : _viewingPlaylistDetail
                      ? _buildPlaylistDetailView(theme)
                      : _buildPlaylistsTab(theme),
        ),
      ],
    );
  }

  Widget _buildSearchTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            enabled: !_search.isSearching && !_library.isDownloading,
            decoration: InputDecoration(
              hintText: 'Search tracks, albums, playlists or paste URL...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _search.clear();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 20),
                    onPressed: (_search.isSearching || _library.isDownloading)
                        ? null
                        : () async {
                            final data =
                                await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              _searchController.text = data!.text!;
                            }
                          },
                  ),
                ],
              ),
            ),
            onSubmitted: (_) => _handleSearchSubmit(),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        if (_search.isSearching)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          )
        else if (_search.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_search.error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
          )
        else if (_search.hasResults)
          Expanded(child: _buildSearchResults(theme))
        else if (_search.lastQuery.isNotEmpty)
          Expanded(
            child: Center(
              child: Text('No results for "${_search.lastQuery}"',
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
    final downloadedIds = _getDownloadedTrackIds();
    return ListView(
      children: [
        if (_search.tracks.isNotEmpty) ...[
          _buildSectionHeader(
              theme, 'Tracks', _search.tracks.length,
              total: _search.totalTracks),
          ..._search.tracks.map(
              (track) => _buildSearchTrackTile(theme, track, downloadedIds)),
        ],
        if (_search.albums.isNotEmpty) ...[
          _buildSectionHeader(
              theme, 'Albums', _search.albums.length,
              total: _search.totalAlbums),
          ..._search.albums
              .map((album) => _buildSearchAlbumTile(theme, album)),
        ],
        if (_search.playlists.isNotEmpty) ...[
          _buildSectionHeader(
              theme, 'Playlists', _search.playlists.length,
              total: _search.totalPlaylists),
          ..._search.playlists
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

  Widget _buildSearchTrackTile(ThemeData theme, Map<String, dynamic> track,
      Set<int> downloadedIds) {
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
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (isExplicit)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.explicit,
                  size: 16, color: theme.colorScheme.outline),
            ),
        ],
      ),
      subtitle: Text('$artist · ${_formatTrackDuration(duration)}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isDownloaded
          ? Icon(Icons.check_circle,
              color: theme.colorScheme.primary, size: 22)
          : IconButton(
              icon: const Icon(Icons.download, size: 22),
              onPressed: _library.isDownloading
                  ? null
                  : () => _downloadTrackFromSearch(track),
              tooltip: 'Download',
              visualDensity: VisualDensity.compact,
            ),
      dense: true,
    );
  }

  Widget _buildSearchAlbumTile(ThemeData theme, Map<String, dynamic> album) {
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
          '$trackCount tracks · ${_formatTrackDuration(duration)}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final uuid = pl['uuid'] as String? ?? '';
        if (uuid.isNotEmpty) {
          await _playlist.fetchPlaylist('playlist/$uuid');
          if (_playlist.currentPlaylist != null) {
            _tabIndex = 2;
            _viewingPlaylistDetail = true;
            setState(() {});
          }
        }
      },
      dense: true,
    );
  }

  Future<void> _downloadTrackFromSearch(Map<String, dynamic> track) async {
    final trackId = track['trackId'];
    final result = await _library.download(
        'track/$trackId', _settings.audioQuality);
    if (result != null) {
      _playback.trackTitle = result['title'] as String?;
      _playback.trackArtist = result['artist'] as String?;
      _playback.trackAlbum = result['album'] as String?;
    }
  }

  Widget _buildAuthContent(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card(
            color: theme.colorScheme.errorContainer.withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(Icons.lock_outline,
                      color: theme.colorScheme.error, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _auth.authUserCode != null
                        ? 'Enter this code on Tidal:'
                        : 'Log in to Tidal to get started',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (_auth.authUserCode != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(_auth.authUserCode!,
                        style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 12),
                    if (_auth.authVerifyUrl != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _handleOpenAuthUrl(_auth.authVerifyUrl!),
                            icon: const Icon(Icons.open_in_browser, size: 16),
                            label: const Text('Open login page'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _auth.authVerifyUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Link copied!')));
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy link'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(strokeWidth: 2),
                    const SizedBox(height: 4),
                    Text('Waiting for authorization...',
                        style: theme.textTheme.bodySmall),
                  ] else ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _auth.isAuthenticating ? null : _startAuth,
                      icon: const Icon(Icons.login),
                      label: const Text('Log in to Tidal'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Powered by tiddl + CPython${_auth.pythonVersion != null ? " ${_auth.pythonVersion}" : ""}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab(ThemeData theme) {
    if (_library.library.isEmpty) {
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

    final groups = _library.groupedLibrary(
      _settings.sortField,
      _settings.sortAscending,
      _settings.groupBy,
    );
    final showHeaders = _settings.groupBy != GroupBy.none;

    return ListView.builder(
      itemCount: groups.fold<int>(0, (sum, g) => sum + g.songs.length + (showHeaders ? 1 : 0)),
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
            return _buildSongTile(theme, group.songs[index - cursor]);
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

  Widget _buildSongTile(ThemeData theme, Map<String, dynamic> song) {
    final filePath = song['filePath'] as String;
    final fileName = song['fileName'] as String;
    final meta = song['meta'] as Map<String, dynamic>?;
    final sizeMB = song['sizeMB'] as num;
    final isActive = _playback.currentFilePath == filePath;
    final name = meta?['title'] as String? ?? LibraryManager.displayName(fileName);

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
      onDismissed: (_) => _deleteSong(filePath),
      child: ListTile(
        leading: Icon(
          isActive && _playback.isPlaying
              ? Icons.equalizer
              : Icons.music_note,
          color: isActive ? theme.colorScheme.primary : null,
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
              onPressed: () => _playSong(filePath, title: name),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 22),
              tooltip: 'Song info',
              onPressed: () => _showSongInfoSheet(theme, song),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: () => _playSong(filePath, title: name),
        dense: true,
      ),
    );
  }

  Widget _buildPlaylistsTab(ThemeData theme) {
    if (_playlist.savedPlaylists.isEmpty) {
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
      itemCount: _playlist.savedPlaylists.length,
      itemBuilder: (ctx, i) {
        final pl = _playlist.savedPlaylists[i];
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
            await _playlist.removePlaylist(pl['uuid'] as String);
            if (_playlist.error != null) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(_playlist.error!)),
                );
              }
              return false;
            }
            return true;
          },
          child: ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '$trackCount tracks · ${_formatTrackDuration(totalDuration)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _playlist.currentPlaylist = Map<String, dynamic>.from(pl);
              _viewingPlaylistDetail = true;
              _playlist.notifyListeners();
              setState(() {});
            },
            dense: true,
          ),
        );
      },
    );
  }

  Widget _buildPlaylistDetailView(ThemeData theme) {
    final pl = _playlist.currentPlaylist;
    if (pl == null) {
      return Center(
        child: _playlist.isLoading
            ? const CircularProgressIndicator()
            : Text(_playlist.error ?? 'No playlist loaded',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.error)),
      );
    }

    final title = pl['title'] as String? ?? 'Untitled';
    final trackCount = pl['numberOfTracks'] as int? ?? 0;
    final totalDuration = pl['duration'] as int? ?? 0;
    final description = pl['description'] as String?;
    final tracks =
        (pl['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final uuid = pl['uuid'] as String;
    final isSaved = _playlist.isSaved(uuid);
    final downloadedIds = _getDownloadedTrackIds();

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _viewingPlaylistDetail = false;
                    _playlist.clearCurrent();
                  });
                },
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
                        '$trackCount tracks · ${_formatTrackDuration(totalDuration)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              IconButton(
                icon: _playlist.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed:
                    _playlist.isLoading ? null : () => _playlist.refreshPlaylist(uuid),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  if (isSaved) {
                    await _playlist.removePlaylist(uuid);
                  } else {
                    await _playlist.savePlaylist(pl);
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
        if (_playlist.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(_playlist.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        const Divider(height: 1),
        // Track list
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
                    final trackId = (track['trackId'] as num?)?.toInt() ?? 0;
                    final isExplicit = track['explicit'] == true;
                    final isDownloaded = downloadedIds.contains(trackId);

                    return ListTile(
                      leading: SizedBox(
                        width: 28,
                        child: Center(
                          child: Text('${i + 1}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
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
                          '$artist · ${_formatTrackDuration(duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: isDownloaded
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary, size: 22)
                          : IconButton(
                              icon: const Icon(Icons.download, size: 22),
                              onPressed: _library.isDownloading
                                  ? null
                                  : () => _downloadTrackFromPlaylist(track),
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

  Widget _buildNowPlayingBar(ThemeData theme) {
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
              valueListenable: _playback.durationNotifier,
              builder: (_, dur, __) => ValueListenableBuilder<double>(
                valueListenable: _playback.positionNotifier,
                builder: (_, pos, __) => SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: dur > 0 ? pos.clamp(0, dur) : 0,
                    max: dur > 0 ? dur : 1,
                    onChangeStart: dur > 0
                        ? (_) => _playback.isSeeking = true
                        : null,
                    onChanged: dur > 0
                        ? (v) => _playback.positionNotifier.value = v
                        : null,
                    onChangeEnd: dur > 0
                        ? (v) {
                            _playback.seekTo(v);
                            _playback.isSeeking = false;
                          }
                        : null,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<double>(
                valueListenable: _playback.durationNotifier,
                builder: (_, dur, __) => ValueListenableBuilder<double>(
                  valueListenable: _playback.positionNotifier,
                  builder: (_, pos, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(pos),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                      Text(_formatDuration(dur),
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
                        Text(_playback.trackTitle ?? 'Unknown',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (_playback.trackArtist != null &&
                            _playback.trackArtist!.isNotEmpty)
                          Text(_playback.trackArtist!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                        _playback.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 40),
                    onPressed: _playback.togglePlayback,
                  ),
                  GestureDetector(
                    onTap: () => _showSpeedSheet(theme),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                          '${(_playback.playbackSpeed * 100).round()}%',
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

  String _buildSongSubtitle(Map<String, dynamic>? meta, num sizeMB) {
    final attrs = _settings.displayAttributes;
    if (attrs.isEmpty) return '';

    final parts = <String>[];
    for (final attr in DisplayAttribute.values) {
      if (!attrs.contains(attr)) continue;
      switch (attr) {
        case DisplayAttribute.artist:
          if (_settings.groupBy == GroupBy.artist) continue;
          final v = meta?['artist'] as String?;
          if (v != null) parts.add(v);
        case DisplayAttribute.duration:
          final v = meta?['duration'];
          if (v != null) parts.add(_formatMetaDuration(v));
        case DisplayAttribute.fileSize:
          final bytes = meta?['fileSize'];
          if (bytes != null) {
            parts.add(_formatFileSize(bytes));
          } else {
            parts.add('${sizeMB.toStringAsFixed(1)} MB');
          }
        case DisplayAttribute.audioQuality:
          final v = meta?['servedQuality'] as String?;
          if (v != null) parts.add(v);
        case DisplayAttribute.downloadDate:
          final v = meta?['downloadDate'] as String?;
          if (v != null) parts.add(_formatRelativeDate(v));
        case DisplayAttribute.album:
          final v = meta?['album'] as String?;
          if (v != null) parts.add(v);
      }
    }

    if (parts.isEmpty) return '${sizeMB.toStringAsFixed(1)} MB';
    return parts.join(' \u00b7 ');
  }

  String _formatRelativeDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 30) {
        final weeks = diff.inDays ~/ 7;
        return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
      }
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return dateStr;
    }
  }

  String _buildSongSubtitlePreview() {
    final attrs = _settings.displayAttributes;
    final parts = <String>[];
    for (final attr in DisplayAttribute.values) {
      if (!attrs.contains(attr)) continue;
      switch (attr) {
        case DisplayAttribute.artist:
          if (_settings.groupBy == GroupBy.artist) continue;
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

  String _formatMetaDuration(dynamic seconds) {
    if (seconds == null) return '-';
    final s = (seconds as num).toInt();
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(dynamic bytes) {
    if (bytes == null) return '-';
    final mb = (bytes as num) / 1048576;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _formatSampleRate(dynamic rate) {
    if (rate == null) return '-';
    final r = (rate as num).toInt();
    if (r >= 1000) {
      final parts = <String>[];
      var remaining = r;
      while (remaining > 0) {
        final chunk = remaining % 1000;
        remaining ~/= 1000;
        parts.insert(0, remaining > 0 ? chunk.toString().padLeft(3, '0') : chunk.toString());
      }
      return '${parts.join(',')} Hz';
    }
    return '$r Hz';
  }

  String _formatDownloadDate(dynamic dateStr) {
    if (dateStr == null) return '-';
    try {
      final dt = DateTime.parse(dateStr as String);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (e) {
      debugPrint('Error parsing download date: $e');
      return dateStr.toString();
    }
  }

  void _showSortGroupSheet(ThemeData theme) {
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
                  Text('Sort & Group', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        _settings.sortField = SortField.downloadDate;
                        _settings.sortAscending = false;
                        _settings.groupBy = GroupBy.none;
                        _settings.displayAttributes = {
                          DisplayAttribute.artist,
                          DisplayAttribute.duration,
                        };
                      });
                      setState(() {});
                      _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
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
                  final selected = _settings.sortField == f;
                  return ChoiceChip(
                    label: Text(sortLabels[f]!),
                    selected: selected,
                    onSelected: (_) {
                      setSheetState(() => _settings.sortField = f);
                      setState(() {});
                      _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
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
                      ButtonSegment(value: true, label: Text(_ascLabel(_settings.sortField))),
                      ButtonSegment(value: false, label: Text(_descLabel(_settings.sortField))),
                    ],
                    selected: {_settings.sortAscending},
                    onSelectionChanged: (v) {
                      setSheetState(() => _settings.sortAscending = v.first);
                      setState(() {});
                      _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
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
                  final selected = _settings.groupBy == g;
                  return ChoiceChip(
                    label: Text(groupLabels[g]!),
                    selected: selected,
                    onSelected: (_) {
                      setSheetState(() => _settings.groupBy = g);
                      setState(() {});
                      _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Display', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              ...DisplayAttribute.values.map((attr) {
                final enabled = _settings.displayAttributes.contains(attr);
                return SwitchListTile(
                  title: Text(SettingsManager.displayAttributeLabels[attr]!),
                  value: enabled,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setSheetState(() {
                      if (val) {
                        _settings.displayAttributes.add(attr);
                      } else {
                        _settings.displayAttributes.remove(attr);
                      }
                    });
                    setState(() {});
                    _settings.saveSettings(currentSpeed: _playback.playbackSpeed);
                  },
                );
              }),
              if (_settings.displayAttributes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Preview: ${_buildSongSubtitlePreview()}',
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

  void _showSongInfoSheet(ThemeData theme, Map<String, dynamic> song) {
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
                    Icon(Icons.info_outline, size: 48,
                        color: theme.colorScheme.outline.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(displayTitle,
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text('No metadata available',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Re-downloading this song will capture full metadata.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline),
                        textAlign: TextAlign.center),
                  ],
                )
              : ListView(
                  controller: scrollController,
                  children: [
                    Text('Song Info', style: theme.textTheme.titleMedium),
                    const Divider(),
                    _infoRow(theme, 'Title', meta['title']),
                    _infoRow(theme, 'Artist', meta['artist']),
                    _infoRow(theme, 'Album', meta['album']),
                    const SizedBox(height: 12),
                    Text('Quality', style: theme.textTheme.titleSmall),
                    const Divider(),
                    _infoRow(theme, 'Requested', meta['requestedQuality']),
                    _infoRow(theme, 'Served', meta['servedQuality']),
                    _infoRow(theme, 'Codec', meta['codec']),
                    _infoRow(theme, 'Bit Depth',
                        meta['bitDepth'] != null ? '${meta['bitDepth']}-bit' : null),
                    _infoRow(theme, 'Sample Rate', _formatSampleRate(meta['sampleRate'])),
                    _infoRow(theme, 'Audio Mode', meta['audioMode']),
                    const SizedBox(height: 12),
                    Text('File', style: theme.textTheme.titleSmall),
                    const Divider(),
                    _infoRow(theme, 'Size', _formatFileSize(meta['fileSize'])),
                    _infoRow(theme, 'Duration', _formatMetaDuration(meta['duration'])),
                    _infoRow(theme, 'Extension', meta['fileExtension']),
                    _infoRow(theme, 'Downloaded', _formatDownloadDate(meta['downloadDate'])),
                  ],
                ),
        ),
      ),
    );
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

  void _showSpeedSheet(ThemeData theme) {
    final customController = TextEditingController(
        text: (_playback.playbackSpeed * 100).round().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final presets = <double>[];
            for (var s = _settings.speedMin;
                s <= _settings.speedMax + 0.001;
                s += _settings.speedStep) {
              presets.add(double.parse(s.toStringAsFixed(3)));
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Playback Speed', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${(_playback.playbackSpeed * 100).round()}%',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Speed changes pitch (turntable style)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 12),
                Slider(
                  value: _playback.playbackSpeed
                      .clamp(_settings.speedMin, _settings.speedMax),
                  min: _settings.speedMin,
                  max: _settings.speedMax,
                  divisions: ((_settings.speedMax - _settings.speedMin) /
                          _settings.speedStep)
                      .round()
                      .clamp(1, 100),
                  label: '${(_playback.playbackSpeed * 100).round()}%',
                  onChanged: (v) {
                    _setSpeed(v);
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
                            _setSpeed(pct / 100);
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
                          (_playback.playbackSpeed - speed).abs() < 0.001;
                      return FilterChip(
                        label: Text('${(speed * 100).round()}%',
                            style: const TextStyle(fontSize: 12)),
                        selected: isActive,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          _setSpeed(speed);
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

  void _showSettingsSheet(ThemeData theme) {
    final minCtrl = TextEditingController(
        text: (_settings.speedMin * 100).round().toString());
    final maxCtrl = TextEditingController(
        text: (_settings.speedMax * 100).round().toString());
    final stepCtrl = TextEditingController(
        text: (_settings.speedStep * 100).toStringAsFixed(1));

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
              Text('Download Quality', style: theme.textTheme.titleSmall),
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
                    selected: _settings.audioQuality == q,
                    onSelected: (_) {
                      setState(() => _settings.audioQuality = q);
                      setSheetState(() {});
                      _settings.saveSettings(
                          currentSpeed: _playback.playbackSpeed);
                    },
                  );
                }).toList(),
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
                            val < _settings.speedMax * 100) {
                          setState(() => _settings.speedMin = val / 100);
                          _settings.saveSettings(
                              currentSpeed: _playback.playbackSpeed);
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
                            val > _settings.speedMin * 100 &&
                            val <= 300) {
                          setState(() => _settings.speedMax = val / 100);
                          _settings.saveSettings(
                              currentSpeed: _playback.playbackSpeed);
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
                      label: Text('${(step * 100).toStringAsFixed(1)}%'),
                      selected: (_settings.speedStep - step).abs() < 0.001,
                      onSelected: (_) {
                        setState(() => _settings.speedStep = step);
                        stepCtrl.text = (step * 100).toStringAsFixed(1);
                        _settings.saveSettings(
                            currentSpeed: _playback.playbackSpeed);
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
                          setState(() => _settings.speedStep = val / 100);
                          _settings.saveSettings(
                              currentSpeed: _playback.playbackSpeed);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Quality affects new downloads only. '
                'Hi-Res requires Tidal HiFi Plus.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (_auth.pythonVersion != null) ...[
                const SizedBox(height: 4),
                Text('Python ${_auth.pythonVersion}',
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
}
