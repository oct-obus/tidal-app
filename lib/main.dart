import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
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

  final _urlController = TextEditingController();
  final _player = AudioPlayer();

  String _status = 'Initializing...';
  bool _isAuthenticated = false;
  bool _isDownloading = false;
  bool _isAuthenticating = false;
  bool _isPlaying = false;
  String? _downloadedPath;
  String? _trackTitle;
  String? _trackArtist;
  String? _pythonVersion;

  // Auth flow state
  String? _authUserCode;
  String? _authVerifyUrl;
  String? _authDeviceCode;
  Timer? _authPollTimer;
  int _authPollInterval = 5;
  DateTime? _lastPollTime;

  @override
  void initState() {
    super.initState();
    _initPython();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _player.dispose();
    _authPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPython() async {
    try {
      // Get Python version
      final version = await _channel.invokeMethod<String>('pythonVersion');
      setState(() => _pythonVersion = version);

      // Check auth status
      final authResponse = await _channel.invokeMethod<String>('authStatus');
      if (authResponse != null) {
        final data = jsonDecode(authResponse);
        if (data['success'] == true) {
          setState(() {
            _isAuthenticated = data['data']?['authenticated'] == true;
            _status = _isAuthenticated ? 'Ready' : 'Not logged in';
          });
        }
      }
    } on MissingPluginException {
      setState(() => _status = 'Python bridge not available');
    } catch (e) {
      setState(() => _status = 'Init error: $e');
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
        setState(() => _status = 'Auth failed: no response');
        return;
      }

      final data = jsonDecode(response);
      if (data['success'] != true) {
        setState(() => _status = 'Auth failed: ${data['error']}');
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

      // Open in-app browser (SFSafariViewController on iOS)
      final uri = Uri.parse(_authVerifyUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      // Start polling for token with proper interval
      _lastPollTime = DateTime.now();
      _authPollTimer = Timer.periodic(
        Duration(seconds: _authPollInterval),
        (_) => _pollAuth(),
      );
    } catch (e) {
      setState(() => _status = 'Auth error: $e');
    }
  }

  Future<void> _pollAuth() async {
    if (_authDeviceCode == null) return;

    // Rate limit: skip if less than interval since last poll
    final now = DateTime.now();
    if (_lastPollTime != null &&
        now.difference(_lastPollTime!).inSeconds < _authPollInterval) {
      return;
    }
    _lastPollTime = now;

    try {
      final response = await _channel.invokeMethod<String>(
        'checkAuth',
        {'deviceCode': _authDeviceCode},
      );
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
      } else if (data['error'] != 'pending') {
        _authPollTimer?.cancel();
        setState(() {
          _isAuthenticating = false;
          _status = 'Auth failed: ${data['error']}';
        });
      }
    } catch (e) {
      // Keep polling
    }
  }

  Future<void> _download() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _status = 'Downloading...';
      _downloadedPath = null;
      _trackTitle = null;
      _trackArtist = null;
    });

    try {
      final response = await _channel.invokeMethod<String>('download', {'url': url});
      if (response == null) {
        setState(() => _status = 'Download failed: no response');
        return;
      }

      final data = jsonDecode(response);
      if (data['success'] == true) {
        final dl = data['data'];
        setState(() {
          _status = 'Downloaded: ${dl['title']}';
          _downloadedPath = dl['filePath'];
          _trackTitle = dl['title'];
          _trackArtist = dl['artist'];
        });
      } else {
        setState(() => _status = 'Error: ${data['error']}');
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    } on MissingPluginException {
      setState(() => _status = 'Python bridge not available');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_downloadedPath == null) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.setFilePath(_downloadedPath!);
      await _player.play();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Downloader'),
        centerTitle: true,
        actions: [
          if (_isAuthenticated)
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () {},
              tooltip: 'Authenticated',
            )
          else
            IconButton(
              icon: const Icon(Icons.login),
              onPressed: _isAuthenticating ? null : _startAuth,
              tooltip: 'Log in to Tidal',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Auth card (shown when not authenticated)
            if (!_isAuthenticated) ...[
              Card(
                color: theme.colorScheme.errorContainer.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.lock_outline, color: theme.colorScheme.error),
                      const SizedBox(height: 8),
                      Text(
                        _authUserCode != null
                            ? 'Open the link and enter this code:'
                            : 'Log in to Tidal to download music',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (_authUserCode != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          _authUserCode!,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_authVerifyUrl != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  final uri = Uri.parse(_authVerifyUrl!);
                                  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                                },
                                icon: const Icon(Icons.open_in_browser, size: 16),
                                label: const Text('Open login page'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                tooltip: 'Copy link',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _authVerifyUrl!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Link copied!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        const CircularProgressIndicator(strokeWidth: 2),
                        const SizedBox(height: 4),
                        Text('Waiting for authorization...',
                            style: theme.textTheme.bodySmall),
                      ] else ...[
                        const SizedBox(height: 12),
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
            ],
            // URL input
            TextField(
              controller: _urlController,
              enabled: _isAuthenticated,
              decoration: InputDecoration(
                labelText: 'Tidal URL',
                hintText: 'https://tidal.com/browse/track/...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: _isAuthenticated
                      ? () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _urlController.text = data!.text!;
                          }
                        }
                      : null,
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_isDownloading || !_isAuthenticated) ? null : _download,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isDownloading ? 'Downloading...' : 'Download'),
            ),
            const SizedBox(height: 24),
            // Status / Player card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _downloadedPath != null
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: _downloadedPath != null
                              ? Colors.green
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _status,
                                style: theme.textTheme.bodyLarge,
                              ),
                              if (_trackArtist != null && _trackTitle != null)
                                Text(
                                  '$_trackArtist — $_trackTitle',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_downloadedPath != null) ...[
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _togglePlayback,
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        label: Text(_isPlaying ? 'Pause' : 'Play'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Powered by tiddl + embedded CPython${_pythonVersion != null ? ' $_pythonVersion' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
