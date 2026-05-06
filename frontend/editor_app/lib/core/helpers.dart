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

/// Coerces a draft's `editor_mode` to a backend-valid choice. The
/// backend `Note.editor_mode` accepts only `'G'` (GFM markdown),
/// `'B'` (Blocks), and `'P'` (Plain Text). Older local drafts
/// were seeded with `'M'` (markdown) / `'T'` (plain text) before
/// 0.1.83 — both alias to the new codes here so a one-time sync
/// after upgrade doesn't fail with `400 editor_mode is not a
/// valid choice`. Unknown codes fall through to `'P'`, matching
/// the backend default.
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
const _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.21');

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

/// Custom image builder for `MarkdownBody.sizedImageBuilder`.
/// Resolves `local://<note_uuid>/<filename>` URIs through
/// `LocalAttachmentStore` and renders the bytes via `Image.memory`.
/// For non-local URIs this falls through to an `Image.network` so
/// existing cloud-hosted attachments keep rendering with the
/// explicit width/height the markdown parser extracted.
///
/// Non-image bytes (e.g. a PDF attached to a local draft) render
/// as a small pill with the filename so the note stays readable.
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
    // Cap stagger index so items beyond the first visible batch animate
    // almost instantly instead of accumulating multi-second delays.
    final effectiveIndex = widget.index.clamp(0, 10);
    final delay = widget.staggerDelay * effectiveIndex;
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

/// Shows a fullscreen dialog with a slide-from-right + fade entrance and
/// a gaussian-blurred backdrop.
Future<T?> _showSlideInDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Stack(
        children: [
          // Blurred + tinted backdrop.
          Positioned.fill(
            child: GestureDetector(
              onTap: barrierDismissible ? () => Navigator.of(context).pop() : null,
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
          ),
          builder(context),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Curated set of Material Icons for course category selection.
/// Values are `Icons.*_outlined.codePoint` integers.
const Map<String, IconData> _kCourseIcons = {
  'Folder': Icons.folder_outlined,
  'School': Icons.school_outlined,
  'Science': Icons.science_outlined,
  'Book': Icons.menu_book_outlined,
  'Code': Icons.code_outlined,
  'Music': Icons.music_note_outlined,
  'Art': Icons.palette_outlined,
  'Math': Icons.calculate_outlined,
  'Language': Icons.translate_outlined,
  'History': Icons.history_edu_outlined,
  'Sports': Icons.sports_outlined,
  'Health': Icons.health_and_safety_outlined,
  'Business': Icons.business_center_outlined,
  'Engineering': Icons.engineering_outlined,
  'Psychology': Icons.psychology_outlined,
  'Globe': Icons.public_outlined,
  'Computer': Icons.computer_outlined,
  'Camera': Icons.camera_alt_outlined,
  'Star': Icons.star_outlined,
  'Heart': Icons.favorite_outlined,
  'Lightbulb': Icons.lightbulb_outlined,
  'Work': Icons.work_outlined,
  'Biotech': Icons.biotech_outlined,
  'Architecture': Icons.architecture_outlined,
  'Travel': Icons.flight_outlined,
  'Law': Icons.gavel_outlined,
  'Finance': Icons.account_balance_outlined,
  'Nature': Icons.eco_outlined,
  'Design': Icons.design_services_outlined,
  'Writing': Icons.edit_note_outlined,
};

/// Reverse lookup: codePoint -> constant IconData from the curated set.
/// Avoids non-constant IconData constructors that break icon tree-shaking.
final Map<int, IconData> _kCodePointToIcon = {
  for (final icon in _kCourseIcons.values) icon.codePoint: icon,
};

/// Resolves a codePoint integer to its constant IconData, with a fallback.
IconData _iconFromCodePoint(int? codePoint, {IconData fallback = Icons.school_outlined}) {
  if (codePoint == null) return fallback;
  return _kCodePointToIcon[codePoint] ?? fallback;
}

/// Resolves the icon for a course map. Falls back to type-based defaults.
IconData _courseIcon(Map<String, dynamic> course) {
  final codePoint = (course['icon'] as num?)?.toInt();
  if (codePoint != null) {
    return _iconFromCodePoint(codePoint);
  }
  if (course['is_uncategorized'] == true) return Icons.inbox_outlined;
  if (course['is_local_course'] == true) return Icons.folder_outlined;
  return Icons.school_outlined;
}

/// Shows a grid dialog for picking a course icon. Returns the selected
/// codePoint, or `null` if cancelled. Pass [currentCodePoint] to highlight
/// the currently selected icon.
Future<int?> _showIconPickerDialog(BuildContext context, {int? currentCodePoint}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Choose icon'),
        content: SizedBox(
          width: 360,
          child: GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: _kCourseIcons.entries.map((entry) {
              final isSelected = entry.value.codePoint == currentCodePoint;
              return Tooltip(
                message: entry.key,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(ctx).pop(entry.value.codePoint),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: colorScheme.primary, width: 2)
                          : null,
                    ),
                    child: Icon(
                      entry.value,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
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
                sizedImageBuilder: _localAttachmentImageBuilder,
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
