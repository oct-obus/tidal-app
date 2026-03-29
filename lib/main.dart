import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'managers/auth_manager.dart';
import 'managers/playback_manager.dart';
import 'managers/library_manager.dart';
import 'managers/settings_manager.dart';
import 'managers/search_manager.dart';
import 'managers/playlist_manager.dart';
import 'widgets/auth_content.dart';
import 'widgets/library_tab.dart';
import 'widgets/search_tab.dart';
import 'widgets/playlists_tab.dart';
import 'widgets/now_playing_bar.dart';
import 'widgets/sort_sheet.dart';
import 'widgets/song_info_sheet.dart';
import 'widgets/speed_sheet.dart';
import 'widgets/settings_sheet.dart';

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
        // Direct track URL - download it
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
                onPressed: () => showSortGroupSheet(
                    context, theme, _settings, _playback, () => setState(() {})),
                tooltip: 'Sort & Group',
              ),
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => showSettingsSheet(context, theme, _settings,
                    _auth, _playback, () => setState(() {})),
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
