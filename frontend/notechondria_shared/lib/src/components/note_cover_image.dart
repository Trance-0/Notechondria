import 'package:flutter/material.dart';

/// Cover-image renderer for a note.
///
/// When [imageUrl] is non-empty, displays the network image inside a
/// rounded card. Otherwise falls back to a deterministic theme-colored
/// barcode generated from [seed] (typically the note's uuid + title)
/// — purely a frontend render, never persisted to R2 / CDN.
///
/// The widget is sized by its parent's max width and a fixed
/// [aspectRatio] (defaults to 16:5, which reads well as a "header
/// strip" above note bodies). Pass [showCaption] = true to render the
/// note's title centered below the bars in the barcode placeholder
/// state — useful for index pages but redundant in viewer UIs that
/// already display the title above the cover.
class NoteCoverImage extends StatelessWidget {
  const NoteCoverImage({
    super.key,
    required this.seed,
    this.imageUrl,
    this.caption,
    this.showCaption = false,
    this.aspectRatio = 16 / 5,
    this.borderRadius = 16,
  });

  /// Stable per-note seed string. The barcode pattern is derived
  /// deterministically from this, so the same note always renders the
  /// same barcode across sessions.
  final String seed;

  /// Optional uploaded cover URL. Empty string is treated as "no
  /// cover" so server payloads with `cover_image_url == ""` produce
  /// the barcode fallback.
  final String? imageUrl;

  /// Caption shown beneath the bars when [showCaption] is true.
  /// Usually the note title.
  final String? caption;
  final bool showCaption;
  final double aspectRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: hasImage
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _BarcodeCover(
                  seed: seed,
                  caption: caption,
                  showCaption: showCaption,
                  scheme: scheme,
                ),
              )
            : _BarcodeCover(
                seed: seed,
                caption: caption,
                showCaption: showCaption,
                scheme: scheme,
              ),
      ),
    );
  }
}

class _BarcodeCover extends StatelessWidget {
  const _BarcodeCover({
    required this.seed,
    required this.caption,
    required this.showCaption,
    required this.scheme,
  });

  final String seed;
  final String? caption;
  final bool showCaption;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _BarcodePainter(
                seed: seed,
                color: scheme.primary,
              ),
            ),
          ),
          if (showCaption && caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Deterministic Code-39-flavored barcode painter. The exact symbology
/// is loose — it's a visual stand-in, not a scannable barcode. We hash
/// each character of [seed] into a 9-bit stripe pattern (5 bars + 4
/// gaps, 2 of which are wide) so the rendered bars look believable
/// without depending on any external symbology library.
class _BarcodePainter extends CustomPainter {
  _BarcodePainter({required this.seed, required this.color});

  final String seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final pattern = _patternFor(seed);
    if (pattern.isEmpty) return;

    // Each "cell" is one logical bar/gap unit; wide ones are 3x.
    final totalUnits = pattern.fold<int>(0, (acc, cell) => acc + cell.units);
    if (totalUnits == 0) return;
    final unitWidth = size.width / totalUnits;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    var x = 0.0;
    for (final cell in pattern) {
      final w = unitWidth * cell.units;
      if (cell.isBar) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.color != color;

  /// Per-character pattern: alternating bar / gap / bar / ... cells,
  /// each either narrow (1 unit) or wide (3 units). Length 9 cells per
  /// character, matching Code 39's bar/space encoding shape so the
  /// output reads as a real barcode at a glance.
  List<_BarCell> _patternFor(String input) {
    if (input.isEmpty) return const [];
    // Quiet zone: leading gap.
    final cells = <_BarCell>[const _BarCell(false, 3)];
    // Start guard: 5 narrow alternating bar/gap stripes.
    for (var i = 0; i < 5; i++) {
      cells.add(_BarCell(i.isEven, 1));
    }
    cells.add(const _BarCell(false, 1));
    var hash = 0x811c9dc5; // FNV-1a seed.
    for (final code in input.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xFFFFFFFF;
      // 9 cells per "character": bar/gap/bar/gap/bar/gap/bar/gap/bar.
      // Wide-or-narrow chosen by hash bits; ensure each char has at
      // least one wide so the visual rhythm doesn't flatten to all-1s.
      var bits = hash;
      var wideCount = 0;
      for (var i = 0; i < 9; i++) {
        final isWide = (bits & 1) == 1 && wideCount < 3;
        if (isWide) wideCount++;
        cells.add(_BarCell(i.isEven, isWide ? 3 : 1));
        bits >>= 1;
      }
      // Inter-character gap (1 narrow gap).
      cells.add(const _BarCell(false, 1));
    }
    // End guard: 5 narrow alternating bar/gap stripes.
    for (var i = 0; i < 5; i++) {
      cells.add(_BarCell(i.isEven, 1));
    }
    cells.add(const _BarCell(false, 3));
    return cells;
  }
}

class _BarCell {
  const _BarCell(this.isBar, this.units);
  final bool isBar;
  final int units;
}
