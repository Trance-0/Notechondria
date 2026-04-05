part of notechondria_frontend;

/// Mutable block row state used by the fallback block editor.
class _BlockDraft {
  _BlockDraft({
    required this.blockType,
    String text = '',
    String args = '',
  })  : textController = TextEditingController(text: text),
        argsController = TextEditingController(text: args);

  String blockType;
  final TextEditingController textController;
  final TextEditingController argsController;

  void dispose() {
    textController.dispose();
    argsController.dispose();
  }
}

/// Full-screen note editor supporting markdown preview and block fallback editing.
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({
    required this.note,
    required this.courses,
    required this.editorMode,
    required this.onSave,
    required this.onSnapshot,
    required this.onGetHistory,
    required this.onRestoreVersion,
    required this.onLogEvent,
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final String editorMode;
  final Future<Map<String, dynamic>> Function(
    int noteId,
    Map<String, dynamic> payload,
  ) onSave;
  final Future<Map<String, dynamic>> Function(int noteId, {String reason})
      onSnapshot;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId)
      onRestoreVersion;
  final ValueChanged<String> onLogEvent;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _titleController;
  late final _MarkdownHighlightingController _bodyController;
  final ScrollController _previewScrollController = ScrollController();
  Timer? _autosaveTimer;
  DateTime? _lastSavedAt;
  DateTime? _lastVersionSnapshotAt;
  String? _saveError;
  bool _dirty = false;
  bool _saving = false;
  int? _activeBlockIndex;
  late Map<String, dynamic> _note;
  late Map<String, dynamic> _metadata;
  late List<_BlockDraft> _blockDrafts;
  late String _editorMode;
  // When live-markdown mode is active, toggles between rendered preview
  // (true) and raw text editing (false). Typora-style full WYSIWYG is not
  // feasible in Flutter; this single-column toggle is the interim UX.
  bool _liveMarkdownPreview = true;

  @override
  void initState() {
    super.initState();
    _note = Map<String, dynamic>.from(widget.note);
    _metadata = _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '');
    _titleController = TextEditingController(
      text: _note['title']?.toString() ?? 'Untitled note',
    );
    _bodyController = _MarkdownHighlightingController(
      text: _bodyWithoutTitle(_note['content']?.toString() ?? ''),
    );
    _blockDrafts = _buildInitialBlockDrafts(_note);
    final noteEditorMode = _note['editor_mode']?.toString() ?? '';
    _editorMode = noteEditorMode.isNotEmpty ? noteEditorMode : widget.editorMode;
    _titleController.addListener(_handleChanged);
    _bodyController.addListener(_handleChanged);
    for (final block in _blockDrafts) {
      block.textController.addListener(_handleChanged);
      block.argsController.addListener(_handleChanged);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _previewScrollController.dispose();
    for (final block in _blockDrafts) {
      block.dispose();
    }
    super.dispose();
  }

  void _handleChanged() {
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 10), () {
      _save(reason: 'autosave');
    });
    setState(() {});
  }

  Future<void> _save({String reason = 'manual'}) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final autosaveLabel = _autosaveSnapshotReason();
      final updated = await widget.onSave(
        _note['id'] as int,
        {
          'title': _titleController.text.trim().isEmpty
              ? 'Untitled note'
              : _titleController.text.trim(),
          'description': _metadata['description'] ?? '',
          'course_id': _metadata['course_id'],
          'is_public': _metadata['is_public'] == true,
          'content': _editorMode == 'B'
              ? _composeBlockMarkdown()
              : _composeMarkdown(_titleController.text, _bodyController.text),
          if (_editorMode == 'B') 'blocks': _serializeBlocks(),
          'metadata_json': jsonEncode(_metadata),
          'editor_mode': _editorMode,
        },
      );
      _note = updated;
      _editorMode = updated['editor_mode']?.toString() ?? _editorMode;
      _dirty = false;
      _lastSavedAt = DateTime.now();
      widget.onLogEvent(
          "Editor saved '${_note['title']?.toString() ?? 'Untitled note'}' via $reason.");
      if (reason == 'autosave' && autosaveLabel != null) {
        await widget.onSnapshot(_note['id'] as int, reason: autosaveLabel);
        _lastVersionSnapshotAt = DateTime.now();
      }
    } catch (error) {
      _saveError = error.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }

  Future<void> _openDetails() async {
    widget.onLogEvent('Opened note metadata dialog.');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NoteMetadataDialog(
        note: _note,
        courses: widget.courses,
        metadata: _metadata,
        allowPublicToggle: (_note['id'] as int? ?? -1) > 0,
        onGetHistory: widget.onGetHistory,
        onRestoreVersion: widget.onRestoreVersion,
      ),
    );
    if (result == null) {
      return;
    }
    final restoredRaw = result['restored_note'];
    if (restoredRaw is Map) {
      final restored = Map<String, dynamic>.from(restoredRaw);
      final restoredMetadata =
          _decodeNoteMetadata(restored['metadata_json']?.toString() ?? '');
      _autosaveTimer?.cancel();
      setState(() {
        _note = restored;
        _metadata = restoredMetadata;
        _editorMode = restored['editor_mode']?.toString() ?? _editorMode;
        _titleController.text =
            restored['title']?.toString() ?? 'Untitled note';
        _bodyController.text =
            _bodyWithoutTitle(restored['content']?.toString() ?? '');
        _replaceBlockDrafts(restored);
        _dirty = false;
        _saveError = null;
        _lastSavedAt = DateTime.now();
      });
      return;
    }
    final metadata =
        Map<String, dynamic>.from(result['metadata'] as Map? ?? result);
    setState(() {
      _metadata = metadata;
    });
    await _save(reason: 'metadata');
  }

  List<_BlockDraft> _buildInitialBlockDrafts(Map<String, dynamic> note) {
    final blocks = (note['blocks'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((block) => block['block_type']?.toString() != 'T')
        .toList();
    if (blocks.isEmpty) {
      return [
        _BlockDraft(
          blockType: 'N',
          text: _bodyWithoutTitle(note['content']?.toString() ?? ''),
        ),
      ];
    }
    return blocks
        .map(
          (block) => _BlockDraft(
            blockType: block['block_type']?.toString() ?? 'N',
            text: block['text']?.toString() ?? '',
            args: block['args']?.toString() ?? '',
          ),
        )
        .toList();
  }

  void _replaceBlockDrafts(Map<String, dynamic> note) {
    for (final block in _blockDrafts) {
      block.dispose();
    }
    _blockDrafts = _buildInitialBlockDrafts(note);
    for (final block in _blockDrafts) {
      block.textController.addListener(_handleChanged);
      block.argsController.addListener(_handleChanged);
    }
    _activeBlockIndex = null;
  }

  String? _autosaveSnapshotReason() {
    final now = DateTime.now();
    final last = _lastVersionSnapshotAt;
    if (last == null || now.difference(last) >= const Duration(hours: 1)) {
      _lastVersionSnapshotAt = now;
      return 'autosave_1h';
    }
    if (now.difference(last) >= const Duration(minutes: 10)) {
      _lastVersionSnapshotAt = now;
      return 'autosave_10m';
    }
    if (now.difference(last) >= const Duration(minutes: 1)) {
      _lastVersionSnapshotAt = now;
      return 'autosave_1m';
    }
    return null;
  }

  List<Map<String, dynamic>> _serializeBlocks() {
    final rows = <Map<String, dynamic>>[
      {
        'block_type': 'T',
        'text': _titleController.text.trim().isEmpty
            ? 'Untitled note'
            : _titleController.text.trim(),
      },
    ];
    for (final block in _blockDrafts) {
      rows.add({
        'block_type': block.blockType,
        'text': block.textController.text,
        'args': block.argsController.text,
      });
    }
    return rows;
  }

  String _composeBlockMarkdown() {
    final rows = _serializeBlocks();
    return _markdownFromBlockDraftRows(rows);
  }

  String _previewMarkdown() {
    if (_editorMode == 'B') {
      return _composeBlockMarkdown();
    }
    return _composeMarkdown(_titleController.text, _bodyController.text);
  }

  void _setEditorMode(String mode) {
    if (_editorMode == mode) {
      return;
    }
    if (_editorMode == 'B' && mode != 'B') {
      _bodyController.text = _bodyWithoutTitle(_composeBlockMarkdown());
    } else if (_editorMode != 'B' && mode == 'B') {
      _replaceBlockDrafts({
        'content': _composeMarkdown(_titleController.text, _bodyController.text),
        'blocks': const [],
      });
    }
    setState(() {
      _editorMode = mode;
    });
    widget.onLogEvent('Editor mode switched to $mode.');
    _handleChanged();
  }

  /// Inserts a new block at [index] with the chosen [type]. Powers the
  /// Notion-style inline add menu that appears between existing blocks.
  void _insertBlockAt(int index, {String type = 'N'}) {
    final draft = _BlockDraft(blockType: type);
    draft.textController.addListener(_handleChanged);
    draft.argsController.addListener(_handleChanged);
    setState(() {
      _blockDrafts.insert(index, draft);
      _activeBlockIndex = index;
    });
    _handleChanged();
  }

  void _removeBlock(int index) {
    final draft = _blockDrafts.removeAt(index);
    draft.dispose();
    setState(() {
      if (_activeBlockIndex == index) {
        _activeBlockIndex = null;
      }
    });
    _handleChanged();
  }

  Future<void> _showBlockMenu(int index, TapDownDetails? details) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          details?.globalPosition ?? const Offset(0, 0),
          details?.globalPosition ?? const Offset(0, 0),
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'N', child: Text('Paragraph')),
        PopupMenuItem(value: 'S', child: Text('Heading')),
        PopupMenuItem(value: 'L', child: Text('List')),
        PopupMenuItem(value: 'C', child: Text('Code')),
        PopupMenuItem(value: 'Q', child: Text('Quote')),
        PopupMenuItem(value: 'U', child: Text('Link')),
        PopupMenuItem(value: 'I', child: Text('Image')),
        PopupMenuItem(value: 'delete', child: Text('Delete block')),
      ],
    );
    if (selected == null) {
      return;
    }
    if (selected == 'delete') {
      _removeBlock(index);
      return;
    }
    setState(() {
      _blockDrafts[index].blockType = selected;
      _activeBlockIndex = index;
    });
    _handleChanged();
  }

  /// Notion-style inline "+" button that appears on hover between blocks.
  /// Tapping it opens a popup menu to insert a new block of the chosen type
  /// at the given position.
  Widget _buildInsertZone(int index) {
    return _BlockInsertZone(
      onInsert: (type) => _insertBlockAt(index, type: type),
    );
  }

  Widget _buildBlockEditor() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            // +1 for the trailing insert zone after the last block.
            itemCount: _blockDrafts.length * 2 + 1,
            itemBuilder: (context, rawIndex) {
              if (rawIndex.isEven) {
                return _buildInsertZone(rawIndex ~/ 2);
              }
              final index = rawIndex ~/ 2;
              final block = _blockDrafts[index];
              final needsArgs = block.blockType == 'S' ||
                  block.blockType == 'C' ||
                  block.blockType == 'U' ||
                  block.blockType == 'I';
              return _buildBlockCard(index, block, needsArgs);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBlockCard(int index, _BlockDraft block, bool needsArgs) {
    return GestureDetector(
      onLongPressStart: (details) => _showBlockMenu(
        index,
        TapDownDetails(globalPosition: details.globalPosition),
      ),
      onSecondaryTapDown: (details) => _showBlockMenu(index, details),
      child: Card(
        margin: EdgeInsets.zero,
        color: _activeBlockIndex == index
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(
                  Theme.of(context).brightness == Brightness.dark ? 0.44 : 0.72,
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_blockTypeLabel(block.blockType),
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _showBlockMenu(index, null),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ],
              ),
              if (needsArgs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: block.argsController,
                    onTap: () => setState(() => _activeBlockIndex = index),
                    decoration: InputDecoration(
                      labelText: block.blockType == 'S'
                          ? 'Heading token (## or ###)'
                          : block.blockType == 'C'
                              ? 'Language'
                              : 'URL',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              TextField(
                controller: block.textController,
                onTap: () => setState(() => _activeBlockIndex = index),
                maxLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write block content...',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-width live markdown editor. Single column: shows rendered preview
  /// by default, tap the "Edit" toggle to switch into the raw editor. This is
  /// the interim implementation until true Typora-style inline rendering
  /// lands.
  Widget _buildLiveMarkdownEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Preview'),
                  icon: Icon(Icons.visibility_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Edit'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_liveMarkdownPreview},
              onSelectionChanged: (values) {
                setState(() {
                  _liveMarkdownPreview = values.first;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _liveMarkdownPreview
                ? SelectionArea(
                    child: Scrollbar(
                      controller: _previewScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _previewScrollController,
                        padding: const EdgeInsets.all(20),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth > 40
                                    ? constraints.maxWidth - 40
                                    : constraints.maxWidth,
                              ),
                              child: MarkdownBody(
                                data: _previewMarkdown(),
                                selectable: true,
                                builders: _markdownBuilders(),
                                inlineSyntaxes: _markdownInlineSyntaxes(),
                                blockSyntaxes: _markdownBlockSyntaxes(),
                                styleSheet: _markdownStyleSheet(context),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Write your note in markdown...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLiveMarkdown = _editorMode == 'G';
    final showBlockEditor = _editorMode == 'B';
    // Run a cheap GFM spec check against the current body so obvious
    // violations (unclosed fence, unmatched backtick, oversized heading) are
    // surfaced immediately below the title.
    final specWarnings = _editorMode == 'B'
        ? const <String>[]
        : _validateMarkdownSpec(_bodyController.text);
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _titleController,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                              border: InputBorder.none, hintText: 'Title'),
                        ),
                        if (specWarnings.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: Text(
                              specWarnings.join(' \u2022 '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SaveStatus(
                        lastSavedAt: _lastSavedAt,
                        errorMessage: _saveError,
                        saving: _saving,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _editorMode,
                      items: const [
                        DropdownMenuItem(
                            value: 'P', child: Text('Plain text editor')),
                        DropdownMenuItem(
                            value: 'G', child: Text('Live markdown editor')),
                        DropdownMenuItem(
                            value: 'B', child: Text('Block editor')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _setEditorMode(value);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Editor mode',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                      onPressed: _openDetails,
                      icon: const Icon(Icons.more_horiz)),
                  IconButton(
                    onPressed: () async {
                      _autosaveTimer?.cancel();
                      if (_dirty) {
                        await _save(reason: 'close');
                        await widget.onSnapshot(_note['id'] as int,
                            reason: 'quit');
                      }
                      widget.onLogEvent('Editor closed.');
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: showBlockEditor
                    ? _buildBlockEditor()
                    : isLiveMarkdown
                        ? _buildLiveMarkdownEditor()
                        : TextField(
                            controller: _bodyController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText: 'Write your note...',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Notion-style inline insert zone: a slim hover-revealed strip between
/// blocks. On hover (or tap on mobile) a "+" button appears and, when
/// clicked, opens a popup menu listing block types to insert at that slot.
class _BlockInsertZone extends StatefulWidget {
  const _BlockInsertZone({required this.onInsert});

  final void Function(String type) onInsert;

  @override
  State<_BlockInsertZone> createState() => _BlockInsertZoneState();
}

class _BlockInsertZoneState extends State<_BlockInsertZone> {
  bool _hovering = false;

  static const List<({String type, String label, IconData icon})> _options = [
    (type: 'N', label: 'Paragraph', icon: Icons.notes_outlined),
    (type: 'S', label: 'Heading', icon: Icons.title),
    (type: 'L', label: 'List', icon: Icons.format_list_bulleted),
    (type: 'Q', label: 'Quote', icon: Icons.format_quote),
    (type: 'C', label: 'Code', icon: Icons.code),
    (type: 'U', label: 'Link', icon: Icons.link),
    (type: 'I', label: 'Image', icon: Icons.image_outlined),
  ];

  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final option in _options)
          PopupMenuItem<String>(
            value: option.type,
            child: Row(
              children: [
                Icon(option.icon, size: 18),
                const SizedBox(width: 8),
                Text(option.label),
              ],
            ),
          ),
      ],
    );
    if (selected != null) widget.onInsert(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _openMenu(context, details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _hovering ? 28 : 10,
          alignment: Alignment.center,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _hovering ? 1 : 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Add block',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
        final bulletMatch =
            RegExp(r'^(\s*[-*+]\s+)(.*)$').firstMatch(line);
        final orderedMatch =
            RegExp(r'^(\s*\d+\.\s+)(.*)$').firstMatch(line);
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

/// Returns the human-readable block label for the fallback block editor.
String _blockTypeLabel(String type) {
  switch (type) {
    case 'S':
      return 'Heading';
    case 'L':
      return 'List';
    case 'C':
      return 'Code';
    case 'Q':
      return 'Quote';
    case 'U':
      return 'Link';
    case 'I':
      return 'Image';
    default:
      return 'Paragraph';
  }
}

/// Rebuilds markdown text from the block-editor rows for backend persistence.
String _markdownFromBlockDraftRows(List<Map<String, dynamic>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    final type = row['block_type']?.toString() ?? 'N';
    final text = row['text']?.toString() ?? '';
    final args = row['args']?.toString() ?? '';
    switch (type) {
      case 'T':
        buffer.writeln('# $text');
        break;
      case 'S':
        buffer.writeln('${args.isEmpty ? '##' : args} $text');
        break;
      case 'L':
        for (final line in text.split('\n')) {
          if (line.trim().isNotEmpty) {
            buffer.writeln('- ${line.trim()}');
          }
        }
        break;
      case 'C':
        buffer.writeln('```$args');
        buffer.writeln(text);
        buffer.writeln('```');
        break;
      case 'Q':
        for (final line in text.split('\n')) {
          if (line.trim().isNotEmpty) {
            buffer.writeln('> ${line.trim()}');
          }
        }
        break;
      case 'U':
        buffer.writeln(args.isEmpty ? text : '[$text]($args)');
        break;
      case 'I':
        buffer.writeln(args.isEmpty ? text : '![$text]($args)');
        break;
      default:
        buffer.writeln(text);
    }
    buffer.writeln();
  }
  return buffer.toString().trim();
}
