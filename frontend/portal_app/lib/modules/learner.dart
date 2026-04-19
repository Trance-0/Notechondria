part of notechondria_frontend;

/// Learner module centered on recent notes, search, and editing workflows.
class _LearnerPage extends StatefulWidget {
  const _LearnerPage({
    required this.notes,
    required this.localDrafts,
    required this.courses,
    required this.selectedNote,
    required this.editorMode,
    required this.hasMoreNotes,
    required this.isLoadingMore,
    required this.searchQuery,
    required this.isAuthenticated,
    required this.apiBaseUrl,
    required this.onSearchChanged,
    required this.onLoadMore,
    required this.onOpenNote,
    required this.onFetchNoteDetail,
    required this.onCreateNote,
    required this.onImportMarkdown,
    required this.onExportNote,
    required this.onSaveNote,
    required this.onGetNoteHistory,
    required this.onSnapshotNote,
    required this.onRestoreNoteVersion,
    required this.onStartNoteSession,
    required this.onFinishNoteSession,
    required this.onDeleteNote,
    required this.onSyncLocalDraft,
    required this.onSyncAllLocalDrafts,
    required this.onLogEvent,
  });

  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> localDrafts;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedNote;
  final String editorMode;
  final bool hasMoreNotes;
  final bool isLoadingMore;
  final String searchQuery;
  final bool isAuthenticated;
  final String? apiBaseUrl;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onLoadMore;
  final ValueChanged<Map<String, dynamic>> onOpenNote;
  final Future<Map<String, dynamic>> Function(int noteId) onFetchNoteDetail;
  final Future<Map<String, dynamic>> Function({String? markdown, String? title})
      onCreateNote;
  final Future<void> Function() onImportMarkdown;
  final Future<void> Function(Map<String, dynamic> note) onExportNote;
  final Future<Map<String, dynamic>> Function(
    int noteId,
    Map<String, dynamic> payload,
  ) onSaveNote;
  final Future<List<Map<String, dynamic>>> Function(int noteId)
      onGetNoteHistory;
  final Future<Map<String, dynamic>> Function(int noteId, {String reason})
      onSnapshotNote;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId)
      onRestoreNoteVersion;
  final Future<int?> Function(int noteId, String title, String summary)
      onStartNoteSession;
  final Future<void> Function(int? sessionId, {String? title, String? summary})
      onFinishNoteSession;
  final Future<void> Function(Map<String, dynamic> note) onDeleteNote;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> draft)
      onSyncLocalDraft;
  final Future<void> Function() onSyncAllLocalDrafts;
  final ValueChanged<String> onLogEvent;

  @override
  State<_LearnerPage> createState() => _LearnerPageState();
}

