part of notechondria_frontend;

/// Wide calendar layout with days as columns and hours on the vertical axis.
class _WideWeekCalendar extends StatefulWidget {
  const _WideWeekCalendar({
    required this.days,
    required this.rangeDays,
    required this.onNavigateWeek,
    required this.onShiftStartDay,
    required this.onChangeRange,
    required this.onCreatePlannerEvent,
    required this.onUpdatePlannerEvent,
  });

  final List<Map<String, dynamic>> days;
  final int rangeDays;
  final Future<void> Function(int direction) onNavigateWeek;
  final Future<void> Function(int dayDelta) onShiftStartDay;
  final Future<void> Function(int days) onChangeRange;
  final Future<ActionFeedback> Function(
    String title,
    DateTime eventDate,
    int difficultyWeight,
    String description, {
    DateTime? endsAt,
  }) onCreatePlannerEvent;
  final Future<void> Function(
          Map<String, dynamic> event, Map<String, dynamic> changes)
      onUpdatePlannerEvent;

  @override
  State<_WideWeekCalendar> createState() => _WideWeekCalendarState();
}

class _WideWeekCalendarState extends State<_WideWeekCalendar>
    with SingleTickerProviderStateMixin {
  static const double _defaultHourHeight = 68.0;
  static const double _minHourHeight = 32.0;
  static const double _maxHourHeight = 140.0;
  static const double _labelWidth = 72.0;
  static const Duration _settleDuration = Duration(milliseconds: 220);

  final ScrollController _verticalScrollController = ScrollController();
  late final AnimationController _animationController;
  Animation<double>? _offsetAnimation;
  double _dragOffset = 0;
  bool _transitioning = false;

  // Scroll-to-zoom: hour row height, adjusted by Ctrl/⌘ + wheel and the
  // zoom buttons. Kept in [_minHourHeight, _maxHourHeight].
  double _hourHeight = _defaultHourHeight;

  // Long-press-and-drag to create: while a press-drag is active on a day
  // column we paint a selection band and, on release, open the create
  // dialog prefilled with the dragged time range. Long-press (not an
  // immediate drag) is used so it never fights the vertical scroll view.
  int? _createDayIndex;
  double? _createStartY;
  double? _createEndY;

  void _zoom(double delta) {
    setState(() {
      _hourHeight = (_hourHeight + delta).clamp(_minHourHeight, _maxHourHeight);
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final zooming = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    if (!zooming) {
      return; // let the vertical scroll view handle plain wheel scrolling
    }
    _zoom(event.scrollDelta.dy < 0 ? 8 : -8);
  }

  int _minutesFromLocalY(double localY) {
    final minutes = ((localY / _hourHeight) * 60).round();
    return minutes.clamp(0, 24 * 60 - 1);
  }

  Future<void> _commitCreateDrag(int dayIndex) async {
    final startY = _createStartY;
    final endY = _createEndY;
    setState(() {
      _createDayIndex = null;
      _createStartY = null;
      _createEndY = null;
    });
    if (startY == null || endY == null) {
      return;
    }
    if (dayIndex < 0 || dayIndex >= widget.days.length) {
      return;
    }
    final dateRaw = widget.days[dayIndex]['date']?.toString() ?? '';
    final date = DateTime.tryParse(dateRaw);
    if (date == null) {
      return;
    }
    final startMinutes = _minutesFromLocalY(math.min(startY, endY));
    // A near-zero drag (a tap) has no meaningful span — fall back to a
    // default one-hour block; a real drag draws start → end.
    final rawEndMinutes = _minutesFromLocalY(math.max(startY, endY));
    final endMinutes =
        rawEndMinutes - startMinutes < 15 ? startMinutes + 60 : rawEndMinutes;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      (endMinutes ~/ 60).clamp(0, 23),
      endMinutes % 60,
    );
    if (!mounted) {
      return;
    }
    await _showCreatePlannerEventDialog(
      context,
      widget.onCreatePlannerEvent,
      initialDateTime: start,
      initialEndDateTime: end,
    );
  }

  /// Hold / right-click handler for an event tile. Only editable planner
  /// ("plan"-kind) events open the editor; calendar-feed and note-session
  /// tiles fall back to their read-only detail sheet.
  void _handleEventHold(Map<String, dynamic> event) {
    final kind = event['kind']?.toString() ?? '';
    if (kind == 'plan' && event['id'] != null) {
      _showEditPlannerEventDialog(context, event, widget.onUpdatePlannerEvent);
      return;
    }
    _showCalendarEventDetails(context, event);
  }

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
    // The 1-month range renders as a Google Calendar-style month grid
    // (date cells with a few prioritized event chips), not the hour grid —
    // 30 hour-columns were unreadably narrow and full of empty space.
    final isMonth = widget.rangeDays == 30;
    final rangeLabel = days.isEmpty
        ? AppLocalizations.of(context).activityWeekCalendar
        : '${_formatWeekDay(days.first['date']?.toString() ?? '')} - ${_formatWeekDay(days.last['date']?.toString() ?? '')}';
    return SizedBox.expand(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bodyWidth = constraints.maxWidth;
            return Listener(
              onPointerSignal: _handlePointerSignal,
              child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: borderColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          _ActivityRangeSelector(
                            rangeDays: widget.rangeDays,
                            onChanged: _transitioning ? null : widget.onChangeRange,
                          ),
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
                          // Zoom controls act on the hour-row height; the
                          // month grid has no hour rows.
                          if (!isMonth) ...[
                            IconButton(
                              tooltip:
                                  AppLocalizations.of(context).activityZoomOut,
                              onPressed: _hourHeight <= _minHourHeight
                                  ? null
                                  : () => _zoom(-12),
                              icon: const Icon(Icons.zoom_out),
                            ),
                            IconButton(
                              tooltip:
                                  AppLocalizations.of(context).activityZoomIn,
                              onPressed: _hourHeight >= _maxHourHeight
                                  ? null
                                  : () => _zoom(12),
                              icon: const Icon(Icons.zoom_in),
                            ),
                          ],
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
                              : (details) => _handleDragEnd(details, bodyWidth),
                          child: Transform.translate(
                            offset: Offset(_dragOffset, 0),
                            child: isMonth
                                ? _MonthCalendarGrid(
                                    days: days,
                                    onEventTap: (event) =>
                                        _showCalendarEventDetails(
                                            context, event),
                                    onEventLongPress: _handleEventHold,
                                    onCreateForDay: (date) =>
                                        _showCreatePlannerEventDialog(
                                      context,
                                      widget.onCreatePlannerEvent,
                                      initialDateTime: DateTime(date.year,
                                          date.month, date.day, 12, 0),
                                    ),
                                  )
                                : Scrollbar(
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
                                          for (var dayIndex = 0;
                                              dayIndex < days.length;
                                              dayIndex++)
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
                                                          days[dayIndex]['date']
                                                                  ?.toString() ??
                                                              '',
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      height: totalHeight,
                                                      child: GestureDetector(
                                                        behavior: HitTestBehavior
                                                            .opaque,
                                                        // Plain vertical
                                                        // drag draws an
                                                        // event's time span
                                                        // (Google Calendar
                                                        // style). It wins the
                                                        // gesture arena over
                                                        // the parent vertical
                                                        // scroll, so scroll
                                                        // the grid with the
                                                        // wheel / scrollbar /
                                                        // hour-label column.
                                                        // The outer surface's
                                                        // horizontal drag
                                                        // still navigates
                                                        // weeks.
                                                        onVerticalDragStart:
                                                            (details) {
                                                          setState(() {
                                                            _createDayIndex =
                                                                dayIndex;
                                                            _createStartY =
                                                                details
                                                                    .localPosition
                                                                    .dy;
                                                            _createEndY = details
                                                                .localPosition.dy;
                                                          });
                                                        },
                                                        onVerticalDragUpdate:
                                                            (details) {
                                                          if (_createDayIndex !=
                                                              dayIndex) {
                                                            return;
                                                          }
                                                          setState(() {
                                                            _createEndY = details
                                                                .localPosition.dy;
                                                          });
                                                        },
                                                        onVerticalDragEnd: (_) =>
                                                            _commitCreateDrag(
                                                                dayIndex),
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
                                                                  border:
                                                                      Border(
                                                                    bottom:
                                                                        BorderSide(
                                                                      color:
                                                                          borderColor,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          if (_createDayIndex ==
                                                                  dayIndex &&
                                                              _createStartY !=
                                                                  null &&
                                                              _createEndY != null)
                                                            Positioned(
                                                              top: math.min(
                                                                  _createStartY!,
                                                                  _createEndY!),
                                                              left: 2,
                                                              right: 2,
                                                              height: math.max(
                                                                  8,
                                                                  (_createEndY! -
                                                                          _createStartY!)
                                                                      .abs()),
                                                              child: Container(
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: theme
                                                                      .colorScheme
                                                                      .primary
                                                                      .withOpacity(
                                                                          0.25),
                                                                  border: Border
                                                                      .all(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .primary,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                ),
                                                              ),
                                                            ),
                                                          for (final event in (days[
                                                                          dayIndex]
                                                                      ['events']
                                                                  as List<
                                                                      dynamic>? ??
                                                              const []))
                                                            _CalendarEventTile(
                                                              event: Map<String,
                                                                      dynamic>.from(
                                                                  event as Map),
                                                              vertical: true,
                                                              slotExtent:
                                                                  _hourHeight,
                                                              onTap: () =>
                                                                  _showCalendarEventDetails(
                                                                context,
                                                                Map<String,
                                                                    dynamic>.from(
                                                                    event),
                                                              ),
                                                              onLongPress: () =>
                                                                  _handleEventHold(
                                                                Map<String,
                                                                    dynamic>.from(
                                                                    event),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
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
                          tooltip: AppLocalizations.of(context).activityPrevWeek,
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
                          tooltip: AppLocalizations.of(context).activityNextWeek,
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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 3-day / 1-week / 1-month range selector for the horizontal calendar.
class _ActivityRangeSelector extends StatelessWidget {
  const _ActivityRangeSelector({
    required this.rangeDays,
    required this.onChanged,
  });

  final int rangeDays;
  final Future<void> Function(int days)? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = const {3, 7, 30}.contains(rangeDays) ? rangeDays : 7;
    return SegmentedButton<int>(
      key: const Key('activity-calendar-range-selector'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 3, label: Text(l10n.activityRange3Day)),
        ButtonSegment(value: 7, label: Text(l10n.activityRange1Week)),
        ButtonSegment(value: 30, label: Text(l10n.activityRange1Month)),
      ],
      selected: {selected},
      onSelectionChanged: onChanged == null
          ? null
          : (values) {
              if (values.isNotEmpty) {
                onChanged!(values.first);
              }
            },
    );
  }
}

/// Shows the read-only detail popup for a tapped calendar event.
Future<void> _showCalendarEventDetails(
  BuildContext context,
  Map<String, dynamic> event,
) async {
  final l10n = AppLocalizations.of(context);
  final start = DateTime.tryParse(event['starts_at']?.toString() ?? '');
  final end = DateTime.tryParse(event['ends_at']?.toString() ?? '');
  final description = event['description']?.toString() ?? '';
  final calendarTitle = event['calendar_title']?.toString() ?? '';
  String timeRange() {
    if (start == null) {
      return '';
    }
    final local = start.toLocal();
    final stamp = '${_formatWeekDay(local.toIso8601String())} '
        '${_formatTime(local)}';
    if (end == null) {
      return stamp;
    }
    return '$stamp – ${_formatTime(end.toLocal())}';
  }

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(event['title']?.toString() ?? l10n.activityEventTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeRange().isNotEmpty)
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(timeRange())),
              ],
            ),
          if (calendarTitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(calendarTitle)),
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
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
    this.onTap,
    this.onLongPress,
  });

  final Map<String, dynamic> event;
  final bool vertical;
  final double slotExtent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
    final color = _calendarEventColor(event, brightness: Theme.of(context).brightness);
    final ink = _calendarEventInkFor(color);

    if (vertical) {
      return Positioned(
        top: offset + 2,
        left: 6,
        right: 6,
        height: math.max(24, extent - 4),
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              event['title']?.toString() ?? 'Event',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              // Ink is derived from the tile colour's luminance so the label
              // stays legible on every palette colour, in light or dark theme.
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Google Calendar-style month grid: weekday header, weeks as rows, each
/// day cell showing the date number and a few prioritized event chips with
/// a locale-neutral "+N" overflow. No hour rows / time offsets — the month
/// range is for scanning what is on each day, not for time-of-day detail.
class _MonthCalendarGrid extends StatelessWidget {
  const _MonthCalendarGrid({
    required this.days,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onCreateForDay,
  });

  final List<Map<String, dynamic>> days;
  final void Function(Map<String, dynamic> event) onEventTap;
  final void Function(Map<String, dynamic> event) onEventLongPress;
  final void Function(DateTime day) onCreateForDay;

  /// Orders a day's events for the limited chip slots: open plans first
  /// (heaviest weight, then earliest start), then feed/session entries,
  /// completed events always last (rendered dimmed).
  static List<Map<String, dynamic>> prioritizedDayEvents(
    List<dynamic> rawEvents,
  ) {
    final events = [
      for (final e in rawEvents) Map<String, dynamic>.from(e as Map),
    ];
    int rank(Map<String, dynamic> e) {
      if (e['is_completed'] == true) return 2;
      return e['kind']?.toString() == 'plan' ? 0 : 1;
    }

    int weight(Map<String, dynamic> e) =>
        int.tryParse(e['difficulty_weight']?.toString() ?? '') ?? 1;
    DateTime start(Map<String, dynamic> e) =>
        DateTime.tryParse(e['starts_at']?.toString() ?? '') ?? DateTime(2100);
    events.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byWeight = weight(b).compareTo(weight(a));
      if (byWeight != 0) return byWeight;
      return start(a).compareTo(start(b));
    });
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    final today = _dateOnly(DateTime.now());

    // Lay the rolling 30-day window out on weekday columns: pad the first
    // row up to the window's starting weekday, then rows of seven.
    final cells = <DateTime?>[];
    final firstDate = days.isEmpty
        ? null
        : DateTime.tryParse(days.first['date']?.toString() ?? '');
    if (firstDate != null) {
      for (var i = 1; i < firstDate.weekday; i++) {
        cells.add(null);
      }
    }
    final byDate = <String, List<dynamic>>{};
    for (final day in days) {
      final raw = day['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      cells.add(_dateOnly(parsed));
      byDate[raw] = day['events'] as List<dynamic>? ?? const [];
    }
    while (cells.isEmpty || cells.length % 7 != 0) {
      cells.add(null);
    }
    final weekCount = cells.length ~/ 7;

    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              for (final label in _kWeekdayAbbrevs)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var week = 0; week < weekCount; week++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _MonthDayCell(
                            date: cells[week * 7 + col],
                            events: cells[week * 7 + col] == null
                                ? const []
                                : prioritizedDayEvents(byDate[
                                        cells[week * 7 + col]!
                                            .toIso8601String()
                                            .split('T')
                                            .first] ??
                                    const []),
                            isToday: cells[week * 7 + col] == today,
                            borderColor: borderColor,
                            onEventTap: onEventTap,
                            onEventLongPress: onEventLongPress,
                            onCreateForDay: onCreateForDay,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.date,
    required this.events,
    required this.isToday,
    required this.borderColor,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onCreateForDay,
  });

  final DateTime? date;
  final List<Map<String, dynamic>> events;
  final bool isToday;
  final Color borderColor;
  final void Function(Map<String, dynamic> event) onEventTap;
  final void Function(Map<String, dynamic> event) onEventLongPress;
  final void Function(DateTime day) onCreateForDay;

  static const double _chipHeight = 18;
  static const double _chipGap = 2;
  static const double _dateRowHeight = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cellDate = date;
    if (cellDate == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => onCreateForDay(cellDate),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final chipBudget = math.max(
              0,
              ((constraints.maxHeight - _dateRowHeight) /
                      (_chipHeight + _chipGap))
                  .floor(),
            );
            final visibleCount =
                math.min(events.length, math.min(chipBudget, 4));
            // Reserve the last slot for "+N" when events overflow.
            final shownEvents = events.length > visibleCount &&
                    visibleCount > 0
                ? events.sublist(0, visibleCount - 1)
                : events.sublist(0, visibleCount);
            final hiddenCount = events.length - shownEvents.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _dateRowHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: isToday
                        ? Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${cellDate.day}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : Text(
                            cellDate.day == 1
                                ? '${cellDate.month}/${cellDate.day}'
                                : '${cellDate.day}',
                            style: theme.textTheme.labelMedium,
                          ),
                  ),
                ),
                for (final event in shownEvents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _chipGap),
                    child: _MonthEventChip(
                      event: event,
                      height: _chipHeight,
                      onTap: () => onEventTap(event),
                      onLongPress: () => onEventLongPress(event),
                    ),
                  ),
                if (hiddenCount > 0)
                  SizedBox(
                    height: _chipHeight,
                    child: InkWell(
                      onTap: () => _showMonthDayEventsDialog(
                        context,
                        cellDate,
                        events,
                        onEventTap,
                        onEventLongPress,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '+$hiddenCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
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

/// Compact single-line event chip for month-grid day cells.
class _MonthEventChip extends StatelessWidget {
  const _MonthEventChip({
    required this.event,
    required this.height,
    required this.onTap,
    this.onLongPress,
  });

  final Map<String, dynamic> event;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final completed = event['is_completed'] == true;
    final color = _calendarEventColor(event, brightness: Theme.of(context).brightness);
    final ink = _calendarEventInkFor(color);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Opacity(
        opacity: completed ? 0.55 : 1,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            event['title']?.toString() ?? 'Event',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ink,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full event list for one month-grid day (the "+N" overflow target).
Future<void> _showMonthDayEventsDialog(
  BuildContext context,
  DateTime date,
  List<Map<String, dynamic>> events,
  void Function(Map<String, dynamic> event) onEventTap,
  void Function(Map<String, dynamic> event) onEventLongPress,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_formatWeekDay(date.toIso8601String())),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _MonthEventChip(
                  event: event,
                  height: 28,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    onEventTap(event);
                  },
                  onLongPress: () {
                    Navigator.of(dialogContext).pop();
                    onEventLongPress(event);
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppLocalizations.of(context).commonClose),
        ),
      ],
    ),
  );
}

/// Weekday column labels shared by the week header and the month grid.
const List<String> _kWeekdayAbbrevs = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Dark ink for tiles painted on light backgrounds.
const Color _kCalendarEventInk = Color(0xFF1F2933);

/// Ink that stays legible on any tile colour (dark ink on light tiles,
/// white on dark ones) — computed from the background luminance so the
/// label is never invisible in either theme.
Color _calendarEventInkFor(Color background) {
  return background.computeLuminance() > 0.5
      ? _kCalendarEventInk
      : Colors.white;
}

/// Evenly-spread fallback hues for courses that haven't set an explicit
/// `color_hue`, so different courses still read as distinct classes.
const List<double> _kCourseHues = [
  145, // mint-green
  28, // peach
  260, // violet
  330, // rose
  205, // sky-blue
  48, // amber
  175, // teal
  15, // terracotta
];

/// The event's importance (difficulty weight) clamped to 1..5.
int _eventImportance(Map<String, dynamic> event) {
  final raw = int.tryParse(event['difficulty_weight']?.toString() ?? '') ?? 1;
  return raw.clamp(1, 5);
}

/// The hue (0-359) for an event's course: the course's explicit `color_hue`
/// if set, otherwise a stable hue derived from its id.
double _courseHueFor(Map<String, dynamic> event) {
  final course = event['course'];
  final explicit = (course is Map) ? course['color_hue'] : null;
  if (explicit is int) {
    return explicit.toDouble().clamp(0, 359);
  }
  if (explicit is double) {
    return explicit.clamp(0, 359);
  }
  final courseId = event['course_id'];
  final seed = (courseId is int) ? courseId.abs() : 0;
  return _kCourseHues[seed % _kCourseHues.length];
}

/// Tile colour for a calendar event, in HSV so the three channels carry
/// meaning: **hue = course** (distinct classes), **saturation = importance**
/// (heavier events read stronger), and **value = theme** (bright pastels in
/// light mode, muted in dark). Note sessions and calendar feeds keep their
/// own fixed hues but still adapt value to the theme.
Color _calendarEventColor(
  Map<String, dynamic> event, {
  Brightness brightness = Brightness.light,
}) {
  final isDark = brightness == Brightness.dark;
  final kind = event['kind']?.toString() ?? '';
  final value = isDark ? 0.52 : 0.97;
  if (kind == 'note_session') {
    return HSVColor.fromAHSV(1, 232, isDark ? 0.45 : 0.16, value).toColor();
  }
  if (kind == 'calendar') {
    return HSVColor.fromAHSV(1, 200, isDark ? 0.45 : 0.16, value).toColor();
  }
  final hue = _courseHueFor(event);
  final importance = _eventImportance(event); // 1..5
  // Importance drives saturation; keep light mode pastel (lower band).
  final base = 0.22 + (importance - 1) * 0.15; // 0.22..0.82
  final saturation = (isDark ? base : base * 0.7).clamp(0.1, 0.9);
  return HSVColor.fromAHSV(1, hue, saturation.toDouble(), value).toColor();
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
    String description, {
    DateTime? endsAt,
  }) onCreatePlannerEvent, {
  DateTime? initialDateTime,
  DateTime? initialEndDateTime,
}) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var selectedDate = _dateOnly(
      initialDateTime ?? DateTime.now().add(const Duration(days: 1)));
  var selectedTime = initialDateTime != null
      ? TimeOfDay(hour: initialDateTime.hour, minute: initialDateTime.minute)
      : const TimeOfDay(hour: 14, minute: 0);
  // End time seeds from a drawn drag (initialEndDateTime) or defaults to
  // one hour after the start.
  final seedEnd = initialEndDateTime ??
      (initialDateTime != null
          ? initialDateTime.add(const Duration(hours: 1))
          : null);
  var selectedEndTime = seedEnd != null
      ? TimeOfDay(hour: seedEnd.hour, minute: seedEnd.minute)
      : const TimeOfDay(hour: 15, minute: 0);
  var weight = 1;
  ActionFeedback? feedback;
  var submitting = false;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(AppLocalizations.of(context).activityNewEvent),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).activityEventTitle,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText:
                      AppLocalizations.of(context).courseDescriptionLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: _dateOnly(DateTime.now()),
                      lastDate: _dateOnly(DateTime.now())
                          .add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = _dateOnly(picked));
                    }
                  },
                  label: Text(
                    selectedDate.toIso8601String().split('T').first,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 16),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                      label: Text(selectedTime.format(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop, size: 16),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime,
                        );
                        if (picked != null) {
                          setState(() => selectedEndTime = picked);
                        }
                      },
                      label: Text(selectedEndTime.format(context)),
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
                    child: Text(
                        AppLocalizations.of(context).activityWeightN(index + 1)),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => weight = value);
                  }
                },
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).activityDifficulty,
                  border: const OutlineInputBorder(),
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
                    final start = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );
                    var end = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedEndTime.hour,
                      selectedEndTime.minute,
                    );
                    // Guard against an end at/before the start (the
                    // backend also forces ends_at > starts_at).
                    if (!end.isAfter(start)) {
                      end = start.add(const Duration(hours: 1));
                    }
                    final result = await onCreatePlannerEvent(
                      titleController.text.trim(),
                      start,
                      weight,
                      descriptionController.text.trim(),
                      endsAt: end,
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
            child: Text(submitting
                ? AppLocalizations.of(context).noteMetaSaving
                : AppLocalizations.of(context).commonCreate),
          ),
        ],
      ),
    ),
  );

  titleController.dispose();
  descriptionController.dispose();
}

