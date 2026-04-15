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
        final hasOfflinePlannerData = plannerEvents.isNotEmpty || deadlines.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: (!isAuthenticated && !hasOfflinePlannerData)
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
                    : (!isAuthenticated || !isHorizontal)
                        ? _VerticalWeekBoard(
                            days: weekDays,
                            deadlines: deadlines,
                            plannerEvents: plannerEvents,
                            onNavigateWeek: onNavigateWeek,
                            onTogglePlannerEventCompletion:
                                onTogglePlannerEventCompletion,
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

/// Wide calendar layout with days as columns and hours on the vertical axis.
class _WideWeekCalendar extends StatefulWidget {
  const _WideWeekCalendar({
    required this.days,
    required this.onNavigateWeek,
    required this.onShiftStartDay,
  });

  final List<Map<String, dynamic>> days;
  final Future<void> Function(int direction) onNavigateWeek;
  final Future<void> Function(int dayDelta) onShiftStartDay;

  @override
  State<_WideWeekCalendar> createState() => _WideWeekCalendarState();
}

class _WideWeekCalendarState extends State<_WideWeekCalendar>
    with SingleTickerProviderStateMixin {
  static const double _hourHeight = 68.0;
  static const double _labelWidth = 72.0;
  static const Duration _settleDuration = Duration(milliseconds: 220);

  final ScrollController _verticalScrollController = ScrollController();
  late final AnimationController _animationController;
  Animation<double>? _offsetAnimation;
  double _dragOffset = 0;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _animateOffset(
    double target, {
    Duration duration = _settleDuration,
    Curve curve = Curves.easeOutCubic,
  }) async {
    final start = _dragOffset;
    _animationController.stop();
    _animationController.duration = duration;
    VoidCallback? listener;
    _offsetAnimation = Tween<double>(
      begin: start,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: curve),
    );
    listener = () {
      if (!mounted || _offsetAnimation == null) {
        return;
      }
      setState(() {
        _dragOffset = _offsetAnimation!.value;
      });
    };
    _offsetAnimation!.addListener(listener);
    await _animationController.forward(from: 0);
    _offsetAnimation?.removeListener(listener);
    if (mounted) {
      setState(() {
        _dragOffset = target;
      });
    }
  }

  Future<void> _runSurfaceTransition({
    required double exitTarget,
    required Future<void> Function() action,
  }) async {
    setState(() {
      _transitioning = true;
    });
    try {
      await _animateOffset(exitTarget);
      await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _dragOffset = -exitTarget * 0.35;
      });
      await _animateOffset(0, curve: Curves.easeOutCubic);
    } finally {
      if (mounted) {
        setState(() {
          _transitioning = false;
        });
      }
    }
  }

  Future<void> _shiftByDay(int dayDelta, double exitTarget) async {
    await _runSurfaceTransition(
      exitTarget: exitTarget,
      action: () => widget.onShiftStartDay(dayDelta),
    );
  }

  Future<void> _jumpWeek(int direction, double surfaceWidth) async {
    final exitTarget = direction < 0 ? surfaceWidth : -surfaceWidth;
    await _runSurfaceTransition(
      exitTarget: exitTarget,
      action: () => widget.onNavigateWeek(direction),
    );
  }

  void _handleDragStart(DragStartDetails _) {
    if (_transitioning) {
      return;
    }
    _animationController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_transitioning) {
      return;
    }
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  Future<void> _handleDragCancel() async {
    if (_transitioning || _dragOffset == 0) {
      return;
    }
    await _animateOffset(0);
  }

  Future<void> _handleWeekTap(int direction, double surfaceWidth) async {
    if (_transitioning) {
      return;
    }
    await _jumpWeek(direction, surfaceWidth);
  }

  Future<void> _handleDragEnd(
    DragEndDetails details,
    double surfaceWidth,
  ) async {
    if (_transitioning) {
      return;
    }
    final threshold = math.max(96.0, surfaceWidth * 0.18);
    if (_dragOffset.abs() < threshold) {
      await _animateOffset(0);
      return;
    }
    final swipeRight = _dragOffset > 0;
    final exitTarget = swipeRight ? surfaceWidth : -surfaceWidth;
    final dayDelta = swipeRight ? -1 : 1;
    await _shiftByDay(dayDelta, exitTarget);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final totalHeight = _hourHeight * 24;
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    final rangeLabel = days.isEmpty
        ? 'Week calendar'
        : '${_formatWeekDay(days.first['date']?.toString() ?? '')} - ${_formatWeekDay(days.last['date']?.toString() ?? '')}';
    return SizedBox.expand(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bodyWidth = constraints.maxWidth;
            return Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: borderColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              rangeLabel,
                              key: const Key('activity-calendar-range-label'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: GestureDetector(
                          key: const Key('activity-calendar-drag-surface'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart:
                              _transitioning ? null : _handleDragStart,
                          onHorizontalDragUpdate:
                              _transitioning ? null : _handleDragUpdate,
                          onHorizontalDragCancel:
                              _transitioning ? null : () => _handleDragCancel(),
                          onHorizontalDragEnd: _transitioning
                              ? null
                              : (details) =>
                                  _handleDragEnd(details, bodyWidth),
                          child: Transform.translate(
                            offset: Offset(_dragOffset, 0),
                            child: Scrollbar(
                              controller: _verticalScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _verticalScrollController,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: _labelWidth,
                                      child: Column(
                                        children: [
                                          const SizedBox(height: 48),
                                          for (var hour = 0; hour < 24; hour++)
                                            SizedBox(
                                              height: _hourHeight,
                                              child: Align(
                                                alignment: Alignment.topCenter,
                                                child: Text(
                                                  '${hour.toString().padLeft(2, '0')}:00',
                                                ),
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
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: borderColor,
                                                    ),
                                                  ),
                                                ),
                                                child: Column(
                                                  children: [
                                                    Container(
                                                      height: 48,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(
                                                          bottom: BorderSide(
                                                            color: borderColor,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        _formatWeekDay(
                                                          day['date']
                                                                  ?.toString() ??
                                                              '',
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: totalHeight,
                                                      child: Stack(
                                                        children: [
                                                          for (var hour = 0;
                                                              hour < 24;
                                                              hour++)
                                                            Positioned(
                                                              top: hour *
                                                                  _hourHeight,
                                                              left: 0,
                                                              right: 0,
                                                              child: Container(
                                                                height:
                                                                    _hourHeight,
                                                                decoration:
                                                                    BoxDecoration(
                                                                  border: Border(
                                                                    bottom:
                                                                        BorderSide(
                                                                      color:
                                                                          borderColor,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          for (final event in (day[
                                                                      'events']
                                                                  as List<
                                                                      dynamic>? ??
                                                              const []))
                                                            _CalendarEventTile(
                                                              event: Map<
                                                                      String,
                                                                      dynamic>.from(
                                                                  event
                                                                      as Map),
                                                              vertical: true,
                                                              slotExtent:
                                                                  _hourHeight,
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
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            theme.colorScheme.surface.withOpacity(0.08),
                            Colors.transparent,
                            Colors.transparent,
                            theme.colorScheme.surface.withOpacity(0.08),
                          ],
                          stops: const [0, 0.05, 0.95, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        _CalendarOverlayButton(
                          key: const Key('activity-calendar-previous-week'),
                          icon: Icons.chevron_left,
                          tooltip: 'Previous week',
                          onPressed: _transitioning
                              ? null
                              : () {
                                  _handleWeekTap(-1, bodyWidth);
                                },
                        ),
                        const Spacer(),
                        _CalendarOverlayButton(
                          key: const Key('activity-calendar-next-week'),
                          icon: Icons.chevron_right,
                          tooltip: 'Next week',
                          onPressed: _transitioning
                              ? null
                              : () {
                                  _handleWeekTap(1, bodyWidth);
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CalendarOverlayButton extends StatelessWidget {
  const _CalendarOverlayButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withOpacity(0.92),
        elevation: 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon),
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
                FeedbackText(feedback: feedback!),
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

/// Lightweight iCalendar parse result used by the import confirmation dialog.
class _IcalPreview {
  _IcalPreview({
    required this.summary,
    required this.eventCount,
    required this.firstStart,
    required this.lastStart,
    required this.sampleEvents,
  });

  final String summary;
  final int eventCount;
  final DateTime? firstStart;
  final DateTime? lastStart;
  final List<_IcalSampleEvent> sampleEvents;
}

class _IcalSampleEvent {
  const _IcalSampleEvent({
    required this.summary,
    required this.start,
  });

  final String summary;
  final DateTime? start;
}

/// Parses the subset of iCalendar we care about for the confirmation page.
/// We only extract SUMMARY and DTSTART since that is enough to show the user
/// a meaningful preview before committing the import.
_IcalPreview _parseIcalPreview(String raw) {
  // Line unfolding per RFC 5545: a leading space/tab on a line continues the
  // previous line.
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rawLines = normalized.split('\n');
  final lines = <String>[];
  for (final line in rawLines) {
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] = lines.last + line.substring(1);
    } else {
      lines.add(line);
    }
  }

  String calendarSummary = '';
  var inEvent = false;
  var currentSummary = '';
  DateTime? currentStart;
  final events = <_IcalSampleEvent>[];
  DateTime? firstStart;
  DateTime? lastStart;

  DateTime? parseIcalDate(String rawValue) {
    // Strip parameters like TZID=...
    final value = rawValue.trim();
    if (value.isEmpty) return null;
    // Formats: 20250401T120000Z, 20250401T120000, 20250401
    try {
      if (value.length >= 15 && value.contains('T')) {
        final year = int.parse(value.substring(0, 4));
        final month = int.parse(value.substring(4, 6));
        final day = int.parse(value.substring(6, 8));
        final hour = int.parse(value.substring(9, 11));
        final minute = int.parse(value.substring(11, 13));
        final second = int.parse(value.substring(13, 15));
        final isUtc = value.endsWith('Z');
        return isUtc
            ? DateTime.utc(year, month, day, hour, minute, second)
            : DateTime(year, month, day, hour, minute, second);
      }
      if (value.length == 8) {
        final year = int.parse(value.substring(0, 4));
        final month = int.parse(value.substring(4, 6));
        final day = int.parse(value.substring(6, 8));
        return DateTime(year, month, day);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      inEvent = true;
      currentSummary = '';
      currentStart = null;
      continue;
    }
    if (line == 'END:VEVENT') {
      events.add(
        _IcalSampleEvent(
          summary: currentSummary.isEmpty ? '(untitled event)' : currentSummary,
          start: currentStart,
        ),
      );
      if (currentStart != null) {
        if (firstStart == null || currentStart.isBefore(firstStart)) {
          firstStart = currentStart;
        }
        if (lastStart == null || currentStart.isAfter(lastStart)) {
          lastStart = currentStart;
        }
      }
      inEvent = false;
      continue;
    }
    if (inEvent) {
      if (line.startsWith('SUMMARY')) {
        final colonAt = line.indexOf(':');
        if (colonAt >= 0) {
          currentSummary = line.substring(colonAt + 1).trim();
        }
      } else if (line.startsWith('DTSTART')) {
        final colonAt = line.indexOf(':');
        if (colonAt >= 0) {
          currentStart = parseIcalDate(line.substring(colonAt + 1));
        }
      }
    } else if (line.startsWith('X-WR-CALNAME')) {
      final colonAt = line.indexOf(':');
      if (colonAt >= 0) {
        calendarSummary = line.substring(colonAt + 1).trim();
      }
    }
  }

  events.sort((a, b) {
    if (a.start == null && b.start == null) return 0;
    if (a.start == null) return 1;
    if (b.start == null) return -1;
    return a.start!.compareTo(b.start!);
  });

  return _IcalPreview(
    summary: calendarSummary,
    eventCount: events.length,
    firstStart: firstStart,
    lastStart: lastStart,
    sampleEvents: events.take(5).toList(growable: false),
  );
}

/// Returns the first .ics entry from a zip archive (as UTF-8 text), or null
/// if no .ics files are present.
String? _extractFirstIcsFromZip(List<int> bytes) {
  try {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.ics')) {
        return utf8.decode(file.content as List<int>, allowMalformed: true);
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Opens a local iCal/zip file picker, parses a preview, and shows a
/// confirmation page with the event summary before forwarding to the
/// backend via [onImport]. Accepts both .ics files and .zip archives
/// (extracting the first .ics entry from the archive).
Future<void> _showImportCalendarDialog(
  BuildContext context,
  Future<void> Function(String rawIcal, String title, {int? courseId}) onImport,
) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'iCal or zip', extensions: ['ics', 'zip'])
    ],
  );
  if (file == null) {
    return;
  }
  String? rawIcal;
  final lowerName = file.name.toLowerCase();
  if (lowerName.endsWith('.zip')) {
    final bytes = await file.readAsBytes();
    rawIcal = _extractFirstIcsFromZip(bytes);
    if (rawIcal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No .ics file found inside the archive.')),
        );
      }
      return;
    }
  } else {
    rawIcal = await file.readAsString();
  }
  if (!context.mounted) {
    return;
  }

  final preview = _parseIcalPreview(rawIcal);
  final defaultTitle = preview.summary.isNotEmpty
      ? preview.summary
      : file.name.replaceAll(RegExp(r'\.(ics|zip)$', caseSensitive: false), '');
  final titleController = TextEditingController(text: defaultTitle);
  var importing = false;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Review calendar import'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Source: ${file.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${preview.eventCount} event${preview.eventCount == 1 ? '' : 's'} parsed',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (preview.firstStart != null && preview.lastStart != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Date range: '
                    '${preview.firstStart!.toIso8601String().split("T").first}'
                    ' → '
                    '${preview.lastStart!.toIso8601String().split("T").first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                if (preview.sampleEvents.isNotEmpty) ...[
                  Text(
                    'Preview (up to 5 events):',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (final event in preview.sampleEvents)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(
                            child: Text(
                              event.start != null
                                  ? '${event.summary} — ${event.start!.toIso8601String()}'
                                  : event.summary,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Calendar title',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: importing ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: importing
                ? null
                : () async {
                    setState(() => importing = true);
                    try {
                      final title = titleController.text.trim().isEmpty
                          ? 'Imported calendar'
                          : titleController.text.trim();
                      await onImport(rawIcal!, title);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (error) {
                      setState(() => importing = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Import failed: $error')),
                        );
                      }
                    }
                  },
            child: Text(importing ? 'Importing...' : 'Confirm import'),
          ),
        ],
      ),
    ),
  );
  titleController.dispose();
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
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
                labelText: 'iCal URL or Google share link',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supports Google Calendar share links (public URL or cid link) '
              'and direct .ics URLs from iCloud, Outlook, or any iCal feed. '
              'For best results, use "Secret address in iCal format" from '
              'Google Calendar settings.',
              style: Theme.of(context).textTheme.bodySmall,
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
