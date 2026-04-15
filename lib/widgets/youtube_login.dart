import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../managers/library_manager.dart';

/// Full-screen WebView for logging into YouTube.
/// After dismissal, cookies are extracted via WKHTTPCookieStore on the native side.
class YouTubeLoginScreen extends StatefulWidget {
  final LibraryManager libraryManager;

  const YouTubeLoginScreen({super.key, required this.libraryManager});

  @override
  State<YouTubeLoginScreen> createState() => _YouTubeLoginScreenState();
}

class _YouTubeLoginScreenState extends State<YouTubeLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _extracting = false;
  String _currentUrl = 'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fwww.youtube.com';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() {
          _isLoading = true;
          _currentUrl = url;
        }),
        onPageFinished: (url) => setState(() {
          _isLoading = false;
          _currentUrl = url;
        }),
      ))
      ..loadRequest(Uri.parse(_currentUrl));
  }

  bool get _isLoggedIn {
    // After successful Google login, the user ends up on youtube.com
    return _currentUrl.contains('youtube.com') &&
        !_currentUrl.contains('accounts.google.com') &&
        !_currentUrl.contains('ServiceLogin');
  }

  Future<void> _extractAndDismiss() async {
    setState(() => _extracting = true);

    final result = await widget.libraryManager.extractYouTubeCookies();
    if (!mounted) return;

    final count = result?['count'] as int? ?? 0;

    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extracted $count YouTube cookies ✓')),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _extracting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No YouTube cookies found — try logging in first')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube Login'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              color: theme.colorScheme.primary,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _extracting ? null : _extractAndDismiss,
                  icon: _extracting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cookie),
                  label: Text(_extracting
                      ? 'Extracting cookies...'
                      : _isLoggedIn
                          ? 'Save cookies & close'
                          : 'Extract cookies'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
