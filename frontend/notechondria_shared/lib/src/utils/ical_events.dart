/// Offline iCalendar (RFC 5545) VEVENT reader (0.1.199).
///
/// The planner parses imported `.ics` files on the device so an import
/// works with no cloud session and no reachable backend. The backend's
/// own importer only reads DTSTART / DTEND / SUMMARY, so this reader
/// covers what the planner renders and stores:
///
/// * line unfolding (CRLF / CR / LF; a leading space or tab continues the
///   previous line), a leading byte-order mark is ignored;
/// * properties read only at VEVENT depth, so a nested `VALARM`'s
///   DESCRIPTION / TRIGGER never leak into the event;
/// * SUMMARY / DESCRIPTION / UID with text unescaping (`\,` `\;` `\n`
///   `\N` `\\`);
/// * DTSTART / DTEND: `...Z` is UTC; `VALUE=DATE` or a bare 8-digit date
///   is an all-day event at local midnight; `TZID=` and floating times
///   are read as device-local time (documented limitation: no VTIMEZONE
///   resolution);
/// * a missing or unreadable DTSTART skips the event (counted in
///   [IcalParseResult.skipped]); a missing, unreadable, or non-positive
///   DTEND becomes start + 1 hour (timed) or start + 1 day (all-day);
/// * `X-WR-CALNAME` names the calendar;
/// * RRULE is not expanded (documented limitation): a recurring event
///   imports as its first occurrence.
library;

/// One parsed VEVENT.
class IcalEvent {
  const IcalEvent({
    required this.uid,
    required this.summary,
    this.description = '',
    required this.start,
    required this.end,
    this.allDay = false,
  });

  final String uid;
  final String summary;
  final String description;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Local-archive `calendar_feeds.json` event shape. UTC times keep
  /// their `Z`; device-local times are written without an offset.
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': summary,
        'description': description,
        'starts_at': start.toIso8601String(),
        'ends_at': end.toIso8601String(),
        'all_day': allDay,
      };
}

/// Result of [parseIcalEvents]: the calendar name (empty when the file
/// has no `X-WR-CALNAME`), the readable events sorted by start, and how
/// many VEVENTs were skipped for lacking a readable DTSTART.
class IcalParseResult {
  const IcalParseResult({
    required this.calendarName,
    required this.events,
    required this.skipped,
  });

  final String calendarName;
  final List<IcalEvent> events;
  final int skipped;
}

class _IcalProperty {
  const _IcalProperty(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;
}

/// Parses the VEVENTs of an iCalendar document. Never throws: unreadable
/// lines are ignored and unreadable events are counted as skipped.
IcalParseResult parseIcalEvents(String raw) {
  var calendarName = '';
  var skipped = 0;
  final events = <IcalEvent>[];
  final stack = <String>[];
  Map<String, _IcalProperty>? current;

  for (final line in _unfoldLines(raw)) {
    final prop = _parseProperty(line);
    if (prop == null) continue;
    if (prop.name == 'BEGIN') {
      final component = prop.value.trim().toUpperCase();
      stack.add(component);
      if (component == 'VEVENT' && current == null) {
        current = <String, _IcalProperty>{};
      }
      continue;
    }
    if (prop.name == 'END') {
      if (stack.isEmpty) continue;
      final closed = stack.removeLast();
      if (closed == 'VEVENT' && current != null) {
        final event = _buildEvent(current, events.length + skipped);
        if (event == null) {
          skipped++;
        } else {
          events.add(event);
        }
        current = null;
      }
      continue;
    }
    if (current != null) {
      // Only the VEVENT's own properties; nested VALARM etc. are ignored.
      if (stack.isNotEmpty && stack.last == 'VEVENT') {
        current.putIfAbsent(prop.name, () => prop);
      }
      continue;
    }
    if (prop.name == 'X-WR-CALNAME' &&
        calendarName.isEmpty &&
        stack.length <= 1) {
      calendarName = _unescapeText(prop.value).trim();
    }
  }

  events.sort((a, b) => a.start.compareTo(b.start));
  return IcalParseResult(
    calendarName: calendarName,
    events: List<IcalEvent>.unmodifiable(events),
    skipped: skipped,
  );
}

IcalEvent? _buildEvent(Map<String, _IcalProperty> props, int index) {
  final startProp = props['DTSTART'];
  final start = startProp == null ? null : _parseIcalDate(startProp);
  if (start == null) return null;
  final endProp = props['DTEND'];
  final parsedEnd = endProp == null ? null : _parseIcalDate(endProp);
  final fallbackEnd = start.allDay
      ? start.value.add(const Duration(days: 1))
      : start.value.add(const Duration(hours: 1));
  final end = parsedEnd == null || !parsedEnd.value.isAfter(start.value)
      ? fallbackEnd
      : parsedEnd.value;
  final summary = _unescapeText(props['SUMMARY']?.value ?? '').trim();
  final uid = _unescapeText(props['UID']?.value ?? '').trim();
  return IcalEvent(
    uid: uid.isEmpty ? 'local-$index-${start.value.toIso8601String()}' : uid,
    summary: summary.isEmpty ? '(untitled event)' : summary,
    description: _unescapeText(props['DESCRIPTION']?.value ?? '').trim(),
    start: start.value,
    end: end,
    allDay: start.allDay,
  );
}

/// RFC 5545 §3.1 unfolding. Empty lines are dropped.
List<String> _unfoldLines(String raw) {
  var text = raw;
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = <String>[];
  for (final line in normalized.split('\n')) {
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] = lines.last + line.substring(1);
    } else {
      lines.add(line);
    }
  }
  return lines;
}

/// Splits `NAME;PARAM=V;PARAM2="a:b":VALUE` at the first colon outside a
/// quoted parameter value.
_IcalProperty? _parseProperty(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ':' && !inQuotes) {
      final head = line.substring(0, i).split(';');
      final name = head.first.trim().toUpperCase();
      if (name.isEmpty) return null;
      final params = <String, String>{};
      for (final param in head.skip(1)) {
        final eq = param.indexOf('=');
        if (eq <= 0) continue;
        params[param.substring(0, eq).trim().toUpperCase()] =
            param.substring(eq + 1).replaceAll('"', '').trim();
      }
      return _IcalProperty(name, params, line.substring(i + 1));
    }
  }
  return null;
}

final RegExp _icalDatePattern =
    RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$');

({DateTime value, bool allDay})? _parseIcalDate(_IcalProperty prop) {
  final raw = prop.value.trim().toUpperCase();
  final match = _icalDatePattern.firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final dateOnly =
      prop.params['VALUE']?.toUpperCase() == 'DATE' || match.group(4) == null;
  if (dateOnly) {
    final value = DateTime(year, month, day);
    // DateTime normalizes overflow (Feb 30 -> Mar 2); treat that as invalid.
    if (value.month != month || value.day != day) return null;
    return (value: value, allDay: true);
  }
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6) ?? '0');
  if (hour > 23 || minute > 59 || second > 60) return null;
  final value = match.group(7) != null
      ? DateTime.utc(year, month, day, hour, minute, second)
      : DateTime(year, month, day, hour, minute, second);
  if (value.month != month || value.day != day) return null;
  return (value: value, allDay: false);
}

String _unescapeText(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == r'\' && i + 1 < value.length) {
      final next = value[i + 1];
      if (next == 'n' || next == 'N') {
        out.write('\n');
        i++;
        continue;
      }
      if (next == ',' || next == ';' || next == r'\') {
        out.write(next);
        i++;
        continue;
      }
    }
    out.write(char);
  }
  return out.toString();
}
