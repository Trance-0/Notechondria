part of notechondria_frontend;

/// Activity module showing planner events, note sessions, and calendar feeds.
class _ActivityPage extends StatelessWidget {
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
  });

  final Map<String, dynamic>? activityWeek;
  final bool isAuthenticated;
  final List<Map<String, dynamic>> plannerEvents;
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

  @override
  Widget build(BuildContext context) {
    final weekDays = (activityWeek?['days'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final deadlines = (activityWeek?['deadlines'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = MediaQuery.of(context).size.width >= 960;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: !isAuthenticated
                    ? const _ActivityFillCard(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'Sign in to view your deadlines, synced study sessions, and weekly calendar.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    : isHorizontal
                        ? (weekDays.isEmpty
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
                                onNavigateWeek: onNavigateWeek,
                                onShiftStartDay: onShiftStartDay,
                              ))
                        : _VerticalWeekBoard(
                            days: weekDays,
                            deadlines: deadlines,
                            plannerEvents: plannerEvents,
                            onNavigateWeek: onNavigateWeek,
                            onTogglePlannerEventCompletion:
                                onTogglePlannerEventCompletion,
                          ),
              ),
              if (isAuthenticated)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: _RoundActivityFab(
                    onCreatePlannerEvent: onCreatePlannerEvent,
                    onImportCalendar: onImportCalendar,
                    onSubscribeCalendar: onSubscribeCalendar,
                  ),
                ),
            ],
          ),
        );
      },
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
        return Card(
          child: CheckboxListTile(
            value: event['is_completed'] == true,
            onChanged: (value) =>
                onTogglePlannerEventCompletion(event, value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              event['title']?.toString() ?? 'Deadline',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
