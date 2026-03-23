import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/channels.dart';

class SearchManager extends ChangeNotifier {
  List<Map<String, dynamic>> tracks = [];
  List<Map<String, dynamic>> albums = [];
  List<Map<String, dynamic>> playlists = [];
  int totalTracks = 0;
  int totalAlbums = 0;
  int totalPlaylists = 0;
  bool isSearching = false;
  String? error;
  String lastQuery = '';

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;

    isSearching = true;
    error = null;
    lastQuery = query;
    notifyListeners();

    try {
      final response = await pythonChannel
          .invokeMethod<String>('searchTidal', {'query': query});
      if (response == null) {
        error = 'No response from bridge';
        return;
      }
      final data = jsonDecode(response);
      if (data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;
        tracks = (result['tracks'] as List).cast<Map<String, dynamic>>();
        albums = (result['albums'] as List).cast<Map<String, dynamic>>();
        playlists = (result['playlists'] as List).cast<Map<String, dynamic>>();
        totalTracks = (result['totalTracks'] as num?)?.toInt() ?? tracks.length;
        totalAlbums = (result['totalAlbums'] as num?)?.toInt() ?? albums.length;
        totalPlaylists = (result['totalPlaylists'] as num?)?.toInt() ?? playlists.length;
        error = null;
      } else {
        error = data['error'] as String? ?? 'Search failed';
      }
    } catch (e) {
      debugPrint('Error in search: $e');
      error = e.toString();
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  void clear() {
    tracks = [];
    albums = [];
    playlists = [];
    totalTracks = 0;
    totalAlbums = 0;
    totalPlaylists = 0;
    error = null;
    lastQuery = '';
    notifyListeners();
  }

  bool get hasResults =>
      tracks.isNotEmpty || albums.isNotEmpty || playlists.isNotEmpty;
}
