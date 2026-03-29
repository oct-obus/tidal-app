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

  int _tracksOffset = 0;
  int _albumsOffset = 0;
  int _playlistsOffset = 0;
  static const int _pageSize = 25;
  bool isLoadingMore = false;

  bool get hasMoreTracks => tracks.length < totalTracks;
  bool get hasMoreAlbums => albums.length < totalAlbums;
  bool get hasMorePlaylists => playlists.length < totalPlaylists;

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
        _tracksOffset = tracks.length;
        _albumsOffset = albums.length;
        _playlistsOffset = playlists.length;
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

  Future<void> loadMore(String type) async {
    if (lastQuery.isEmpty || isLoadingMore) return;

    isLoadingMore = true;
    notifyListeners();

    try {
      int offset;
      if (type == 'tracks') {
        offset = _tracksOffset;
      } else if (type == 'albums') {
        offset = _albumsOffset;
      } else {
        offset = _playlistsOffset;
      }

      final response = await pythonChannel.invokeMethod<String>(
        'searchTidal',
        {'query': lastQuery, 'limit': _pageSize, 'offset': offset},
      );
      if (response == null) return;

      final data = jsonDecode(response);
      if (data['success'] == true) {
        final result = data['data'] as Map<String, dynamic>;

        if (type == 'tracks') {
          final newTracks =
              (result['tracks'] as List).cast<Map<String, dynamic>>();
          tracks.addAll(newTracks);
          _tracksOffset = tracks.length;
          totalTracks =
              (result['totalTracks'] as num?)?.toInt() ?? totalTracks;
        } else if (type == 'albums') {
          final newAlbums =
              (result['albums'] as List).cast<Map<String, dynamic>>();
          albums.addAll(newAlbums);
          _albumsOffset = albums.length;
          totalAlbums =
              (result['totalAlbums'] as num?)?.toInt() ?? totalAlbums;
        } else {
          final newPlaylists =
              (result['playlists'] as List).cast<Map<String, dynamic>>();
          playlists.addAll(newPlaylists);
          _playlistsOffset = playlists.length;
          totalPlaylists =
              (result['totalPlaylists'] as num?)?.toInt() ?? totalPlaylists;
        }
      }
    } catch (e) {
      debugPrint('Error loading more $type: $e');
    } finally {
      isLoadingMore = false;
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
    _tracksOffset = 0;
    _albumsOffset = 0;
    _playlistsOffset = 0;
    isLoadingMore = false;
    error = null;
    lastQuery = '';
    notifyListeners();
  }

  bool get hasResults =>
      tracks.isNotEmpty || albums.isNotEmpty || playlists.isNotEmpty;
}
