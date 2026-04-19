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
          "Note saved from editor: Editor.UI/editor.save \u2014 "
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
        'Note metadata dialog opened: Editor.UI/editor.metadata \u2014 '
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
    widget.onLogEvent(
        'Editor mode switched: Editor.UI/editor.mode \u2014 '
        'active mode set to $mode.');
    _handleChanged();
  }

  Future<void> _pickAndUploadAttachment() async {
    final noteId = _note['id'] as int?;
    if (noteId == null) return;

    final xfile = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'All files'),
    ]);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (bytes.length > LocalAttachmentStore.maxBytesPerAttachment) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment not added: '
              'Editor.UI/editor.attachment \u2014 '
              'file exceeds '
              '${LocalAttachmentStore.maxBytesPerAttachment ~/ (1024 * 1024)} '
              'MB per-attachment limit.',
            ),
          ),
        );
      }
      return;
    }

    final filename = xfile.name;
    final contentType = _guessContentType(xfile.name, bytes);
    final isImage = contentType.startsWith('image/');
    final isLocalNote = noteId < 0;
    final uploadFn = widget.onUploadAttachment;

    // Cloud-ready path: we have a saved cloud note id AND an upload
    // callback AND the host actually has a session. If the host rejects
    // mid-upload (no token, network failure), fall through to the
    // offline-queue path so the user never loses the file.
    if (!isLocalNote && uploadFn != null) {
      try {
        final attachment = await uploadFn(noteId, xfile);
        final url = attachment['url']?.toString() ?? '';
        final serverName =
            attachment['original_filename']?.toString() ?? filename;
        final embed = isImage ? '![$serverName]($url)' : '[$serverName]($url)';
        _bodyController.text = '${_bodyController.text}\n\n$embed';
        _handleChanged();
        widget.onLogEvent(
          'Attachment uploaded: Editor.UI/editor.attachment \u2014 '
          '"$serverName" attached to the open note.',
        );
        return;
      } catch (_) {
        // Fall through to the local-store offline-queue path below.
      }
    }

    // Offline / local-draft / upload-failed path: save the bytes to
    // LocalAttachmentStore under a note-uuid-scoped key, embed a
    // compact `local://<uuid>/<filename>` URL into the markdown body,
    // and record a pointer in `metadata_json['queued_attachments']`
    // so the next sync pass can promote it to a real upload. Unlike
    // the 0.1.37 path this never puts base64 into the note body.
    final storeNoteUuid = _resolveStoreNoteUuid();
    try {
      final store = await LocalAttachmentStore.open();
      final record = await store.put(
        noteUuid: storeNoteUuid,
        filename: filename,
        contentType: contentType,
        bytes: bytes,
      );
      final embed = isImage
          ? '![${record.filename}](${record.localUrl})'
          : '[${record.filename}](${record.localUrl})';
      _bodyController.text = '${_bodyController.text}\n\n$embed';
      _handleChanged();

      final metadata =
          _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
      final queued = List<Map<String, dynamic>>.from(
        (metadata['queued_attachments'] as List?) ?? const [],
      );
      queued.add({
        'filename': record.filename,
        'content_type': record.contentType,
        'size_bytes': record.sizeBytes,
        'local_url': record.localUrl,
        'note_uuid': record.noteUuid,
        'queued_at': record.createdAt.toIso8601String(),
      });
      metadata['queued_attachments'] = queued;
      _note = {
        ..._note,
        'metadata_json': jsonEncode(metadata),
      };
      _handleChanged();

      widget.onLogEvent(
        'Attachment queued for sync: '
        'Editor.Sync.Notes/attachment.queue \u2014 '
        '"${record.filename}" stored at ${record.localUrl} '
        '(${record.sizeBytes} bytes); will upload on next sync.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment saved locally: '
              'Editor.Sync.Notes/attachment.queue \u2014 '
              '"${record.filename}" kept offline under ${record.localUrl}; '
              'it will upload on the next sync.',
            ),
          ),
        );
      }
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      widget.onLogEvent(
        'Attachment not saved locally: '
        'Editor.Sync.Notes/attachment.queue \u2014 $cause.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attachment not saved: '
              'Editor.Sync.Notes/attachment.queue \u2014 $cause.',
            ),
          ),
        );
      }
    }
  }

  /// Store-key rules:
  ///   - server note with a uuid: use the uuid verbatim.
  ///   - local draft without a server uuid: prefix with `local-`
  ///     + client-draft-id so the namespace never collides.
  String _resolveStoreNoteUuid() {
    final serverUuid = _note['uuid']?.toString() ?? '';
    if (serverUuid.isNotEmpty) return serverUuid;
    final client = _note['client_draft_id']?.toString() ??
        _note['id']?.toString() ??
        '';
    return client.isEmpty ? 'local-unknown' : 'local-$client';
  }

  /// Opens a modal bottom sheet listing every attachment currently
  /// embedded in the note:
  ///   - **Local (queued)**: entries from
  ///     `metadata_json['queued_attachments']` that carry a
  ///     `local_url`. These have a small inline image preview
  ///     (via FutureBuilder + LocalAttachmentStore.getBytes) for
  ///     image/* content-types. Delete removes from the store,
  ///     drops the queue entry, and strips the URL from the body.
  ///   - **Cloud (CDN URLs)**: `http(s)://...` URLs scraped from
  ///     the body. Shown read-only with a copy-link action; to
  ///     delete a cloud attachment the user still goes through
  ///     the server endpoint (not wired here).
  ///
  /// The sheet is populated from a snapshot of the current state;
  /// it does not live-update while open. Closing and re-opening
  /// refreshes the list.
  Future<void> _openAttachmentsList() async {
    final queued = _readQueuedAttachmentEntries();
    final cloudUrls = _extractCloudAttachmentUrls(_bodyController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Attachments',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    '${queued.length} local, ${cloudUrls.length} uploaded',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (queued.isEmpty && cloudUrls.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No attachments in this note yet.',
                            ),
                          ),
                        ),
                      for (final entry in queued)
                        _AttachmentSheetRow(
                          filename: (entry['filename'] ?? '').toString(),
                          sizeBytes:
                              (entry['size_bytes'] as num?)?.toInt() ?? 0,
                          contentType:
                              (entry['content_type'] ?? '').toString(),
                          localUrl:
                              (entry['local_url'] ?? '').toString(),
                          cloudUrl: null,
                          onDelete: () async {
                            Navigator.of(ctx).pop();
                            await _deleteLocalAttachment(entry);
                            if (mounted) await _openAttachmentsList();
                          },
                        ),
                      for (final url in cloudUrls)
                        _AttachmentSheetRow(
                          filename: _filenameFromUrl(url),
                          sizeBytes: 0,
                          contentType: _guessContentType(
                              _filenameFromUrl(url), Uint8List(0)),
                          localUrl: null,
                          cloudUrl: url,
                          onDelete: null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Reads the list of local queued-attachment entries from the
  /// draft's metadata. Returns an empty list when the note has
  /// never been pickered or when migration stripped the queue.
  List<Map<String, dynamic>> _readQueuedAttachmentEntries() {
    final metadata =
        _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
    final raw = metadata['queued_attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((entry) =>
            (entry['local_url']?.toString().isNotEmpty ?? false) ||
            (entry['filename']?.toString().isNotEmpty ?? false))
        .toList(growable: false);
  }

  /// Extracts every `http(s)://...` image / link URL embedded in the
  /// note body. Used by the attachments sheet to surface
  /// already-uploaded CDN attachments.
  List<String> _extractCloudAttachmentUrls(String body) {
    final re = RegExp(r'(?:!\[[^\]]*\]|\[[^\]]*\])\((https?://[^)\s]+)\)');
    final seen = <String>{};
    final out = <String>[];
    for (final match in re.allMatches(body)) {
      final url = match.group(1);
      if (url == null) continue;
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isEmpty) return url;
      return uri.pathSegments.last;
    } catch (_) {
      return url;
    }
  }

  /// Removes a local queued-attachment entry from the store, from
  /// the draft's metadata, and strips its `local://` URL from the
  /// note body. Silently no-ops when the store key doesn't exist.
  Future<void> _deleteLocalAttachment(Map<String, dynamic> entry) async {
    final localUrl = entry['local_url']?.toString() ?? '';
    final filename = entry['filename']?.toString() ?? 'attachment';
    if (localUrl.isEmpty) return;
    try {
      final store = await LocalAttachmentStore.open();
      await store.delete(localUrl: localUrl);
    } catch (_) {
      // Silent: user cleanup of a missing blob still succeeds
      // because the metadata strip below removes the queue entry.
    }
    final metadata =
        _decodeNoteMetadata(_note['metadata_json']?.toString() ?? '{}');
    final queued = List<Map<String, dynamic>>.from(
      (metadata['queued_attachments'] as List?) ?? const [],
    );
    queued.removeWhere((e) => e['local_url']?.toString() == localUrl);
    metadata['queued_attachments'] = queued;
    _note = {
      ..._note,
      'metadata_json': jsonEncode(metadata),
    };
    // Remove any markdown line that references this localUrl so the
    // body doesn't render a broken-attachment pill afterwards.
    final lines = _bodyController.text.split('\n');
    _bodyController.text = lines
        .where((line) => !line.contains(localUrl))
        .join('\n');
    _handleChanged();
    widget.onLogEvent(
      'Attachment deleted locally: '
      'Editor.UI/editor.attachment.delete \u2014 '
      '"$filename" removed from note body and local store.',
    );
  }

  /// Best-effort content-type guess from filename extension, falling back
  /// to a short magic-bytes sniff for common image formats when the
  /// extension is missing.
  String _guessContentType(String filename, Uint8List bytes) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
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
                sizedImageBuilder: _localAttachmentImageBuilder,
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
    // Hoisted so it can be referenced both in the top bar LayoutBuilder
    // and as the floating lower-left subtitle in the editor Stack below.
    final saveStatus = _SaveStatus(
      lastSavedAt: _lastSavedAt,
      errorMessage: _saveError,
      saving: _saving,
    );
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
                  widget.onLogEvent(
                      'Note editor closed: Editor.UI/editor.close \u2014 '
                      'dialog dismissed and focus returned to the learner view.');
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          titleField,
                          if (warningWidget != null) warningWidget,
                        ],
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
                                  border: InputBorder.none,
                                  alignLabelWithHint: true,
                                ),
                              ),
                    if (widget.onUploadAttachment != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'editor-attachments-list',
                              onPressed: _openAttachmentsList,
                              tooltip: 'Open attachments list',
                              child: const Icon(Icons.attachment_outlined),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'editor-attach-file',
                              onPressed: _pickAndUploadAttachment,
                              tooltip: 'Attach file',
                              child: const Icon(Icons.attach_file),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: IgnorePointer(
                        child: DefaultTextStyle(
                          style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.55),
                                  ) ??
                              const TextStyle(),
                          child: saveStatus,
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

