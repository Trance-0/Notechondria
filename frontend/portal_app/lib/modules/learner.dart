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

  /// Opens the note editor and records the note-edit session around the dialog.
  Future<void> _openEditor(Map<String, dynamic> noteSummary) async {
    final detail = await widget.onFetchNoteDetail(noteSummary['id'] as int);
    if (!mounted) {
      return;
    }
    widget.onLogEvent("Note editor opened: Portal.UI/open_editor \u2014 "
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
    widget.onLogEvent('Note shell created: Portal.UI/create_note \u2014 '
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
      items: [
        PopupMenuItem(
            value: 'new',
            child: Text(AppLocalizations.of(context).feedComposerCreate)),
        PopupMenuItem(
            value: 'import',
            child: Text(AppLocalizations.of(context).feedImportMarkdown)),
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
    final l10n = AppLocalizations.of(context);
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
                    ? l10n.feedSearchCloud
                    : l10n.feedSearchLocalDrafts,
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
                              l10n.feedUnsyncedDrafts,
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
                            label: Text(l10n.feedSyncAll),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.feedSyncHelp),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              widget.isAuthenticated
                  ? l10n.feedRecentNotes
                  : l10n.feedLocalDrafts,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (widget.isAuthenticated && widget.notes.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    localDrafts.isEmpty
                        ? l10n.feedEmptyPersonal
                        : l10n.feedEmptyCloudSynced,
                  ),
                ),
              ),
            if (!widget.isAuthenticated && localDrafts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.feedEmptyLocalLogin),
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
                  label: Text(l10n.feedLoadNotes),
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
              Text(l10n.feedLocalDrafts,
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
                  child: Text(widget.isLoadingMore
                      ? l10n.commonLoading
                      : l10n.courseLoadMore),
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
                ? l10n.feedFabImport
                : l10n.feedFabImportLocal,
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
                              note['title']?.toString() ??
                                  AppLocalizations.of(context).noteUntitled,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (isLocalDraft)
                                  AppLocalizations.of(context)
                                      .feedLocalDraftBadge
                                else if (isPublic)
                                  AppLocalizations.of(context).feedBadgePublic
                                else
                                  AppLocalizations.of(context).feedBadgePrivate,
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
                            PopupMenuItem(
                                value: 'edit',
                                child: Text(
                                    AppLocalizations.of(context).commonEdit)),
                          if (canSync)
                            PopupMenuItem(
                                value: 'sync',
                                child: Text(AppLocalizations.of(context)
                                    .feedSyncToCloud)),
                          PopupMenuItem(
                              value: 'export',
                              child: Text(AppLocalizations.of(context)
                                  .noteExportMarkdown)),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                  AppLocalizations.of(context).commonDelete)),
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
                        AppLocalizations.of(context).feedCourseMetaHint,
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
