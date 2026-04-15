part of notechondria_frontend;

class _CoursePage extends StatefulWidget {
  const _CoursePage({
    required this.courses,
    required this.localCourses,
    required this.selectedCourse,
    required this.notes,
    required this.localNotes,
    required this.isAuthenticated,
    required this.canCreateLocalCourses,
    required this.apiBaseUrl,
    required this.onCourseChanged,
    required this.onCreateLocalCourse,
    required this.onSyncLocalData,
    required this.onSubscribe,
    required this.onUnsubscribe,
    required this.onFetchNoteDetail,
  });

  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> localCourses;
  final Map<String, dynamic>? selectedCourse;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> localNotes;
  final bool isAuthenticated;
  final bool canCreateLocalCourses;
  final String? apiBaseUrl;
  final ValueChanged<Map<String, dynamic>> onCourseChanged;
  final Future<Map<String, dynamic>> Function(String title, String description)
      onCreateLocalCourse;
  final Future<ActionFeedback> Function({bool showMessage}) onSyncLocalData;
  final Future<void> Function(Map<String, dynamic> course) onSubscribe;
  final Future<void> Function(Map<String, dynamic> course) onUnsubscribe;
  final Future<Map<String, dynamic>> Function(int noteId) onFetchNoteDetail;

  @override
  State<_CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<_CoursePage> {
  late final TextEditingController _searchController;
  String _scope = 'public';
  Map<String, dynamic>? _openedCourse;
  Map<String, dynamic>? _openedModule;
  int _courseVisibleNotes = 4;
  int _moduleVisibleNotes = 4;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scope = widget.isAuthenticated ? 'subscribed' : 'mine';
  }

  @override
  void didUpdateWidget(covariant _CoursePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isAuthenticated && _scope == 'subscribed') {
      _scope = 'mine';
    }
    final selectedId = (widget.selectedCourse?['id'] as num?)?.toInt();
    final openedId = (_openedCourse?['id'] as num?)?.toInt();
    if (selectedId != null && openedId != null && selectedId == openedId) {
      _openedCourse = widget.selectedCourse;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> course, String query) {
    if (query.isEmpty) {
      return true;
    }
    final normalized = query.toLowerCase();
    final title = course['title']?.toString().toLowerCase() ?? '';
    final description = course['description']?.toString().toLowerCase() ?? '';
    return title.contains(normalized) || description.contains(normalized);
  }

  List<Map<String, dynamic>> _localNotesForCourse(Map<String, dynamic> course) {
    final courseId = (course['id'] as num?)?.toInt();
    return widget.localNotes.where((note) {
      final metadata =
          _decodeNoteMetadata(note['metadata_json']?.toString() ?? '{}');
      final assignedId = (metadata['course_id'] as num?)?.toInt() ??
          (note['course_id'] as num?)?.toInt();
      return assignedId == courseId;
    }).map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
  }

