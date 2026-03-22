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

  @override
  Widget build(BuildContext context) {
    final weekDays = (activityWeek?['days'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: isAuthenticated ? () => onNavigateWeek(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  weekDays.isEmpty
                      ? 'Week calendar'
                      : '${_formatWeekDay(weekDays.first['date']?.toString() ?? '')} - ${_formatWeekDay(weekDays.last['date']?.toString() ?? '')}',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: isAuthenticated ? () => onNavigateWeek(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
              if (isAuthenticated) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () =>
                      _showImportCalendarDialog(context, onImportCalendar),
                  child: const Text('Import iCal'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showSubscribeCalendarDialog(
                    context,
                    onSubscribeCalendar,
                  ),
                  child: const Text('Subscribe'),
                ),
              ],
            ],
          ),
        ),
        if (isAuthenticated)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _PlannerEventComposer(
              plannerEvents: plannerEvents,
              onCreatePlannerEvent: onCreatePlannerEvent,
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: weekDays.isEmpty
                ? const Card(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Sign in to view and manage your weekly calendar.',
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide =
                          constraints.maxWidth >= constraints.maxHeight;
                      return isWide
                          ? _WideWeekCalendar(days: weekDays)
                          : _TallWeekCalendar(days: weekDays);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Composer for future study events that feed the planning heatmap and calendar.
class _PlannerEventComposer extends StatefulWidget {
  const _PlannerEventComposer({
    required this.plannerEvents,
    required this.onCreatePlannerEvent,
  });

  final List<Map<String, dynamic>> plannerEvents;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description,
  ) onCreatePlannerEvent;

  @override
  State<_PlannerEventComposer> createState() => _PlannerEventComposerState();
}

class _PlannerEventComposerState extends State<_PlannerEventComposer> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate =
      _dateOnly(DateTime.now()).add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 14, minute: 0);
  int _weight = 1;
  bool _submitting = false;
  ActionFeedback? _feedback;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onCreatePlannerEvent(
      _titleController.text,
      DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      ),
      _weight,
      _descriptionController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
      if (!feedback.isError) {
        _titleController.clear();
        _descriptionController.clear();
        _weight = 1;
        _selectedDate = _dateOnly(DateTime.now()).add(const Duration(days: 1));
        _selectedTime = const TimeOfDay(hour: 14, minute: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Register future events',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                'These events feed the green half of the heatmap. Default difficulty is 1.'),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
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
                        initialDate: _selectedDate,
                        firstDate: _dateOnly(DateTime.now()),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _selectedDate = _dateOnly(picked);
                        });
                      }
                    },
                    child: Text(
                        'Date: ${_selectedDate.toIso8601String().split('T').first}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _selectedTime = picked;
                        });
                      }
                    },
                    child: Text('Time: ${_selectedTime.format(context)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _weight,
                    items: List.generate(
                      5,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('Weight ${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _weight = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Saving...' : 'Add event'),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 10),
              Text(
                _feedback!.message,
                style: TextStyle(
                  color: _feedback!.isError
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF166534),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.plannerEvents.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Upcoming events',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final event in widget.plannerEvents.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFFD1FAE5),
                    child: Text(
                      '${event['difficulty_weight'] ?? 1}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF166534)),
                    ),
                  ),
                  title: Text(event['title']?.toString() ?? 'Event'),
                  subtitle: Text(event['event_date']?.toString() ?? ''),
                ),
            ],
          ],
        ),
      ),
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

/// Tall calendar layout with days as rows and time on the horizontal axis.
class _TallWeekCalendar extends StatelessWidget {
  const _TallWeekCalendar({required this.days});

  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    const hourWidth = 88.0;
    const dayLabelWidth = 94.0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: dayLabelWidth + (hourWidth * 24),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: dayLabelWidth, height: 40),
                  for (var hour = 0; hour < 24; hour++)
                    SizedBox(
                      width: hourWidth,
                      height: 40,
                      child: Center(
                          child: Text('${hour.toString().padLeft(2, '0')}:00')),
                    ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final day in days)
                      SizedBox(
                        height: 96,
                        child: Row(
                          children: [
                            SizedBox(
                              width: dayLabelWidth,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(_formatWeekDay(
                                    day['date']?.toString() ?? '')),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  for (var hour = 0; hour < 24; hour++)
                                    Positioned(
                                      left: hour * hourWidth,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: hourWidth,
                                        decoration: const BoxDecoration(
                                          border: Border(
                                              left: BorderSide(
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
                                      vertical: false,
                                      slotExtent: hourWidth,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

    return Positioned(
      left: offset + 2,
      top: 8,
      width: math.max(60, extent - 4),
      height: 80,
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
}