class _LearnerPageState extends State<_LearnerPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant _LearnerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _localSearchScore(Map<String, dynamic> note, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 1;
    }
    final haystack = [
      note['title']?.toString() ?? '',
      note['description']?.toString() ?? '',
      note['content']?.toString() ?? '',
      (note['preview_lines'] as List<dynamic>? ?? const []).join(' '),
    ].join(' ').toLowerCase();
    if (haystack.contains(normalized)) {
      return 100;
    }
    var cursor = 0;
    var hits = 0;
    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      final next = haystack.indexOf(char, cursor);
      if (next == -1) {
        continue;
      }
      hits += 1;
      cursor = next + 1;
    }
    final tokenHits = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && haystack.contains(token))
        .length;
    return (tokenHits * 10) + hits / math.max(1, normalized.length);
  }

  List<Map<String, dynamic>> _visibleLocalDrafts() {
    final query = widget.searchQuery.trim();
    final rows = widget.localDrafts
        .where((note) => query.isEmpty || _localSearchScore(note, query) >= 0.6)
        .toList();
    rows.sort((a, b) =>
        _localSearchScore(b, query).compareTo(_localSearchScore(a, query)));
    return rows;
  }

  /// Opens the note editor and records the note-edit session around the dialog.
  Future<void> _openEditor(Map<String, dynamic> noteSummary) async {
    final detail = await widget.onFetchNoteDetail(noteSummary['id'] as int);
    if (!mounted) {
      return;
    }
    widget.onLogEvent(
        "Note editor opened: Portal.UI/open_editor \u2014 "
        "'${detail['title']?.toString() ?? 'Untitled note'}' loaded into dialog.");
    final sessionId = await widget.onStartNoteSession(
      detail['id'] as int,
      detail['title']?.toString() ?? 'Untitled note',
      detail['description']?.toString() ?? '',
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NoteEditorDialog(
        note: detail,
        courses: widget.courses,
        editorMode: widget.editorMode,
        onSave: widget.onSaveNote,
        onSnapshot: widget.onSnapshotNote,
        onGetHistory: widget.onGetNoteHistory,
        onRestoreVersion: widget.onRestoreNoteVersion,
        onLogEvent: widget.onLogEvent,
      ),
    );
    final refreshed = await widget.onFetchNoteDetail(detail['id'] as int);
    await widget.onFinishNoteSession(
      sessionId,
      title: refreshed['title']?.toString(),
      summary: refreshed['description']?.toString(),
    );
  }

  /// Opens a read-only note viewer dialog from a recent-note card.
  Future<void> _openViewer(Map<String, dynamic> noteSummary) async {
    final detail = await widget.onFetchNoteDetail(noteSummary['id'] as int);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NoteViewerDialog(note: detail),
    );
  }

  Future<void> _createAndOpenNote() async {
    final created = await widget.onCreateNote(title: 'Untitled note');
    if (!mounted) {
      return;
    }
    widget.onLogEvent(
        'Note shell created: Portal.UI/create_note \u2014 '
        'server issued note id ${created['id']}; editor about to open.');
    await _openEditor(created);
  }

  Future<void> _showComposerMenu(TapDownDetails? details) async {
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
        PopupMenuItem(value: 'new', child: Text('Create note')),
        PopupMenuItem(value: 'import', child: Text('Import markdown')),
      ],
    );
    if (selected == 'import') {
      await widget.onImportMarkdown();
    } else if (selected == 'new') {
      await _createAndOpenNote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localDrafts = _visibleLocalDrafts();
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            TextField(
              controller: _searchController,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.isAuthenticated
                    ? 'Search your cloud notes'
                    : 'Search local drafts',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.isAuthenticated && localDrafts.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Unsynced local drafts',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () {
                              widget.onSyncAllLocalDrafts();
                            },
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Sync all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Local drafts stay private by default. Sync uploads them as private cloud notes.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              widget.isAuthenticated ? 'Recent notes' : 'Local drafts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (widget.isAuthenticated && widget.notes.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    localDrafts.isEmpty
                        ? 'No cloud notes yet. Use the add button to create one.'
                        : 'No synced cloud notes yet. Sync a local draft or create a new note.',
                  ),
                ),
              ),
            if (!widget.isAuthenticated && localDrafts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No local drafts yet. Use the add button to create one and sync later after login.',
                  ),
                ),
              ),
            if (!widget.isAuthenticated)
              for (final note in localDrafts)
                _LearnerNoteCard(
                  note: note,
                  apiBaseUrl: widget.apiBaseUrl,
                  canEdit: true,
                  isLocalDraft: true,
                  onOpen: () => _openViewer(note),
                  onEdit: () => _openEditor(note),
                  onExport: () => widget.onExportNote(note),
                  onDelete: () => widget.onDeleteNote(note),
                ),
            if (widget.isAuthenticated)
              for (final note in widget.notes)
                _LearnerNoteCard(
                  note: note,
                  apiBaseUrl: widget.apiBaseUrl,
                  canEdit: true,
                  onOpen: () => _openViewer(note),
                  onEdit: () => _openEditor(note),
                  onExport: () => widget.onExportNote(note),
                  onDelete: () => widget.onDeleteNote(note),
                ),
            if (widget.isAuthenticated && localDrafts.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Local drafts', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final draft in localDrafts)
                _LearnerNoteCard(
                  note: draft,
                  apiBaseUrl: widget.apiBaseUrl,
                  canEdit: true,
                  isLocalDraft: true,
                  canSync: true,
                  onOpen: () => _openViewer(draft),
                  onEdit: () => _openEditor(draft),
                  onExport: () => widget.onExportNote(draft),
                  onDelete: () => widget.onDeleteNote(draft),
                  onSync: () => widget.onSyncLocalDraft(draft),
                ),
            ],
            if (widget.isAuthenticated && widget.hasMoreNotes) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: widget.isLoadingMore
                      ? null
                      : () {
                          widget.onLoadMore();
                        },
                  child:
                      Text(widget.isLoadingMore ? 'Loading...' : 'Load more'),
                ),
              ),
            ],
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: Tooltip(
            message: widget.isAuthenticated
                ? 'Create note. Long press to import markdown.'
                : 'Create a local draft. Long press to import markdown.',
            child: GestureDetector(
              onLongPress: () {
                widget.onImportMarkdown();
              },
              onSecondaryTapDown: _showComposerMenu,
              child: FloatingActionButton(
                key: const Key('learner-add-note-fab'),
                shape: const CircleBorder(),
                onPressed: _createAndOpenNote,
                child: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Recent-note card with public/private styling and note actions.
class _LearnerNoteCard extends StatelessWidget {
  const _LearnerNoteCard({
    required this.note,
    required this.apiBaseUrl,
    required this.canEdit,
    required this.onOpen,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    this.onSync,
    this.isLocalDraft = false,
    this.canSync = false,
  });

  final Map<String, dynamic> note;
  final String? apiBaseUrl;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final Future<void> Function() onExport;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onSync;
  final bool isLocalDraft;
  final bool canSync;

  @override
  Widget build(BuildContext context) {
    final previewLines = (note['preview_lines'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .take(3)
        .toList();
    final isPublic = note['is_public'] == true;
    final author = Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course = Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final authorName = author['username']?.toString() ?? '';
    final avatarFallback = authorName.isEmpty ? 'L' : authorName.substring(0, 1);
    final avatarUrl = _resolveRemoteUrl(
      author['image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    return Card(
      color: isLocalDraft
          ? Theme.of(context).colorScheme.surfaceVariant
          : (isPublic
              ? Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.34)
                  : Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.42)
              : Theme.of(context).colorScheme.surface),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RemoteAvatar(
                    radius: 18,
                    imageUrl: avatarUrl,
                    fallbackLabel: avatarFallback,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note['title']?.toString() ?? 'Untitled note',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (isLocalDraft)
                              'Local draft'
                            else if (isPublic)
                              'Public'
                            else
                              'Private',
                            if ((course['title']?.toString() ?? '').isNotEmpty)
                              course['title'].toString(),
                            formatCompactTimestamp(
                              note['last_edit']?.toString() ?? '',
                            ),
                          ].join(' | '),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        await onDelete();
                      } else if (value == 'sync' && onSync != null) {
                        await onSync!();
                      } else if (value == 'export') {
                        await onExport();
                      }
                    },
                    itemBuilder: (context) => [
                      if (canEdit)
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (canSync)
                        const PopupMenuItem(value: 'sync', child: Text('Sync to cloud')),
                      const PopupMenuItem(
                          value: 'export', child: Text('Export markdown')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              if ((note['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  note['description'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                previewLines.isEmpty
                    ? (note['excerpt']?.toString() ?? '')
                    : previewLines.join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (!isLocalDraft) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'Course metadata stays editable from the editor details panel',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
          "Note saved from editor: Portal.UI/editor.save \u2014 "
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
        'Note metadata dialog opened: Portal.UI/editor.metadata \u2014 '
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
    widget.onLogEvent(
        'Editor mode switched: Portal.UI/editor.mode \u2014 '
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
                          'Note editor closed: Portal.UI/editor.close \u2014 '
                          'dialog dismissed and focus returned to the portal view.');
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

/// Dialog for editing note metadata and restoring saved versions.
class _NoteMetadataDialog extends StatefulWidget {
  const _NoteMetadataDialog({
    required this.note,
    required this.courses,
    required this.metadata,
    required this.allowPublicToggle,
    required this.onGetHistory,
    required this.onRestoreVersion,
  });

  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic> metadata;
  final bool allowPublicToggle;
  final Future<List<Map<String, dynamic>>> Function(int noteId) onGetHistory;
  final Future<Map<String, dynamic>> Function(int noteId, int versionId)
      onRestoreVersion;

  @override
  State<_NoteMetadataDialog> createState() => _NoteMetadataDialogState();
}

class _NoteMetadataDialogState extends State<_NoteMetadataDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _sectionController;
  int? _courseId;
  bool _isPublic = false;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.metadata['description']?.toString() ??
          widget.note['description']?.toString() ??
          '',
    );
    _sectionController = TextEditingController(
      text: widget.metadata['section']?.toString() ?? '',
    );
    _courseId = (widget.metadata['course_id'] as num?)?.toInt() ??
        (widget.note['course']?['id'] as num?)?.toInt();
    _isPublic = widget.metadata['is_public'] == true ||
        widget.note['is_public'] == true;
    _historyFuture = widget.onGetHistory(widget.note['id'] as int);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note details'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int?>(
                value: _courseId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No assigned course'),
                  ),
                  ...widget.courses.map(
                    (course) => DropdownMenuItem<int?>(
                      value: course['id'] as int,
                      child: Text(course['title']?.toString() ?? 'Course'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _courseId = value),
                decoration: const InputDecoration(
                  labelText: 'Assigned course / plan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sectionController,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Short description / comments',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isPublic,
                onChanged: widget.allowPublicToggle
                    ? (value) => setState(() => _isPublic = value)
                    : null,
                contentPadding: EdgeInsets.zero,
                title: const Text('Public note'),
                subtitle: Text(
                  widget.allowPublicToggle
                      ? 'Public notes appear in the recommendation feed.'
                      : 'Sync this note to the cloud before making it public.',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Version history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? const [];
                    if (rows.isEmpty) {
                      return const Text('No saved versions yet.');
                    }
                    return ListView(
                      children: [
                        for (final version in rows)
                          ListTile(
                            dense: true,
                            title:
                                Text(version['label']?.toString() ?? 'Version'),
                            subtitle:
                                Text(version['date_created']?.toString() ?? ''),
                            trailing: TextButton(
                              onPressed: () async {
                                final restored = await widget.onRestoreVersion(
                                  widget.note['id'] as int,
                                  version['id'] as int,
                                );
                                if (mounted) {
                                  Navigator.of(context).pop({
                                    'metadata': {
                                      'description':
                                          _descriptionController.text,
                                      'section': _sectionController.text,
                                      'course_id': _courseId,
                                      'is_public': _isPublic,
                                    },
                                    'restored_note': restored,
                                  });
                                }
                              },
                              child: const Text('Restore'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'description': _descriptionController.text,
            'section': _sectionController.text,
            'course_id': _courseId,
            'is_public': _isPublic,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
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
