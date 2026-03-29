import 'package:flutter/foundation.dart';

String formatDuration(num seconds) {
  if (seconds <= 0 ||
      (seconds is double && (seconds.isInfinite || seconds.isNaN))) {
    return '0:00';
  }
  final total = seconds.toInt();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatTrackDuration(dynamic seconds) {
  if (seconds == null) return '-';
  return formatDuration((seconds as num));
}

String formatRelativeDate(String dateStr) {
  try {
    final dt = DateTime.parse(dateStr);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final weeks = diff.inDays ~/ 7;
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  } catch (_) {
    return dateStr;
  }
}

String formatFileSize(dynamic bytes) {
  if (bytes == null) return '-';
  final mb = (bytes as num) / 1048576;
  return '${mb.toStringAsFixed(1)} MB';
}

String formatSampleRate(dynamic rate) {
  if (rate == null) return '-';
  final r = (rate as num).toInt();
  if (r >= 1000) {
    final parts = <String>[];
    var remaining = r;
    while (remaining > 0) {
      final chunk = remaining % 1000;
      remaining ~/= 1000;
      parts.insert(
          0, remaining > 0 ? chunk.toString().padLeft(3, '0') : chunk.toString());
    }
    return '${parts.join(',')} Hz';
  }
  return '$r Hz';
}

String formatDownloadDate(dynamic dateStr) {
  if (dateStr == null) return '-';
  try {
    final dt = DateTime.parse(dateStr as String);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  } catch (e) {
    debugPrint('Error parsing download date: $e');
    return dateStr.toString();
  }
}
