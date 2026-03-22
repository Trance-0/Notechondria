part of notechondria_frontend;

/// Course module for subscribed collections and public previews.
class _CoursePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final subscribed =
        courses.where((course) => course['is_subscribed'] == true).toList();
    final previews =
        courses.where((course) => course['is_subscribed'] != true).toList();
    final activeCourse = selectedCourse ??
        (subscribed.isNotEmpty ? subscribed.first : (courses.isNotEmpty ? courses.first : null));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (activeCourse != null)
          _CourseHeaderCard(
            course: activeCourse,
            apiBaseUrl: apiBaseUrl,
            isAuthenticated: isAuthenticated,
            onOpen: () => onCourseChanged(activeCourse),
            onSubscribe: () {
              onSubscribe(activeCourse);
            },
            onUnsubscribe: () {
              onUnsubscribe(activeCourse);
            },
          ),
        const SizedBox(height: 24),
        Text(
          isAuthenticated ? 'Subscribed courses' : 'Course previews',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (isAuthenticated && subscribed.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                previews.isEmpty
                    ? 'No courses available yet.'
                    : 'You are not subscribed to any course yet. Preview a course below and subscribe to bring it into your synced sidebar order.',
              ),
            ),
          ),
        if (isAuthenticated)
          for (final course in subscribed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseListCard(
                course: course,
                apiBaseUrl: apiBaseUrl,
                actionLabel: 'Unsubscribe',
                onTap: () => onCourseChanged(course),
                onAction: () {
                  onUnsubscribe(course);
                },
              ),
            ),
        if (previews.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Public previews',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final course in previews)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseListCard(
                course: course,
                apiBaseUrl: apiBaseUrl,
                actionLabel: isAuthenticated ? 'Subscribe' : 'Sign in',
                onTap: () => onCourseChanged(course),
                onAction: () {
                  if (isAuthenticated) {
                    onSubscribe(course);
                  } else {
                    onCourseChanged(course);
                  }
                },
              ),
            ),
        ],
        if (activeCourse != null) ...[
          const SizedBox(height: 24),
          Text(
            'Course notes',
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
                child: Text(
                  activeCourse['is_subscribed'] == true
                      ? 'No notes in this course yet.'
                      : 'Preview is available, but notes are limited until you subscribe or open a public course feed.',
                ),
              ),
            ),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  title: Text(note['title']?.toString() ?? 'Untitled note'),
                  subtitle: Text(note['excerpt']?.toString() ?? ''),
                  trailing: const Icon(Icons.arrow_forward_outlined),
                  onTap: () async {
                    final detail = await onFetchNoteDetail(note['id'] as int);
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