/// Hold-to-edit dialog for an existing planner ("plan"-kind) event. Pre-fills
/// from `event` and, on save, PATCHes only the writable fields — including
/// the recurrence rule (does-not-repeat / weekly / monthly / yearly, an
/// interval, and an optional end on a date or after N occurrences).
Future<void> _showEditPlannerEventDialog(
  BuildContext context,
  Map<String, dynamic> event,
  Future<void> Function(
          Map<String, dynamic> event, Map<String, dynamic> changes)
      onUpdate,
) async {
  final l10n = AppLocalizations.of(context);
  final titleController =
      TextEditingController(text: event['title']?.toString() ?? '');
  final descriptionController =
      TextEditingController(text: event['description']?.toString() ?? '');
  final start = DateTime.tryParse(event['starts_at']?.toString() ?? '')?.toLocal();
  final end = DateTime.tryParse(event['ends_at']?.toString() ?? '')?.toLocal();
  final baseDate = DateTime.tryParse(event['event_date']?.toString() ?? '') ??
      start ??
      DateTime.now();
  var selectedDate = _dateOnly(baseDate);
  var selectedTime = start != null
      ? TimeOfDay(hour: start.hour, minute: start.minute)
      : const TimeOfDay(hour: 14, minute: 0);
  var selectedEndTime = end != null
      ? TimeOfDay(hour: end.hour, minute: end.minute)
      : const TimeOfDay(hour: 15, minute: 0);
  var weight = (event['difficulty_weight'] as num?)?.toInt() ?? 1;
  if (weight < 1) {
    weight = 1;
  } else if (weight > 5) {
    weight = 5;
  }
  var freq = event['recurrence_freq']?.toString() ?? 'N';
  if (!const ['N', 'W', 'M', 'Y'].contains(freq)) {
    freq = 'N';
  }
  var interval = (event['recurrence_interval'] as num?)?.toInt() ?? 1;
  if (interval < 1) {
    interval = 1;
  }
  DateTime? recurrenceEndDate =
      DateTime.tryParse(event['recurrence_end_date']?.toString() ?? '');
  var recurrenceCount = (event['recurrence_count'] as num?)?.toInt();
  // End mode: 0 never, 1 on-date, 2 after-count.
  var endMode = recurrenceEndDate != null ? 1 : (recurrenceCount != null ? 2 : 0);
  final intervalController =
      TextEditingController(text: interval.toString());
  final countController =
      TextEditingController(text: (recurrenceCount ?? 1).toString());
  ActionFeedback? feedback;
  var submitting = false;

  String freqLabel(String value) {
    switch (value) {
      case 'W':
        return l10n.activityRepeatWeekly;
      case 'M':
        return l10n.activityRepeatMonthly;
      case 'Y':
        return l10n.activityRepeatYearly;
      default:
        return l10n.activityRepeatNever;
    }
  }

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.activityEditEvent),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: l10n.activityEventTitle,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.courseDescriptionLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 16),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: _dateOnly(
                            DateTime.now().subtract(const Duration(days: 365))),
                        lastDate: _dateOnly(
                            DateTime.now().add(const Duration(days: 365 * 3))),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = _dateOnly(picked));
                      }
                    },
                    label:
                        Text(selectedDate.toIso8601String().split('T').first),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 16),
                        onPressed: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: selectedTime);
                          if (picked != null) {
                            setState(() => selectedTime = picked);
                          }
                        },
                        label: Text(selectedTime.format(context)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stop, size: 16),
                        onPressed: () async {
                          final picked = await showTimePicker(
                              context: context, initialTime: selectedEndTime);
                          if (picked != null) {
                            setState(() => selectedEndTime = picked);
                          }
                        },
                        label: Text(selectedEndTime.format(context)),
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
                      child: Text(l10n.activityWeightN(index + 1)),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => weight = value);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: l10n.activityDifficulty,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 28),
                DropdownButtonFormField<String>(
                  value: freq,
                  items: [
                    for (final value in const ['N', 'W', 'M', 'Y'])
                      DropdownMenuItem<String>(
                        value: value,
                        child: Text(freqLabel(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => freq = value);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: l10n.activityRepeatLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (freq != 'N') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: intervalController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.activityRepeatIntervalLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: endMode,
                    items: [
                      DropdownMenuItem(
                          value: 0, child: Text(l10n.activityRepeatEndNever)),
                      DropdownMenuItem(
                          value: 1, child: Text(l10n.activityRepeatEndOnDate)),
                      DropdownMenuItem(
                          value: 2, child: Text(l10n.activityRepeatEndAfter)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => endMode = value);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: l10n.activityRepeatEndsLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (endMode == 1) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event_busy, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: recurrenceEndDate ??
                                selectedDate.add(const Duration(days: 30)),
                            firstDate: selectedDate,
                            lastDate: _dateOnly(
                                DateTime.now().add(const Duration(days: 365 * 5))),
                          );
                          if (picked != null) {
                            setState(() => recurrenceEndDate = _dateOnly(picked));
                          }
                        },
                        label: Text(recurrenceEndDate == null
                            ? l10n.activityRepeatEndOnDate
                            : recurrenceEndDate!
                                .toIso8601String()
                                .split('T')
                                .first),
                      ),
                    ),
                  ],
                  if (endMode == 2) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.activityRepeatCountLabel,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (feedback != null) ...[
                  const SizedBox(height: 12),
                  FeedbackText(feedback: feedback!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setState(() {
                      submitting = true;
                      feedback = null;
                    });
                    final startAt = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedTime.hour,
                      selectedTime.minute,
                    );
                    var endAt = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      selectedEndTime.hour,
                      selectedEndTime.minute,
                    );
                    if (!endAt.isAfter(startAt)) {
                      endAt = startAt.add(const Duration(hours: 1));
                    }
                    final parsedInterval =
                        int.tryParse(intervalController.text.trim()) ?? 1;
                    final parsedCount =
                        int.tryParse(countController.text.trim()) ?? 1;
                    final changes = <String, dynamic>{
                      'title': titleController.text.trim(),
                      'description': descriptionController.text.trim(),
                      'event_date':
                          selectedDate.toIso8601String().split('T').first,
                      'starts_at': startAt.toUtc().toIso8601String(),
                      'ends_at': endAt.toUtc().toIso8601String(),
                      'difficulty_weight': weight,
                      'recurrence_freq': freq,
                      'recurrence_interval':
                          freq == 'N' ? 1 : math.max(1, parsedInterval),
                      'recurrence_end_date': freq != 'N' && endMode == 1
                          ? recurrenceEndDate?.toIso8601String().split('T').first
                          : null,
                      'recurrence_count': freq != 'N' && endMode == 2
                          ? math.max(1, parsedCount)
                          : null,
                    };
                    try {
                      await onUpdate(event, changes);
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      setState(() {
                        submitting = false;
                        feedback =
                            ActionFeedback(message: error.toString(), isError: true);
                      });
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
            child: Text(submitting ? l10n.noteMetaSaving : l10n.commonSave),
          ),
        ],
      ),
    ),
  );

  titleController.dispose();
  descriptionController.dispose();
  intervalController.dispose();
  countController.dispose();
}

