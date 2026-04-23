part of notechondria_frontend;

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

