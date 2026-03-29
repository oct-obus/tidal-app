import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/channels.dart';

class AuthManager extends ChangeNotifier {
  bool isAuthenticated = false;
  bool isAuthenticating = false;
  String? authUserCode;
  String? authVerifyUrl;
  String? authDeviceCode;
  String? pythonVersion;
  String status = 'Initializing...';

  int _authPollInterval = 5;
  DateTime? _lastPollTime;
  Timer? _authPollTimer;

  VoidCallback? onAuthenticated;

  Future<void> initPython() async {
    try {
      final version = await pythonChannel.invokeMethod<String>('pythonVersion');
      pythonVersion = version;

      final authResponse =
          await pythonChannel.invokeMethod<String>('authStatus');
      if (authResponse != null) {
        final data = jsonDecode(authResponse);
        if (data['success'] == true) {
          final authData = data['data'];
          if (authData?['expired'] == true) {
            isAuthenticated = false;
            status = 'Session expired, please log in again';
          } else {
            isAuthenticated = authData?['authenticated'] == true;
            if (authData?['refreshed'] == true) {
              status = 'Session refreshed';
            } else {
              status = isAuthenticated ? 'Ready' : 'Not logged in';
            }
          }
          notifyListeners();
          if (isAuthenticated) onAuthenticated?.call();
        }
      }
    } on MissingPluginException {
      status = 'Python bridge not available';
      notifyListeners();
    } catch (e) {
      status = 'Init error: $e';
      notifyListeners();
    }
  }

  /// Returns true if the URL was successfully opened in a browser.
  Future<bool> openAuthUrl(String url) async {
    final uri = Uri.parse(url);
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      debugPrint('Error in openAuthUrl (inApp): $e');
    }
    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error in openAuthUrl (external): $e');
      }
    }
    return opened;
  }

  Future<void> startAuth() async {
    isAuthenticating = true;
    status = 'Starting authentication...';
    notifyListeners();

    try {
      final response = await pythonChannel.invokeMethod<String>('startAuth');
      if (response == null) {
        isAuthenticating = false;
        status = 'Auth failed: no response';
        notifyListeners();
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] != true) {
        isAuthenticating = false;
        status = 'Auth failed: ${data["error"]}';
        notifyListeners();
        return;
      }

      final authData = data['data'];
      authUserCode = authData['userCode'];
      authVerifyUrl = authData['verificationUriComplete'];
      authDeviceCode = authData['deviceCode'];
      _authPollInterval = (authData['interval'] as int?) ?? 5;
      status = 'Enter code: $authUserCode';
      notifyListeners();

      _lastPollTime = DateTime.now();
      _authPollTimer = Timer.periodic(
        Duration(seconds: _authPollInterval),
        (_) => pollAuth(),
      );
    } catch (e) {
      isAuthenticating = false;
      status = 'Auth error: $e';
      notifyListeners();
    }
  }

  Future<void> pollAuth() async {
    if (authDeviceCode == null) return;
    final now = DateTime.now();
    if (_lastPollTime != null &&
        now.difference(_lastPollTime!).inSeconds < _authPollInterval) {
      return;
    }
    _lastPollTime = now;

    try {
      final response = await pythonChannel.invokeMethod<String>(
          'checkAuth', {'deviceCode': authDeviceCode});
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        _authPollTimer?.cancel();
        isAuthenticated = true;
        isAuthenticating = false;
        authUserCode = null;
        authVerifyUrl = null;
        authDeviceCode = null;
        status = 'Logged in!';
        notifyListeners();
        onAuthenticated?.call();
      } else if (data['error'] != 'pending') {
        _authPollTimer?.cancel();
        isAuthenticating = false;
        status = 'Auth failed: ${data["error"]}';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in pollAuth: $e');
    }
  }

  Future<void> logout() async {
    try {
      await pythonChannel.invokeMethod<String>('logout');
      isAuthenticated = false;
      authUserCode = null;
      authVerifyUrl = null;
      authDeviceCode = null;
      status = 'Logged out';
      notifyListeners();
    } catch (e) {
      status = 'Logout error: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authPollTimer?.cancel();
    super.dispose();
  }
}
