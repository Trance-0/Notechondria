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

/// Parsed representation of an imported markdown document. Populated by the
/// import flow in `_AppShellState._parseImportedMarkdown`, which optionally
/// strips a YAML frontmatter block and pulls `title` / `description` out of it.
class _ImportedMarkdown {
  const _ImportedMarkdown({
    this.title,
    this.description,
    required this.body,
  });

  final String? title;
  final String? description;
  final String body;
}

/// Generates a short excerpt from markdown content for list cards.
String _excerptFromMarkdown(String markdown) {
  final body = _bodyWithoutTitle(markdown).trim();
  return body.length <= 180 ? body : '${body.substring(0, 180)}...';
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

/// Formats note timestamps for compact card footers.
String _formatCompactTimestamp(String raw) {
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final now = DateTime.now();
  final local = parsed.toLocal();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  if (local.isAfter(startOfWeek) && local.year == now.year) {
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][local.weekday - 1];
  }
  if (local.year == now.year) {
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
  return '${(local.year % 100).toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
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

String _defaultApiBaseUrl() {
  if (kIsWeb) {
    final base = Uri.base;
    final origin = '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
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
    return Uri.base.hasScheme && Uri.base.host.isNotEmpty ? Uri.base.origin : '';
  }
  final parsed = Uri.tryParse(candidate);
  if (parsed == null) {
    return Uri.base.hasScheme && Uri.base.host.isNotEmpty ? Uri.base.origin : '';
  }
  if (!parsed.hasScheme || parsed.host.isEmpty) {
    return candidate.startsWith('/') &&
            Uri.base.hasScheme &&
            Uri.base.host.isNotEmpty
        ? Uri.base.origin
        : '';
  }
  return parsed.replace(path: '', query: '', fragment: '').toString().replaceAll(RegExp(r'/$'), '');
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

/// Builds markdown renderers, including inline LaTeX support, scrollable
/// code blocks, and GFM <details>/<summary> collapsible sections.
Map<String, MarkdownElementBuilder> _markdownBuilders() {
  return {
    'latex': _LatexBuilder(),
    'pre': _ScrollableCodeBlockBuilder(),
    'details': _DetailsBuilder(),
  };
}

/// Block syntaxes used for viewer/editor previews — currently the GFM
/// `<details>`/`<summary>` collapsible section.
List<md.BlockSyntax> _markdownBlockSyntaxes() {
  return [_DetailsBlockSyntax()];
}

/// Shared MarkdownStyleSheet used by the note viewer and editor preview so
/// headers, code blocks, and horizontal rules render consistently. Headers
/// use a clearer size progression with padding-like spacing.
MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final base = MarkdownStyleSheet.fromTheme(theme);
  return base.copyWith(
    h1: theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.2,
    ),
    h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
    h2: theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
    h3: theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    h3Padding: const EdgeInsets.only(top: 18, bottom: 8),
    h4: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    h4Padding: const EdgeInsets.only(top: 14, bottom: 6),
    h5: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    h5Padding: const EdgeInsets.only(top: 12, bottom: 6),
    h6: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    h6Padding: const EdgeInsets.only(top: 10, bottom: 4),
    p: theme.textTheme.bodyLarge,
    pPadding: const EdgeInsets.symmetric(vertical: 4),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
      border: Border(
        left: BorderSide(color: colorScheme.primary, width: 4),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    codeblockDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    code: theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: colorScheme.surfaceContainerHighest,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: theme.dividerColor),
      ),
    ),
  );
}

/// Registers markdown inline syntaxes used across note viewers and previews.
List<md.InlineSyntax> _markdownInlineSyntaxes() {
  return [_LatexInlineSyntax()];
}

/// Lightweight GFM-spec validator: scans [markdown] for obvious structural
/// problems that would prevent the note from rendering correctly. Returns a
/// list of human-readable warnings; empty means the note is well-formed.
///
/// Intentionally conservative — this is a safety net, not a full parser.
List<String> _validateMarkdownSpec(String markdown) {
  if (markdown.isEmpty) return const [];
  final warnings = <String>[];
  final lines = markdown.split('\n');
  // Unclosed fenced code blocks.
  var fenceOpen = false;
  var fenceLine = 0;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      if (!fenceOpen) {
        fenceOpen = true;
        fenceLine = i + 1;
      } else {
        fenceOpen = false;
      }
    }
  }
  if (fenceOpen) {
    warnings.add('Unclosed code fence opened on line $fenceLine.');
  }
  // Headings with more than 6 `#`.
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'^(#{7,})\s').firstMatch(lines[i]);
    if (match != null) {
      warnings.add('Heading on line ${i + 1} exceeds 6 `#` characters.');
      break;
    }
  }
  // Inline code backticks: odd count of single backticks outside code fences.
  var inFence = false;
  var backticks = 0;
  var dollarSingles = 0;
  var dollarDoubles = 0;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '`') backticks += 1;
      if (c == r'$') {
        if (i + 1 < line.length && line[i + 1] == r'$') {
          dollarDoubles += 1;
          i += 1;
        } else if (i == 0 || line[i - 1] != r'\\') {
          dollarSingles += 1;
        }
      }
    }
  }
  if (backticks.isOdd) {
    warnings.add('Unmatched inline backtick (`) — close your inline code.');
  }
  if (dollarSingles.isOdd) {
    warnings.add(r'Unmatched inline math delimiter ($).');
  }
  if (dollarDoubles.isOdd) {
    warnings.add(r'Unmatched display math delimiter ($$).');
  }
  return warnings;
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

