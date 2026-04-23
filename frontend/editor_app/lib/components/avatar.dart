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
      errorBuilder: (_, error, stackTrace) {
        debugPrint('[_RemoteMedia] failed to load image: $imageUrl — $error');
        return fallback;
      },
    );
  }
}

/// Preview dialog shown before uploading a new avatar. Displays the selected
/// image in a circular clip so the user can confirm it looks correct.
class _AvatarPreviewDialog extends StatelessWidget {
  const _AvatarPreviewDialog({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preview avatar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('This image will be cropped to a circle for your profile.'),
          const SizedBox(height: 20),
          ClipOval(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 160,
                  height: 160,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  alignment: Alignment.center,
                  child: const Text('Cannot preview this image'),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Upload'),
        ),
      ],
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
          ? Icon(fallbackIcon, size: radius, color: colorScheme.onSurfaceVariant)
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
