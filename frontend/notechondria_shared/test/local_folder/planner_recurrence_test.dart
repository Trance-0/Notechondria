// Recurrence and calendar-URL parity (F35, F42). The expected values come
// from `_expand_occurrence_dates` and `normalize_calendar_url` of
// backend/notes/services.py, loaded by recurrence_cases.py (CPython 3.9.23)
// and embedded below; the deadline and occurrence cases follow
// `_occurrence_payload` and `planner_deadline_payload` (services.py:278-307).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/handlers/calendar.dart';
import 'package:notechondria_shared/src/local_folder/handlers/planner_records.dart';
import 'package:notechondria_shared/src/local_folder/handlers/records.dart';

const String _cases = r'''
{
 "expand": [
  [
   "N",
   1,
   "2026-10-21",
   null,
   null,
   "2026-10-19",
   "2026-10-25",
   [
    "2026-10-21"
   ]
  ],
  [
   "N",
   1,
   "2026-10-26",
   null,
   null,
   "2026-10-19",
   "2026-10-25",
   []
  ],
  [
   "W",
   1,
   "2026-09-01",
   null,
   null,
   "2026-10-19",
   "2026-11-17",
   [
    "2026-10-20",
    "2026-10-27",
    "2026-11-03",
    "2026-11-10",
    "2026-11-17"
   ]
  ],
  [
   "W",
   2,
   "2026-10-05",
   null,
   3,
   "2026-10-01",
   "2027-01-31",
   [
    "2026-10-05",
    "2026-10-19",
    "2026-11-02"
   ]
  ],
  [
   "W",
   1,
   "2026-10-05",
   "2026-10-26",
   null,
   "2026-10-01",
   "2026-12-31",
   [
    "2026-10-05",
    "2026-10-12",
    "2026-10-19",
    "2026-10-26"
   ]
  ],
  [
   "W",
   0,
   "2026-10-05",
   null,
   2,
   "2026-10-01",
   "2026-12-31",
   [
    "2026-10-05",
    "2026-10-12"
   ]
  ],
  [
   "M",
   1,
   "2027-01-31",
   null,
   6,
   "2027-01-01",
   "2027-12-31",
   [
    "2027-01-31",
    "2027-02-28",
    "2027-03-31",
    "2027-04-30",
    "2027-05-31",
    "2027-06-30"
   ]
  ],
  [
   "M",
   1,
   "2028-01-31",
   null,
   3,
   "2028-01-01",
   "2028-12-31",
   [
    "2028-01-31",
    "2028-02-29",
    "2028-03-31"
   ]
  ],
  [
   "M",
   3,
   "2026-11-30",
   "2027-09-01",
   null,
   "2026-01-01",
   "2027-12-31",
   [
    "2026-11-30",
    "2027-02-28",
    "2027-05-30",
    "2027-08-30"
   ]
  ],
  [
   "Y",
   1,
   "2028-02-29",
   null,
   5,
   "2028-01-01",
   "2033-12-31",
   [
    "2028-02-29",
    "2029-02-28",
    "2030-02-28",
    "2031-02-28",
    "2032-02-29"
   ]
  ],
  [
   "Y",
   2,
   "2026-10-19",
   null,
   null,
   "2030-01-01",
   "2034-12-31",
   [
    "2030-10-19",
    "2032-10-19",
    "2034-10-19"
   ]
  ],
  [
   "M",
   1,
   "2026-10-15",
   null,
   1,
   "2026-11-01",
   "2026-12-31",
   []
  ],
  [
   "W",
   1,
   "2026-10-19",
   null,
   0,
   "2026-10-01",
   "2026-12-31",
   []
  ],
  [
   "W",
   1,
   "2026-01-05",
   null,
   null,
   "2101-01-01",
   "2101-02-01",
   [
    "2101-01-03",
    "2101-01-10",
    "2101-01-17",
    "2101-01-24",
    "2101-01-31"
   ]
  ],
  [
   "W",
   1,
   "2026-01-05",
   null,
   null,
   "2102-08-01",
   "2102-09-30",
   [
    "2102-08-07",
    "2102-08-14",
    "2102-08-21",
    "2102-08-28"
   ]
  ]
 ],
 "urls": [
  [
   "",
   ""
  ],
  [
   "https://example.com/feed.ics",
   "https://example.com/feed.ics"
  ],
  [
   "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/public/basic.ics",
   "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar/embed?src=abc%40group.calendar.google.com&ctz=UTC",
   "https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar/embed?src=en.usa%23holiday%40group.v.calendar.google.com",
   "https://calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar/u/0/r?cid=dGVhbUBncm91cC5jYWxlbmRhci5nb29nbGUuY29t",
   "https://calendar.google.com/calendar/ical/team%40group.calendar.google.com/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar?cid=dGVhbUBncm91cC5jYWxlbmRhci5nb29nbGUuY29t==",
   "https://calendar.google.com/calendar/ical/team%40group.calendar.google.com/public/basic.ics"
  ],
  [
   "https://Calendar.Google.com/calendar/embed?src=a+b%21%2A%28%29",
   "https://calendar.google.com/calendar/ical/a%20b%21%2A%28%29/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar/embed?ctz=UTC",
   "https://calendar.google.com/calendar/embed?ctz=UTC"
  ],
  [
   "https://calendar.google.com/calendar/embed?src=&cid=dGVhbUBncm91cC5jYWxlbmRhci5nb29nbGUuY29t",
   "https://calendar.google.com/calendar/ical/team%40group.calendar.google.com/public/basic.ics"
  ],
  [
   "https://calendar.google.com/calendar/r?cid=%21%21%21",
   "https://calendar.google.com/calendar/r?cid=%21%21%21"
  ]
 ]
}
''';

