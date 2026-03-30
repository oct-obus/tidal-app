import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AuthWebView extends StatefulWidget {
  final String url;

  const AuthWebView({super.key, required this.url});

  @override
  State<AuthWebView> createState() => _AuthWebViewState();
}

class _AuthWebViewState extends State<AuthWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tidal Login'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            LinearProgressIndicator(
              color: theme.colorScheme.primary,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }
}
