import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Localized display name for a log level (used in the filter chips +
/// empty states). The log ROWS keep `level.label` (English) so the
/// structured log line stays greppable.
String _localizedLevel(AppLocalizations l10n, DebugLogLevel level) {
  switch (level) {
    case DebugLogLevel.error:
      return l10n.logLevelError;
    case DebugLogLevel.warning:
      return l10n.logLevelWarning;
    case DebugLogLevel.info:
      return l10n.logLevelInfo;
    case DebugLogLevel.debug:
      return l10n.logLevelDebug;
  }
}

/// Severity label attached to a debug log entry. The splash / settings UI
/// renders each level with a distinct chip color; the terminal filter chip
/// row lets the user narrow to a single level.
enum DebugLogLevel { error, warning, info, debug }

extension DebugLogLevelLabel on DebugLogLevel {
  String get label {
    switch (this) {
      case DebugLogLevel.error:
        return 'Error';
      case DebugLogLevel.warning:
        return 'Warning';
      case DebugLogLevel.info:
        return 'Info';
      case DebugLogLevel.debug:
        return 'Debug';
    }
  }

  /// Single-letter token used when serializing to the persisted
  /// `[ts] [L] source — message (Xms)` string form.
  String get sentinel {
    switch (this) {
      case DebugLogLevel.error:
        return 'E';
      case DebugLogLevel.warning:
        return 'W';
      case DebugLogLevel.info:
        return 'I';
      case DebugLogLevel.debug:
        return 'D';
    }
  }

  static DebugLogLevel? fromSentinel(String s) {
    switch (s.toUpperCase()) {
      case 'E':
        return DebugLogLevel.error;
      case 'W':
        return DebugLogLevel.warning;
      case 'I':
        return DebugLogLevel.info;
      case 'D':
        return DebugLogLevel.debug;
    }
    return null;
  }
}

/// One debug log row. [source] is typically `"ClassName.methodName"` so the
/// line reads like `Editor_LoadInitialData: Loaded 4 courses (123ms)`.
/// [durationMs] is only set for timed operations (e.g. backend requests).
class DebugLogEntry {
  DebugLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.durationMs,
  });

  final DateTime timestamp;
  final DebugLogLevel level;
  final String source;
  final String message;
  final int? durationMs;

  String toPersistedString() {
    final durationPart = durationMs != null ? ' (${durationMs}ms)' : '';
    return '[${timestamp.toIso8601String()}] '
        '[${level.sentinel}] '
        '${source.isEmpty ? '-' : source} '
        '\u2014 $message$durationPart';
  }

  /// Parses a persisted string back into an entry. Legacy strings of the
  /// shape `[ts] plain message` (no level sentinel) decode as Debug level
  /// with an empty source so existing stored logs stay readable.
  static DebugLogEntry fromPersistedString(String raw) {
    final fallback = DebugLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: DebugLogLevel.debug,
      source: '',
      message: raw,
    );
    final tsMatch = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(raw);
    if (tsMatch == null) return fallback;
    DateTime ts;
    try {
      ts = DateTime.parse(tsMatch.group(1)!).toUtc();
    } catch (_) {
      ts = DateTime.now().toUtc();
    }
    final after = tsMatch.group(2) ?? '';
    final levelMatch = RegExp(r'^\[([EWID])\]\s*(.*)$').firstMatch(after);
    if (levelMatch == null) {
      return DebugLogEntry(
        timestamp: ts,
        level: DebugLogLevel.debug,
        source: '',
        message: after,
      );
    }
    final level = DebugLogLevelLabel.fromSentinel(levelMatch.group(1)!) ??
        DebugLogLevel.debug;
    final rest = levelMatch.group(2) ?? '';
    final sepIdx = rest.indexOf('\u2014');
    if (sepIdx < 0) {
      return DebugLogEntry(
        timestamp: ts,
        level: level,
        source: '',
        message: rest.trim(),
      );
    }
    final source = rest.substring(0, sepIdx).trim();
    var message = rest.substring(sepIdx + 1).trim();
    int? durationMs;
    final durMatch = RegExp(r'\s*\((\d+)ms\)\s*$').firstMatch(message);
    if (durMatch != null) {
      durationMs = int.tryParse(durMatch.group(1)!);
      message = message.substring(0, durMatch.start).trim();
    }
    return DebugLogEntry(
      timestamp: ts,
      level: level,
      source: source == '-' ? '' : source,
      message: message,
      durationMs: durationMs,
    );
  }
}

