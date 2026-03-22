part of notechondria_frontend;

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
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
