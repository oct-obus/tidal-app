import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/channels.dart';

class PlaylistManager extends ChangeNotifier {
  List<Map<String, dynamic>> savedPlaylists = [];
  Map<String, dynamic>? currentPlaylist;
  bool isLoading = false;
  String? error;

  Future<void> fetchPlaylist(String url) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final response = await pythonChannel
          .invokeMethod<String>('getPlaylistInfo', {'url': url});
      if (response == null) {
        error = 'No response from bridge';
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] == true) {
        currentPlaylist = data['data'] as Map<String, dynamic>;
        error = null;
      } else {
        error = data['error'] as String? ?? 'Unknown error';
      }
    } catch (e) {
      debugPrint('Error in fetchPlaylist: $e');
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSavedPlaylists() async {
    try {
      final response =
          await pythonChannel.invokeMethod<String>('listPlaylists');
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        savedPlaylists = (data['data']['playlists'] as List)
            .cast<Map<String, dynamic>>();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in loadSavedPlaylists: $e');
    }
  }

  Future<void> savePlaylist(Map<String, dynamic> playlist) async {
    try {
      final jsonStr = jsonEncode(playlist);
      final response = await pythonChannel
          .invokeMethod<String>('savePlaylist', {'json': jsonStr});
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        await loadSavedPlaylists();
      }
    } catch (e) {
      debugPrint('Error in savePlaylist: $e');
    }
  }

  Future<void> removePlaylist(String uuid) async {
    try {
      final response = await pythonChannel
          .invokeMethod<String>('removePlaylist', {'uuid': uuid});
      if (response == null) return;
      final data = jsonDecode(response);
      if (data['success'] == true) {
        await loadSavedPlaylists();
        if (currentPlaylist?['uuid'] == uuid) {
          currentPlaylist = null;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error in removePlaylist: $e');
    }
  }

  Future<void> refreshPlaylist(String uuid) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      // Fetch fresh data using playlist/<uuid> format
      final response = await pythonChannel
          .invokeMethod<String>('getPlaylistInfo', {'url': 'playlist/$uuid'});
      if (response == null) {
        error = 'No response from bridge';
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] == true) {
        final refreshed = data['data'] as Map<String, dynamic>;
        currentPlaylist = refreshed;
        // Update saved copy if it exists
        if (isSaved(uuid)) {
          await savePlaylist(refreshed);
        }
        error = null;
      } else {
        error = data['error'] as String? ?? 'Unknown error';
      }
    } catch (e) {
      debugPrint('Error in refreshPlaylist: $e');
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  bool isSaved(String uuid) {
    return savedPlaylists.any((p) => p['uuid'] == uuid);
  }

  void clearCurrent() {
    currentPlaylist = null;
    error = null;
    notifyListeners();
  }
}