/// Holds the live list of log entries. Rebuilds the log card when entries
/// are appended or cleared. Also exposes the host app's in-memory "cache"
/// snapshot — a map of named buckets (e.g. `settings`, `drafts`, `courses`,
/// `stats`, `cache`, `logs`) — which the embedded terminal navigates with
/// `ls` / `cd`.
class DebugLogController extends ChangeNotifier {
  DebugLogController({int maxEntries = 200}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final List<DebugLogEntry> _entries = [];
  Map<String, Object?> Function()? _cacheProvider;

  List<DebugLogEntry> get entries => List<DebugLogEntry>.unmodifiable(_entries);

  /// Replaces the full list (e.g. on first load from persistence).
  void replaceAll(Iterable<DebugLogEntry> items) {
    _entries
      ..clear()
      ..addAll(items);
    _trim();
    notifyListeners();
  }

  /// Prepends a new entry and trims the tail.
  void append(DebugLogEntry entry) {
    _entries.insert(0, entry);
    _trim();
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// Host supplies a callback returning the current in-memory buckets the
  /// terminal can navigate. Values may be maps, lists, or scalars; the
  /// terminal prints leaf keys for maps and `[N items]` counts for lists.
  void bindCacheProvider(Map<String, Object?> Function()? provider) {
    _cacheProvider = provider;
  }

  Map<String, Object?> snapshotCache() {
    final provider = _cacheProvider;
    if (provider == null) return const {};
    try {
      return provider();
    } catch (_) {
      return const {};
    }
  }

  void _trim() {
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
  }
}

/// Compact debug log card: filter chips per level, scrollable log list, and
/// a terminal input below supporting `ls`, `cd`, and `clear`.
/// Outcome of a backend ping issued from the debug-log terminal.
/// Returned by `DebugLogCard.onPing` so the card can render a latency
/// line. On success, `latencyMs` is the client-measured round trip in
/// milliseconds and `detail` is a short human-readable summary
/// (typically `'pong'` or the backend's `service` field). On failure,
/// `ok` is false and `detail` carries the cause string.
class PingResult {
  const PingResult({
    required this.ok,
    required this.latencyMs,
    required this.detail,
  });

  final bool ok;
  final int latencyMs;
  final String detail;
}

class DebugLogCard extends StatefulWidget {
  const DebugLogCard({
    super.key,
    required this.controller,
    required this.title,
    required this.summary,
    this.onCopyLogs,
    this.onPing,
    this.initialLevelFilter = DebugLogLevel.debug,
  });

  final DebugLogController controller;
  final String title;
  final String summary;
  final Future<void> Function()? onCopyLogs;

  /// Hook for the terminal's `ping` command. Each app wires this to
  /// a lightweight HTTP GET against the backend's `/api/v1/ping/`
  /// endpoint. Returning `null` means "ping is unsupported in this
  /// host"; returning a `PingResult` drives the terminal output.
  final Future<PingResult> Function()? onPing;

  /// Minimum severity shown initially. `debug` means "show everything".
  final DebugLogLevel initialLevelFilter;

  @override
  State<DebugLogCard> createState() => _DebugLogCardState();
}

class _DebugLogCardState extends State<DebugLogCard> {
  late DebugLogLevel _minLevel;
  String? _sourceFilter;
  final TextEditingController _terminalController = TextEditingController();
  final ScrollController _terminalOutputController = ScrollController();
  final FocusNode _terminalFocus = FocusNode();
  bool _filtersExpanded = false;
  final List<String> _terminalOutput = [
    'nchron-shell: type `ls`, `cd <key>`, `cd ..`, `ping`, or `clear`.',
  ];
  List<String> _terminalPath = const [];

  @override
  void initState() {
    super.initState();
    _minLevel = widget.initialLevelFilter;
    widget.controller.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEntriesChanged);
    _terminalController.dispose();
    _terminalOutputController.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  void _onEntriesChanged() {
    if (mounted) setState(() {});
  }

  bool _passesFilter(DebugLogEntry e) {
    final sourceMatches = _sourceFilter == null || e.source == _sourceFilter;
    return sourceMatches && e.level.index <= _minLevel.index;
  }

  Color _levelColor(ThemeData theme, DebugLogLevel level) {
    switch (level) {
      case DebugLogLevel.error:
        return theme.colorScheme.error;
      case DebugLogLevel.warning:
        return Colors.orange.shade700;
      case DebugLogLevel.info:
        return theme.colorScheme.primary;
      case DebugLogLevel.debug:
        return theme.colorScheme.onSurface.withValues(alpha: 0.6);
    }
  }

  void _runCommand(String raw) {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;
    setState(() {
      _terminalOutput.add('\$ ${_prompt()} $cmd');
    });
    if (cmd == 'clear') {
      widget.controller.clear();
      setState(() {
        _terminalOutput
          ..clear()
          ..add('cleared debug log.');
      });
      return;
    }
    if (cmd == 'ls') {
      _handleLs();
    } else if (cmd == 'pwd') {
      setState(() {
        _terminalOutput.add('/${_terminalPath.join('/')}');
      });
    } else if (cmd.startsWith('cd')) {
      final arg = cmd.substring(2).trim();
      _handleCd(arg);
    } else if (cmd == 'ping') {
      _handlePing();
    } else if (cmd == 'help' || cmd == '?') {
      setState(() {
        _terminalOutput
            .add('commands: ls, cd <key>, cd .., pwd, ping, clear, help');
      });
    } else {
      setState(() {
        _terminalOutput.add('unknown command: $cmd');
      });
    }
    _terminalController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalOutputController.hasClients) {
        _terminalOutputController.jumpTo(
          _terminalOutputController.position.maxScrollExtent,
        );
      }
    });
  }

  String _prompt() {
    if (_terminalPath.isEmpty) return '/';
    return '/${_terminalPath.join('/')}';
  }

  Object? _resolveAt(List<String> path) {
    Object? cursor = widget.controller.snapshotCache();
    for (final part in path) {
      if (cursor is Map) {
        if (!cursor.containsKey(part)) return null;
        cursor = cursor[part];
      } else if (cursor is List) {
        final idx = int.tryParse(part);
        if (idx == null || idx < 0 || idx >= cursor.length) return null;
        cursor = cursor[idx];
      } else {
        return null;
      }
    }
    return cursor;
  }

  void _handleLs() {
    final node = _resolveAt(_terminalPath);
    final lines = <String>[];
    if (node is Map) {
      if (node.isEmpty) {
        lines.add('(empty)');
      } else {
        node.forEach((key, value) {
          lines.add('${key.toString().padRight(24)} ${_summarize(value)}');
        });
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        lines.add('${i.toString().padRight(24)} ${_summarize(node[i])}');
      }
    } else {
      lines.add(_summarize(node));
    }
    setState(() {
      _terminalOutput.addAll(lines);
    });
  }

  Future<void> _handlePing() async {
    if (widget.onPing == null) {
      setState(() {
        _terminalOutput
            .add('ping: no backend ping handler wired on this host.');
      });
      return;
    }
    setState(() {
      _terminalOutput.add('pinging backend...');
    });
    try {
      final result = await widget.onPing!();
      if (!mounted) return;
      setState(() {
        if (result.ok) {
          _terminalOutput.add('pong: ${result.latencyMs}ms — ${result.detail}');
        } else {
          _terminalOutput
              .add('ping failed: ${result.latencyMs}ms — ${result.detail}');
        }
      });
    } catch (error) {
      if (!mounted) return;
      final cause = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _terminalOutput.add('ping failed: $cause');
      });
    }
  }

  void _handleCd(String arg) {
    if (arg.isEmpty || arg == '/') {
      setState(() {
        _terminalPath = const [];
      });
      return;
    }
    if (arg == '..') {
      setState(() {
        if (_terminalPath.isNotEmpty) {
          _terminalPath = _terminalPath.sublist(0, _terminalPath.length - 1);
        }
      });
      return;
    }
    final candidate = [..._terminalPath, arg];
    final node = _resolveAt(candidate);
    if (node == null) {
      setState(() {
        _terminalOutput.add('no such key: $arg');
      });
      return;
    }
    if (node is! Map && node is! List) {
      setState(() {
        _terminalOutput.add('$arg is a leaf: ${_summarize(node)}');
      });
      return;
    }
    setState(() {
      _terminalPath = candidate;
    });
  }

  String _summarize(Object? value) {
    if (value == null) return 'null';
    if (value is Map) return '{${value.length} keys}';
    if (value is List) return '[${value.length} items]';
    if (value is String) {
      final flat = value.replaceAll('\n', ' ');
      return flat.length > 60 ? '"${flat.substring(0, 57)}..."' : '"$flat"';
    }
    return value.toString();
  }

  Future<void> _copyAll() async {
    if (widget.onCopyLogs != null) {
      await widget.onCopyLogs!();
      return;
    }
    final visible = widget.controller.entries
        .where(_passesFilter)
        .map((e) => e.toPersistedString())
        .join('\n');
    await Clipboard.setData(ClipboardData(text: visible));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sources = widget.controller.entries
        .map((e) => e.source)
        .where((source) => source.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (_sourceFilter != null && !sources.contains(_sourceFilter)) {
      _sourceFilter = null;
    }
    final entries =
        widget.controller.entries.where(_passesFilter).toList(growable: false);
    final filterSummary = _sourceFilter == null
        ? '${_localizedLevel(l10n, _minLevel)}+ / ${l10n.debugAllSources}'
        : '${_localizedLevel(l10n, _minLevel)}+ / ${_sourceLabel(_sourceFilter!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(widget.summary)),
                TextButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.debugCopyLogs),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _filtersExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        filterSummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(l10n.debugFilters),
                  ],
                ),
              ),
            ),
            if (_filtersExpanded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final level in DebugLogLevel.values)
                    ChoiceChip(
                      label: Text(_localizedLevel(l10n, level)),
                      selected: _minLevel == level,
                      onSelected: (_) => setState(() => _minLevel = level),
                      labelStyle: TextStyle(color: _levelColor(theme, level)),
                    ),
                ],
              ),
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.debugAllSources),
                      selected: _sourceFilter == null,
                      onSelected: (_) => setState(() => _sourceFilter = null),
                    ),
                    for (final source in sources)
                      ChoiceChip(
                        label: Text(_sourceLabel(source)),
                        selected: _sourceFilter == source,
                        onSelected: (_) =>
                            setState(() => _sourceFilter = source),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        widget.controller.entries.isEmpty
                            ? l10n.debugNoLogs
                            : l10n.debugNoEntriesAtLevel(
                                _localizedLevel(l10n, _minLevel)),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return _LogRow(
                            entry: e, color: _levelColor(theme, e.level));
                      },
                    ),
            ),
            const SizedBox(height: 8),
            _TerminalBlock(
              output: _terminalOutput,
              input: _terminalController,
              focus: _terminalFocus,
              onSubmit: _runCommand,
              prompt: _prompt(),
              scrollController: _terminalOutputController,
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String source) {
    const prefix = 'Editor.';
    final label =
        source.startsWith(prefix) ? source.substring(prefix.length) : source;
    return label.length > 26 ? '${label.substring(0, 23)}...' : label;
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.color});

  final DebugLogEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace', color: theme.colorScheme.onSurface);
    final levelStyle =
        baseStyle?.copyWith(color: color, fontWeight: FontWeight.w700);
    final dim = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final sourceStyle = baseStyle?.copyWith(color: dim);
    final durationPart =
        entry.durationMs != null ? '  (${entry.durationMs}ms)' : '';
    final hh = entry.timestamp.toLocal().hour.toString().padLeft(2, '0');
    final mm = entry.timestamp.toLocal().minute.toString().padLeft(2, '0');
    final ss = entry.timestamp.toLocal().second.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$hh:$mm:$ss  ', style: sourceStyle),
            TextSpan(
              text: entry.level.label.padRight(7),
              style: levelStyle,
            ),
            if (entry.source.isNotEmpty)
              TextSpan(text: '${entry.source}: ', style: sourceStyle),
            TextSpan(text: entry.message),
            if (durationPart.isNotEmpty)
              TextSpan(text: durationPart, style: sourceStyle),
          ],
        ),
      ),
    );
  }
}

class _TerminalBlock extends StatelessWidget {
  const _TerminalBlock({
    required this.output,
    required this.input,
    required this.focus,
    required this.onSubmit,
    required this.prompt,
    required this.scrollController,
  });

  final List<String> output;
  final TextEditingController input;
  final FocusNode focus;
  final ValueChanged<String> onSubmit;
  final String prompt;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final monoStyle = theme.textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace', color: theme.colorScheme.onSurface);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 90,
            child: ListView.builder(
              controller: scrollController,
              padding: EdgeInsets.zero,
              itemCount: output.length,
              itemBuilder: (context, i) =>
                  SelectableText(output[i], style: monoStyle),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('$prompt\u00a0>', style: monoStyle),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: input,
                  focusNode: focus,
                  style: monoStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'ls | cd <key> | clear',
                  ),
                  onSubmitted: onSubmit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
