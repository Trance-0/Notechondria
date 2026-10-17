import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// Offline iCal reader (0.1.199) used by the planner's local import.
String _calendar(String body, {String name = 'Phase1 Test Calendar'}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n'
    '${name.isEmpty ? '' : 'X-WR-CALNAME:$name\r\n'}'
    '$body'
    'END:VCALENDAR\r\n';

void main() {
  test('reads a timed UTC event, the calendar name, and the UID', () {
    final result = parseIcalEvents(_calendar(
      'BEGIN:VEVENT\r\nUID:abc-1\r\nSUMMARY:Phase1 Lecture\r\n'
      'DTSTART:20261020T140000Z\r\nDTEND:20261020T150000Z\r\nEND:VEVENT\r\n',
    ));
    expect(result.calendarName, 'Phase1 Test Calendar');
    expect(result.skipped, 0);
    expect(result.events, hasLength(1));
    final event = result.events.single;
    expect(event.uid, 'abc-1');
    expect(event.summary, 'Phase1 Lecture');
    expect(event.start, DateTime.utc(2026, 10, 20, 14));
    expect(event.start.isUtc, isTrue);
    expect(event.end, DateTime.utc(2026, 10, 20, 15));
    expect(event.allDay, isFalse);
    expect(event.toJson()['starts_at'], '2026-10-20T14:00:00.000Z');
    expect(event.toJson()['title'], 'Phase1 Lecture');
  });

  test('unfolds continuation lines and unescapes text', () {
    final result = parseIcalEvents(_calendar(
      'BEGIN:VEVENT\r\nSUMMARY:Long \r\n title\\, with comma\r\n'
      'DESCRIPTION:Line one\\nLine two\\; done\\\\\r\n'
      'DTSTART:20261021T090000\r\nEND:VEVENT\r\n',
    ));
    final event = result.events.single;
    expect(event.summary, 'Long title, with comma');
    expect(event.description, 'Line one\nLine two; done\\');
  });

  test('floating and TZID times are device-local; all-day dates too', () {
    final result = parseIcalEvents(_calendar(
      'BEGIN:VEVENT\r\nSUMMARY:Floating\r\nDTSTART:20261021T090000\r\n'
      'END:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Zoned\r\n'
      'DTSTART;TZID=America/Chicago:20261022T100000\r\n'
      'DTEND;TZID=America/Chicago:20261022T113000\r\nEND:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Holiday\r\nDTSTART;VALUE=DATE:20261023\r\n'
      'END:VEVENT\r\n',
    ));
    expect(result.events.map((e) => e.summary),
        ['Floating', 'Zoned', 'Holiday']);
    final floating = result.events[0];
    expect(floating.start, DateTime(2026, 10, 21, 9));
    expect(floating.start.isUtc, isFalse);
    // Missing DTEND on a timed event: one hour.
    expect(floating.end, DateTime(2026, 10, 21, 10));
    expect(result.events[1].end, DateTime(2026, 10, 22, 11, 30));
    final holiday = result.events[2];
    expect(holiday.allDay, isTrue);
    expect(holiday.start, DateTime(2026, 10, 23));
    // Missing DTEND on an all-day event: one day.
    expect(holiday.end, DateTime(2026, 10, 24));
  });

  test('nested VALARM properties do not leak into the event', () {
    final result = parseIcalEvents(_calendar(
      'BEGIN:VEVENT\r\nSUMMARY:Exam\r\nDTSTART:20261024T080000Z\r\n'
      'BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Reminder text\r\n'
      'TRIGGER:-PT15M\r\nEND:VALARM\r\n'
      'DESCRIPTION:Bring a pencil\r\nEND:VEVENT\r\n',
    ));
    final event = result.events.single;
    expect(event.summary, 'Exam');
    expect(event.description, 'Bring a pencil');
  });

  test('events without a readable DTSTART are skipped and counted', () {
    final result = parseIcalEvents(_calendar(
      'BEGIN:VEVENT\r\nSUMMARY:No start\r\nEND:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Bad start\r\nDTSTART:not-a-date\r\n'
      'END:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Later\r\nDTSTART:20261030T100000Z\r\n'
      'END:VEVENT\r\n'
      'BEGIN:VEVENT\r\nSUMMARY:Earlier\r\nDTSTART:20261025T100000Z\r\n'
      'END:VEVENT\r\n',
    ));
    expect(result.skipped, 2);
    // Sorted by start.
    expect(result.events.map((e) => e.summary), ['Earlier', 'Later']);
  });

  test('an empty VCALENDAR has no events and no name', () {
    final result = parseIcalEvents(_calendar('', name: ''));
    expect(result.events, isEmpty);
    expect(result.skipped, 0);
    expect(result.calendarName, isEmpty);
    expect(parseIcalEvents('').events, isEmpty);
    expect(parseIcalEvents('not a calendar at all').events, isEmpty);
  });
}
