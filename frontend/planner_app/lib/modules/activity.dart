part of notechondria_frontend;

/// Activity module showing planner events, note sessions, and calendar feeds.
class _ActivityPage extends StatefulWidget {
  const _ActivityPage({
    required this.activityWeek,
    required this.isAuthenticated,
    required this.plannerEvents,
    required this.onCreatePlannerEvent,
    required this.onImportCalendar,
    required this.onSubscribeCalendar,
    required this.onNavigateWeek,
    required this.onShiftStartDay,
    required this.onTogglePlannerEventCompletion,
    this.courses = const <Map<String, dynamic>>[],
    this.onEditCourse,
  });

  final Map<String, dynamic>? activityWeek;
  final bool isAuthenticated;
  final List<Map<String, dynamic>> plannerEvents;
  final List<Map<String, dynamic>> courses;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent;
  final Future<void> Function(String rawIcal, String title, {int? courseId})
      onImportCalendar;
  final Future<void> Function(String title, String url, {int? courseId})
      onSubscribeCalendar;
  final Future<void> Function(int direction) onNavigateWeek;
  final Future<void> Function(int dayDelta) onShiftStartDay;
  final Future<void> Function(Map<String, dynamic> event, bool completed)
      onTogglePlannerEventCompletion;

  /// Owner-only course metadata editor opened from the filter bar's
  /// settings button; null hides the button.
  final Future<ActionFeedback> Function(
    Map<String, dynamic> course,
    Map<String, dynamic> payload,
  )? onEditCourse;

