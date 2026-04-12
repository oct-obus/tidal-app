import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../managers/settings_manager.dart';
import '../managers/auth_manager.dart';
import '../managers/playback_manager.dart';
import '../managers/library_manager.dart';

void showSettingsSheet(
  BuildContext context,
  ThemeData theme,
  SettingsManager settings,
  AuthManager auth,
  PlaybackManager playback,
  VoidCallback onChanged, {
  LibraryManager? libraryManager,
}) {
  final minCtrl = TextEditingController(
      text: (settings.speedMin * 100).round().toString());
  final maxCtrl = TextEditingController(
      text: (settings.speedMax * 100).round().toString());
  final stepCtrl = TextEditingController(
      text: (settings.speedStep * 100).toStringAsFixed(1));

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
            Text('Download Quality',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Tidal',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
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
                  selected: settings.audioQuality == q,
                  onSelected: (_) {
                    settings.audioQuality = q;
                    onChanged();
                    setSheetState(() {});
                    settings.saveSettings(
                        currentSpeed: playback.playbackSpeed);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.play_arrow, size: 14, color: const Color(0xFFFF0000)),
                const SizedBox(width: 4),
                Text('YouTube',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 8),
                Text('AAC ~128kbps (256kbps with Premium cookies)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline.withOpacity(0.7))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.cloud, size: 14, color: const Color(0xFFFF5500)),
                const SizedBox(width: 4),
                Text('SoundCloud',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 8),
                Text('AAC 160kbps',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline.withOpacity(0.7))),
              ],
            ),
            if (libraryManager != null) ...[
              const SizedBox(height: 16),
              Text('YouTube Premium Cookies',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _CookieSection(
                theme: theme,
                libraryManager: libraryManager,
              ),
              const SizedBox(height: 16),
              Text('YouTube JS Runtime',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _JsRuntimeSection(
                theme: theme,
                libraryManager: libraryManager,
              ),
            ],
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
                          val < settings.speedMax * 100) {
                        settings.speedMin = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
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
                          val > settings.speedMin * 100 &&
                          val <= 300) {
                        settings.speedMax = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
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
                    label:
                        Text('${(step * 100).toStringAsFixed(1)}%'),
                    selected:
                        (settings.speedStep - step).abs() < 0.001,
                    onSelected: (_) {
                      settings.speedStep = step;
                      stepCtrl.text =
                          (step * 100).toStringAsFixed(1);
                      onChanged();
                      settings.saveSettings(
                          currentSpeed: playback.playbackSpeed);
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
                        settings.speedStep = val / 100;
                        onChanged();
                        settings.saveSettings(
                            currentSpeed: playback.playbackSpeed);
                        setSheetState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Tidal quality affects new Tidal downloads only. '
              'Hi-Res requires Tidal HiFi Plus. '
              'YouTube Premium cookies unlock 256kbps AAC.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (auth.pythonVersion != null) ...[
              const SizedBox(height: 4),
              Text('Python ${auth.pythonVersion}',
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

class _CookieSection extends StatefulWidget {
  final ThemeData theme;
  final LibraryManager libraryManager;

  const _CookieSection({
    required this.theme,
    required this.libraryManager,
  });

  @override
  State<_CookieSection> createState() => _CookieSectionState();
}

class _CookieSectionState extends State<_CookieSection> {
  bool _loading = true;
  bool _hasCookies = false;
  String? _modifiedAt;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await widget.libraryManager.getCookiesStatus();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hasCookies = status?['hasCookies'] == true;
      _modifiedAt = status?['modifiedAt'] as String?;
    });
  }

  Future<void> _importCookies() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!mounted) return;

    setState(() => _loading = true);
    final dest = await widget.libraryManager.importCookies(path);
    if (dest != null) {
      await _loadStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('YouTube cookies imported ✓')),
        );
      }
    } else {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to import cookies')),
        );
      }
    }
  }

  Future<void> _clearCookies() async {
    await widget.libraryManager.clearCookies();
    await _loadStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube cookies cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        child: Center(child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }

    if (_hasCookies) {
      String subtitle = 'Cookies loaded';
      if (_modifiedAt != null) {
        try {
          final dt = DateTime.parse(_modifiedAt!);
          final diff = DateTime.now().difference(dt);
          if (diff.inDays > 0) {
            subtitle += ' (${diff.inDays}d ago)';
          } else if (diff.inHours > 0) {
            subtitle += ' (${diff.inHours}h ago)';
          }
        } catch (_) {}
      }
      return Row(
        children: [
          Icon(Icons.check_circle, size: 16,
              color: widget.theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(subtitle,
                style: widget.theme.textTheme.bodySmall
                    ?.copyWith(color: widget.theme.colorScheme.outline)),
          ),
          TextButton(
            onPressed: _importCookies,
            child: const Text('Replace'),
          ),
          TextButton(
            onPressed: _clearCookies,
            style: TextButton.styleFrom(
              foregroundColor: widget.theme.colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Import a cookies.txt file from Firefox to unlock '
          '256kbps AAC on YouTube.',
          style: widget.theme.textTheme.bodySmall
              ?.copyWith(color: widget.theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _importCookies,
          icon: const Icon(Icons.file_upload, size: 18),
          label: const Text('Import cookies.txt'),
        ),
      ],
    );
  }
}

class _JsRuntimeSection extends StatefulWidget {
  final ThemeData theme;
  final LibraryManager libraryManager;

  const _JsRuntimeSection({
    required this.theme,
    required this.libraryManager,
  });

  @override
  State<_JsRuntimeSection> createState() => _JsRuntimeSectionState();
}

class _JsRuntimeSectionState extends State<_JsRuntimeSection> {
  bool _loading = true;
  bool _ctypes = false;
  bool _pluginInstalled = false;
  bool _pluginAvailable = false;
  String? _pluginVersion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final data = await widget.libraryManager.checkJsRuntime();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ctypes = data?['ctypes'] == true;
      _pluginInstalled = data?['pluginInstalled'] == true;
      _pluginAvailable = data?['pluginAvailable'] == true;
      _pluginVersion = data?['pluginVersion'] as String?;
      _error = (data?['pluginError'] ?? data?['ctypesError']) as String?;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        child: Center(child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }

    final allGood = _ctypes && _pluginInstalled && _pluginAvailable;
    final icon = allGood ? Icons.check_circle : Icons.info_outline;
    final color = allGood
        ? widget.theme.colorScheme.primary
        : widget.theme.colorScheme.outline;

    String status;
    if (allGood) {
      status = 'WebKit JSI v$_pluginVersion - anti-throttle active';
    } else if (!_ctypes) {
      status = 'ctypes not available - JS runtime disabled';
    } else if (!_pluginInstalled) {
      status = 'Plugin not installed';
    } else {
      status = _error ?? 'Plugin not available on this platform';
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(status,
              style: widget.theme.textTheme.bodySmall
                  ?.copyWith(color: widget.theme.colorScheme.outline)),
        ),
      ],
    );
  }
}
