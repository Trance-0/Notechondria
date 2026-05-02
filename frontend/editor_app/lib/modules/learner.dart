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
    required this.isLocalCourseSelected,
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
  /// One of: `local`, `personal`, `private`, `public`.
  ///   local    — show only local drafts (no cloud call).
  ///   personal — own cloud notes (private + public).
  ///   private  — own cloud notes, private only.
  ///   public   — own cloud notes, public only.
  final String searchScope;
  final bool isAuthenticated;
  /// `true` when the user has a locally-created (offline) category open.
  /// In that case the page forces `searchScope = 'local'` because public
  /// or cloud-personal notes have no relationship to a category that
  /// only exists on this device.
  final bool isLocalCourseSelected;
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
        onUploadCover: widget.onUploadCover,
        onDeleteCover: widget.onDeleteCover,
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

  String _searchHint(String scope) {
    if (!widget.isAuthenticated) {
      return 'Search local drafts';
    }
    switch (scope) {
      case 'local':
        return 'Search local drafts';
      case 'private':
        return 'Search your private notes';
      case 'public':
        return 'Search your public notes';
      case 'personal':
      default:
        return 'Search your notes';
    }
  }

  String _cloudSectionLabel(String scope) {
    switch (scope) {
      case 'private':
        return 'Your private notes';
      case 'public':
        return 'Your public notes';
      case 'personal':
      default:
        return widget.isAuthenticated ? 'Recent notes' : 'Public notes';
    }
  }

  String _emptyCloudCopy(String scope) {
    if (!widget.isAuthenticated) {
      return 'No notes yet. Use the add button to create a local draft.';
    }
    switch (scope) {
      case 'private':
        return 'No private notes yet.';
      case 'public':
        return 'No public notes yet.';
      case 'personal':
      default:
        return 'No cloud notes yet. Use the add button to create one.';
    }
  }

  /// Builds the dropdown items the user picks from to filter the
  /// learner view. Authenticated users get the full four-option list
  /// (personal / private / public / local); anonymous users only
  /// see "Public notes" + "Local drafts only" because personal /
  /// private require a signed-in identity.
  List<DropdownMenuItem<String>> _buildScopeItems() {
    if (widget.isAuthenticated) {
      return const [
        DropdownMenuItem(value: 'personal', child: Text('Personal notes')),
        DropdownMenuItem(value: 'private', child: Text('Private notes')),
        DropdownMenuItem(value: 'public', child: Text('Public notes')),
        DropdownMenuItem(value: 'local', child: Text('Local drafts only')),
      ];
    }
    return const [
      DropdownMenuItem(value: 'all', child: Text('Public notes')),
      DropdownMenuItem(value: 'local', child: Text('Local drafts only')),
    ];
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
    // When the user opens a locally-created category, public/personal
    // cloud notes are unrelated to it, so we force the filter to
    // `local` regardless of what they last picked from the dropdown.
    // For anonymous users, the only valid cloud scope is `all`
    // (public-only on the backend) — coerce stale auth-time scopes
    // like `personal` / `private` to `all` so the dropdown widget
    // value matches one of its items.
    final rawScope =
        widget.isLocalCourseSelected ? 'local' : widget.searchScope;
    final effectiveScope = widget.isAuthenticated
        ? rawScope
        : (rawScope == 'local' ? 'local' : 'all');
    final showCloudNotes = effectiveScope != 'local';
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
                hintText: _searchHint(effectiveScope),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              child: Row(
                children: [
                  Text(
                    'Show:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: effectiveScope,
                      isDense: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _buildScopeItems(),
                      onChanged: widget.isLocalCourseSelected
                          ? null
                          : (value) {
                              if (value != null) {
                                widget.onSearchScopeChanged(value);
                              }
                            },
                    ),
                  ),
                  if (widget.isLocalCourseSelected) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          'Local categories only contain local drafts. '
                          'Switch to a synced category to filter cloud notes.',
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.isAuthenticated &&
                localDrafts.isNotEmpty &&
                effectiveScope == 'personal') ...[
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
            if (localDrafts.isNotEmpty &&
                (effectiveScope == 'local' ||
                    effectiveScope == 'personal')) ...[
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
            if (showCloudNotes) ...[
              Text(
                _cloudSectionLabel(effectiveScope),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (widget.notes.isEmpty && localDrafts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _emptyCloudCopy(effectiveScope),
                    ),
                  ),
                ),
              if (widget.notes.isEmpty &&
                  localDrafts.isNotEmpty &&
                  widget.isAuthenticated)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No matching cloud notes yet. Sync a local draft or '
                      'create a new note.',
                    ),
                  ),
                ),
              if (widget.offlineMode && widget.notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: widget.onLoadPublicNotes,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Load public notes'),
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
            ] else if (effectiveScope == 'local' && localDrafts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.isLocalCourseSelected
                        ? 'No local drafts in this offline category yet. '
                            'Use the add button to create one.'
                        : 'No local drafts yet. Use the add button to '
                            'create one.',
                  ),
                ),
              ),
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
    final uuid = note['uuid']?.toString() ?? '';
    final title = note['title']?.toString() ?? '';
    final coverUrl = _resolveRemoteUrl(
      note['cover_image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    // Show a Bootstrap-card-style cover banner on PUBLIC cloud notes
    // (the only ones whose cover image is meaningful to other
    // readers). Private cloud notes and unsynced local drafts skip
    // the banner so the card reads as a compact list row instead of
    // a feature card.
    final showCoverBanner = isPublic && !isLocalDraft;
    return Card(
      clipBehavior: Clip.antiAlias,
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
        child: LayoutBuilder(builder: (ctx, constraints) {
          // Wide enough for a side-by-side cover + body layout.
          // Below this threshold the card stays vertical (cover
          // banner on top, content below) — that reads better on
          // phone-width and narrow drawer-list contexts. The
          // threshold matches the editor's compact / wide
          // scaffold breakpoint roughly so a card transitions at
          // the same visual moment the rest of the app does.
          final horizontal = showCoverBanner && constraints.maxWidth >= 600;
          final cover = NoteCoverImage(
            seed: uuid.isNotEmpty ? uuid : 'note-$title',
            imageUrl: coverUrl.isNotEmpty ? coverUrl : null,
            caption: title,
            showCaption: coverUrl.isEmpty,
            aspectRatio: horizontal ? 4 / 3 : 21 / 9,
            borderRadius: 0,
          );
          final body = Padding(
            padding: const EdgeInsets.all(16),
            child: _LearnerNoteCardBody(
              note: note,
              previewLines: previewLines,
              isPublic: isPublic,
              author: author,
              course: course,
              authorName: authorName,
              avatarFallback: avatarFallback,
              avatarUrl: avatarUrl,
              isLocalDraft: isLocalDraft,
              canSync: canSync,
              onSync: onSync,
            ),
          );
          if (horizontal) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: SizedBox(height: 200, child: cover)),
                Expanded(flex: 6, child: body),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showCoverBanner) cover,
              body,
            ],
          );
        }),
      ),
    );
  }
}

