part of notechondria_frontend;

/// Fullscreen startup overlay showing the user's custom splash image
/// (local upload via LocalAttachmentStore, else a remote URL) instead of
/// the default reactor animation. The image spans the whole screen with a
/// fixed x-y aspect ratio (BoxFit.cover). Auto-dismisses after a short
/// beat (tap to skip); falls back to a plain surface if the image fails.
class _CustomSplashOverlay extends StatefulWidget {
  const _CustomSplashOverlay({
    required this.appTitle,
    required this.appVersion,
    this.localImageUrl = '',
    this.remoteImageUrl = '',
    this.loadingStatus,
    this.onFinished,
  });

  final String appTitle;
  final String appVersion;
  final String localImageUrl;
  final String remoteImageUrl;
  final ValueListenable<String>? loadingStatus;
  final VoidCallback? onFinished;

  @override
  State<_CustomSplashOverlay> createState() => _CustomSplashOverlayState();
}

class _CustomSplashOverlayState extends State<_CustomSplashOverlay> {
  Timer? _timer;
  double _opacity = 1;
  Uint8List? _localBytes;

  @override
  void initState() {
    super.initState();
    if (widget.localImageUrl.isNotEmpty) {
      LocalAttachmentStore.open()
          .then((store) => store.getBytes(localUrl: widget.localImageUrl))
          .then((bytes) {
        if (mounted) setState(() => _localBytes = bytes);
      }).catchError((_) {
        // Missing/corrupt local image → plain surface fallback below.
      });
    }
    _timer = Timer(const Duration(milliseconds: 2400), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _opacity == 0) return;
    setState(() => _opacity = 0);
    Timer(const Duration(milliseconds: 350), () {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget image;
    if (_localBytes != null) {
      image = Image.memory(_localBytes!, fit: BoxFit.cover);
    } else if (widget.remoteImageUrl.isNotEmpty &&
        widget.localImageUrl.isEmpty) {
      image = Image.network(
        widget.remoteImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            ColoredBox(color: theme.colorScheme.surface),
      );
    } else {
      image = ColoredBox(color: theme.colorScheme.surface);
    }
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 350),
      child: GestureDetector(
        onTap: _dismiss,
        child: Material(
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              // Bottom scrim so the title/status stay legible on any image.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.appTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${widget.appVersion}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white70),
                    ),
                    if (widget.loadingStatus != null) ...[
                      const SizedBox(height: 4),
                      ValueListenableBuilder<String>(
                        valueListenable: widget.loadingStatus!,
                        builder: (context, value, _) => Text(
                          value,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
