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
        final isHorizontal = constraints.maxWidth >= constraints.maxHeight;
        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: isAuthenticated && isHorizontal
                            ? () {
                                onNavigateWeek(-1);
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          weekDays.isEmpty
                              ? (isHorizontal
                                  ? 'Week calendar'
                                  : 'Recent deadlines')
                              : '${_formatWeekDay(weekDays.first['date']?.toString() ?? '')} - ${_formatWeekDay(weekDays.last['date']?.toString() ?? '')}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: isAuthenticated && isHorizontal
                            ? () {
                                onNavigateWeek(1);
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    child: !isAuthenticated
                        ? const Card(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Sign in to view your deadlines, synced study sessions, and weekly calendar.',
                                ),
                              ),
                            ),
                          )
                        : isHorizontal
                            ? (weekDays.isEmpty
                                ? const SizedBox.shrink()
                                : _WideWeekCalendar(days: weekDays))
                            : _DeadlineList(
                                deadlines: deadlines,
                                plannerEvents: plannerEvents,
                                onTogglePlannerEventCompletion:
                                    onTogglePlannerEventCompletion,
                              ),
                  ),
                ),
              ],
            ),
            if (isAuthenticated)
              Positioned(
                left: 24,
                bottom: 24,
                child: _RoundActivityFab(
                  onCreatePlannerEvent: onCreatePlannerEvent,
                  onImportCalendar: onImportCalendar,
                  onSubscribeCalendar: onSubscribeCalendar,
                ),
              ),
          ],
        );
      },
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            plannerEvents.isEmpty
                ? 'No active deadlines yet. Use the add button to create one.'
                : 'No urgent deadlines remain in the current view.',
          ),
        ),
      );
    }
    return ListView.separated(
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

/// Wide calendar layout with days as columns and hours on the vertical axis.
class _WideWeekCalendar extends StatelessWidget {
  const _WideWeekCalendar({required this.days});

  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    const hourHeight = 68.0;
    const labelWidth = 72.0;
    final totalHeight = hourHeight * 24;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  for (var hour = 0; hour < 24; hour++)
                    SizedBox(
                      height: hourHeight,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text('${hour.toString().padLeft(2, '0')}:00'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (final day in days)
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                              left: BorderSide(color: Color(0xFFE5E7EB))),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xFFE5E7EB))),
                              ),
                              child: Text(_formatWeekDay(
                                  day['date']?.toString() ?? '')),
                            ),
                            SizedBox(
                              height: totalHeight,
                              child: Stack(
                                children: [
                                  for (var hour = 0; hour < 24; hour++)
                                    Positioned(
                                      top: hour * hourHeight,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: hourHeight,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                              bottom: BorderSide(
                                                  color: Color(0xFFE5E7EB))),
                                        ),
                                      ),
                                    ),
                                  for (final event
                                      in (day['events'] as List<dynamic>? ??
                                          const []))
                                    _CalendarEventTile(
                                      event: Map<String, dynamic>.from(
                                          event as Map),
                                      vertical: true,
                                      slotExtent: hourHeight,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a time-bounded event block inside the week calendar grid.
class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({
    required this.event,
    required this.vertical,
    required this.slotExtent,
  });

  final Map<String, dynamic> event;
  final bool vertical;
  final double slotExtent;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(event['starts_at']?.toString() ?? '');
    final end = DateTime.tryParse(event['ends_at']?.toString() ?? '');
    final startMinutes = start == null
        ? 0
        : (start.toLocal().hour * 60) + start.toLocal().minute;
    final endMinutes = end == null
        ? startMinutes + 60
        : (end.toLocal().hour * 60) + end.toLocal().minute;
    final spanMinutes = math.max(30, endMinutes - startMinutes);
    final offset = (startMinutes / 60.0) * slotExtent;
    final extent = (spanMinutes / 60.0) * slotExtent;
    final color = _calendarEventColor(event['kind']?.toString() ?? '');

    if (vertical) {
      return Positioned(
        top: offset + 2,
        left: 6,
        right: 6,
        height: math.max(24, extent - 4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(10)),
          child: Text(
            event['title']?.toString() ?? 'Event',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Returns the color used for each calendar event type.
Color _calendarEventColor(String kind) {
  switch (kind) {
    case 'plan':
      return const Color(0xFFDFF6E9);
    case 'note_session':
      return const Color(0xFFE0E7FF);
    default:
      return const Color(0xFFE0F2FE);
  }
}

/// Formats ISO week dates for calendar headers.
String _formatWeekDay(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return '${[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ][parsed.weekday - 1]} ${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}';
}

String _formatDeadlineStamp(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  return '${_formatWeekDay(local.toIso8601String())} ${_formatTime(local)}';
}

Future<void> _showCreatePlannerEventDialog(
  BuildContext context,
  Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent,
) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var selectedDate = _dateOnly(DateTime.now()).add(const Duration(days: 1));
  var selectedTime = const TimeOfDay(hour: 14, minute: 0);
  var weight = 1;
  ActionFeedback? feedback;
  var submitting = false;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New event'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Event title',
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: _dateOnly(DateTime.now()),
                          lastDate:
                              _dateOnly(DateTime.now()).add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = _dateOnly(picked));
                        }
                      },
                      child: Text(
                        selectedDate.toIso8601String().split('T').first,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                      child: Text(selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: weight,
                items: List.generate(
                  5,
                  (index) => DropdownMenuItem<int>(
                    value: index + 1,
                    child: Text('Weight ${index + 1}'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => weight = value);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Difficulty',
                  border: OutlineInputBorder(),
                ),
              ),
              if (feedback != null) ...[
                const SizedBox(height: 12),
                _FeedbackText(feedback: feedback!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setState(() {
                      submitting = true;
                      feedback = null;
                    });
                    final result = await onCreatePlannerEvent(
                      titleController.text.trim(),
                      DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      ),
                      weight,
                      descriptionController.text.trim(),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    setState(() {
                      submitting = false;
                      feedback = result;
                    });
                    if (!result.isError) {
                      Navigator.of(context).pop();
                    }
                  },
            child: Text(submitting ? 'Saving...' : 'Create'),
          ),
        ],
      ),
    ),
  );

  titleController.dispose();
  descriptionController.dispose();
}

/// Opens a local iCal file picker and forwards the result to the callback.
Future<void> _showImportCalendarDialog(
  BuildContext context,
  Future<void> Function(String rawIcal, String title, {int? courseId}) onImport,
) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'iCal', extensions: ['ics'])
    ],
  );
  if (file == null) {
    return;
  }
  final rawIcal = await file.readAsString();
  if (!context.mounted) {
    return;
  }
  await onImport(rawIcal, file.name);
}

/// Opens a dialog for subscribing to a remote iCal feed.
Future<void> _showSubscribeCalendarDialog(
  BuildContext context,
  Future<void> Function(String title, String url, {int? courseId}) onSubscribe,
) async {
  final titleController = TextEditingController();
  final urlController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Subscribe to calendar'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                  labelText: 'iCal URL', border: OutlineInputBorder()),
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
            await onSubscribe(
              titleController.text.trim().isEmpty
                  ? 'Subscribed calendar'
                  : titleController.text.trim(),
              urlController.text.trim(),
            );
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Subscribe'),
        ),
      ],
    ),
  );
  titleController.dispose();
  urlController.dispose();
}
