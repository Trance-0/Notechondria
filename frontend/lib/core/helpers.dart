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

String _defaultApiBaseUrl() {
  if (kIsWeb) {
    return '/api/v1';
  }
  return 'http://localhost:9080/api/v1';
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

/// Builds markdown renderers, including inline LaTeX support.
Map<String, MarkdownElementBuilder> _markdownBuilders() {
  return {'latex': _LatexBuilder()};
}

/// Registers markdown inline syntaxes used across note viewers and previews.
List<md.InlineSyntax> _markdownInlineSyntaxes() {
  return [_LatexInlineSyntax()];
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
