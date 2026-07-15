part of notechondria_frontend;

/// Activity module showing planner events, note sessions, and calendar feeds.
class _ActivityPage extends StatefulWidget {
  const _ActivityPage({
    required this.activityWeek,
    required this.isAuthenticated,
    required this.plannerEvents,
    required this.courses,
    required this.rangeDays,
    required this.onCreatePlannerEvent,
    required this.onImportCalendar,
    required this.onSubscribeCalendar,
    required this.onNavigateWeek,
    required this.onShiftStartDay,
    required this.onChangeRange,
    required this.onTogglePlannerEventCompletion,
    required this.onUpdatePlannerEvent,
    this.onEditCourse,
  });

  final Map<String, dynamic>? activityWeek;
  final bool isAuthenticated;
  final List<Map<String, dynamic>> plannerEvents;
  final List<Map<String, dynamic>> courses;
  final int rangeDays;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description, {
    DateTime? endsAt,
    int? courseId,
  }) onCreatePlannerEvent;
  final Future<Map<String, dynamic>?> Function(String rawIcal, String title,
      {int? courseId}) onImportCalendar;
  final Future<Map<String, dynamic>?> Function(String title, String url,
      {int? courseId}) onSubscribeCalendar;
  final Future<void> Function(int direction) onNavigateWeek;
  final Future<void> Function(int dayDelta) onShiftStartDay;
  final Future<void> Function(int days) onChangeRange;
  final Future<void> Function(Map<String, dynamic> event, bool completed)
      onTogglePlannerEventCompletion;
  final Future<void> Function(
          Map<String, dynamic> event, Map<String, dynamic> changes)
      onUpdatePlannerEvent;

  /// Owner-only course metadata editor opened from the filter bar's
  /// settings button; null hides the button entirely.
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

  /// Keeps only events matching the active course filter, per day.
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
    final l10n = AppLocalizations.of(context);
    final weekDays = _filterDays(
      (widget.activityWeek?['days'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
    final deadlines = _filterEvents(
      (widget.activityWeek?['deadlines'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = MediaQuery.of(context).size.width >= 960;
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
                    // Signed-out users get the same calendar + FAB, served
                    // from device-local events (0.1.162) — the old
                    // full-surface sign-in prompt blocked offline planning.
                    Positioned.fill(
                      child: isHorizontal
                          ? (weekDays.isEmpty
                              ? _ActivityFillCard(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        l10n.activityNoWeekEvents,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                )
                              : _WideWeekCalendar(
                                  days: weekDays,
                                  rangeDays: widget.rangeDays,
                                  courses: widget.courses,
                                  onNavigateWeek: widget.onNavigateWeek,
                                  onShiftStartDay: widget.onShiftStartDay,
                                  onChangeRange: widget.onChangeRange,
                                  onCreatePlannerEvent:
                                      widget.onCreatePlannerEvent,
                                  onUpdatePlannerEvent:
                                      widget.onUpdatePlannerEvent,
                                ))
                          : _VerticalWeekBoard(
                              days: weekDays,
                              deadlines: deadlines,
                              plannerEvents:
                                  _filterEvents(widget.plannerEvents),
                              onNavigateWeek: widget.onNavigateWeek,
                              onTogglePlannerEventCompletion:
                                  widget.onTogglePlannerEventCompletion,
                            ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: _RoundActivityFab(
                        onCreatePlannerEvent: widget.onCreatePlannerEvent,
                        onImportCalendar: widget.onImportCalendar,
                        onSubscribeCalendar: widget.onSubscribeCalendar,
                        courses: widget.courses,
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
/// course (category). Hidden when the user has no courses.
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

  /// Opens the course-metadata editor for the selected course. The button
  /// renders disabled (with an explanatory tooltip) while the filter is on
  /// "All courses" — course attributes are edited one course at a time.
  final VoidCallback? onEditSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // De-duplicate courses by id (local + cloud lists can overlap).
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
    // Guard against a stale selection (e.g. an unsubscribed course).
    final value = entries.containsKey(selectedCourseId) ? selectedCourseId : null;
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
    final l10n = AppLocalizations.of(context);
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    final rangeLabel = days.isEmpty
        ? l10n.activityThisWeek
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
                  tooltip: l10n.activityPrevWeek,
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
                  tooltip: l10n.activityNextWeek,
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
    this.courses = const <Map<String, dynamic>>[],
  });

  final List<Map<String, dynamic>> courses;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description, {
    DateTime? endsAt,
    int? courseId,
  }) onCreatePlannerEvent;
  final Future<Map<String, dynamic>?> Function(String rawIcal, String title,
      {int? courseId}) onImportCalendar;
  final Future<Map<String, dynamic>?> Function(String title, String url,
      {int? courseId}) onSubscribeCalendar;

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
      items: [
        PopupMenuItem(
            value: 'create',
            child: Text(AppLocalizations.of(context).activityCreateEvent)),
        PopupMenuItem(
            value: 'import',
            child: Text(AppLocalizations.of(context).activityImportIcal)),
        PopupMenuItem(
            value: 'subscribe',
            child:
                Text(AppLocalizations.of(context).activitySubscribeCalendar)),
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
    await _showCreatePlannerEventDialog(context, onCreatePlannerEvent,
        courses: courses);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context).activityFabHint,
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
              courses: courses,
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
                  ? AppLocalizations.of(context).activityNoDeadlines
                  : AppLocalizations.of(context).activityNoUrgent,
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