/// Opens a local iCal file picker and forwards the result to the callback.
Future<void> _showImportCalendarDialog(
  BuildContext context,
  Future<Map<String, dynamic>?> Function(String rawIcal, String title,
          {int? courseId})
      onImport,
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
  Map<String, dynamic>? summary;
  String? failure;
  try {
    summary = await onImport(rawIcal, file.name);
  } catch (error) {
    failure = error.toString();
  }
  if (!context.mounted) {
    return;
  }
  await _showImportResultModal(context, summary, failure, file.name);
}

/// Result modal shown after an iCal import / subscription: lists the
/// imported events on success, or the reason it failed. `summary` is the
/// backend `import_summary` ({ok,count,events,error}); `failure` is a
/// client-side/transport error (e.g. not signed in).
Future<void> _showImportResultModal(
  BuildContext context,
  Map<String, dynamic>? summary,
  String? failure,
  String feedTitle,
) async {
  final l10n = AppLocalizations.of(context);
  final ok = failure == null && (summary?['ok'] == true);
  final events = (summary?['events'] as List<dynamic>? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final count = (summary?['count'] as num?)?.toInt() ?? events.length;
  final errorText = failure ?? summary?['error']?.toString();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok
                ? Colors.green
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? l10n.activityImportSucceeded
                  : l10n.activityImportFailed,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ok) ...[
              Text(l10n.activityImportedCount(count, feedTitle)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in events)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(
                                child: Text(
                                  _importEventLabel(event),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ] else
              Text(errorText ?? l10n.activityImportFailed),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonOk),
        ),
      ],
    ),
  );
}

