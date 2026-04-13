import 'dart:convert';
import 'dart:io';

class LinkResolverResult {
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String source;

  LinkResolverResult({
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.source,
  });

  String get searchQuery => '$artist $title';
}

class LinkResolver {
  static final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  /// Patterns to strip from YouTube video titles for cleaner search queries.
  static final _youtubeCleanupPatterns = [
    RegExp(r'\s*[\(\[]\s*Official\s*(Music\s*)?Video\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Official\s*Audio\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Lyric(s)?\s*Video\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Official\s*Lyric(s)?\s*Video\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Official\s*Visuali[sz]er\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Music\s*Video\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*(4K|HD)\s*Remaster(ed)?\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Audio\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*MV\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Lyrics\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Official\s*HD\s*Video\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*\d{4}\s*Remaster(ed)?\s*[\)\]]',
        caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*Explicit\s*[\)\]]', caseSensitive: false),
    RegExp(r'\s*[\(\[]\s*HQ\s*[\)\]]', caseSensitive: false),
  ];

  /// Resolve a Spotify track link to title + artist via oEmbed + page scraping.
  static Future<LinkResolverResult?> resolveSpotify(String url) async {
    try {
      final oembedUrl =
          'https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}';

      // Fetch oEmbed and page HTML in parallel
      final results = await Future.wait([
        _fetchJson(oembedUrl),
        _fetchString(url),
      ]);

      final oembedData = results[0] as Map<String, dynamic>?;
      final pageHtml = results[1] as String?;

      if (oembedData == null) return null;

      final title = oembedData['title'] as String? ?? '';
      if (title.isEmpty) return null;

      final thumbnailUrl = oembedData['thumbnail_url'] as String?;

      // Extract artist from page metadata
      String artist = '';
      if (pageHtml != null) {
        // Try og:description: "Artist · Album · Song · Year"
        final ogDescMatch =
            RegExp(r'og:description["\s]+content="([^"]*)"')
                .firstMatch(pageHtml);
        if (ogDescMatch != null) {
          final desc = _decodeHtmlEntities(ogDescMatch.group(1)!);
          final parts = desc.split('·').map((s) => s.trim()).toList();
          if (parts.isNotEmpty && parts[0].isNotEmpty) {
            artist = parts[0];
          }
        }

        // Fallback: <title> tag "Track - song and lyrics by Artist | Spotify"
        if (artist.isEmpty) {
          final titleMatch =
              RegExp(r'by\s+([^|]+)\s*\|').firstMatch(pageHtml);
          if (titleMatch != null) {
            artist = titleMatch.group(1)!.trim();
          }
        }
      }

      if (artist.isEmpty) artist = 'Unknown';

      return LinkResolverResult(
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        source: 'spotify',
      );
    } catch (_) {
      return null;
    }
  }

  /// Resolve a YouTube/YouTube Music link via oEmbed.
  static Future<LinkResolverResult?> resolveYouTube(String url) async {
    try {
      final oembedUrl =
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json';
      final data = await _fetchJson(oembedUrl);
      if (data == null) return null;

      final rawTitle = data['title'] as String? ?? '';
      final authorName = data['author_name'] as String? ?? '';
      final thumbnailUrl = data['thumbnail_url'] as String?;

      String artist;
      String title;

      // Most music videos use "Artist - Title" format
      final dashIndex = rawTitle.indexOf(' - ');
      if (dashIndex > 0) {
        artist = rawTitle.substring(0, dashIndex).trim();
        title = rawTitle.substring(dashIndex + 3).trim();
      } else {
        artist = authorName;
        title = rawTitle;
      }

      title = cleanYouTubeTitle(title);

      return LinkResolverResult(
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        source: 'youtube',
      );
    } catch (_) {
      return null;
    }
  }

  /// Strip common video-related tags from a YouTube title.
  static String cleanYouTubeTitle(String title) {
    var cleaned = title;
    for (final pattern in _youtubeCleanupPatterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned.trim();
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }

  static Future<Map<String, dynamic>?> _fetchJson(String url) async {
    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Mozilla/5.0');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchString(String url) async {
    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Mozilla/5.0');
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    }
  }
}
