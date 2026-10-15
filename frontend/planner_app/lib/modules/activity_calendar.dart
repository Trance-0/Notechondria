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
          const SnackBar(
              content: Text('No .ics file found inside the archive.')),
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
                if (preview.firstStart != null &&
                    preview.lastStart != null) ...[
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
