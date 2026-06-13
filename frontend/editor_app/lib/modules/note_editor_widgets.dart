part of notechondria_frontend;

/// Hover-only insert slot between paragraphs. The hairline is invisible until
/// the pointer enters; clicking inserts an empty paragraph.
class _HoverInsertSlot extends StatefulWidget {
  const _HoverInsertSlot({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_HoverInsertSlot> createState() => _HoverInsertSlotState();
}

class _HoverInsertSlotState extends State<_HoverInsertSlot> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 10,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovering ? 1 : 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [TextEditingController] that paints live GFM syntax highlighting inside
/// the plain-text and live-markdown editors. It recognizes headings, bold,
/// italic, strikethrough, inline code, and links so users get visual feedback
/// as they type without waiting for a preview render.
class _MarkdownHighlightingController extends TextEditingController {
  _MarkdownHighlightingController({super.text});

  static final RegExp _inlinePattern = RegExp(
    r'(\*\*[^*\n]+\*\*)'
    r'|(__[^_\n]+__)'
    r'|(\*[^*\n]+\*)'
    r'|(_[^_\n]+_)'
    r'|(~~[^~\n]+~~)'
    r'|(`[^`\n]+`)'
    r'|(\[[^\]\n]+\]\([^)\n]+\))',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final theme = Theme.of(context);
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[];
    final lines = text.split('\n');
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        children.add(TextSpan(
          text: line,
          style: base.copyWith(
            color: theme.colorScheme.primary,
            fontFamily: 'monospace',
          ),
        ));
      } else if (inFence) {
        children.add(TextSpan(
          text: line,
          style: base.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ));
      } else {
        final headerMatch = RegExp(r'^(#{1,6})(\s+.*)$').firstMatch(line);
        final quoteMatch = RegExp(r'^(\s*>+\s*)(.*)$').firstMatch(line);
        final bulletMatch = RegExp(r'^(\s*[-*+]\s+)(.*)$').firstMatch(line);
        final orderedMatch = RegExp(r'^(\s*\d+\.\s+)(.*)$').firstMatch(line);
        if (headerMatch != null) {
          final hashes = headerMatch.group(1)!;
          final rest = headerMatch.group(2)!;
          final level = hashes.length;
          final fontSize = (base.fontSize ?? 14) + (7 - level) * 1.5;
          children.add(TextSpan(
            text: hashes,
            style: base.copyWith(color: theme.colorScheme.primary),
          ));
          children.addAll(_inlineSpans(
            rest,
            base.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
            ),
            theme,
          ));
        } else if (quoteMatch != null) {
          children.add(TextSpan(
            text: quoteMatch.group(1),
            style: base.copyWith(color: theme.colorScheme.primary),
          ));
          children.addAll(_inlineSpans(
            quoteMatch.group(2)!,
            base.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
            theme,
          ));
        } else if (bulletMatch != null) {
          children.add(TextSpan(
            text: bulletMatch.group(1),
            style: base.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ));
          children.addAll(_inlineSpans(bulletMatch.group(2)!, base, theme));
        } else if (orderedMatch != null) {
          children.add(TextSpan(
            text: orderedMatch.group(1),
            style: base.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ));
          children.addAll(_inlineSpans(orderedMatch.group(2)!, base, theme));
        } else {
          children.addAll(_inlineSpans(line, base, theme));
        }
      }
      if (i < lines.length - 1) {
        children.add(const TextSpan(text: '\n'));
      }
    }
    return TextSpan(style: base, children: children);
  }

  List<InlineSpan> _inlineSpans(String line, TextStyle base, ThemeData theme) {
    if (line.isEmpty) return const [];
    final result = <InlineSpan>[];
    var cursor = 0;
    for (final match in _inlinePattern.allMatches(line)) {
      if (match.start > cursor) {
        result.add(TextSpan(
          text: line.substring(cursor, match.start),
          style: base,
        ));
      }
      final token = match.group(0)!;
      if (token.startsWith('**') || token.startsWith('__')) {
        result.add(TextSpan(
          text: token,
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (token.startsWith('~~')) {
        result.add(TextSpan(
          text: token,
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (token.startsWith('`')) {
        result.add(TextSpan(
          text: token,
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ));
      } else if (token.startsWith('[')) {
        result.add(TextSpan(
          text: token,
          style: base.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ));
      } else {
        // Single * or _ → italic
        result.add(TextSpan(
          text: token,
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      cursor = match.end;
    }
    if (cursor < line.length) {
      result.add(TextSpan(text: line.substring(cursor), style: base));
    }
    return result;
  }
}

/// One row in the attachments bottom-sheet. Renders a leading preview
/// (image thumbnail for image/* locals, icon otherwise), filename,
/// formatted size + content-type, and either a delete or copy-link
/// trailing action depending on whether the row is local or cloud.
class _AttachmentSheetRow extends StatelessWidget {
  const _AttachmentSheetRow({
    required this.filename,
    required this.sizeBytes,
    required this.contentType,
    required this.localUrl,
    required this.cloudUrl,
    required this.onDelete,
  });

  final String filename;
  final int sizeBytes;
  final String contentType;
  final String? localUrl;
  final String? cloudUrl;
  final VoidCallback? onDelete;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildLeading(BuildContext context) {
    final isImage = contentType.startsWith('image/');
    if (isImage && localUrl != null && localUrl!.isNotEmpty) {
      return SizedBox(
        width: 40,
        height: 40,
        child: FutureBuilder<Uint8List?>(
          future: LocalAttachmentStore.open()
              .then((s) => s.getBytes(localUrl: localUrl!)),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final data = snap.data;
            if (data == null || data.isEmpty) {
              return const Icon(Icons.broken_image_outlined);
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                data,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            );
          },
        ),
      );
    }
    final icon = isImage
        ? Icons.image_outlined
        : contentType.startsWith('video/')
            ? Icons.videocam_outlined
            : contentType.startsWith('audio/')
                ? Icons.audiotrack_outlined
                : Icons.attachment_outlined;
    return SizedBox(
      width: 40,
      height: 40,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeLabel = _formatBytes(sizeBytes);
    final subtitleParts = <String>[
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (contentType.isNotEmpty) contentType,
      if (cloudUrl != null) 'uploaded',
      if (localUrl != null && cloudUrl == null) 'local',
    ];
    return ListTile(
      leading: _buildLeading(context),
      title: Text(
        filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove attachment',
              onPressed: onDelete,
            )
          : cloudUrl != null
              ? IconButton(
                  icon: const Icon(Icons.link),
                  tooltip: 'Copy link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: cloudUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Link copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                )
              : null,
    );
  }
}
