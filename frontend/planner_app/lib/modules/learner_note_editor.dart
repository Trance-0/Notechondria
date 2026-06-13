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
    this.onUploadCover,
    this.onDeleteCover,
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
  final Future<Map<String, dynamic>> Function(XFile file)? onUploadCover;
  final Future<Map<String, dynamic>> Function()? onDeleteCover;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
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

  @override
  void initState() {
    super.initState();
    _note = Map<String, dynamic>.from(widget.note);
    _metadata = _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '');
    _titleController = TextEditingController(
      text: _note['title']?.toString() ?? 'Untitled note',
    );
    _bodyController = TextEditingController(
      text: _bodyWithoutTitle(_note['content']?.toString() ?? ''),
    );
    _blockDrafts = _buildInitialBlockDrafts(_note);
    final noteEditorMode = _note['editor_mode']?.toString() ?? '';
    _editorMode =
        noteEditorMode.isNotEmpty ? noteEditorMode : widget.editorMode;
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
          'metadata_json': jsonEncode(
            // `custom_meta` lives on its own column on the backend.
            // Stripping it from the system metadata blob avoids
            // double-storing the same key/value pairs.
            Map<String, dynamic>.from(_metadata)..remove('custom_meta'),
          ),
          'custom_meta': _metadata['custom_meta']?.toString() ?? '',
          'editor_mode': _editorMode,
        },
      );
      _note = updated;
      _editorMode = updated['editor_mode']?.toString() ?? _editorMode;
      _dirty = false;
      _lastSavedAt = DateTime.now();
      widget.onLogEvent("Note saved from editor: Planner.UI/editor.save \u2014 "
          "'${_note['title']?.toString() ?? 'Untitled note'}' persisted via $reason.");
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
    widget.onLogEvent(
        'Note metadata dialog opened: Planner.UI/editor.metadata \u2014 '
        'user requested metadata edit from the editor toolbar.');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _NoteMetadataDialog(
        note: _note,
        courses: widget.courses,
        metadata: _metadata,
        allowPublicToggle: (_note['id'] as int? ?? -1) > 0,
        onGetHistory: widget.onGetHistory,
        onRestoreVersion: widget.onRestoreVersion,
        onUploadCover: widget.onUploadCover,
        onDeleteCover: widget.onDeleteCover,
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
        'content':
            _composeMarkdown(_titleController.text, _bodyController.text),
        'blocks': const [],
      });
    }
    setState(() {
      _editorMode = mode;
    });
    widget.onLogEvent('Editor mode switched: Planner.UI/editor.mode \u2014 '
        'active mode set to $mode.');
    _handleChanged();
  }

  void _addBlock({String type = 'N'}) {
    final draft = _BlockDraft(blockType: type);
    draft.textController.addListener(_handleChanged);
    draft.argsController.addListener(_handleChanged);
    setState(() {
      _blockDrafts.add(draft);
      _activeBlockIndex = _blockDrafts.length - 1;
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

  void _wrapActiveSelection(String prefix, String suffix) {
    final index = _activeBlockIndex;
    if (index == null || index < 0 || index >= _blockDrafts.length) {
      return;
    }
    final controller = _blockDrafts[index].textController;
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final selectedText = text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    controller.value = controller.value.copyWith(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  Widget _buildBlockEditor() {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
                onPressed: () => _wrapActiveSelection('**', '**'),
                child: const Text('Bold')),
            OutlinedButton(
                onPressed: () => _wrapActiveSelection('_', '_'),
                child: const Text('Italic')),
            OutlinedButton(
                onPressed: () => _wrapActiveSelection('~~', '~~'),
                child: const Text('Strike')),
            OutlinedButton(
                onPressed: () => _addBlock(),
                child: const Text('Add paragraph')),
            OutlinedButton(
                onPressed: () => _addBlock(type: 'L'),
                child: const Text('Add list')),
            OutlinedButton(
                onPressed: () => _addBlock(type: 'C'),
                child: const Text('Add code')),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _blockDrafts.length,
            itemBuilder: (context, index) {
              final block = _blockDrafts[index];
              final needsArgs = block.blockType == 'S' ||
                  block.blockType == 'C' ||
                  block.blockType == 'U' ||
                  block.blockType == 'I';
              return GestureDetector(
                onLongPressStart: (details) => _showBlockMenu(
                  index,
                  TapDownDetails(globalPosition: details.globalPosition),
                ),
                onSecondaryTapDown: (details) => _showBlockMenu(index, details),
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: _activeBlockIndex == index
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(
                            Theme.of(context).brightness == Brightness.dark
                                ? 0.44
                                : 0.72,
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
                              onTap: () =>
                                  setState(() => _activeBlockIndex = index),
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
                          onTap: () =>
                              setState(() => _activeBlockIndex = index),
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
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMarkdownPreview() {
    return SelectionArea(
      child: Scrollbar(
        controller: _previewScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _previewScrollController,
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth > 32
                      ? constraints.maxWidth - 32
                      : constraints.maxWidth,
                ),
                child: MarkdownBody(
                  data: _previewMarkdown(),
                  selectable: true,
                  builders: _markdownBuilders(),
                  sizedImageBuilder: _localAttachmentImageBuilder,
                  inlineSyntaxes: _markdownInlineSyntaxes(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPreview = _editorMode == 'G';
    final showBlockEditor = _editorMode == 'B';
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
                    child: TextField(
                      controller: _titleController,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                          border: InputBorder.none, hintText: 'Title'),
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
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      value: _editorMode,
                      items: const [
                        DropdownMenuItem(value: 'P', child: Text('Plain')),
                        DropdownMenuItem(value: 'G', child: Text('Preview')),
                        DropdownMenuItem(value: 'B', child: Text('Blocks')),
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
                      widget.onLogEvent(
                          'Note editor closed: Planner.UI/editor.close \u2014 '
                          'dialog dismissed and focus returned to the planner view.');
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
                    : Row(
                        children: [
                          if (showPreview) ...[
                            Expanded(
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: _buildMarkdownPreview(),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            child: TextField(
                              controller: _bodyController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText: 'Write your note...',
                                border: InputBorder.none,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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

/// Compact save indicator shown beside the note title while editing.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({
    required this.lastSavedAt,
    required this.errorMessage,
    required this.saving,
  });

  final DateTime? lastSavedAt;
  final String? errorMessage;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Text('Saving...');
    }
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return Tooltip(
        message: errorMessage!,
        child: const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFF59E0B),
        ),
      );
    }
    return Text(
      lastSavedAt == null ? 'Not saved' : 'Saved ${_formatTime(lastSavedAt!)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
