import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _channel = MethodChannel('com.obus.tidal_app/python');
  static const _audioChannel = MethodChannel('com.obus.tidal_app/audio');

  final _urlController = TextEditingController();

  // Player position/duration as ValueNotifiers for efficient rebuilds
  final _positionNotifier = ValueNotifier<double>(0);
  final _durationNotifier = ValueNotifier<double>(0);

  String _status = 'Initializing...';
  bool _isAuthenticated = false;
  bool _isDownloading = false;
  bool _isAuthenticating = false;
  bool _isPlaying = false;
  String? _currentFilePath;
  String? _trackTitle;
  String? _trackArtist;
  String? _trackAlbum;
  String? _pythonVersion;
  String _downloadStep = '';
  double _downloadProgress = 0;
  double _playbackSpeed = 1.0;
  List<Map<String, dynamic>> _library = [];

  // Settings (persisted)
  String _audioQuality = 'LOSSLESS';
  double _speedMin = 0.70;
  double _speedMax = 1.40;
  double _speedStep = 0.05;

  String? _authUserCode;
  String? _authVerifyUrl;
  String? _authDeviceCode;
  Timer? _authPollTimer;
  Timer? _progressTimer;
  Timer? _playerStateTimer;
  int _authPollInterval = 5;
  DateTime? _lastPollTime;

  static const _qualityOptions = ['LOW', 'HIGH', 'LOSSLESS', 'HI_RES_LOSSLESS'];
  static const _stepOptions = [0.025, 0.05, 0.10, 0.15];

  @override
  void initState() {
    super.initState();
    _setupAudioCallbacks();
    _loadSettings();
    _initPython();
  }

  void _setupAudioCallbacks() {
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPlaybackComplete') {
        setState(() => _isPlaying = false);
      }
    });
  }

  void _startPlayerStatePolling() {
    _playerStateTimer?.cancel();
    _playerStateTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final state =
            await _audioChannel.invokeMapMethod<String, dynamic>('getState');
        if (state != null && mounted) {
          final newPos = (state['position'] as num?)?.toDouble() ?? 0;
          final newDur = (state['duration'] as num?)?.toDouble() ?? 0;
          final newPlaying = state['isPlaying'] == true;

          // Update ValueNotifiers (only triggers slider rebuild)
          _positionNotifier.value = newPos;
          _durationNotifier.value = newDur;

          // Only setState if play state changed (avoids full tree rebuild)
          if (newPlaying != _isPlaying) {
            setState(() => _isPlaying = newPlaying);
          }
        }
      } catch (_) {}
    });
  }

  void _stopPlayerStatePolling() {
    _playerStateTimer?.cancel();
    _playerStateTimer = null;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _authPollTimer?.cancel();
    _progressTimer?.cancel();
    _playerStateTimer?.cancel();
    super.dispose();
  }

  // --- Settings persistence ---

  Future<void> _loadSettings() async {
    try {
      final json = await _channel.invokeMethod<String>('loadSettings');
      if (json != null) {
        final data = jsonDecode(json);
        setState(() {
          _audioQuality = data['audioQuality'] as String? ?? 'LOSSLESS';
          _speedMin = (data['speedMin'] as num?)?.toDouble() ?? 0.70;
          _speedMax = (data['speedMax'] as num?)?.toDouble() ?? 1.40;
          _speedStep = (data['speedStep'] as num?)?.toDouble() ?? 0.05;
          _playbackSpeed = (data['lastSpeed'] as num?)?.toDouble() ?? 1.0;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final json = jsonEncode({
        'audioQuality': _audioQuality,
        'speedMin': _speedMin,
        'speedMax': _speedMax,
        'speedStep': _speedStep,
        'lastSpeed': _playbackSpeed,
      });
      await _channel.invokeMethod('saveSettings', {'json': json});
    } catch (_) {}
  }

  // --- Init ---

  Future<void> _initPython() async {
    try {
      final version = await _channel.invokeMethod<String>('pythonVersion');
      setState(() => _pythonVersion = version);

      final authResponse = await _channel.invokeMethod<String>('authStatus');
      if (authResponse != null) {
        final data = jsonDecode(authResponse);
        if (data['success'] == true) {
          setState(() {
            _isAuthenticated = data['data']?['authenticated'] == true;
            _status = _isAuthenticated ? 'Ready' : 'Not logged in';
          });
          if (_isAuthenticated) _loadLibrary();
        }
      }
    } on MissingPluginException {
      setState(() => _status = 'Python bridge not available');
    } catch (e) {
      setState(() => _status = 'Init error: $e');
    }
  }

  // --- Auth ---

  Future<void> _openAuthUrl(String url) async {
    final uri = Uri.parse(url);
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not open browser. Link copied to clipboard.')),
      );
    }
  }

  Future<void> _startAuth() async {
    setState(() {
      _isAuthenticating = true;
      _status = 'Starting authentication...';
    });

    try {
      final response = await _channel.invokeMethod<String>('startAuth');
      if (response == null) {
        setState(() {
          _isAuthenticating = false;
          _status = 'Auth failed: no response';
        });
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] != true) {
        setState(() {
          _isAuthenticating = false;
          _status = 'Auth failed: ${data["error"]}';
        });
        return;
      }

      final authData = data['data'];
      setState(() {
        _authUserCode = authData['userCode'];
        _authVerifyUrl = authData['verificationUriComplete'];
        _authDeviceCode = authData['deviceCode'];
        _authPollInterval = (authData['interval'] as int?) ?? 5;
        _status = 'Enter code: $_authUserCode';
      });

      if (_authVerifyUrl != null) await _openAuthUrl(_authVerifyUrl!);

      _lastPollTime = DateTime.now();
      _authPollTimer = Timer.periodic(
        Duration(seconds: _authPollInterval),
        (_) => _pollAuth(),
      );
    } catch (e) {
      setState(() {
        _isAuthenticating = false;
        _status = 'Auth error: $e';
      });
    }
  }

  Future<void> _pollAuth() async {
    if (_authDeviceCode == null) return;
    final now = DateTime.now();
    if (_lastPollTime != null &&
        now.difference(_lastPollTime!).inSeconds < _authPollInterval) {
      return;
    }
    _lastPollTime = now;

    try {
      final response = await _channel.invokeMethod<String>(
          'checkAuth', {'deviceCode': _authDeviceCode});
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        _authPollTimer?.cancel();
        setState(() {
          _isAuthenticated = true;
          _isAuthenticating = false;
          _authUserCode = null;
          _authVerifyUrl = null;
          _authDeviceCode = null;
          _status = 'Logged in!';
        });
        _loadLibrary();
      } else if (data['error'] != 'pending') {
        _authPollTimer?.cancel();
        setState(() {
          _isAuthenticating = false;
          _status = 'Auth failed: ${data["error"]}';
        });
      }
    } catch (_) {}
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

    try {
      await _channel.invokeMethod<String>('logout');
      await _audioChannel.invokeMethod('stop');
      _stopPlayerStatePolling();
      setState(() {
        _isAuthenticated = false;
        _isPlaying = false;
        _currentFilePath = null;
        _trackTitle = null;
        _trackArtist = null;
        _trackAlbum = null;
        _library = [];
        _status = 'Logged out';
      });
    } catch (e) {
      setState(() => _status = 'Logout error: $e');
    }
  }

  // --- Download ---

  void _startProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final response =
            await _channel.invokeMethod<String>('downloadProgress');
        if (response == null) return;
        final data = jsonDecode(response);
        if (data['success'] == true) {
          final p = data['data'];
          final pct = (p['pct'] as num?)?.toDouble() ?? 0;
          final detail = p['detail'] as String? ?? '';
          setState(() {
            _downloadProgress = pct / 100.0;
            if (detail.isNotEmpty) _downloadStep = detail;
          });
        }
      } catch (_) {}
    });
  }

  void _stopProgressPolling() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _download() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadStep = 'Starting...';
      _downloadProgress = 0;
    });
    _startProgressPolling();

    try {
      final response = await _channel.invokeMethod<String>(
          'download', {'url': url, 'quality': _audioQuality});
      if (response == null) {
        setState(() => _status = 'Download failed: no response');
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] == true) {
        final dl = data['data'];
        setState(() {
          _downloadProgress = 1.0;
          _status = 'Downloaded: ${dl["title"]}';
          _trackTitle = dl['title'];
          _trackArtist = dl['artist'];
          _trackAlbum = dl['album'];
        });
        _urlController.clear();
        _loadLibrary();
      } else {
        setState(() => _status = 'Error: ${data["error"]}');
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    } on MissingPluginException {
      setState(() => _status = 'Python bridge not available');
    } finally {
      _stopProgressPolling();
      setState(() {
        _isDownloading = false;
        _downloadStep = '';
      });
    }
  }

  // --- Audio Playback (native AVPlayer with varispeed) ---

  Future<void> _playSong(String filePath,
      {String? title, String? artist, String? album}) async {
    try {
      await _audioChannel.invokeMethod('play', {
        'filePath': filePath,
        'speed': _playbackSpeed,
        'title': title ?? _parseFileName(filePath),
        'artist': artist ?? '',
        'album': album ?? '',
      });
      setState(() {
        _currentFilePath = filePath;
        _trackTitle = title ?? _parseFileName(filePath);
        _trackArtist = artist;
        _trackAlbum = album;
        _isPlaying = true;
      });
      _startPlayerStatePolling();
    } catch (e) {
      setState(() => _status = 'Playback error: $e');
    }
  }

  String _parseFileName(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioChannel.invokeMethod('pause');
      setState(() => _isPlaying = false);
    } else if (_currentFilePath != null) {
      await _audioChannel.invokeMethod('resume');
      setState(() => _isPlaying = true);
      _startPlayerStatePolling();
    }
  }

  Future<void> _setSpeed(double speed) async {
    final clamped = speed.clamp(_speedMin, _speedMax);
    try {
      await _audioChannel.invokeMethod('setSpeed', {'speed': clamped});
      setState(() => _playbackSpeed = clamped);
      _saveSettings();
    } catch (_) {}
  }

  Future<void> _seekTo(double seconds) async {
    try {
      await _audioChannel.invokeMethod('seek', {'position': seconds});
    } catch (_) {}
  }

  // --- Library ---

  Future<void> _loadLibrary() async {
    try {
      final response = await _channel.invokeMethod<String>('listDownloads');
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        final songs =
            (data['data']['songs'] as List).cast<Map<String, dynamic>>();
        setState(() => _library = songs);
      }
    } catch (_) {}
  }

  Future<void> _deleteSong(String filePath) async {
    try {
      await _channel
          .invokeMethod<String>('deleteDownload', {'filePath': filePath});
      if (_currentFilePath == filePath) {
        await _audioChannel.invokeMethod('stop');
        _stopPlayerStatePolling();
        setState(() {
          _isPlaying = false;
          _currentFilePath = null;
        });
      }
      _loadLibrary();
    } catch (_) {}
  }

  // --- Helpers ---

  String _formatDuration(double seconds) {
    if (seconds <= 0 || seconds.isInfinite || seconds.isNaN) return '0:00';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // Strip track ID from display name: "Artist - Title [12345]" → "Artist - Title"
  String _displayName(String fileName) {
    var name =
        fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
    final bracketIdx = name.lastIndexOf(' [');
    if (bracketIdx > 0 && name.endsWith(']')) {
      name = name.substring(0, bracketIdx);
    }
    return name;
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Downloader'),
        centerTitle: true,
        actions: [
          if (_isAuthenticated) ...[
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
                onPressed: _isAuthenticating ? null : _startAuth,
                tooltip: 'Log in'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isAuthenticated
                ? _buildMainContent(theme)
                : _buildAuthContent(theme),
          ),
          if (_currentFilePath != null) _buildNowPlayingBar(theme),
        ],
      ),
    );
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
                    _authUserCode != null
                        ? 'Enter this code on Tidal:'
                        : 'Log in to Tidal to get started',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (_authUserCode != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(_authUserCode!,
                        style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 12),
                    if (_authVerifyUrl != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => _openAuthUrl(_authVerifyUrl!),
                            icon: const Icon(Icons.open_in_browser, size: 16),
                            label: const Text('Open login page'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _authVerifyUrl!));
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
                      onPressed: _isAuthenticating ? null : _startAuth,
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
            'Powered by tiddl + CPython${_pythonVersion != null ? " $_pythonVersion" : ""}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme) {
    return Column(
      children: [
        // URL input
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !_isDownloading,
                  decoration: InputDecoration(
                    labelText: 'Tidal URL',
                    hintText: 'https://tidal.com/browse/track/...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste, size: 20),
                      onPressed: _isDownloading
                          ? null
                          : () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                _urlController.text = data!.text!;
                              }
                            },
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _download(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    (_isDownloading || _urlController.text.trim().isEmpty)
                        ? null
                        : _download,
                child: _isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
              ),
            ],
          ),
        ),
        // Download progress
        if (_isDownloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                LinearProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null),
                const SizedBox(height: 4),
                Text(_downloadStep,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Library
        Expanded(
          child: _library.isEmpty
              ? Center(
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
                      Text('Paste a Tidal URL above to download',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _library.length,
                  itemBuilder: (ctx, i) {
                    final song = _library[i];
                    final filePath = song['filePath'] as String;
                    final fileName = song['fileName'] as String;
                    final sizeMB = song['sizeMB'] as num;
                    final isActive = _currentFilePath == filePath;
                    final name = _displayName(fileName);

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
                          context: ctx,
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
                          isActive && _isPlaying
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
                        subtitle: Text('${sizeMB.toStringAsFixed(1)} MB'),
                        onTap: () => _playSong(filePath, title: name),
                        dense: true,
                      ),
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
            // Seek slider — uses ValueListenableBuilder for efficient updates
            ValueListenableBuilder<double>(
              valueListenable: _durationNotifier,
              builder: (_, dur, __) => ValueListenableBuilder<double>(
                valueListenable: _positionNotifier,
                builder: (_, pos, __) => SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 2,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: dur > 0 ? pos.clamp(0, dur) : 0,
                    max: dur > 0 ? dur : 1,
                    onChanged: dur > 0 ? (v) => _seekTo(v) : null,
                  ),
                ),
              ),
            ),
            // Time indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<double>(
                valueListenable: _durationNotifier,
                builder: (_, dur, __) => ValueListenableBuilder<double>(
                  valueListenable: _positionNotifier,
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
            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_trackTitle ?? 'Unknown',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (_trackArtist != null && _trackArtist!.isNotEmpty)
                          Text(_trackArtist!,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                        _isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 40),
                    onPressed: _togglePlayback,
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
                      child: Text('${(_playbackSpeed * 100).round()}%',
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

  // --- Speed Sheet ---

  void _showSpeedSheet(ThemeData theme) {
    final customController = TextEditingController(
        text: (_playbackSpeed * 100).round().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Generate preset chips from range and step
            final presets = <double>[];
            for (var s = _speedMin; s <= _speedMax + 0.001; s += _speedStep) {
              presets.add(double.parse(s.toStringAsFixed(3)));
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Playback Speed', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${(_playbackSpeed * 100).round()}%',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Speed changes pitch (turntable style)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 12),
                Slider(
                  value: _playbackSpeed.clamp(_speedMin, _speedMax),
                  min: _speedMin,
                  max: _speedMax,
                  divisions:
                      ((_speedMax - _speedMin) / _speedStep).round().clamp(1, 100),
                  label: '${(_playbackSpeed * 100).round()}%',
                  onChanged: (v) {
                    _setSpeed(v);
                    setSheetState(() {});
                    customController.text = (v * 100).round().toString();
                  },
                ),
                const SizedBox(height: 4),
                // Custom speed input
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
                // Preset chips
                if (presets.length <= 20)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: presets.map((speed) {
                      final isActive = (_playbackSpeed - speed).abs() < 0.001;
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

  // --- Settings Sheet ---

  void _showSettingsSheet(ThemeData theme) {
    final minCtrl =
        TextEditingController(text: (_speedMin * 100).round().toString());
    final maxCtrl =
        TextEditingController(text: (_speedMax * 100).round().toString());
    final stepCtrl =
        TextEditingController(text: (_speedStep * 100).toStringAsFixed(1));

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

              // Audio quality
              Text('Download Quality', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _qualityOptions.map((q) {
                  final label = {
                    'LOW': 'Low (96)',
                    'HIGH': 'High (320)',
                    'LOSSLESS': 'Lossless',
                    'HI_RES_LOSSLESS': 'Hi-Res',
                  }[q] ?? q;
                  return ChoiceChip(
                    label: Text(label),
                    selected: _audioQuality == q,
                    onSelected: (_) {
                      setState(() => _audioQuality = q);
                      setSheetState(() {});
                      _saveSettings();
                    },
                  );
                }).toList(),
              ),
              const Divider(height: 32),

              // Speed range
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
                        if (val != null && val >= 10 && val < _speedMax * 100) {
                          setState(() => _speedMin = val / 100);
                          _saveSettings();
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('—'),
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
                        if (val != null && val > _speedMin * 100 && val <= 300) {
                          setState(() => _speedMax = val / 100);
                          _saveSettings();
                          setSheetState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Step size
              Text('Speed Step', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._stepOptions.map((step) {
                    return ChoiceChip(
                      label: Text('${(step * 100).toStringAsFixed(1)}%'),
                      selected: (_speedStep - step).abs() < 0.001,
                      onSelected: (_) {
                        setState(() => _speedStep = step);
                        stepCtrl.text = (step * 100).toStringAsFixed(1);
                        _saveSettings();
                        setSheetState(() {});
                      },
                    );
                  }),
                  // Custom step input
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
                          setState(() => _speedStep = val / 100);
                          _saveSettings();
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
              if (_pythonVersion != null) ...[
                const SizedBox(height: 4),
                Text('Python $_pythonVersion',
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
