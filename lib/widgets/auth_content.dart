import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../managers/auth_manager.dart';

class AuthContent extends StatelessWidget {
  final AuthManager auth;
  final Future<void> Function(String url) onOpenAuthUrl;
  final VoidCallback onStartAuth;

  const AuthContent({
    super.key,
    required this.auth,
    required this.onOpenAuthUrl,
    required this.onStartAuth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    auth.authUserCode != null
                        ? 'Enter this code on Tidal:'
                        : 'Log in to Tidal to get started',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (auth.authUserCode != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(auth.authUserCode!,
                        style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold, letterSpacing: 4)),
                    const SizedBox(height: 12),
                    if (auth.authVerifyUrl != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                onOpenAuthUrl(auth.authVerifyUrl!),
                            icon: const Icon(Icons.open_in_browser, size: 16),
                            label: const Text('Open login page'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: auth.authVerifyUrl!));
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
                      onPressed: auth.isAuthenticating ? null : onStartAuth,
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
            'Powered by tiddl + CPython${auth.pythonVersion != null ? " ${auth.pythonVersion}" : ""}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
