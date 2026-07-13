part of notechondria_frontend;

/// Converts a note payload into markdown when only block data is available.
String _noteToMarkdown(Map<String, dynamic> note) {
  final blocks = (note['blocks'] as List<dynamic>? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  if (blocks.isEmpty) {
    return '# ${note['title'] ?? 'Untitled'}\n\n${note['description'] ?? ''}';
  }
  final buffer = StringBuffer();
  for (final block in blocks) {
    final type = block['block_type']?.toString() ?? 'N';
    final text = block['text']?.toString() ?? '';
    switch (type) {
      case 'T':
        buffer.writeln('# $text');
        break;
      case 'S':
        buffer.writeln('${block['args'] ?? '##'} $text');
        break;
      case 'C':
        buffer.writeln('```');
        buffer.writeln(text);
        buffer.writeln('```');
        break;
      default:
        buffer.writeln(text);
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// Normalizes a [DateTime] to its date-only local representation.
DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Builds markdown with the note title stored as the first H1 heading.
String _composeMarkdown(String title, String body) {
  final normalizedTitle = title.trim().isEmpty ? 'Untitled note' : title.trim();
  final normalizedBody = _bodyWithoutTitle(body);
  return '# $normalizedTitle\n\n$normalizedBody'.trim();
}

/// Removes the top-level H1 from markdown editor text for body-only editing.
String _bodyWithoutTitle(String markdown) {
  final lines = markdown.split('\n');
  if (lines.isNotEmpty && lines.first.trim().startsWith('# ')) {
    return lines.skip(1).join('\n').trimLeft();
  }
  return markdown;
}

/// Extracts the first markdown H1 as the note title.
String _extractTitleFromMarkdown(String markdown) {
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) {
      return trimmed.substring(2).trim();
    }
  }
  return 'Untitled note';
}

/// Generates a short excerpt from markdown content for list cards.
String _excerptFromMarkdown(String markdown) {
  final body = _bodyWithoutTitle(markdown).trim();
  return body.length <= 180 ? body : '${body.substring(0, 180)}...';
}

/// Coerces a draft's `editor_mode` to a backend-valid choice
/// (`'G'` / `'B'` / `'P'`). Pre-0.1.83 starter drafts used `'M'`
/// / `'T'` — both alias to the new codes so a one-time sync
/// doesn't fail with `400 editor_mode is not a valid choice`.
String _normalizeEditorMode(dynamic raw) {
  final value = raw?.toString();
  switch (value) {
    case 'G':
    case 'B':
    case 'P':
      return value!;
    case 'M':
      return 'G';
    case 'T':
      return 'P';
    default:
      return 'P';
  }
}

/// Safely decodes JSON note metadata into a mutable map.
Map<String, dynamic> _decodeNoteMetadata(String raw) {
  if (raw.trim().isEmpty) {
    return {};
  }
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return {};
  }
}

/// Formats a local time for save status and activity surfaces.
String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${value.minute.toString().padLeft(2, '0')} $suffix';
}

/// Build-time configurable backend URL: pass --dart-define=DEFAULT_API_URL=https://your-backend.com/api/v1
const _kDefaultApiUrl = String.fromEnvironment('DEFAULT_API_URL',
    defaultValue: 'https://notechondria.trance-0.com/api/v1');

/// Build-time app version. The release pipeline should pass
/// `--dart-define=APP_VERSION=$(cat VERSION)` so the splash screen and any
/// debug surface report the same version as the Docker image tag. The
/// default tracks the value committed to the repo's ./VERSION file at the
/// time of writing — bump both together.
const _kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '0.1.21');

String _defaultApiBaseUrl() {
  if (kIsWeb) {
    final base = Uri.base;
    final origin =
        '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
    if (base.host == 'localhost' || base.host == '127.0.0.1') {
      return '$origin/api/v1';
    }
    // Static hosting (e.g. GitHub Pages) - API is cross-origin
    if (base.host.endsWith('.github.io')) {
      return _kDefaultApiUrl;
    }
  }
  return _kDefaultApiUrl;
}