/// Right-side body of `_LearnerNoteCard` — avatar + title + state
/// badge + preview lines + the single sync/status icon. Extracted
/// so the parent card can render it both inside a vertical Column
/// (under a cover banner) and inside a horizontal Row (next to a
/// 4:6 cover thumbnail) without duplicating the layout. Pulled out
/// in 0.1.84 with the horizontal-cover layout addition.
class _LearnerNoteCardBody extends StatelessWidget {
  const _LearnerNoteCardBody({
    required this.note,
    required this.previewLines,
    required this.isPublic,
    required this.author,
    required this.course,
    required this.authorName,
    required this.avatarFallback,
    required this.avatarUrl,
    required this.isLocalDraft,
    required this.canSync,
    required this.onSync,
  });

  final Map<String, dynamic> note;
  final List<String> previewLines;
  final bool isPublic;
  final Map<String, dynamic> author;
  final Map<String, dynamic> course;
  final String authorName;
  final String avatarFallback;
  final String avatarUrl;
  final bool isLocalDraft;
  final bool canSync;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    return Column(
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
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Visual badge distinguishing the four note
                        // states — Local draft, Public, Private — at
                        // a glance. The text row below it carries the
                        // category and last-edit metadata.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _NoteStateBadge(
                              isLocalDraft: isLocalDraft,
                              isPublic: isPublic,
                            ),
                            if ((course['title']?.toString() ?? '').isNotEmpty)
                              Text(
                                course['title'].toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            Text(
                              formatCompactTimestamp(
                                note['last_edit']?.toString() ?? '',
                              ),
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
                      ],
                    ),
                  ),
                  // Single status / action icon. Three states for
                  // local drafts (offline-only / unsynced / failed)
                  // plus a static cloud-done indicator for cloud
                  // notes. Replaces the prior split where both an
                  // inline status icon AND an action button rendered
                  // simultaneously.
                  Builder(builder: (ctx) {
                    if (!isLocalDraft) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Tooltip(
                          message: 'Synced to cloud',
                          child: Icon(
                            Icons.cloud_done_outlined,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                      );
                    }
                    final lastSyncError =
                        note['last_sync_error']?.toString() ?? '';
                    final hasFailure = lastSyncError.isNotEmpty;
                    if (canSync && onSync != null) {
                      return IconButton(
                        tooltip: hasFailure
                            ? 'Sync failed: $lastSyncError\nTap to retry.'
                            : 'Sync to cloud',
                        icon: Icon(
                          hasFailure
                              ? Icons.sync_problem_outlined
                              : Icons.cloud_upload_outlined,
                          color: hasFailure
                              ? Theme.of(ctx).colorScheme.error
                              : null,
                        ),
                        onPressed: () async {
                          await onSync!();
                        },
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Tooltip(
                        message: 'Offline draft — sign in to sync.',
                        child: Icon(
                          Icons.cloud_off_outlined,
                          size: 18,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }),
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
            ],
          );
  }
}

/// Compact pill-style badge showing a note's persistence state.
/// Three variants:
///   * Local draft — only on this device, not synced (yellow / tertiary).
///   * Private — synced, not visible to other users (neutral surface).
///   * Public — synced, visible to other users (primary).
/// Shape and color give the user an at-a-glance signal next to the
/// note title so they don't have to read the metadata text.
class _NoteStateBadge extends StatelessWidget {
  const _NoteStateBadge({
    required this.isLocalDraft,
    required this.isPublic,
  });

  final bool isLocalDraft;
  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color background;
    late final Color foreground;
    late final IconData icon;
    late final String label;
    if (isLocalDraft) {
      background = scheme.tertiaryContainer;
      foreground = scheme.onTertiaryContainer;
      icon = Icons.cloud_off_outlined;
      label = 'Local draft';
    } else if (isPublic) {
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
      icon = Icons.public;
      label = 'Public';
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
      icon = Icons.lock_outline;
      label = 'Private';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