/// Shows a fullscreen dialog with a slide-from-right + fade entrance.
Future<T?> _showSlideInDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
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

/// Parses GFM `<details>` HTML blocks into a custom markdown element so they
/// can be rendered as collapsible [ExpansionTile]s. Accepts an optional
/// `<summary>` on the first or second line and treats the rest of the block
/// as nested markdown that will be re-rendered inside the expansion body.
class _DetailsBlockSyntax extends md.BlockSyntax {
  /// Match `<details` at the start of a line, optionally followed by attributes
  /// and/or `<summary>` on the same line.
  @override
  RegExp get pattern => RegExp(r'^\s{0,3}<details\b', caseSensitive: false);

  @override
  bool canEndBlock(md.BlockParser parser) => false;

  @override
  md.Node? parse(md.BlockParser parser) {
    var summary = 'Details';
    final bodyLines = <String>[];
    final summaryRegex = RegExp(r'<summary[^>]*>(.*?)</summary>',
        caseSensitive: false, dotAll: true);
    final closingRegex = RegExp(r'</details\s*>', caseSensitive: false);

    // Process the opening line — may contain <summary> and/or <details> attrs.
    final firstLine = parser.current.content;
    parser.advance();

    // Check if the opening line also has a <summary> tag.
    final firstMatch = summaryRegex.firstMatch(firstLine);
    if (firstMatch != null) {
      summary = firstMatch.group(1)?.trim() ?? summary;
    }
    // If the opening line also has </details> (single-line block), emit now.
    if (closingRegex.hasMatch(firstLine)) {
      var remaining = firstLine
          .replaceFirst(RegExp(r'<details\b[^>]*>', caseSensitive: false), '')
          .replaceFirst(summaryRegex, '')
          .replaceFirst(closingRegex, '')
          .trim();
      if (remaining.isNotEmpty) bodyLines.add(remaining);
      final element = md.Element('details', [md.Text(bodyLines.join('\n'))])
        ..attributes['summary'] = summary;
      return element;
    }

    while (!parser.isDone) {
      final line = parser.current.content;
      if (closingRegex.hasMatch(line)) {
        // Capture any content before the closing tag on the same line.
        final before = line
            .replaceFirst(closingRegex, '')
            .replaceFirst(summaryRegex, '')
            .trim();
        if (before.isNotEmpty) bodyLines.add(before);
        parser.advance();
        break;
      }
      final match = summaryRegex.firstMatch(line);
      if (match != null && summary == 'Details') {
        summary = match.group(1)?.trim() ?? summary;
        final remaining = line
            .replaceFirst(summaryRegex, '')
            .trim();
        if (remaining.isNotEmpty) bodyLines.add(remaining);
      } else {
        bodyLines.add(line);
      }
      parser.advance();
    }
    final element = md.Element('details', [md.Text(bodyLines.join('\n'))])
      ..attributes['summary'] = summary;
    return element;
  }
}

/// Renders `<details>` elements as a GitHub-style collapsible dropdown with
/// nested markdown inside the body.
class _DetailsBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final summary = element.attributes['summary'] ?? 'Details';
    final body = element.textContent.trim();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            summary,
            style: (preferredStyle ?? theme.textTheme.bodyLarge)
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          children: [
            if (body.isNotEmpty)
              MarkdownBody(
                data: body,
                selectable: true,
                builders: _markdownBuilders(),
                inlineSyntaxes: _markdownInlineSyntaxes(),
                blockSyntaxes: _markdownBlockSyntaxes(),
                styleSheet: _markdownStyleSheet(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders fenced code blocks inside a horizontal [SingleChildScrollView]
/// so long lines scroll instead of overflowing.
class _ScrollableCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent.trimRight();
    final codeStyle = (preferredStyle ?? parentStyle)?.copyWith(
          fontFamily: 'monospace',
        ) ??
        const TextStyle(fontFamily: 'monospace');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          code,
          style: codeStyle,
        ),
      ),
    );
  }
}
