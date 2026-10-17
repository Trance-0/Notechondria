part of notechondria_frontend;

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
  });

  final Map<String, dynamic> event;
  final bool vertical;
  final double slotExtent;
  final VoidCallback? onTap;

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
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              event['title']?.toString() ?? 'Event',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              // Backgrounds are fixed light pastels, so pin the label to a
              // dark ink color — the theme's onSurface goes white in dark
              // mode and would be invisible on these tiles.
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kCalendarEventInk,
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Fixed dark ink for event tiles painted on light pastel backgrounds so the
/// label stays legible in both light and dark themes.
const Color _kCalendarEventInk = Color(0xFF1F2933);

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
    int? courseId,
  }) onCreatePlannerEvent, {
  List<Map<String, dynamic>> courses = const <Map<String, dynamic>>[],
}) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var selectedDate = _dateOnly(DateTime.now()).add(const Duration(days: 1));
  var selectedTime = const TimeOfDay(hour: 14, minute: 0);
  var weight = 1;
  // null = uncategorized "inbox" (course optional by design).
  int? selectedCourseId;
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
                          lastDate: _dateOnly(DateTime.now())
                              .add(const Duration(days: 365)),
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
                    child: Text(AppLocalizations.of(context)
                        .activityWeightN(index + 1)),
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
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: selectedCourseId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Inbox (uncategorized)'),
                  ),
                  for (final course in courses)
                    if (course['id'] is int)
                      DropdownMenuItem<int?>(
                        value: course['id'] as int,
                        child: Text(
                          course['title']?.toString() ?? 'Course',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: (value) => setState(() => selectedCourseId = value),
                decoration: const InputDecoration(
                  labelText: 'Course (project)',
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
                      courseId: selectedCourseId,
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


/// Opens a local iCal/zip file picker, parses a preview on the device, and
/// shows a confirmation page with the event summary before handing the
/// file to [onImport]. Accepts both .ics files and .zip archives
/// (extracting the first .ics entry from the archive).
///
/// 0.1.199: the preview and the import use the same parser
/// (`parseIcalEvents`), so the previewed count is what gets imported. An
/// import error stays inside the dialog as copyable inline text; it used
/// to be a SnackBar raised under the dialog's modal barrier, where it
/// could be neither read in full nor copied.
Future<void> _showImportCalendarDialog(
  BuildContext context,
  Future<ActionFeedback> Function(
    String rawIcal,
    String title, {
    int? courseId,
    String sourceName,
  }) onImport,
) async {
  XFile? file;
  final String rawIcal;
  try {
    file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'iCal or zip', extensions: ['ics', 'zip'])
      ],
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (file.name.toLowerCase().endsWith('.zip')) {
      final extracted = _extractFirstIcsFromZip(bytes);
      if (extracted == null) {
        if (context.mounted) {
          showCopyableSnackBar(
            context,
            'Calendar not imported: Planner.Sync.Calendar/parse \u2014 '
            '"${file.name}" contains no .ics file.',
            isError: true,
          );
        }
        return;
      }
      rawIcal = extracted;
    } else {
      rawIcal = utf8.decode(bytes, allowMalformed: true);
    }
  } catch (error) {
    if (context.mounted) {
      showCopyableSnackBar(
        context,
        'Calendar not imported: Planner.Sync.Calendar/parse \u2014 '
        '"${file?.name ?? 'the selected file'}" could not be read '
        '(${describeRequestFailure(error)}).',
        isError: true,
      );
    }
    return;
  }
  if (!context.mounted) {
    return;
  }

  final sourceName = file.name;
  final result = await showDialog<ActionFeedback>(
    context: context,
    builder: (_) => _ImportCalendarReviewDialog(
      sourceName: sourceName,
      rawIcal: rawIcal,
      preview: parseIcalEvents(rawIcal),
      onImport: onImport,
    ),
  );
  if (result != null && context.mounted) {
    showCopyableSnackBar(context, result.message, isError: result.isError);
  }
}

/// Review page of the iCal import. A StatefulWidget so the title
/// controller is disposed with the route (after its exit animation), not
/// right after `showDialog` returns. Pops with the successful
/// [ActionFeedback] (or the kept-locally warning after a failed upload);
/// an error result stays inline.
class _ImportCalendarReviewDialog extends StatefulWidget {
  const _ImportCalendarReviewDialog({
    required this.sourceName,
    required this.rawIcal,
    required this.preview,
    required this.onImport,
  });

  final String sourceName;
  final String rawIcal;
  final IcalParseResult preview;
  final Future<ActionFeedback> Function(
    String rawIcal,
    String title, {
    int? courseId,
    String sourceName,
  }) onImport;

  @override
  State<_ImportCalendarReviewDialog> createState() =>
      _ImportCalendarReviewDialogState();
}

class _ImportCalendarReviewDialogState
    extends State<_ImportCalendarReviewDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.preview.calendarName.isNotEmpty
        ? widget.preview.calendarName
        : widget.sourceName
            .replaceAll(RegExp(r'\.(ics|zip)$', caseSensitive: false), ''),
  );
  var _importing = false;
  ActionFeedback? _feedback;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _importing = true;
      _feedback = null;
    });
    final title = _titleController.text.trim().isEmpty
        ? 'Imported calendar'
        : _titleController.text.trim();
    ActionFeedback result;
    try {
      result = await widget.onImport(
        widget.rawIcal,
        title,
        sourceName: widget.sourceName,
      );
    } catch (error) {
      result = ActionFeedback(
        message: 'Calendar not imported: Planner.Sync.Calendar/import '
            '\u2014 unexpected error (${describeRequestFailure(error)}).',
        isError: true,
      );
    }
    if (!mounted) return;
    // A calendar kept locally after a failed upload is a warning, but it
    // was imported, so the dialog closes like a success.
    if (result.isError && result is! _CalendarKeptLocallyFeedback) {
      setState(() {
        _importing = false;
        _feedback = result;
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = widget.preview.events;
    final skipped = widget.preview.skipped;
    String day(DateTime value) =>
        value.toLocal().toIso8601String().split('T').first;
    return AlertDialog(
      title: const Text('Review calendar import'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Source: ${widget.sourceName}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${events.length} event${events.length == 1 ? '' : 's'} parsed',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (skipped > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$skipped skipped (no start time)',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (events.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Date range: ${day(events.first.start)} → '
                  '${day(events.last.start)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Preview (up to 5 events):',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                for (final event in events.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(
                          child: Text(
                            '${event.summary} — '
                            '${event.start.toLocal().toIso8601String()}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Calendar title',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                FeedbackText(feedback: _feedback!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _importing ? null : _confirm,
          child: Text(_importing ? 'Importing...' : 'Confirm import'),
        ),
      ],
    );
  }
}

/// Opens a dialog for subscribing to a remote iCal feed. Errors (for
/// example "needs a cloud session" while signed out) stay inline and
/// copyable; the dialog closes only on success.
Future<void> _showSubscribeCalendarDialog(
  BuildContext context,
  Future<ActionFeedback> Function(String title, String url, {int? courseId})
      onSubscribe,
) async {
  final result = await showDialog<ActionFeedback>(
    context: context,
    builder: (_) => _SubscribeCalendarDialog(onSubscribe: onSubscribe),
  );
  if (result != null && context.mounted) {
    showCopyableSnackBar(context, result.message);
  }
}

class _SubscribeCalendarDialog extends StatefulWidget {
  const _SubscribeCalendarDialog({required this.onSubscribe});

  final Future<ActionFeedback> Function(String title, String url,
      {int? courseId}) onSubscribe;

  @override
  State<_SubscribeCalendarDialog> createState() =>
      _SubscribeCalendarDialogState();
}

class _SubscribeCalendarDialogState extends State<_SubscribeCalendarDialog> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  var _submitting = false;
  ActionFeedback? _feedback;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    ActionFeedback result;
    try {
      result = await widget.onSubscribe(
        _titleController.text.trim().isEmpty
            ? 'Subscribed calendar'
            : _titleController.text.trim(),
        _urlController.text.trim(),
      );
    } catch (error) {
      result = ActionFeedback(
        message: 'Calendar not subscribed: Planner.Sync.Calendar/subscribe '
            '\u2014 unexpected error (${describeRequestFailure(error)}).',
        isError: true,
      );
    }
    if (!mounted) return;
    if (result.isError) {
      setState(() {
        _submitting = false;
        _feedback = result;
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Subscribe to calendar'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'iCal URL or Google share link',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Supports Google Calendar share links (public URL or cid '
                'link) and direct .ics URLs from iCloud, Outlook, or any '
                'iCal feed. For best results, use "Secret address in iCal '
                'format" from Google Calendar settings. Subscribing needs a '
                'cloud session (the server downloads the feed); offline, '
                'download the .ics file and use Import iCal.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                FeedbackText(feedback: _feedback!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Subscribing...' : 'Subscribe'),
        ),
      ],
    );
  }
}