  @override
  State<_ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<_ActivityPage> {
  // null = show every course; otherwise only events with this course_id.
  int? _courseFilter;

  List<Map<String, dynamic>> _filterDays(List<Map<String, dynamic>> days) {
    if (_courseFilter == null) {
      return days;
    }
    return [
      for (final day in days)
        {
          ...day,
          'events': [
            for (final event in (day['events'] as List<dynamic>? ?? const []))
              if ((event as Map)['course_id'] == _courseFilter) event,
          ],
        },
    ];
  }

  List<Map<String, dynamic>> _filterEvents(List<Map<String, dynamic>> events) {
    if (_courseFilter == null) {
      return events;
    }
    return [
      for (final event in events)
        if (event['course_id'] == _courseFilter) event,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _filterDays(
        (widget.activityWeek?['days'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList());
    final deadlines = _filterEvents(
        (widget.activityWeek?['deadlines'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList());
    final plannerEvents = _filterEvents(widget.plannerEvents);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = MediaQuery.of(context).size.width >= 960;
        final hasOfflinePlannerData =
            plannerEvents.isNotEmpty || deadlines.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _CourseFilterBar(
                courses: widget.courses,
                selectedCourseId: _courseFilter,
                onChanged: (value) => setState(() => _courseFilter = value),
                onEditSelected: widget.onEditCourse == null
                    ? null
                    : () {
                        final id = _courseFilter;
                        if (id == null) return;
                        Map<String, dynamic>? match;
                        for (final course in widget.courses) {
                          if ((course['id'] as num?)?.toInt() == id) {
                            match = course;
                            break;
                          }
                        }
                        if (match != null) {
                          _showCourseEditDialog(
                              context, match, widget.onEditCourse!);
                        }
                      },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: (!widget.isAuthenticated && !hasOfflinePlannerData)
                          ? const _ActivityFillCard(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: Text(
                                    'No local planner events yet. Add one with the button below, or sign in to view synced deadlines and calendar feeds.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            )
                          : (!widget.isAuthenticated || !isHorizontal)
                              ? _VerticalWeekBoard(
                                  days: weekDays,
                                  deadlines: deadlines,
                                  plannerEvents: plannerEvents,
                                  onNavigateWeek: widget.onNavigateWeek,
                                  onTogglePlannerEventCompletion:
                                      widget.onTogglePlannerEventCompletion,
                                )
                              : (weekDays.isEmpty
                                  ? const _ActivityFillCard(
                                      child: Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(20),
                                          child: Text(
                                            'No weekly events are available for the current view.',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    )
                                  : _WideWeekCalendar(
                                      days: weekDays,
                                      onNavigateWeek: widget.onNavigateWeek,
                                      onShiftStartDay: widget.onShiftStartDay,
                                    )),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: _RoundActivityFab(
                        onCreatePlannerEvent: widget.onCreatePlannerEvent,
                        onImportCalendar: widget.onImportCalendar,
                        onSubscribeCalendar: widget.onSubscribeCalendar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Top-of-activity filter that narrows the calendar + deadlines to a single
/// course, with a settings button to edit the selected course's attributes
/// (disabled with a tooltip while the filter is on "All courses"). Hidden
/// when the user has no courses.
class _CourseFilterBar extends StatelessWidget {
  const _CourseFilterBar({
    required this.courses,
    required this.selectedCourseId,
    required this.onChanged,
    this.onEditSelected,
  });

  final List<Map<String, dynamic>> courses;
  final int? selectedCourseId;
  final void Function(int?) onChanged;
  final VoidCallback? onEditSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <int, String>{};
    for (final course in courses) {
      final id = course['id'];
      if (id is int) {
        final title = course['title']?.toString() ?? '';
        entries[id] = title.isEmpty ? 'Course $id' : title;
      }
    }
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final value =
        entries.containsKey(selectedCourseId) ? selectedCourseId : null;
    return Row(
      children: [
        const Icon(Icons.filter_list, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButton<int?>(
            isExpanded: true,
            value: value,
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(l10n.activityAllCourses),
              ),
              for (final entry in entries.entries)
                DropdownMenuItem<int?>(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
        if (onEditSelected != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: value == null
                ? 'Select a specific course to edit its attributes'
                : 'Edit course attributes (colour, title, description)',
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: value == null ? null : onEditSelected,
            ),
          ),
        ],
      ],
    );
  }
}

/// Owner-only course metadata editor: title, description, and the accent
/// hue that colours this course's events on the calendar.
Future<void> _showCourseEditDialog(
  BuildContext context,
  Map<String, dynamic> course,
  Future<ActionFeedback> Function(
    Map<String, dynamic> course,
    Map<String, dynamic> payload,
  ) onSubmit,
) async {
  final titleController =
      TextEditingController(text: course['title']?.toString() ?? '');
  final descriptionController =
      TextEditingController(text: course['description']?.toString() ?? '');
  double? hue = (course['color_hue'] as num?)?.toDouble();
  ActionFeedback? feedback;
  var submitting = false;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final currentHue = hue;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final preview = currentHue == null
            ? Theme.of(context).colorScheme.primary
            : HSVColor.fromAHSV(
                    1, currentHue.clamp(0, 359), 0.55, isDark ? 0.6 : 0.9)
                .toColor();
        return AlertDialog(
          title: const Text('Edit course'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: preview,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: currentHue == null
                            ? const Text('Theme default colour')
                            : Slider(
                                min: 0,
                                max: 359,
                                value: currentHue.clamp(0, 359).toDouble(),
                                onChanged: (value) =>
                                    setState(() => hue = value),
                              ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: currentHue != null,
                        onChanged: (checked) => setState(
                            () => hue = (checked == true) ? 200.0 : null),
                      ),
                      const Expanded(
                        child: Text(
                            'Custom hue (colours this course\'s events on the calendar)'),
                      ),
                    ],
                  ),
                  if (feedback != null) ...[
                    const SizedBox(height: 8),
                    FeedbackText(feedback: feedback!),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setState(() {
                        submitting = true;
                        feedback = null;
                      });
                      final trimmedTitle = titleController.text.trim();
                      final result = await onSubmit(course, {
                        'title': trimmedTitle.isEmpty
                            ? (course['title']?.toString() ?? 'Course')
                            : trimmedTitle,
                        'description': descriptionController.text,
                        'color_hue': hue?.round(),
                      });
                      if (result.isError) {
                        setState(() {
                          submitting = false;
                          feedback = result;
                        });
                        return;
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

class _ActivityFillCard extends StatelessWidget {
  const _ActivityFillCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _VerticalWeekBoard extends StatelessWidget {
  const _VerticalWeekBoard({
    required this.days,
    required this.deadlines,
    required this.plannerEvents,
    required this.onNavigateWeek,
    required this.onTogglePlannerEventCompletion,
  });

  final List<Map<String, dynamic>> days;
  final List<Map<String, dynamic>> deadlines;
  final List<Map<String, dynamic>> plannerEvents;
  final Future<void> Function(int direction) onNavigateWeek;
  final Future<void> Function(Map<String, dynamic> event, bool completed)
      onTogglePlannerEventCompletion;

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final rangeLabel = days.isEmpty
        ? 'This week'
        : '${_formatWeekDay(days.first['date']?.toString() ?? '')} - ${_formatWeekDay(days.last['date']?.toString() ?? '')}';
    return _ActivityFillCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: () => onNavigateWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    rangeLabel,
                    key: const Key('activity-vertical-range-label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: () => onNavigateWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: _DeadlineList(
              deadlines: deadlines,
              plannerEvents: plannerEvents,
              onTogglePlannerEventCompletion: onTogglePlannerEventCompletion,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundActivityFab extends StatelessWidget {
  const _RoundActivityFab({
    required this.onCreatePlannerEvent,
    required this.onImportCalendar,
    required this.onSubscribeCalendar,
  });

  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent;
  final Future<void> Function(String rawIcal, String title, {int? courseId})
      onImportCalendar;
  final Future<void> Function(String title, String url, {int? courseId})
      onSubscribeCalendar;

  Future<void> _showMenu(BuildContext context, TapDownDetails? details) async {
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
        PopupMenuItem(value: 'create', child: Text('Create event')),
        PopupMenuItem(value: 'import', child: Text('Import iCal')),
        PopupMenuItem(value: 'subscribe', child: Text('Subscribe calendar')),
      ],
    );
    if (!context.mounted || selected == null) {
      return;
    }
    if (selected == 'import') {
      await _showImportCalendarDialog(context, onImportCalendar);
      return;
    }
    if (selected == 'subscribe') {
      await _showSubscribeCalendarDialog(context, onSubscribeCalendar);
      return;
    }
    await _showCreatePlannerEventDialog(context, onCreatePlannerEvent);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Tap to create a new event. Long press or right click to import iCal or subscribe.',
      child: GestureDetector(
        onLongPressStart: (details) => _showMenu(
          context,
          TapDownDetails(globalPosition: details.globalPosition),
        ),
        onSecondaryTapDown: (details) => _showMenu(context, details),
        child: FloatingActionButton(
          shape: const CircleBorder(),
          onPressed: () {
            _showCreatePlannerEventDialog(
              context,
              onCreatePlannerEvent,
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _DeadlineList extends StatelessWidget {
  const _DeadlineList({
    required this.deadlines,
    required this.plannerEvents,
    required this.onTogglePlannerEventCompletion,
  });

  final List<Map<String, dynamic>> deadlines;
  final List<Map<String, dynamic>> plannerEvents;
  final Future<void> Function(Map<String, dynamic> event, bool completed)
      onTogglePlannerEventCompletion;

  @override
  Widget build(BuildContext context) {
    if (deadlines.isEmpty) {
      return SizedBox.expand(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              plannerEvents.isEmpty
                  ? 'No active deadlines yet. Use the add button to create one.'
                  : 'No urgent deadlines remain in the current view.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: deadlines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = deadlines[index];
        final urgency = (event['urgency_score'] as num?)?.toDouble() ?? 0;
        final isCompleted = event['is_completed'] == true;
        return Card(
          child: Opacity(
            opacity: isCompleted ? 0.6 : 1,
            child: CheckboxListTile(
            value: isCompleted,
            onChanged: (value) =>
                onTogglePlannerEventCompletion(event, value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              event['title']?.toString() ?? 'Deadline',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                  ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((event['description']?.toString() ?? '').isNotEmpty)
                    Text(event['description'].toString()),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DeadlineBadge(
                        label:
                            'Due ${_formatDeadlineStamp(event['starts_at']?.toString() ?? event['event_date']?.toString() ?? '')}',
                      ),
                      _DeadlineBadge(
                        label: 'Weight ${event['difficulty_weight'] ?? 1}',
                      ),
                      _DeadlineBadge(
                        label: 'Urgency ${urgency.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
