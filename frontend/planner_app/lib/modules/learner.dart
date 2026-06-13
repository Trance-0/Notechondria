part of notechondria_frontend;

/// Holds a group of notes that share a course (folder) for the grouped
/// rendering in the learner view.
class _NoteFolder {
  _NoteFolder({
    required this.key,
    required this.title,
    required this.courseId,
    required this.notes,
  });

  final String key;
  final String title;
  final int? courseId;
  final List<Map<String, dynamic>> notes;
}

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
    this.onUploadCover,
    this.onDeleteCover,
    this.offlineMode = false,
    this.onLoadPublicNotes,
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
  final Future<Map<String, dynamic>> Function(int noteId, XFile file)?
      onUploadCover;
  final Future<Map<String, dynamic>> Function(int noteId)? onDeleteCover;
  final bool offlineMode;
  final VoidCallback? onLoadPublicNotes;

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

  /// Returns notes grouped by their course (folder) with most-recent-first
  /// ordering within each group. Notes without a course land in an
  /// "Uncategorized" bucket. The outer list is sorted by the group's most
  /// recent note so the freshest folder floats to the top.
  List<_NoteFolder> _groupNotesByCourse(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) {
      return const [];
    }
    final buckets = <String, _NoteFolder>{};
    for (final note in notes) {
      final course =
          Map<String, dynamic>.from(note['course'] as Map? ?? const {});
      final courseId = (course['id'] as num?)?.toInt();
      final key = courseId != null ? 'c$courseId' : 'none';
      final title = (course['title']?.toString().trim().isNotEmpty ?? false)
          ? course['title']!.toString()
          : 'Uncategorized';
      final bucket = buckets.putIfAbsent(
        key,
        () => _NoteFolder(
          key: key,
          title: title,
          courseId: courseId,
          notes: <Map<String, dynamic>>[],
        ),
      );
      bucket.notes.add(note);
    }
    // Sort each bucket's notes by `updated_at` descending (fall back to `created_at`).
    int compareRecency(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aTs =
          a['updated_at']?.toString() ?? a['created_at']?.toString() ?? '';
      final bTs =
          b['updated_at']?.toString() ?? b['created_at']?.toString() ?? '';
      return bTs.compareTo(aTs);
    }

    for (final bucket in buckets.values) {
      bucket.notes.sort(compareRecency);
    }
    // Sort buckets by their most-recent note.
    final folders = buckets.values.toList(growable: false);
    folders.sort((a, b) {
      if (a.notes.isEmpty) return 1;
      if (b.notes.isEmpty) return -1;
      return compareRecency(a.notes.first, b.notes.first);
    });
    return folders;
  }

  /// Opens the note editor and records the note-edit session around the dialog.
  Future<void> _openEditor(Map<String, dynamic> noteSummary) async {
    final detail = await widget.onFetchNoteDetail(noteSummary['id'] as int);
    if (!mounted) {
      return;
    }
    widget.onLogEvent("Note editor opened: Planner.UI/open_editor \u2014 "
        "'${detail['title']?.toString() ?? 'Untitled note'}' loaded into dialog.");
    final sessionId = await widget.onStartNoteSession(
      detail['id'] as int,
      detail['title']?.toString() ?? 'Untitled note',
      detail['description']?.toString() ?? '',
    );
    final noteId = detail['id'] as int;
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
        onUploadCover: widget.onUploadCover != null
            ? (file) => widget.onUploadCover!(noteId, file)
            : null,
        onDeleteCover: widget.onDeleteCover != null
            ? () => widget.onDeleteCover!(noteId)
            : null,
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
    widget.onLogEvent('Note shell created: Planner.UI/create_note \u2014 '
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
            if (widget.offlineMode &&
                widget.notes.isEmpty &&
                widget.isAuthenticated)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: widget.onLoadPublicNotes,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Load notes'),
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
            // Cloud notes are grouped by course (folder) with expandable
            // sections, chronological order within each folder, and all
            // folders expanded by default.
            if (widget.isAuthenticated)
              for (final folder in _groupNotesByCourse(widget.notes))
                _NoteFolderSection(
                  folder: folder,
                  apiBaseUrl: widget.apiBaseUrl,
                  onOpen: _openViewer,
                  onEdit: _openEditor,
                  onExport: widget.onExportNote,
                  onDelete: widget.onDeleteNote,
                ),
            if (widget.isAuthenticated && localDrafts.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Local drafts',
                  style: Theme.of(context).textTheme.titleLarge),
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

/// Expandable folder grouping cloud notes by their course. Defaults to
/// expanded so everything is visible at a glance, and each inner row is a
/// regular `_LearnerNoteCard` so card behavior stays consistent with the
/// previous flat rendering.
class _NoteFolderSection extends StatefulWidget {
  const _NoteFolderSection({
    required this.folder,
    required this.apiBaseUrl,
    required this.onOpen,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  final _NoteFolder folder;
  final String? apiBaseUrl;
  final void Function(Map<String, dynamic> note) onOpen;
  final void Function(Map<String, dynamic> note) onEdit;
  final Future<void> Function(Map<String, dynamic> note) onExport;
  final Future<void> Function(Map<String, dynamic> note) onDelete;

  @override
  State<_NoteFolderSection> createState() => _NoteFolderSectionState();
}

class _NoteFolderSectionState extends State<_NoteFolderSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Theme(
        // Drop ExpansionTile's default divider so it blends into the card.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          onExpansionChanged: (value) => setState(() => _expanded = value),
          leading: Icon(
            _expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            widget.folder.title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${widget.folder.notes.length} note${widget.folder.notes.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final note in widget.folder.notes)
              _LearnerNoteCard(
                note: note,
                apiBaseUrl: widget.apiBaseUrl,
                canEdit: true,
                onOpen: () => widget.onOpen(note),
                onEdit: () => widget.onEdit(note),
                onExport: () => widget.onExport(note),
                onDelete: () => widget.onDelete(note),
              ),
          ],
        ),
      ),
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
    final coverUrl = note['cover_image_url']?.toString() ?? '';
    final uuid = note['uuid']?.toString() ?? '';
    final noteTitle = note['title']?.toString() ?? '';
    final isPublic = note['is_public'] == true;
    final author =
        Map<String, dynamic>.from(note['author'] as Map? ?? const {});
    final course =
        Map<String, dynamic>.from(note['course'] as Map? ?? const {});
    final authorName = author['username']?.toString() ?? '';
    final avatarFallback =
        authorName.isEmpty ? 'L' : authorName.substring(0, 1);
    final avatarUrl = _resolveRemoteUrl(
      author['image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    return Card(
      clipBehavior: coverUrl.isNotEmpty ? Clip.antiAlias : Clip.none,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coverUrl.isNotEmpty)
              NoteCoverImage(
                seed: uuid.isNotEmpty ? uuid : 'note-$noteTitle',
                imageUrl: coverUrl,
                caption: noteTitle,
                aspectRatio: 21 / 9,
                borderRadius: 0,
              ),
            Padding(
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
                                if ((course['title']?.toString() ?? '')
                                    .isNotEmpty)
                                  course['title'].toString(),
                                formatCompactTimestamp(
                                  note['last_edit']?.toString() ?? '',
                                ),
                              ].join(' | '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit')),
                          if (canSync)
                            const PopupMenuItem(
                                value: 'sync', child: Text('Sync to cloud')),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
