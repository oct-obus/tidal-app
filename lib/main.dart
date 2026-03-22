import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'managers/auth_manager.dart';
import 'managers/playback_manager.dart';
import 'managers/library_manager.dart';
import 'managers/settings_manager.dart';

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
  final _urlController = TextEditingController();
  final _auth = AuthManager();
  final _playback = PlaybackManager();
  final _library = LibraryManager();
  final _settings = SettingsManager();

  @override
  void initState() {
    super.initState();
    _auth.onAuthenticated = () => _library.loadLibrary();
    _auth.addListener(_onManagerChanged);
    _playback.addListener(_onManagerChanged);
    _library.addListener(_onManagerChanged);
    _settings.addListener(_onManagerChanged);
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
    _urlController.dispose();
    _auth.removeListener(_onManagerChanged);
    _playback.removeListener(_onManagerChanged);
    _library.removeListener(_onManagerChanged);
    _settings.removeListener(_onManagerChanged);
    _auth.dispose();
    _playback.dispose();
    _library.dispose();
    _settings.dispose();
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

  Future<void> _download() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final result = await _library.download(url, _settings.audioQuality);
    if (result != null) {
      _playback.trackTitle = result['title'] as String?;
      _playback.trackArtist = result['artist'] as String?;
      _playback.trackAlbum = result['album'] as String?;
      _urlController.clear();
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
    final m = seconds ~/ 60;
    final s = (seconds % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
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
                ? _buildMainContent(theme)
                : _buildAuthContent(theme),
          ),
          if (_playback.currentFilePath != null) _buildNowPlayingBar(theme),
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

  Widget _buildMainContent(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !_library.isDownloading,
                  decoration: InputDecoration(
                    labelText: 'Tidal URL',
                    hintText: 'https://tidal.com/browse/track/...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste, size: 20),
                      onPressed: _library.isDownloading
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
                    (_library.isDownloading || _urlController.text.trim().isEmpty)
                        ? null
                        : _download,
                child: _library.isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
              ),
            ],
          ),
        ),
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
        const SizedBox(height: 8),
        Expanded(
          child: _library.library.isEmpty
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
                  itemCount: _library.library.length,
                  itemBuilder: (ctx, i) {
                    final song = _library.library[i];
                    final filePath = song['filePath'] as String;
                    final fileName = song['fileName'] as String;
                    final sizeMB = song['sizeMB'] as num;
                    final isActive = _playback.currentFilePath == filePath;
                    final name = LibraryManager.displayName(fileName);

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
                    onChanged: dur > 0 ? (v) => _playback.seekTo(v) : null,
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
