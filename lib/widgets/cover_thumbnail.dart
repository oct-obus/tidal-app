import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CoverThumbnail extends StatelessWidget {
  final String? coverUrl;
  final double size;
  final IconData fallbackIcon;

  const CoverThumbnail({
    super.key,
    this.coverUrl,
    this.size = 48,
    this.fallbackIcon = Icons.music_note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (coverUrl == null || coverUrl!.isEmpty) {
      return _fallback(theme);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: coverUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => _fallback(theme),
        errorWidget: (_, __, ___) => _fallback(theme),
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(fallbackIcon,
          size: size * 0.5, color: theme.colorScheme.outline),
    );
  }
}
