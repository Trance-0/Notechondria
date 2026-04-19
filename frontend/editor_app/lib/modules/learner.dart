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
    required this.searchScope,
    required this.isAuthenticated,
    required this.currentUsername,
    required this.apiBaseUrl,
    required this.onSearchChanged,
    required this.onSearchScopeChanged,
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
    this.onUploadAttachment,
  });

  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> localDrafts;
  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedNote;
  final String editorMode;
  final bool hasMoreNotes;
  final bool isLoadingMore;
  final String searchQuery;
  /// 'personal' = only own notes, 'all' = own notes + public notes from any user.
  final String searchScope;
  final bool isAuthenticated;
  final String currentUsername;
  final String? apiBaseUrl;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchScopeChanged;
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
  final Future<Map<String, dynamic>> Function(int noteId, XFile file)?
      onUploadAttachment;

  @override
  State<_LearnerPage> createState() => _LearnerPageState();
}

class _LearnerPageState extends State<_LearnerPage> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (!widget.hasMoreNotes || widget.isLoadingMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
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
    _scrollController.dispose();
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
        "Note editor opened: Editor.UI/open_editor \u2014 "
        "'${detail['title']?.toString() ?? 'Untitled note'}' loaded into dialog.");
    final sessionId = await widget.onStartNoteSession(
      detail['id'] as int,
      detail['title']?.toString() ?? 'Untitled note',
      detail['description']?.toString() ?? '',
    );
    await _showSlideInDialog<void>(
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
        onUploadAttachment: widget.onUploadAttachment,
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
    final author = Map<String, dynamic>.from(
        detail['author'] as Map? ?? const {});
    final isOwner = widget.currentUsername.isNotEmpty &&
        author['username']?.toString() == widget.currentUsername;
    // Local drafts (no author) are always editable.
    final isLocal = (detail['id'] as num?)?.toInt() != null &&
        ((detail['id'] as num).toInt() < 0);
    final canEdit = isOwner || isLocal;
    await _showSlideInDialog<void>(
      context: context,
      builder: (context) => _NoteViewerDialog(
        note: detail,
        onEdit: canEdit ? () => _openEditor(detail) : null,
        onExport: () => widget.onExportNote(detail),
        onDelete: canEdit ? () => widget.onDeleteNote(detail) : null,
      ),
    );
  }

  Future<void> _createAndOpenNote() async {
    final created = await widget.onCreateNote(title: 'Untitled note');
    if (!mounted) {
      return;
    }
    widget.onLogEvent(
        'Note shell created: Editor.UI/create_note \u2014 '
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
        PopupMenuItem(value: 'import', child: Text('Import markdown or zip')),
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
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            TextField(
              controller: _searchController,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.isAuthenticated
                    ? (widget.searchScope == 'all'
                        ? 'Search all notes (yours + public)'
                        : 'Search your notes')
                    : 'Search local drafts',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            if (widget.isAuthenticated)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Row(
                  children: [
                    // Checkbox mirrors the task spec: checked = "All" scope
                    // (your notes + every other user's public notes),
                    // unchecked = "Personal" (only your own private + public).
                    Checkbox(
                      value: widget.searchScope == 'all',
                      onChanged: (value) {
                        widget.onSearchScopeChanged(
                            value == true ? 'all' : 'personal');
                      },
                    ),
                    const Text('Include public notes from other users'),
                  ],
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
            if (localDrafts.isNotEmpty) ...[
              Text(
                'Local drafts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < localDrafts.length; i++)
                _StaggeredFadeIn(
                  index: i,
                  child: _LearnerNoteCard(
                    note: localDrafts[i],
                    apiBaseUrl: widget.apiBaseUrl,
                    isLocalDraft: true,
                    canSync: widget.isAuthenticated,
                    onOpen: () => _openViewer(localDrafts[i]),
                    onSync: widget.isAuthenticated
                        ? () => widget.onSyncLocalDraft(localDrafts[i])
                        : null,
                  ),
                ),
              const SizedBox(height: 20),
            ],
            Text(
              widget.isAuthenticated ? 'Recent notes' : 'Public notes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (widget.notes.isEmpty && localDrafts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.isAuthenticated
                        ? 'No cloud notes yet. Use the add button to create one.'
                        : 'No notes yet. Use the add button to create a local draft.',
                  ),
                ),
              ),
            if (widget.notes.isEmpty && localDrafts.isNotEmpty && widget.isAuthenticated)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No synced cloud notes yet. Sync a local draft or create a new note.',
                  ),
                ),
              ),
            for (var i = 0; i < widget.notes.length; i++)
              _StaggeredFadeIn(
                index: i,
                child: _LearnerNoteCard(
                  note: widget.notes[i],
                  apiBaseUrl: widget.apiBaseUrl,
                  onOpen: () => _openViewer(widget.notes[i]),
                ),
              ),
            if (widget.isLoadingMore) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
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

/// Recent-note card with public/private styling. Tap to open the viewer;
/// note actions (edit/export/delete) live inside the viewer itself.
class _LearnerNoteCard extends StatelessWidget {
  const _LearnerNoteCard({
    required this.note,
    required this.apiBaseUrl,
    required this.onOpen,
    this.onSync,
    this.isLocalDraft = false,
    this.canSync = false,
  });

  final Map<String, dynamic> note;
  final String? apiBaseUrl;
  final VoidCallback onOpen;
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                note['title']?.toString() ?? 'Untitled note',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: isLocalDraft
                                  ? (canSync
                                      ? 'Not synced — tap sync to upload'
                                      : 'Offline')
                                  : 'Synced to cloud',
                              child: Icon(
                                isLocalDraft
                                    ? (canSync
                                        ? Icons.cloud_upload_outlined
                                        : Icons.cloud_off_outlined)
                                    : Icons.cloud_done_outlined,
                                size: 16,
                                color: isLocalDraft
                                    ? (canSync
                                        ? Theme.of(context).colorScheme.tertiary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
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
                  if (canSync && onSync != null)
                    IconButton(
                      tooltip: 'Sync to cloud',
                      icon: const Icon(Icons.cloud_upload_outlined),
                      onPressed: () async {
                        await onSync!();
                      },
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
              if (isLocalDraft) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'Stored locally until you sync',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
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
