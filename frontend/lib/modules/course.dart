part of notechondria_frontend;

class _CoursePage extends StatefulWidget {
  const _CoursePage({
    required this.courses,
    required this.selectedCourse,
    required this.notes,
    required this.isAuthenticated,
    required this.apiBaseUrl,
    required this.onCourseChanged,
    required this.onSubscribe,
    required this.onUnsubscribe,
    required this.onFetchNoteDetail,
  });

  final List<Map<String, dynamic>> courses;
  final Map<String, dynamic>? selectedCourse;
  final List<Map<String, dynamic>> notes;
  final bool isAuthenticated;
  final String? apiBaseUrl;
  final ValueChanged<Map<String, dynamic>> onCourseChanged;
  final Future<void> Function(Map<String, dynamic> course) onSubscribe;
  final Future<void> Function(Map<String, dynamic> course) onUnsubscribe;
  final Future<Map<String, dynamic>> Function(int noteId) onFetchNoteDetail;

  @override
  State<_CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<_CoursePage> {
  late final TextEditingController _searchController;
  String _scope = 'public';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scope = widget.isAuthenticated ? 'subscribed' : 'public';
  }

  @override
  void didUpdateWidget(covariant _CoursePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isAuthenticated && _scope != 'public') {
      setState(() => _scope = 'public');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _visibleCourses() {
    final subscribed =
        widget.courses.where((course) => course['is_subscribed'] == true).toList();
    var rows = <Map<String, dynamic>>[];
    if (_scope == 'subscribed') {
      rows = subscribed;
    } else if (_scope == 'mine') {
      return const [];
    } else {
      rows = List<Map<String, dynamic>>.from(widget.courses);
    }
    final query = _searchController.text.trim().toLowerCase();
    if (_scope == 'public' && query.isNotEmpty) {
      rows = rows.where((course) {
        final title = course['title']?.toString().toLowerCase() ?? '';
        final description =
            course['description']?.toString().toLowerCase() ?? '';
        return title.contains(query) || description.contains(query);
      }).toList();
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final visibleCourses = _visibleCourses();
    final scopeOptions = <Map<String, String>>[
      {
        'value': 'public',
        'label': 'Public courses',
        'compact': 'Public',
      },
      if (widget.isAuthenticated)
        {
          'value': 'subscribed',
          'label': 'Subscribed courses',
          'compact': 'Subscribed',
        },
      if (widget.isAuthenticated)
        {
          'value': 'mine',
          'label': 'My courses',
          'compact': 'Mine',
        },
    ];
    final activeCourse = visibleCourses.firstWhere(
      (course) => course['id'] == widget.selectedCourse?['id'],
      orElse: () =>
          visibleCourses.isNotEmpty ? visibleCourses.first : <String, dynamic>{},
    );
    final hasActiveCourse = activeCourse.isNotEmpty;
    final noteRows = widget.selectedCourse?['id'] == activeCourse['id']
        ? widget.notes
        : const <Map<String, dynamic>>[];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final selector = DropdownButtonFormField<String>(
              key: const Key('course-scope-selector'),
              value: _scope,
              isExpanded: true,
              selectedItemBuilder: (context) => scopeOptions
                  .map(
                    (option) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        compact ? option['compact']! : option['label']!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              items: [
                for (final option in scopeOptions)
                  DropdownMenuItem(
                    value: option['value'],
                    child: Text(option['label']!),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _scope = value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Course list',
                border: OutlineInputBorder(),
              ),
            );
            final scopeContent = _scope == 'public'
                ? TextField(
                    key: const Key('course-public-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search public courses',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  )
                : Text(
                    _scope == 'subscribed'
                        ? 'Your synced subscribed courses.'
                        : 'My courses is not available yet. Course creation is disabled.',
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  scopeContent,
                  const SizedBox(height: 12),
                  selector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: scopeContent),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: selector,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (_scope == 'mine')
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'My courses is not implemented yet. Users cannot create courses in the current build.',
              ),
            ),
          )
        else if (!hasActiveCourse)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _scope == 'subscribed'
                    ? 'No subscribed courses yet. Switch to public courses and subscribe to one first.'
                    : 'No public courses matched the current search.',
              ),
            ),
          )
        else ...[
          _CourseHeaderCard(
            course: activeCourse,
            apiBaseUrl: widget.apiBaseUrl,
            isAuthenticated: widget.isAuthenticated,
            onOpen: () => widget.onCourseChanged(activeCourse),
            onSubscribe: () => widget.onSubscribe(activeCourse),
            onUnsubscribe: () => widget.onUnsubscribe(activeCourse),
          ),
          const SizedBox(height: 20),
          for (final course in visibleCourses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseListCard(
                course: course,
                apiBaseUrl: widget.apiBaseUrl,
                actionLabel: course['is_subscribed'] == true
                    ? 'Unsubscribe'
                    : (widget.isAuthenticated ? 'Subscribe' : 'Open'),
                onTap: () => widget.onCourseChanged(course),
                onAction: () {
                  if (course['is_subscribed'] == true) {
                    widget.onUnsubscribe(course);
                  } else if (widget.isAuthenticated) {
                    widget.onSubscribe(course);
                  } else {
                    widget.onCourseChanged(course);
                  }
                },
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Course notes',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (noteRows.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.selectedCourse?['id'] == activeCourse['id']
                      ? (activeCourse['is_subscribed'] == true
                          ? 'No notes in this course yet.'
                          : 'Open a public course to browse its public notes, or subscribe to keep it in your synced list.')
                      : 'Select a course from the list to load its notes.',
                ),
              ),
            ),
          for (final note in noteRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  title: Text(note['title']?.toString() ?? 'Untitled note'),
                  subtitle: Text(note['excerpt']?.toString() ?? ''),
                  trailing: const Icon(Icons.arrow_forward_outlined),
                  onTap: () async {
                    final detail =
                        await widget.onFetchNoteDetail(note['id'] as int);
                    if (context.mounted) {
                      await showDialog<void>(
                        context: context,
                        builder: (context) => _NoteViewerDialog(note: detail),
                      );
                    }
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _CourseHeaderCard extends StatelessWidget {
  const _CourseHeaderCard({
    required this.course,
    required this.apiBaseUrl,
    required this.isAuthenticated,
    required this.onOpen,
    required this.onSubscribe,
    required this.onUnsubscribe,
  });

  final Map<String, dynamic> course;
  final String? apiBaseUrl;
  final bool isAuthenticated;
  final VoidCallback onOpen;
  final VoidCallback onSubscribe;
  final VoidCallback onUnsubscribe;

  @override
  Widget build(BuildContext context) {
    final coverUrl = _resolveRemoteUrl(
      course['cover_image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: coverUrl.isEmpty
                      ? Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(Icons.auto_stories_outlined, size: 46),
                        )
                      : Image.network(coverUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course['title']?.toString() ?? 'Course',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      course['description']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _CourseChip(
                          label:
                              '${course['subscriber_count'] ?? 0} subscribed',
                        ),
                        if ((course['last_opened_at']?.toString() ?? '')
                            .isNotEmpty)
                          _CourseChip(
                            label:
                                'Last opened ${_formatCompactTimestamp(course['last_opened_at'].toString())}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: onOpen,
                          child: const Text('Open course'),
                        ),
                        if (isAuthenticated && course['is_subscribed'] == true)
                          OutlinedButton(
                            onPressed: onUnsubscribe,
                            child: const Text('Unsubscribe'),
                          ),
                        if (isAuthenticated && course['is_subscribed'] != true)
                          OutlinedButton(
                            onPressed: onSubscribe,
                            child: const Text('Subscribe'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseListCard extends StatelessWidget {
  const _CourseListCard({
    required this.course,
    required this.apiBaseUrl,
    required this.actionLabel,
    required this.onTap,
    required this.onAction,
  });

  final Map<String, dynamic> course;
  final String? apiBaseUrl;
  final String actionLabel;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final coverUrl = _resolveRemoteUrl(
      course['cover_image_url']?.toString() ?? '',
      apiBaseUrl: apiBaseUrl,
    );
    final previewNotes = (course['recent_notes'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                height: 92,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: coverUrl.isEmpty
                      ? Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(Icons.collections_bookmark_outlined),
                        )
                      : Image.network(coverUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            course['title']?.toString() ?? 'Course',
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                        TextButton(
                          onPressed: onAction,
                          child: Text(actionLabel),
                        ),
                      ],
                    ),
                    Text(
                      course['description']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _CourseChip(
                          label: '${course['subscriber_count'] ?? 0} subscribed',
                        ),
                        for (final note in previewNotes.take(2))
                          _CourseChip(
                            label: note['title']?.toString() ?? 'Preview note',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}
