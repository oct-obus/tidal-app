import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CoverThumbnail extends StatelessWidget {
  final String? coverUrl;
  final double size;
  final IconData fallbackIcon;
  final String? source;

  const CoverThumbnail({
    super.key,
    this.coverUrl,
    this.size = 48,
    this.fallbackIcon = Icons.music_note,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = (coverUrl == null || coverUrl!.isEmpty)
        ? _fallback(theme)
        : ClipRRect(
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

    if (source == null || source == 'tidal') return image;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          image,
          Positioned(
            right: 0,
            bottom: 0,
            child: _sourceBadge(theme),
          ),
        ],
      ),
    );
  }

  Widget _sourceBadge(ThemeData theme) {
    final badgeSize = (size * 0.38).clamp(14.0, 22.0);
    final iconSize = badgeSize * 0.65;
    final Color bgColor;
    final IconData icon;

    switch (source) {
      case 'youtube':
        bgColor = const Color(0xFFFF0000);
        icon = Icons.play_arrow;
      case 'soundcloud':
        bgColor = const Color(0xFFFF5500);
        icon = Icons.cloud;
      default:
        bgColor = theme.colorScheme.primary;
        icon = Icons.music_note;
    }

    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black54, width: 0.5),
      ),
      child: Icon(icon, size: iconSize, color: Colors.white),
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
