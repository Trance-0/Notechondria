part of notechondria_frontend;

class _RemoteMedia extends StatelessWidget {
  const _RemoteMedia({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final Widget fallback;
  final BoxFit fit;

  bool get _isSvg {
    final lower = imageUrl.toLowerCase();
    return lower.endsWith('.svg') || lower.contains('.svg?');
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return fallback;
    }
    if (_isSvg) {
      return SvgPicture.network(
        imageUrl,
        fit: fit,
        placeholderBuilder: (_) => fallback,
      );
    }
    return Image.network(
      imageUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _RemoteAvatar extends StatelessWidget {
  const _RemoteAvatar({
    required this.radius,
    this.imageUrl = '',
    this.fallbackLabel = '',
    this.fallbackIcon = Icons.person_outline,
  });

  final double radius;
  final String imageUrl;
  final String fallbackLabel;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: fallbackLabel.trim().isEmpty
          ? Icon(fallbackIcon,
              size: radius, color: colorScheme.onSurfaceVariant)
          : Text(
              fallbackLabel.trim().substring(0, 1).toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
    );

    if (imageUrl.trim().isEmpty) {
      return fallback;
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: _RemoteMedia(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
      ),
    );
  }
}
