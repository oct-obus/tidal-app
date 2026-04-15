import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'managers/auth_manager.dart';
import 'managers/playback_manager.dart';
import 'managers/library_manager.dart';
import 'managers/settings_manager.dart';
import 'managers/search_manager.dart';
import 'managers/playlist_manager.dart';
import 'services/channels.dart';
import 'services/link_resolver.dart';
import 'widgets/auth_content.dart';
import 'widgets/library_tab.dart';
import 'widgets/search_tab.dart';
import 'widgets/playlists_tab.dart';
import 'widgets/now_playing_bar.dart';
import 'widgets/sort_sheet.dart';
import 'widgets/song_info_sheet.dart';
import 'widgets/speed_sheet.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/auth_webview.dart';
import 'utils/formatters.dart';

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
    if (mounted) {
      // Show error snackbar if playback failed
      if (_playback.lastError != null) {
        final error = _playback.lastError!;
        _playback.lastError = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Playback error: $error'),
                duration: const Duration(seconds: 5),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        });
      }
      setState(() {});
    }
  }

  Future<void> _init() async {
    await _settings.loadSettings();
    _playback.playbackSpeed = _settings.lastSpeed;
    _playback.setSkipIntervals(_settings.skipDuration);
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
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthWebView(url: url)),
    );
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

  bool _isTidalUrl(String input) {
    return input.contains('tidal.com') ||
        input.startsWith('track/') ||
        input.startsWith('playlist/');
  }

  static final _youtubePattern = RegExp(
    r'(youtube\.com/watch|youtu\.be/|youtube\.com/shorts/|music\.youtube\.com/watch)',
    caseSensitive: false,
  );
  static final _soundcloudPattern = RegExp(
    r'soundcloud\.com/',
    caseSensitive: false,
  );
  static final _spotifyPattern = RegExp(
    r'open\.spotify\.com/track/',
    caseSensitive: false,
  );

  bool _isExternalUrl(String input) {
    return _youtubePattern.hasMatch(input) ||
        _soundcloudPattern.hasMatch(input);
  }

  bool _isSpotifyUrl(String input) {
    return _spotifyPattern.hasMatch(input);
  }

  Future<void> _handleSearchSubmit() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) return;

    if (_isSpotifyUrl(input)) {
      await _handleSpotifyLink(input);
    } else if (_isExternalUrl(input)) {
      // YouTube or SoundCloud URL: fetch info first, show preview
      await _showUrlPreview(input);
    } else if (_isTidalUrl(input)) {
      if (_isPlaylistUrl(input)) {
        await _playlist.fetchPlaylist(input);
        if (_playlist.currentPlaylist != null) {
          _searchController.clear();
          _tabIndex = 2;
          _viewingPlaylistDetail = true;
          setState(() {});
        }
      } else {
        // Direct Tidal track URL - download it
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

  Future<void> _showUrlPreview(String url) async {
    if (!mounted) return;

    // Show loading indicator
    setState(() {
      _library.status = '';
      _search.setSearching(true);
    });

    final info = await _library.getUrlInfo(url);

    if (!mounted) return;
    setState(() => _search.setSearching(false));

    if (info == null) {
      final errorMsg = _library.lastUrlError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg != null
              ? 'Could not fetch info: $errorMsg'
              : 'Could not fetch info for this URL'),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    final isPlaylist = info['type'] == 'playlist';
    final title = info['title'] as String? ?? 'Unknown';
    final artist = isPlaylist
        ? (info['uploader'] as String? ?? 'Unknown')
        : (info['artist'] as String? ?? 'Unknown');
    final source = info['platform'] as String? ?? 'unknown';
    final duration = isPlaylist ? null : info['duration'];
    final coverUrl = info['thumbnailUrl'] as String?;
    final trackCount = isPlaylist ? (info['trackCount'] as num?)?.toInt() : null;

    // Derive quality string from best audio format (highest bitrate)
    String? quality;
    final audioFormats = info['audioFormats'] as List?;
    if (audioFormats != null && audioFormats.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(
          audioFormats.cast<Map<String, dynamic>>());
      sorted.sort((a, b) =>
          ((b['abr'] as num?) ?? 0).compareTo((a['abr'] as num?) ?? 0));
      final best = sorted.first;
      final abr = best['abr'];
      final codec = best['acodec'] as String? ?? '';
      if (abr != null) {
        quality = '${(abr as num).round()}kbps $codec'.trim();
      }
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final Color sourceColor;
        final IconData sourceIcon;
        final String sourceLabel;
        switch (source) {
          case 'youtube':
            sourceColor = const Color(0xFFFF0000);
            sourceIcon = Icons.play_arrow;
            sourceLabel = 'YouTube';
          case 'soundcloud':
            sourceColor = const Color(0xFFFF5500);
            sourceIcon = Icons.cloud;
            sourceLabel = 'SoundCloud';
          default:
            sourceColor = theme.colorScheme.primary;
            sourceIcon = Icons.music_note;
            sourceLabel = source;
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(coverUrl, width: 64, height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.music_note, color: theme.colorScheme.outline),
                          )),
                    )
                  else
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.music_note, color: theme.colorScheme.outline),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(artist, style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(sourceIcon, size: 16, color: sourceColor),
                  const SizedBox(width: 4),
                  Text(sourceLabel, style: theme.textTheme.bodySmall),
                  if (duration != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.schedule, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(formatTrackDuration(duration),
                        style: theme.textTheme.bodySmall),
                  ],
                  if (quality != null) ...[
                    const SizedBox(width: 12),
                    Text(quality, style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ],
              ),
              if (isPlaylist) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.playlist_play, size: 16,
                        color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        trackCount != null
                            ? 'Playlist ($trackCount tracks) — first track will be downloaded'
                            : 'Playlist — first track will be downloaded',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text('Download from $sourceLabel'),
                  onPressed: () => Navigator.pop(ctx, 'download'),
                ),
              ),
              if (!isPlaylist) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Search on Tidal'),
                    onPressed: () => Navigator.pop(ctx, 'search_tidal'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    if (action == 'search_tidal') {
      // Clean up the title for better Tidal search results
      var searchTitle = title;
      if (source == 'youtube') {
        searchTitle = LinkResolver.cleanYouTubeTitle(searchTitle);
      }
      await _searchTidalForTrack(searchTitle, artist);
      return;
    }

    final result = await _library.downloadUrl(url);
    if (result != null) {
      _playback.trackTitle = result['title'] as String?;
      _playback.trackArtist = result['artist'] as String?;
      _playback.trackAlbum = result['album'] as String?;
      _searchController.clear();
    }
  }

  Future<void> _handleSpotifyLink(String url) async {
    if (!mounted) return;

    setState(() {
      _library.status = '';
      _search.setSearching(true);
    });

    final resolved = await LinkResolver.resolveSpotify(url);

    if (!mounted) return;
    setState(() => _search.setSearching(false));

    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not resolve Spotify link')),
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        const spotifyGreen = Color(0xFF1DB954);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (resolved.thumbnailUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        resolved.thumbnailUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.music_note,
                              color: theme.colorScheme.outline),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.music_note,
                          color: theme.colorScheme.outline),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resolved.title,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(resolved.artist,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.music_note, size: 16, color: spotifyGreen),
                  const SizedBox(width: 4),
                  Text('Spotify',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: spotifyGreen)),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward,
                      size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Text('Tidal search',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Search on Tidal'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _searchTidalForTrack(resolved.title, resolved.artist);
  }

  Future<void> _searchTidalForTrack(String title, String artist) async {
    final query = artist != 'Unknown' ? '$artist $title' : title;
    _searchController.text = query;
    await _search.search(query);
    if (mounted) setState(() {});
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

  Future<void> _importAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'm4a', 'mp4', 'wav', 'ogg', 'opus', 'aac', 'wma', 'webm'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      if (paths.isEmpty) return;

      setState(() {
        _library.isDownloading = true;
        _library.downloadStep = 'Importing ${paths.length} file${paths.length > 1 ? 's' : ''}...';
        _library.downloadProgress = 0;
      });

      final response = await pythonChannel.invokeMethod<String>(
          'importFiles', {'filePaths': paths});
      if (response != null) {
        final data = jsonDecode(response);
        if (data['success'] == true) {
          final count = data['data']['importedCount'] as int? ?? 0;
          final errors = (data['data']['errors'] as List?)?.cast<String>() ?? [];
          await _library.loadLibrary();
          if (mounted) {
            if (errors.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Imported $count file${count != 1 ? 's' : ''}')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported $count, ${errors.length} failed:\n${errors.join('\n')}'),
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          }
        } else {
          final error = data['error'] ?? 'Unknown error';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Import failed: $error')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      _library.isDownloading = false;
      _library.downloadStep = '';
      _library.notifyListeners();
    }
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
            if (_tabIndex == 0) ...[
              IconButton(
                icon: const Icon(Icons.file_open),
                onPressed: _library.isDownloading ? null : _importAudioFiles,
                tooltip: 'Import audio files',
              ),
              if (_library.library.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.sort),
                  onPressed: () => showSortGroupSheet(
                      context, theme, _settings, _playback, () => setState(() {})),
                  tooltip: 'Sort & Group',
                ),
            ],
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => showSettingsSheet(context, theme, _settings,
                    _auth, _playback, () => setState(() {}),
                    libraryManager: _library),
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
                : AuthContent(
                    auth: _auth,
                    onOpenAuthUrl: _handleOpenAuthUrl,
                    onStartAuth: _startAuth,
                  ),
          ),
          if (_playback.currentFilePath != null)
            NowPlayingBar(
              playback: _playback,
              settings: _settings,
              onShowSpeedSheet: () => showSpeedSheet(
                  context, theme, _playback, _settings, _setSpeed),
            ),
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
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                          value: _library.downloadProgress > 0
                              ? _library.downloadProgress
                              : null),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _library.cancelDownload,
                        padding: EdgeInsets.zero,
                        tooltip: 'Cancel download',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_library.downloadStep,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        Expanded(
          child: _tabIndex == 0
              ? LibraryTab(
                  library: _library,
                  settings: _settings,
                  playback: _playback,
                  onPlay: _playSong,
                  onDelete: _deleteSong,
                  onShowInfo: (song) =>
                      showSongInfoSheet(context, theme, song),
                )
              : _tabIndex == 1
                  ? SearchTab(
                      search: _search,
                      library: _library,
                      searchController: _searchController,
                      onSearch: _handleSearchSubmit,
                      onDownloadTrack: _downloadTrackFromSearch,
                      onOpenPlaylist: (uuid) async {
                        await _playlist.fetchPlaylist('playlist/$uuid');
                        if (_playlist.currentPlaylist != null) {
                          _tabIndex = 2;
                          _viewingPlaylistDetail = true;
                          setState(() {});
                        }
                      },
                      downloadedIds: _getDownloadedTrackIds(),
                      onTextChanged: () => setState(() {}),
                      onLoadMore: _search.loadMore,
                    )
                  : _viewingPlaylistDetail
                      ? PlaylistDetailView(
                          playlist: _playlist,
                          library: _library,
                          downloadedIds: _getDownloadedTrackIds(),
                          onDownloadTrack: _downloadTrackFromPlaylist,
                          onBack: () => setState(() {
                            _viewingPlaylistDetail = false;
                            _playlist.clearCurrent();
                          }),
                        )
                      : PlaylistsTab(
                          playlist: _playlist,
                          onViewDetail: (pl) {
                            _playlist.currentPlaylist =
                                Map<String, dynamic>.from(pl);
                            _viewingPlaylistDetail = true;
                            _playlist.notifyListeners();
                            setState(() {});
                          },
                        ),
        ),
      ],
    );
  }
}
