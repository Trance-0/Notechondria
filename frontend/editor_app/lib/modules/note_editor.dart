part of notechondria_frontend;

/// Full-screen note editor supporting plain-text and live-markdown editing.
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
    this.onUploadAttachment,
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
  final Future<Map<String, dynamic>> Function(int noteId, XFile file)?
      onUploadAttachment;

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
  late Map<String, dynamic> _note;
  late Map<String, dynamic> _metadata;
  late String _editorMode;
  /// Index of the paragraph currently being edited inline in the Typora-style
  /// live editor. Null means every paragraph is rendered as a preview.
  int? _liveEditingParagraphIndex;
  /// Scratch controller used while a paragraph is being edited. Rebuilt every
  /// time the user enters a different paragraph and disposed on commit.
  TextEditingController? _liveParagraphController;
  final FocusNode _liveParagraphFocusNode = FocusNode();

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
    final noteEditorMode = _note['editor_mode']?.toString() ?? '';
    _editorMode = noteEditorMode.isNotEmpty ? noteEditorMode : widget.editorMode;
    // Fall back to live markdown if the note was saved as block editor.
    if (_editorMode == 'B') _editorMode = 'G';
    _titleController.addListener(_handleChanged);
    _bodyController.addListener(_handleChanged);
    // When the paragraph being edited inline loses focus, commit its contents
    // back into _bodyController and swap it back to a rendered preview.
    _liveParagraphFocusNode.addListener(_handleLiveParagraphFocusChange);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    _previewScrollController.dispose();
    _liveParagraphFocusNode.removeListener(_handleLiveParagraphFocusChange);
    _liveParagraphFocusNode.dispose();
    _liveParagraphController?.dispose();
    super.dispose();
  }

  /// Splits the current body into top-level markdown blocks. Unlike a naive
  /// `split(\n\s*\n)`, this walks the source line-by-line so multi-line
  /// constructs stay in a single paragraph entry:
  ///   * fenced code blocks (``` or ~~~) including blank lines inside the fence
  ///   * HTML blocks such as `<details>…</details>` and `<summary>` regions
  ///   * pipe tables (header row followed by a `|---|---|` separator)
  ///   * lists and blockquotes that have no intervening blank lines
  ///   * ATX headings (single-line, but kept as their own block)
  /// Every block returned here is later re-joined with `\n\n`, so the parser
  /// treats each entry as its own top-level markdown block when rendering.
  List<String> _liveParagraphs() {
    final text = _bodyController.text;
    if (text.isEmpty) return const [''];
    final lines = text.split('\n');
    final blocks = <String>[];
    final buffer = <String>[];

    void flush() {
      if (buffer.isEmpty) return;
      // Trim trailing empty lines inside a block; they are block separators.
      while (buffer.isNotEmpty && buffer.last.trim().isEmpty) {
        buffer.removeLast();
      }
      if (buffer.isNotEmpty) {
        blocks.add(buffer.join('\n'));
      }
      buffer.clear();
    }

    final fenceOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
    final headingLine = RegExp(r'^\s{0,3}#{1,6}\s');
    final tableSeparator =
        RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$');
    final htmlBlockOpen = RegExp(
        r'^\s{0,3}<(details|summary|table|thead|tbody|tr|div|section|article|aside|figure|pre|blockquote)\b',
        caseSensitive: false);

    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trimLeft();

      // Blank line → current block ends.
      if (line.trim().isEmpty) {
        flush();
        i++;
        continue;
      }

      // Fenced code block — consume until matching closing fence.
      final fenceMatch = fenceOpen.firstMatch(line);
      if (fenceMatch != null) {
        flush();
        final fenceMarker = fenceMatch.group(1)!;
        final fenceChar = fenceMarker[0];
        final fenceLen = fenceMarker.length;
        buffer.add(line);
        i++;
        while (i < lines.length) {
          final inner = lines[i];
          buffer.add(inner);
          i++;
          final closeMatch =
              RegExp('^\\s{0,3}($fenceChar{$fenceLen,})\\s*\$')
                  .firstMatch(inner);
          if (closeMatch != null) break;
        }
        flush();
        continue;
      }

      // HTML block — consume until a blank line or a matching closing tag.
      final htmlMatch = htmlBlockOpen.firstMatch(line);
      if (htmlMatch != null) {
        flush();
        final tag = htmlMatch.group(1)!.toLowerCase();
        final closeTag = RegExp('</$tag\\s*>', caseSensitive: false);
        buffer.add(line);
        // Single-line HTML block (opens and closes on the same line) still
        // flushes immediately via the blank-line / EOF path below.
        if (closeTag.hasMatch(line)) {
          i++;
          flush();
          continue;
        }
        i++;
        while (i < lines.length) {
          final inner = lines[i];
          buffer.add(inner);
          i++;
          if (closeTag.hasMatch(inner)) break;
        }
        flush();
        continue;
      }

      // ATX heading — emit as its own block so the caller can tap into it
      // without dragging adjacent paragraphs along.
      if (headingLine.hasMatch(line)) {
        flush();
        buffer.add(line);
        flush();
        i++;
        continue;
      }

      // Pipe table — current line starts with `|` and the next line is the
      // `|---|---|` separator. Consume all subsequent non-blank rows.
      if (trimmed.startsWith('|') &&
          i + 1 < lines.length &&
          tableSeparator.hasMatch(lines[i + 1])) {
        flush();
        buffer.add(line);
        buffer.add(lines[i + 1]);
        i += 2;
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          buffer.add(lines[i]);
          i++;
        }
        flush();
        continue;
      }

      // Default: accumulate until the next blank line (handles paragraphs,
      // lists, blockquotes, setext headings, etc. as a single block).
      buffer.add(line);
      i++;
    }

    flush();
    if (blocks.isEmpty) return const [''];
    return blocks;
  }

  /// Rewrites [_bodyController] from the paragraph list, joining with double
  /// newlines so the markdown parser keeps treating each entry as its own
  /// block.
  void _updateBodyFromParagraphs(List<String> paragraphs) {
    final next = paragraphs.join('\n\n');
    if (_bodyController.text != next) {
      _bodyController.text = next;
    }
  }

  /// Swaps paragraph [index] into edit mode, seeding a fresh controller with
  /// its raw markdown source and requesting focus on the next frame so the
  /// caret lands inside the newly materialized TextField.
  void _beginEditingLiveParagraph(int index) {
    final paragraphs = _liveParagraphs();
    if (index < 0 || index >= paragraphs.length) return;
    _liveParagraphController?.dispose();
    _liveParagraphController =
        TextEditingController(text: paragraphs[index]);
    setState(() {
      _liveEditingParagraphIndex = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _liveParagraphFocusNode.requestFocus();
    });
  }

  /// Commits the in-progress paragraph edit back into the master body and
  /// clears the transient edit controller. Called when focus leaves the
  /// inline editor or the user taps somewhere else.
  void _commitEditingLiveParagraph() {
    final index = _liveEditingParagraphIndex;
    final controller = _liveParagraphController;
    if (index == null || controller == null) return;
    final paragraphs = [..._liveParagraphs()];
    if (index >= 0 && index < paragraphs.length) {
      paragraphs[index] = controller.text;
    }
    // Drop trailing empty paragraphs so we don't keep accumulating phantom
    // blocks every time the user cancels an insertion.
    while (paragraphs.length > 1 && paragraphs.last.trim().isEmpty) {
      paragraphs.removeLast();
    }
    _updateBodyFromParagraphs(paragraphs);
    controller.dispose();
    _liveParagraphController = null;
    setState(() {
      _liveEditingParagraphIndex = null;
    });
  }

  void _handleLiveParagraphFocusChange() {
    if (!_liveParagraphFocusNode.hasFocus) {
      _commitEditingLiveParagraph();
    }
  }

  /// Inserts an empty paragraph at [index] and immediately enters edit mode on
  /// it so the user can start typing.
  void _insertLiveParagraph(int index) {
    // Flush any pending edit first so we don't clobber the user's in-progress
    // paragraph.
    if (_liveEditingParagraphIndex != null) {
      _commitEditingLiveParagraph();
    }
    final paragraphs = [..._liveParagraphs()];
    final clamped = index.clamp(0, paragraphs.length);
    paragraphs.insert(clamped, '');
    _updateBodyFromParagraphs(paragraphs);
    _beginEditingLiveParagraph(clamped);
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
          'content': _composeMarkdown(_titleController.text, _bodyController.text),
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

  void _setEditorMode(String mode) {
    if (_editorMode == mode) return;
    setState(() {
      _editorMode = mode;
    });
    widget.onLogEvent('Editor mode switched to $mode.');
    _handleChanged();
  }

  Future<void> _pickAndUploadAttachment() async {
    final noteId = _note['id'] as int?;
    if (noteId == null || noteId < 0 || widget.onUploadAttachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the note before adding attachments.')),
      );
      return;
    }
    final xfile = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'All files'),
    ]);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    const maxSize = 20 * 1024 * 1024;
    if (bytes.length > maxSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File exceeds 20 MB limit.')),
        );
      }
      return;
    }
    try {
      final attachment = await widget.onUploadAttachment!(noteId, xfile);
      final url = attachment['url']?.toString() ?? '';
      final filename = attachment['original_filename']?.toString() ?? xfile.name;
      final contentType = attachment['content_type']?.toString() ?? '';
      final isImage = contentType.startsWith('image/');
      final embed = isImage ? '![$filename]($url)' : '[$filename]($url)';
      _bodyController.text = '${_bodyController.text}\n\n$embed';
      _handleChanged();
      widget.onLogEvent('Attachment uploaded: $filename');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  /// Full-width live markdown editor. Emulates Typora-style inline rendering:
  /// every paragraph renders as a `MarkdownBody` preview until the user taps
  /// it, at which point that single paragraph swaps into a borderless
  /// TextField for editing. Focus loss commits the change and swaps the
  /// paragraph back to rendered form. Thin "+" buttons between paragraphs
  /// insert empty blocks at the exact cursor position.
  Widget _buildLiveMarkdownEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _buildInlineLiveMarkdownBody(),
          ),
        ),
      ],
    );
  }

  /// Builds the Typora-style stacked paragraph editor. Each paragraph is
  /// either a tap-to-edit preview or an active borderless TextField.
  Widget _buildInlineLiveMarkdownBody() {
    final paragraphs = _liveParagraphs();
    final editingIndex = _liveEditingParagraphIndex;
    return Scrollbar(
      controller: _previewScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _previewScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildParagraphInsertSlot(0),
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (editingIndex == i)
                _buildInlineParagraphEditor(paragraphs[i])
              else
                _buildInlineParagraphPreview(i, paragraphs[i]),
              _buildParagraphInsertSlot(i + 1),
            ],
          ],
        ),
      ),
    );
  }

  /// A paragraph rendered in preview mode. Clicking it swaps to edit mode.
  Widget _buildInlineParagraphPreview(int index, String source) {
    final trimmed = source.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _beginEditingLiveParagraph(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: trimmed.isEmpty
            ? Text(
                'Empty paragraph — click to edit',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
              )
            : MarkdownBody(
                data: source,
                selectable: false,
                builders: _markdownBuilders(),
                inlineSyntaxes: _markdownInlineSyntaxes(),
                blockSyntaxes: _markdownBlockSyntaxes(),
                styleSheet: _markdownStyleSheet(context),
              ),
      ),
    );
  }

  /// The active paragraph editor. Borderless TextField so it visually blends
  /// with the surrounding preview rows.
  Widget _buildInlineParagraphEditor(String initialText) {
    final controller = _liveParagraphController;
    if (controller == null) {
      // Shouldn't happen, but fall back to a stale preview if it does.
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: TextField(
        controller: controller,
        focusNode: _liveParagraphFocusNode,
        maxLines: null,
        autofocus: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Edit paragraph markdown...',
        ),
      ),
    );
  }

  /// Thin hairline button sitting between paragraphs. Only visible on hover;
  /// clicking inserts an empty paragraph at that slot and focuses it.
  Widget _buildParagraphInsertSlot(int index) {
    return _HoverInsertSlot(onTap: () => _insertLiveParagraph(index));
  }

  @override
  Widget build(BuildContext context) {
    final isLiveMarkdown = _editorMode == 'G';
    final specWarnings = _validateMarkdownSpec(_bodyController.text);
    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final titleField = TextField(
                controller: _titleController,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                    border: InputBorder.none, hintText: 'Title'),
              );
              final warningWidget = specWarnings.isNotEmpty
                  ? Padding(
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
                    )
                  : null;
              final saveStatus = _SaveStatus(
                lastSavedAt: _lastSavedAt,
                errorMessage: _saveError,
                saving: _saving,
              );
              final editorDropdown = DropdownButtonFormField<String>(
                initialValue: _editorMode,
                items: const [
                  DropdownMenuItem(
                      value: 'P', child: Text('Plain text')),
                  DropdownMenuItem(
                      value: 'G', child: Text('Live markdown')),
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
              );
              final detailsButton = IconButton(
                  onPressed: _openDetails,
                  icon: const Icon(Icons.more_horiz));
              final shareButton = _note['uuid'] != null
                  ? IconButton(
                      onPressed: () async {
                        final uuid = _note['uuid'].toString();
                        final base = Uri.base.removeFragment();
                        final link = '$base#/notes/$uuid';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied to clipboard')),
                          );
                        }
                      },
                      icon: const Icon(Icons.link),
                      tooltip: 'Copy link',
                    )
                  : const SizedBox.shrink();
              final closeButton = IconButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  _autosaveTimer?.cancel();
                  if (_dirty) {
                    await _save(reason: 'close');
                    await widget.onSnapshot(_note['id'] as int,
                        reason: 'quit');
                  }
                  widget.onLogEvent('Editor closed.');
                  if (mounted) {
                    nav.pop();
                  }
                },
                icon: const Icon(Icons.close),
              );

              if (isNarrow) {
                // Vertical layout: title on top, controls below.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: titleField),
                          shareButton,
                          detailsButton,
                          closeButton,
                        ],
                      ),
                      if (warningWidget != null) warningWidget,
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: editorDropdown),
                          const SizedBox(width: 8),
                          saveStatus,
                        ],
                      ),
                    ],
                  ),
                );
              }

              // Wide layout: single row.
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          titleField,
                          if (warningWidget != null) warningWidget,
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: saveStatus,
                      ),
                    ),
                    SizedBox(width: 220, child: editorDropdown),
                    const SizedBox(width: 8),
                    shareButton,
                    detailsButton,
                    closeButton,
                  ],
                ),
              );
            }),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    isLiveMarkdown
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
                    if (widget.onUploadAttachment != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          onPressed: _pickAndUploadAttachment,
                          tooltip: 'Attach file',
                          child: const Icon(Icons.attach_file),
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

