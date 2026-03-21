import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

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

  String _status = 'Ready';
  bool _isDownloading = false;
  bool _isPlaying = false;
  String? _downloadedPath;

  @override
  void dispose() {
    _urlController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _status = 'Downloading...';
      _downloadedPath = null;
    });

    try {
      final result = await _channel.invokeMethod<String>('download', {'url': url});
      setState(() {
        _status = 'Downloaded!';
        _downloadedPath = result;
      });
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    } on MissingPluginException {
      setState(() => _status = 'Python bridge not available (dev mode)');
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Tidal URL',
                hintText: 'https://tidal.com/browse/track/...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _urlController.text = data!.text!;
                    }
                  },
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isDownloading ? null : _download,
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
                          child: Text(
                            _status,
                            style: theme.textTheme.bodyLarge,
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
              'Powered by tiddl + embedded CPython',
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
