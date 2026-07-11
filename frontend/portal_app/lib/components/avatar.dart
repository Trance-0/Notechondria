part of notechondria_frontend;

class _RemoteMedia extends StatelessWidget {
  const _RemoteMedia({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.fallbackUrl = '',
  });

  final String imageUrl;
  final Widget fallback;
  final BoxFit fit;

  /// Secondary URL tried when [imageUrl] is empty or fails to load.
  /// Used for the Casdoor-avatar → legacy-upload fallback: when the
  /// Casdoor server is offline / the avatar 404s, the locally uploaded
  /// image is shown instead of the generic placeholder.
  final String fallbackUrl;

  bool _isSvg(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.svg') || lower.contains('.svg?');
  }

  @override
  Widget build(BuildContext context) {
    // On empty/failed primary, recurse into the fallback URL (once),
    // then the placeholder widget.
    final onFail = fallbackUrl.trim().isEmpty
        ? fallback
        : _RemoteMedia(imageUrl: fallbackUrl, fallback: fallback, fit: fit);
    if (imageUrl.trim().isEmpty) {
      return onFail;
    }
    if (_isSvg(imageUrl)) {
      return SvgPicture.network(
        imageUrl,
        fit: fit,
        placeholderBuilder: (_) => onFail,
      );
    }
    return Image.network(
      imageUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => onFail,
    );
  }
}

class _RemoteAvatar extends StatelessWidget {
  const _RemoteAvatar({
    required this.radius,
    this.imageUrl = '',
    this.fallbackImageUrl = '',
    this.fallbackLabel = '',
    this.fallbackIcon = Icons.person_outline,
  });

  final double radius;
  final String imageUrl;

  /// Legacy locally-uploaded avatar used when [imageUrl] (the Casdoor
  /// avatar) is empty or fails to load — see [_RemoteMedia.fallbackUrl].
  final String fallbackImageUrl;
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

    if (imageUrl.trim().isEmpty && fallbackImageUrl.trim().isEmpty) {
      return fallback;
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: _RemoteMedia(
          imageUrl: imageUrl,
          fallbackUrl: fallbackImageUrl,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
      ),
    );
  }
}