final CourseLookup _noCourses = CourseLookup(const []);

void main() {
  final cases = jsonDecode(_cases) as Map<String, dynamic>;

  group('recurrence expansion matches _expand_occurrence_dates', () {
    for (final c in cases['expand'] as List) {
      final [freq, interval, base, end, count, ws, we, dates] = c as List;
      test('$freq every $interval from $base (end $end, count $count) in $ws..$we', () {
        final rule = EventRule({
          'event_date': base,
          'recurrence_freq': freq,
          'recurrence_interval': interval,
          'recurrence_end_date': end,
          'recurrence_count': count,
        });
        final got = rule
            .occurrences(parseIsoDay(ws as String)!, parseIsoDay(we as String)!)
            .map((d) => d.toIso8601String().substring(0, 10))
            .toList();
        expect(got, dates);
      });
    }
  });

  test('normalizeCalendarUrl matches normalize_calendar_url', () {
    for (final c in cases['urls'] as List) {
      final [input, expected] = c as List;
      expect(normalizeCalendarUrl(input as String), expected, reason: input);
    }
  });

  test('an occurrence keeps the time of day and names its date', () {
    final record = {
      'id': 4,
      'title': 'Lab',
      'event_date': '2026-10-05',
      'starts_at': '2026-10-05T14:30:00.000Z',
      'ends_at': '2026-10-05T16:00:00.000Z',
      'recurrence_freq': 'W',
      'recurrence_interval': 1,
    };
    final p = occurrencePayload(record, _noCourses, DateTime.utc(2026, 10, 19));
    expect(p['event_date'], '2026-10-19');
    expect(p['occurrence_date'], '2026-10-19');
    expect(p['starts_at'], '2026-10-19T14:30:00.000Z');
    expect(p['ends_at'], '2026-10-19T16:00:00.000Z');
    expect(p['recurrence_freq'], 'W');
    final base = occurrencePayload(record, _noCourses, DateTime.utc(2026, 10, 5));
    expect(base['starts_at'], '2026-10-05T14:30:00.000Z');
  });

  test('urgency is the weight over the hours left, at least one minute', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    Map<String, Object?> event(String startsAt, int weight) => {
          'id': 1,
          'title': 'Exam',
          'event_date': startsAt.substring(0, 10),
          'starts_at': startsAt,
          'difficulty_weight': weight,
        };
    // 3 / 48 h = 0.0625; 2 / 7 h = 0.285714... -> 0.2857.
    expect(deadlinePayload(event('2026-10-21T12:00:00Z', 3), _noCourses, now)['urgency_score'],
        0.0625);
    expect(deadlinePayload(event('2026-10-19T19:00:00Z', 2), _noCourses, now)['urgency_score'],
        0.2857);
    // Past or now: 1/60 h, so the weight times 60.
    expect(deadlinePayload(event('2026-10-19T08:00:00Z', 2), _noCourses, now)['urgency_score'],
        120.0);
    final occ = deadlinePayload(
        {...event('2026-10-12T12:00:00Z', 1), 'recurrence_freq': 'W'}, _noCourses, now,
        occ: DateTime.utc(2026, 10, 26));
    expect(occ['occurrence_date'], '2026-10-26');
    // 1 / 168 h = 0.00595... -> 0.006.
    expect(occ['urgency_score'], 0.006);
  });

  test('a missing start is local noon of the day; a missing end one hour later', () {
    final p = plannerEventPayload({'id': 1, 'title': 'x', 'event_date': '2026-10-21'}, _noCourses);
    final start = DateTime.parse('${p['starts_at']}').toLocal();
    expect([start.year, start.month, start.day, start.hour], [2026, 10, 21, 12]);
    expect(DateTime.parse('${p['ends_at']}').difference(start), const Duration(hours: 1));
    expect(p['recurrence_freq'], 'N');
    expect(p['course'], isNull);
  });

  test('addMonths clamps to the end of the month', () {
    expect(addMonths(DateTime.utc(2027, 1, 31), 1), DateTime.utc(2027, 2, 28));
    expect(addMonths(DateTime.utc(2028, 1, 31), 1), DateTime.utc(2028, 2, 29));
    expect(addMonths(DateTime.utc(2026, 11, 30), 14), DateTime.utc(2028, 1, 30));
  });
}