String _importEventLabel(Map<String, dynamic> event) {
  final title = event['title']?.toString() ?? 'Event';
  final startsAt = event['starts_at']?.toString() ?? '';
  if (startsAt.isEmpty) {
    return title;
  }
  return '$title — ${_formatDeadlineStamp(startsAt)}';
}

/// Opens a dialog for subscribing to a remote iCal feed.
Future<void> _showSubscribeCalendarDialog(
  BuildContext context,
  Future<Map<String, dynamic>?> Function(String title, String url,
          {int? courseId})
      onSubscribe,
) async {
  final titleController = TextEditingController();
  final urlController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context).activitySubscribeToCalendar),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).noteTitleHint,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).activityIcalUrl,
                  border: const OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () async {
            final feedTitle = titleController.text.trim().isEmpty
                ? AppLocalizations.of(context).activitySubscribedCalendar
                : titleController.text.trim();
            Map<String, dynamic>? summary;
            String? failure;
            try {
              summary = await onSubscribe(feedTitle, urlController.text.trim());
            } catch (error) {
              failure = error.toString();
            }
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pop();
            await _showImportResultModal(context, summary, failure, feedTitle);
          },
          child: Text(AppLocalizations.of(context).courseSubscribe),
        ),
      ],
    ),
  );
  titleController.dispose();
  urlController.dispose();
}