  List<Map<String, dynamic>> _visibleCourses() {
    final subscribed =
        widget.courses.where((course) => course['is_subscribed'] == true).toList();
    final mine = [
      ...widget.localCourses,
      ...widget.courses.where((course) => course['is_owned'] == true),
    ];
    var rows = switch (_scope) {
      'subscribed' => subscribed,
      'mine' => mine,
      _ => List<Map<String, dynamic>>.from(widget.courses),
    };
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      rows = rows.where((course) => _matches(course, query)).toList();
    }
    return rows;
  }

  Future<Map<String, dynamic>?> _showCreateLocalCourseDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create local course'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Course title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final created = await widget.onCreateLocalCourse(
                  titleController.text.trim(),
                  descriptionController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.of(context).pop(created);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      );
    } finally {
      titleController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _openCourse(Map<String, dynamic> course) async {
    setState(() {
      _openedCourse = course;
      _openedModule = null;
      _courseVisibleNotes = 4;
      _moduleVisibleNotes = 4;
    });
    widget.onCourseChanged(course);
  }

  Map<String, dynamic>? _activeCourse(List<Map<String, dynamic>> visibleCourses) {
    if (_openedCourse == null) {
      return null;
    }
    final openedId = (_openedCourse?['id'] as num?)?.toInt();
    if (openedId == null) {
      return _openedCourse;
    }
    final source = [
      ...visibleCourses,
      ...widget.courses,
      ...widget.localCourses,
    ];
    for (final course in source) {
      if ((course['id'] as num?)?.toInt() == openedId) {
        if ((widget.selectedCourse?['id'] as num?)?.toInt() == openedId) {
          return widget.selectedCourse;
        }
        return course;
      }
    }
    return _openedCourse;
  }

  List<Map<String, dynamic>> _courseNotes(Map<String, dynamic> course) {
    if (course['is_local_course'] == true) {
      return _localNotesForCourse(course);
    }
    if ((widget.selectedCourse?['id'] as num?)?.toInt() ==
        (course['id'] as num?)?.toInt()) {
      return widget.notes;
    }
    return (course['recent_notes'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _modulesFromNotes(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) {
      return const [];
    }
    final modules = <String, Map<String, dynamic>>{};
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      final metadata =
          _decodeNoteMetadata(note['metadata_json']?.toString() ?? '{}');
      final rawTitle = metadata['module_title']?.toString() ??
          metadata['section']?.toString() ??
          note['title']?.toString() ??
          'Module ${index + 1}';
      final title = rawTitle.trim().isEmpty ? 'Module ${index + 1}' : rawTitle.trim();
      final key = title.toLowerCase();
      final module = modules.putIfAbsent(
        key,
        () => {
          'id': metadata['module_id']?.toString() ?? 'module-$index',
          'title': title,
          'description': metadata['module_description']?.toString() ??
              note['description']?.toString() ??
              note['excerpt']?.toString() ??
              'Study materials and public discussion for this module.',
          'objectives': (metadata['objectives'] as List?)
                  ?.map((item) => item.toString())
                  .toList() ??
              <String>[
                note['description']?.toString().isNotEmpty == true
                    ? note['description'].toString()
                    : 'Review the module notes.',
              ],
          'assignments': (metadata['assignments'] as List?)
                  ?.map((item) => item.toString())
                  .toList() ??
              <String>[
                'Read the module notes.',
                'Review the discussion board.',
              ],
          'notes': <Map<String, dynamic>>[],
        },
      );
      (module['notes'] as List<Map<String, dynamic>>).add(note);
    }
    return modules.values.toList(growable: false);
  }

  Future<void> _openNote(Map<String, dynamic> note) async {
    final noteId = (note['id'] as num?)?.toInt();
    if (noteId == null) {
      return;
    }
    final detail = await widget.onFetchNoteDetail(noteId);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NoteViewerDialog(note: detail),
    );
  }

  Widget _topControls(BuildContext context, bool compact) {
    final search = TextField(
      key: const Key('course-public-search'),
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: _scope == 'public'
            ? 'Search public courses'
            : _scope == 'mine'
                ? 'Search local and owned courses'
                : 'Search subscribed courses',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
    final selector = _CourseScopeSelector(
      scope: _scope,
      isAuthenticated: widget.isAuthenticated,
      buttonKey: const Key('course-scope-selector'),
      onChanged: (value) {
        setState(() {
          _scope = value;
          _openedCourse = null;
          _openedModule = null;
        });
      },
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: selector),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 12),
        selector,
      ],
    );
  }

  Widget _scopeActions(BuildContext context) {
    if (_scope != 'mine') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (widget.canCreateLocalCourses)
            FilledButton.icon(
              onPressed: () async {
                final created = await _showCreateLocalCourseDialog();
                if (created != null && mounted) {
                  setState(() {
                    _openedCourse = created;
                    _openedModule = null;
                  });
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Create local course'),
            ),
          if (widget.isAuthenticated &&
              (widget.localCourses.isNotEmpty || widget.localNotes.isNotEmpty))
            OutlinedButton.icon(
              onPressed: () => widget.onSyncLocalData(showMessage: true),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Sync local data'),
            ),
        ],
      ),
    );
  }

  Widget _courseImage(Map<String, dynamic> course, {double? width, double? height}) {
    final coverUrl = _resolveRemoteUrl(
      course['cover_image_url']?.toString() ?? '',
      apiBaseUrl: widget.apiBaseUrl,
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: coverUrl.isEmpty
            ? Container(
                color: Theme.of(context).colorScheme.surfaceVariant,
                alignment: Alignment.center,
                child: const Icon(Icons.auto_stories_outlined, size: 42),
              )
            : _RemoteMedia(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                fallback: Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  alignment: Alignment.center,
                  child: const Icon(Icons.auto_stories_outlined, size: 42),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleCourses = _visibleCourses();
    final activeCourse = _activeCourse(visibleCourses);
    final activeNotes =
        activeCourse == null ? const <Map<String, dynamic>>[] : _courseNotes(activeCourse);
    final modules = _modulesFromNotes(activeNotes);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              _topControls(context, constraints.maxWidth < 900),
        ),
        _scopeActions(context),
        const SizedBox(height: 20),
        if (activeCourse == null) ...[
          if (visibleCourses.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _scope == 'subscribed'
                      ? 'No subscribed courses yet.'
                      : _scope == 'mine'
                          ? 'No local or owned courses matched the current search.'
                          : 'No public courses matched the current search.',
                ),
              ),
            ),
          for (var i = 0; i < visibleCourses.length; i++)
            _StaggeredFadeIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openCourse(visibleCourses[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final course = visibleCourses[i];
                          final compact = constraints.maxWidth < 720;
                          final content = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      course['title']?.toString() ?? 'Course',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: course['is_subscribed'] == true
                                        ? () => widget.onUnsubscribe(course)
                                        : (widget.isAuthenticated
                                            ? () => widget.onSubscribe(course)
                                            : () => _openCourse(course)),
                                    child: Text(
                                      course['is_subscribed'] == true
                                          ? 'Unsubscribe'
                                          : (widget.isAuthenticated
                                              ? 'Subscribe'
                                              : 'Open'),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                course['description']?.toString() ?? '',
                                maxLines: compact ? 3 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _CourseChip(
                                    label:
                                        '${course['subscriber_count'] ?? 0} subscribed',
                                  ),
                                  if (course['is_local_course'] == true)
                                    const _CourseChip(label: 'Local only'),
                                ],
                              ),
                            ],
                          );
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _courseImage(course, height: 112),
                                const SizedBox(height: 14),
                                content,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _courseImage(course, width: 168, height: 112),
                              const SizedBox(width: 16),
                              Expanded(child: content),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ] else if (_openedModule != null) ...[
          TextButton.icon(
            onPressed: () {
              setState(() {
                _openedModule = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: Text('Back to ${activeCourse['title'] ?? 'course'}'),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _openedModule!['title']?.toString() ?? 'Module',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(_openedModule!['description']?.toString() ?? ''),
                  const SizedBox(height: 16),
                  Text(
                    'Objectives',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final item
                      in (_openedModule!['objectives'] as List<dynamic>? ?? const []))
                    Text('• ${item.toString()}'),
                  const SizedBox(height: 16),
                  Text(
                    'Assignments',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final item
                      in (_openedModule!['assignments'] as List<dynamic>? ?? const []))
                    Text('• ${item.toString()}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _DiscussionBoard(
            title: 'Module discussion',
            notes: (_openedModule!['notes'] as List<dynamic>? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(growable: false),
            visibleCount: _moduleVisibleNotes,
            onOpenNote: _openNote,
            onLoadMore: () {
              setState(() {
                _moduleVisibleNotes += 4;
              });
            },
            emptyMessage: 'No public notes are available for this module yet.',
          ),
        ] else ...[
          TextButton.icon(
            onPressed: () {
              setState(() {
                _openedCourse = null;
                _openedModule = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to course results'),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 780;
                  final summary = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeCourse['title']?.toString() ?? 'Course',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(activeCourse['description']?.toString() ?? ''),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CourseChip(
                            label:
                                '${activeCourse['subscriber_count'] ?? 0} subscribed',
                          ),
                          if ((activeCourse['last_opened_at']?.toString() ?? '')
                              .isNotEmpty)
                            _CourseChip(
                              label:
                                  'Opened ${formatCompactTimestamp(activeCourse['last_opened_at'].toString())}',
                            ),
                        ],
                      ),
                      if (widget.isAuthenticated) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (activeCourse['is_subscribed'] == true)
                              OutlinedButton(
                                onPressed: () =>
                                    widget.onUnsubscribe(activeCourse),
                                child: const Text('Unsubscribe'),
                              ),
                            if (activeCourse['is_subscribed'] != true)
                              FilledButton(
                                onPressed: () => widget.onSubscribe(activeCourse),
                                child: const Text('Subscribe'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _courseImage(activeCourse, height: 176),
                        const SizedBox(height: 16),
                        summary,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _courseImage(activeCourse, width: 260, height: 176),
                      const SizedBox(width: 18),
                      Expanded(child: summary),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Modules',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (modules.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No modules have been mapped for this course yet.'),
              ),
            ),
          for (var i = 0; i < modules.length; i++)
            _StaggeredFadeIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    title: Text(modules[i]['title']?.toString() ?? 'Module'),
                    subtitle: Text(
                      modules[i]['description']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '${(modules[i]['notes'] as List<dynamic>? ?? const []).length} note(s)',
                    ),
                    onTap: () {
                      setState(() {
                        _openedModule = modules[i];
                        _moduleVisibleNotes = 4;
                      });
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          _DiscussionBoard(
            title: 'Course discussion',
            notes: activeNotes,
            visibleCount: _courseVisibleNotes,
            onOpenNote: _openNote,
            onLoadMore: () {
              setState(() {
                _courseVisibleNotes += 4;
              });
            },
            emptyMessage:
                'No public discussion notes are available for this course yet.',
          ),
        ],
      ],
    );
  }
}

class _CourseScopeSelector extends StatelessWidget {
  const _CourseScopeSelector({
    required this.scope,
    required this.isAuthenticated,
    required this.buttonKey,
    required this.onChanged,
  });

  final String scope;
  final bool isAuthenticated;
  final Key buttonKey;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <Map<String, String>>[
      {'value': 'public', 'label': 'Public courses'},
      {'value': 'mine', 'label': 'My courses'},
      if (isAuthenticated)
        {'value': 'subscribed', 'label': 'Subscribed courses'},
    ];
    final current =
        options.firstWhere((item) => item['value'] == scope, orElse: () => options.first);
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<String>(
            value: option['value'],
            child: Text(option['label']!),
          ),
      ],
      child: Container(
        key: buttonKey,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_outlined, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Course list',
                    style: Theme.of(context).textTheme.labelSmall),
                Text(
                  current['label']!,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }
}

class _DiscussionBoard extends StatelessWidget {
  const _DiscussionBoard({
    required this.title,
    required this.notes,
    required this.visibleCount,
    required this.onOpenNote,
    required this.onLoadMore,
    required this.emptyMessage,
  });

  final String title;
  final List<Map<String, dynamic>> notes;
  final int visibleCount;
  final ValueChanged<Map<String, dynamic>> onOpenNote;
  final VoidCallback onLoadMore;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final visible = notes.take(visibleCount).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (notes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyMessage),
            ),
          )
        else ...[
          for (var i = 0; i < visible.length; i++)
            _StaggeredFadeIn(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    title: Text(visible[i]['title']?.toString() ?? 'Untitled note'),
                    subtitle: Text(
                      visible[i]['description']?.toString() ??
                          visible[i]['excerpt']?.toString() ??
                          '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.arrow_forward_outlined),
                    onTap: () => onOpenNote(visible[i]),
                  ),
                ),
              ),
            ),
          if (notes.length > visible.length)
            TextButton(
              onPressed: onLoadMore,
              child: const Text('Load more'),
            ),
        ],
      ],
    );
  }
}

class _CourseChip extends StatelessWidget {
  const _CourseChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