String _slugifyLocalText(String value, {String fallback = 'item'}) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return normalized.isEmpty ? fallback : normalized;
}

String _apiOrigin(String? baseUrl) {
  final candidate = (baseUrl ?? '').trim();
  if (candidate.isEmpty) {
    return Uri.base.hasScheme && Uri.base.host.isNotEmpty
        ? Uri.base.origin
        : '';
  }
  final parsed = Uri.tryParse(candidate);
  if (parsed == null) {
    return Uri.base.hasScheme && Uri.base.host.isNotEmpty
        ? Uri.base.origin
        : '';
  }
  if (!parsed.hasScheme || parsed.host.isEmpty) {
    return candidate.startsWith('/') &&
            Uri.base.hasScheme &&
            Uri.base.host.isNotEmpty
        ? Uri.base.origin
        : '';
  }
  return parsed
      .replace(path: '', query: '', fragment: '')
      .toString()
      .replaceAll(RegExp(r'/$'), '');
}

String _resolveRemoteUrl(String raw, {String? apiBaseUrl}) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '';
  }
  final parsed = Uri.tryParse(value);
  final origin = _apiOrigin(apiBaseUrl);
  final originUri = origin.isEmpty ? null : Uri.tryParse(origin);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    if (originUri != null &&
        parsed.host == originUri.host &&
        !parsed.hasPort &&
        originUri.hasPort) {
      final defaultPort = parsed.scheme == 'https' ? 443 : 80;
      if (originUri.port != defaultPort) {
        return parsed.replace(port: originUri.port).toString();
      }
    }
    return value;
  }
  var normalized = value;
  if (parsed != null && parsed.scheme == 'file' && parsed.host.isEmpty) {
    normalized = parsed.path;
  }
  if (origin.isEmpty) {
    return normalized.startsWith('/media/') || normalized.startsWith('/static/')
        ? normalized
        : '';
  }
  if (normalized.startsWith('/')) {
    return '$origin$normalized';
  }
  return '$origin/$normalized';
}

/// Theme preset labels exposed in settings.
const Map<String, String> _themePresetEntries = {
  'teal': 'Teal',
  'amber': 'Amber',
  'blue': 'Blue',
  'rose': 'Rose',
  'mint': 'Mint',
  'slate': 'Slate',
  'emerald': 'Emerald',
  'orange': 'Orange',
  'indigo': 'Indigo',
  'red': 'Red',
  'cyan': 'Cyan',
  'lime': 'Lime',
};

/// Resolves the Material seed color for a saved theme preset.
Color _themeSeed(String preset) {
  switch (preset) {
    case 'amber':
      return const Color(0xFFD97706);
    case 'blue':
      return const Color(0xFF2563EB);
    case 'rose':
      return const Color(0xFFE11D48);
    case 'mint':
      return const Color(0xFF10B981);
    case 'slate':
      return const Color(0xFF475569);
    case 'emerald':
      return const Color(0xFF059669);
    case 'orange':
      return const Color(0xFFEA580C);
    case 'indigo':
      return const Color(0xFF4F46E5);
    case 'red':
      return const Color(0xFFDC2626);
    case 'cyan':
      return const Color(0xFF0891B2);
    case 'lime':
      return const Color(0xFF65A30D);
    default:
      return const Color(0xFF0F766E);
  }
}

/// Maps persisted theme mode codes to Flutter [ThemeMode] values.
ThemeMode _themeModeFromSetting(String raw) {
  switch (raw) {
    case 'L':
      return ThemeMode.light;
    case 'D':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Builds markdown renderers, including inline LaTeX support.
Map<String, MarkdownElementBuilder> _markdownBuilders() {
  return {'latex': _LatexBuilder()};
}

/// Registers markdown inline syntaxes used across note viewers and previews.
List<md.InlineSyntax> _markdownInlineSyntaxes() {
  return [_LatexInlineSyntax()];
}

/// Theme-aware markdown styling shared by every note reader (viewer +
/// learner). Without an explicit sheet, `flutter_markdown` renders
/// blockquotes and code with its package defaults (a hardcoded pale-blue
/// blockquote box) that look wrong in dark mode and washed-out in light.
/// This derives everything from the active [ColorScheme] so both themes
/// read correctly.
MarkdownStyleSheet _noteMarkdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final base = MarkdownStyleSheet.fromTheme(theme);
  return base.copyWith(
    blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
    blockquote: (base.blockquote ?? theme.textTheme.bodyMedium)
        ?.copyWith(color: scheme.onSurfaceVariant),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceVariant.withOpacity(0.4),
      border: Border(
        left: BorderSide(
          color: scheme.primary.withOpacity(0.6),
          width: 4,
        ),
      ),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
    ),
    code: (base.code ?? theme.textTheme.bodyMedium)?.copyWith(
      backgroundColor: scheme.surfaceVariant.withOpacity(0.55),
      color: scheme.onSurface,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceVariant.withOpacity(0.45),
      borderRadius: BorderRadius.circular(8),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(width: 1, color: scheme.outlineVariant),
      ),
    ),
  );
}

/// Custom image builder for `MarkdownBody.sizedImageBuilder`.
/// Resolves `local://<note_uuid>/<filename>` URIs through the
/// shared `LocalAttachmentStore` and renders the bytes via
/// `Image.memory`. Matches the editor's helper verbatim so portal
/// drafts imported from a `.nchron` archive keep rendering their
/// attachments; non-local URIs fall through to `Image.network`.
Widget _localAttachmentImageBuilder(MarkdownImageConfig config) {
  final uri = config.uri;
  if (uri.scheme != 'local') {
    return Image.network(
      uri.toString(),
      width: config.width,
      height: config.height,
      errorBuilder: (context, error, stack) {
        final display = (config.alt?.isNotEmpty == true)
            ? config.alt!
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'image');
        return Text(
          '\u26a0 $display failed to load',
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
  final key = 'local-attachment:$uri';
  return FutureBuilder<Uint8List>(
    key: ValueKey(key),
    future: () async {
      final store = await LocalAttachmentStore.open();
      return store.getBytes(localUrl: uri.toString());
    }(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (snapshot.hasError || !snapshot.hasData) {
        final display = (config.alt?.isNotEmpty == true)
            ? config.alt!
            : (uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : 'attachment');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '\u26a0 attachment not in local store: $display',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }
      return Image.memory(
        snapshot.data!,
        width: config.width,
        height: config.height,
        errorBuilder: (context, error, stack) {
          final display = (config.alt?.isNotEmpty == true)
              ? config.alt!
              : (uri.pathSegments.isNotEmpty
                  ? uri.pathSegments.last
                  : 'attachment');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '\ud83d\udcce $display',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      );
    },
  );
}

/// Animates a child with a staggered fade + optional slide entrance.
///
/// Use [index] to stagger items in a list: each successive item starts its
/// animation [staggerDelay] later (default 50ms per index). The slide comes
/// from the direction specified by [slideOffset] (default: 4% from the bottom).
class _StaggeredFadeIn extends StatefulWidget {
  const _StaggeredFadeIn({
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.staggerDelay = const Duration(milliseconds: 50),
    this.slideOffset = const Offset(0, 0.04),
  });

  final int index;
  final Widget child;
  final Duration duration;
  final Duration staggerDelay;
  final Offset slideOffset;

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: widget.slideOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    final delay = widget.staggerDelay * widget.index;
    if (delay > Duration.zero) {
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

/// Parses `$...$` and `$$...$$` LaTeX spans into markdown elements.
class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax() : super(r'(?<!\\)\$\$([^$]+)\$\$|(?<!\\)\$([^$\n]+)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = (match[1] ?? match[2] ?? '').trim();
    if (expression.isEmpty) {
      return false;
    }
    final element = md.Element.text('latex', expression);
    parser.addNode(element);
    return true;
  }
}

/// Renders LaTeX markdown elements with `flutter_math_fork`.
class _LatexBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Math.tex(
      element.textContent,
      mathStyle: MathStyle.text,
      textStyle: preferredStyle ?? parentStyle,
    );
  }
}
