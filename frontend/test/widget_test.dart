import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements NotechondriaClient {
  FakeClient();

  final List<String> requestedActivityWeekStarts = [];

  List<Map<String, dynamic>> _notes = [
    _sampleNote(
      id: 11,
      title: 'Project outcome',
      description: 'Repository layout and build order.',
      courseTitle: 'Vibe Coding 101',
      isPublic: true,
    ),
  ];

  List<Map<String, dynamic>> _deletedNotes = [];
  List<Map<String, dynamic>> _courses = [
    _sampleCourse(
      id: 7,
      title: 'Vibe Coding 101',
      isSubscribed: true,
      lastOpenedAt: '2026-03-21T10:00:00Z',
    ),
    _sampleCourse(
      id: 8,
      title: 'Meaning of Work in Age of AI',
      isSubscribed: false,
    ),
    _sampleCourse(
      id: 9,
      title: 'Self-identity and Expression in Modern Arts',
      isSubscribed: false,
    ),
  ];

  static Map<String, dynamic> _sampleCourse({
    required int id,
    required String title,
    bool isSubscribed = false,
    String? lastOpenedAt,
  }) {
    return {
      'id': id,
      'slug': title.toLowerCase().replaceAll(' ', '-'),
      'title': title,
      'description': '$title preview description',
      'cover_image_url': '',
      'subscriber_count': 3,
      'is_subscribed': isSubscribed,
      'last_opened_at': lastOpenedAt,
      'owner': {
        'id': 1,
        'username': 'CodeX',
        'display_name': 'CodeX',
        'image_url': '',
      },
      'recent_notes': [
        _sampleNote(
          id: id * 10,
          title: '$title note',
          description: 'Preview note',
          courseTitle: title,
          isPublic: true,
        ),
      ],
      'media': const [],
    };
  }

  static Map<String, dynamic> _sampleNote({
    required int id,
    required String title,
    required String description,
    required String courseTitle,
    bool isPublic = false,
  }) {
    return {
      'id': id,
      'title': title,
      'description': description,
      'excerpt': description,
      'preview_lines': [description],
      'editor_mode': 'P',
      'is_public': isPublic,
      'last_edit': '2026-03-21T12:00:00Z',
      'date_created': '2026-03-20T12:00:00Z',
      'course_id': 7,
      'course': {
        'id': 7,
        'title': courseTitle,
        'slug': courseTitle.toLowerCase().replaceAll(' ', '-'),
      },
      'author': {
        'id': 1,
        'username': 'CodeX',
        'display_name': 'CodeX',
        'image_url': '',
      },
      'content': '# $title\n\n$description\n\nInline math: \$a^2+b^2=c^2\$',
      'metadata_json': '{}',
      'blocks': [
        {'block_type': 'T', 'text': title},
        {'block_type': 'N', 'text': description},
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async => [
        {
          'id': 1,
          'title': 'Project outcome',
          'excerpt': 'Repository layout and build order.',
        }
      ];

  @override
  Future<Map<String, dynamic>> getActivityWeek(String token,
          {String? startDate}) async {
    final effectiveStart = _dateOnly(
      DateTime.tryParse(startDate ?? '') ?? DateTime(2026, 3, 21),
    );
    requestedActivityWeekStarts.add(_isoDate(effectiveStart));
    return {
      'start_date': _isoDate(effectiveStart),
      'previous_week_start':
          _isoDate(effectiveStart.subtract(const Duration(days: 7))),
      'next_week_start': _isoDate(effectiveStart.add(const Duration(days: 7))),
      'days': List.generate(7, (index) {
        final day = effectiveStart.add(Duration(days: index));
        return {
          'date': _isoDate(day),
          'events': [
            {
              'title': index == 0 ? 'Study block' : 'Review block',
              'kind': index.isEven ? 'calendar' : 'plan',
              'starts_at': DateTime.utc(day.year, day.month, day.day, 14)
                  .toIso8601String(),
              'ends_at': DateTime.utc(day.year, day.month, day.day, 15)
                  .toIso8601String(),
            }
          ],
        };
      }),
      'deadlines': [
        {
          'id': 22,
          'title': 'Essay draft',
          'description': 'Finish the argument outline.',
          'event_date':
              _isoDate(effectiveStart.add(const Duration(days: 1))),
          'starts_at': DateTime.utc(
            effectiveStart.year,
            effectiveStart.month,
            effectiveStart.day + 1,
            18,
          ).toIso8601String(),
          'ends_at': DateTime.utc(
            effectiveStart.year,
            effectiveStart.month,
            effectiveStart.day + 1,
            19,
          ).toIso8601String(),
          'difficulty_weight': 3,
          'is_completed': false,
          'urgency_score': 1.75,
        }
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token) async => [];

  @override
  Future<Map<String, dynamic>> createCalendarFeed(
          String token, Map<String, dynamic> payload) async =>
      payload;

  @override
  Future<Map<String, dynamic>> updateCalendarFeed(
          String token, int feedId, Map<String, dynamic> payload) async =>
      payload;

  @override
  Future<void> deleteCalendarFeed(String token, int feedId) async {}

  @override
  Future<Map<String, dynamic>> createNote(
      String token, Map<String, dynamic> payload) async {
    final note = _sampleNote(
      id: 99,
      title: payload['title']?.toString() ?? 'Untitled note',
      description: payload['description']?.toString() ?? '',
      courseTitle: 'Vibe Coding 101',
      isPublic: payload['is_public'] == true,
    )
      ..['content'] = payload['content'] ?? ''
      ..['metadata_json'] = payload['metadata_json'] ?? '{}'
      ..['client_draft_id'] = payload['client_draft_id'];
    _notes = [note, ..._notes];
    return note;
  }

  @override
  Future<Map<String, dynamic>> createPlannerEvent(
          String token, Map<String, dynamic> payload) async =>
      payload;

  @override
  Future<void> deleteNote(String token, int noteId) async {
    final match = _notes.firstWhere((note) => note['id'] == noteId);
    _notes = _notes.where((note) => note['id'] != noteId).toList();
    _deletedNotes = [match, ..._deletedNotes];
  }

  @override
  Future<Map<String, dynamic>> emptyDeletedNotes(String token) async {
    _deletedNotes = [];
    return {'count': 0};
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async => {
        'token': 'token',
        'user': {
          'email': email,
          'username': 'demo',
          'is_staff': false,
          'is_superuser': false,
        }
      };

  @override
  Future<void> logout(String token) async {}

  @override
  Future<Map<String, dynamic>> register(String email, String password) async =>
      {'message': 'Verification email sent.'};

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async => {
        'token': 'token',
        'user': {
          'email': email,
          'username': 'demo',
          'is_staff': false,
          'is_superuser': false,
        }
      };

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      {'message': 'Password reset email sent.'};

  @override
  Future<Map<String, dynamic>> confirmPasswordReset(
          String email, String code, String password) async =>
      {'message': 'Password updated. You can now log in.'};

  @override
  Future<Map<String, dynamic>> getFrontPage({String? token}) async => {
        'default_course': _courses.first,
        'carousel_courses': _courses,
        'collections': _courses,
        'recent_notes': _notes,
        'recommended_notes': _notes,
        'heatmap': {
          'cells': List.generate(
            21,
            (index) => {
              'date': '2026-03-${(index + 1).toString().padLeft(2, '0')}',
              'kind': index < 10 ? 'past' : (index == 10 ? 'today' : 'future'),
              'past_value': index < 10 ? 200 : 0,
              'future_value': index > 10 ? 2 : 0,
              'is_today': index == 10,
            },
          ),
        },
      };

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId,
          {String? token}) async =>
      _notes
          .where((note) => (note['course'] as Map?)?['id'] == courseId)
          .toList();

  @override
  Future<List<Map<String, dynamic>>> getCourses({String? token}) async => _courses;

  @override
  Future<Map<String, dynamic>> createCourse(
      String token, Map<String, dynamic> payload) async {
    final created = FakeClient._sampleCourse(
      id: 100 + _courses.length,
      title: payload['title']?.toString() ?? 'Untitled course',
      isSubscribed: false,
    )
      ..['description'] = payload['description']?.toString() ?? ''
      ..['client_course_id'] = payload['client_course_id']
      ..['is_local_course'] = false
      ..['is_owned'] = true;
    _courses = [created, ..._courses];
    return created;
  }

  @override
  Future<Map<String, dynamic>> getCourseDetail(int courseId,
          {String? token}) async =>
      _courses.firstWhere((course) => course['id'] == courseId);

  @override
  Future<List<Map<String, dynamic>>> getDeletedNotes(String token) async =>
      _deletedNotes;

  @override
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token}) async =>
      _notes.firstWhere((note) => note['id'] == noteId, orElse: () {
        return _sampleNote(
          id: noteId,
          title: 'Project outcome',
          description: 'Repository layout and build order.',
          courseTitle: 'Vibe Coding 101',
          isPublic: true,
        );
      });

  @override
  Future<List<Map<String, dynamic>>> getNoteHistory(
          String token, int noteId) async =>
      [
        {
          'id': 1,
          'reason': 'quit',
          'date_created': '2026-03-21T12:00:00Z',
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token) async => [
        {
          'id': 22,
          'title': 'Essay draft',
          'event_date': '2026-03-22',
          'difficulty_weight': 3,
          'is_completed': false,
        }
      ];

  @override
  Future<Map<String, dynamic>> getSettings(String token) async => {
        'email': 'demo@example.com',
        'username': 'demo',
        'is_staff': false,
        'is_superuser': false,
        'motto': 'Ship the thing.',
        'social_link': 'https://example.com',
        'editor_mode': 'P',
        'theme_preset': 'teal',
        'theme_mode': 'S',
        'api_base_url': 'http://localhost:9060/api/v1',
        'app_settings': {
          'theme_preset': 'teal',
          'theme_mode': 'S',
          'api_base_url': 'http://localhost:9060/api/v1',
          'log_preferences': {},
        },
        'app_settings_updated_at': '2026-03-21T12:00:00Z',
        'image_url': '',
      };

  @override
  Future<Map<String, dynamic>> restoreTemplateCourses(String token) async =>
      {
        'message': 'Template courses restored.',
        'courses': _courses,
      };

  @override
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async {
    final rows = _notes
        .where((note) =>
            query.isEmpty ||
            note['title']
                .toString()
                .toLowerCase()
                .contains(query.toLowerCase()))
        .skip(offset)
        .take(limit)
        .toList();
    return {
      'results': rows,
      'total': _notes.length,
      'offset': offset,
      'limit': limit,
      'has_more': false,
    };
  }

  @override
  Future<Map<String, dynamic>> openCourse(String token, int courseId) async {
    _courses = _courses
        .map((course) => course['id'] == courseId
            ? {...course, 'last_opened_at': '2026-03-22T09:00:00Z'}
            : course)
        .toList();
    return _courses.firstWhere((course) => course['id'] == courseId);
  }

  @override
  Future<Map<String, dynamic>> restoreDeletedNote(String token, int noteId) async {
    final note = _deletedNotes.firstWhere((item) => item['id'] == noteId);
    _deletedNotes = _deletedNotes.where((item) => item['id'] != noteId).toList();
    _notes = [note, ..._notes];
    return note;
  }

  @override
  Future<Map<String, dynamic>> restoreNoteVersion(
          String token, int noteId, int versionId) async =>
      getNoteDetail(noteId, token: token);

  @override
  Future<Map<String, dynamic>> snapshotNote(String token, int noteId,
          {String reason = 'manual'}) async =>
      {
        'id': 1,
        'reason': reason,
      };

  @override
  Future<Map<String, dynamic>> startNoteSession(
          String token, Map<String, dynamic> payload) async =>
      {'id': 1, ...payload};

  @override
  Future<Map<String, dynamic>> subscribeCourse(String token, int courseId) async {
    _courses = _courses
        .map((course) => course['id'] == courseId
            ? {
                ...course,
                'is_subscribed': true,
                'last_opened_at': '2026-03-22T09:00:00Z',
              }
            : course)
        .toList();
    return _courses.firstWhere((course) => course['id'] == courseId);
  }

  @override
  Future<Map<String, dynamic>> unsubscribeCourse(
      String token, int courseId) async {
    _courses = _courses
        .map((course) => course['id'] == courseId
            ? {
                ...course,
                'is_subscribed': false,
                'last_opened_at': null,
              }
            : course)
        .toList();
    return _courses.firstWhere((course) => course['id'] == courseId);
  }

  @override
  Future<Map<String, dynamic>> updateNote(
      String token, int noteId, Map<String, dynamic> payload) async {
    final updated = {
      ...await getNoteDetail(noteId, token: token),
      ...payload,
      'id': noteId,
      'course': {
        'id': payload['course_id'] ?? 7,
        'title': 'Vibe Coding 101',
        'slug': 'vibe-coding-101',
      },
      'last_edit': '2026-03-21T12:10:00Z',
    };
    _notes = _notes.map((note) => note['id'] == noteId ? updated : note).toList();
    return updated;
  }

  @override
  Future<Map<String, dynamic>> updateNoteSession(
          String token, int sessionId, Map<String, dynamic> payload) async =>
      {'id': sessionId, ...payload};

  @override
  Future<Map<String, dynamic>> updatePlannerEvent(
          String token, int eventId, Map<String, dynamic> payload) async =>
      {'id': eventId, ...payload};

  @override
  Future<Map<String, dynamic>> updateSettings(
          String token, Map<String, dynamic> payload) async =>
      {
        'email': payload['email'] ?? 'demo@example.com',
        'username': payload['username'] ?? 'demo',
        'motto': payload['motto'],
        'social_link': payload['social_link'],
        'editor_mode': payload['editor_mode'] ?? 'P',
        'theme_preset': payload['theme_preset'] ?? 'teal',
        'theme_mode': payload['theme_mode'] ?? 'S',
        'api_base_url':
            payload['api_base_url'] ?? 'http://localhost:9060/api/v1',
        'app_settings': payload['app_settings'] ??
            {
              'theme_preset': payload['theme_preset'] ?? 'teal',
              'theme_mode': payload['theme_mode'] ?? 'S',
              'api_base_url':
                  payload['api_base_url'] ?? 'http://localhost:9060/api/v1',
              'log_preferences': {},
            },
        'app_settings_updated_at':
            payload['app_settings_updated_at'] ?? '2026-03-21T12:00:00Z',
        'image_url': '',
      };

  @override
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file) async =>
      {
        'email': 'demo@example.com',
        'username': 'demo',
        'image_url': '',
      };

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _isoDate(DateTime value) =>
      _dateOnly(value).toIso8601String().split('T').first;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxPumps = 80,
    Duration step = const Duration(milliseconds: 100),
    String description = 'condition',
  }) async {
    for (var index = 0; index < maxPumps; index++) {
      if (condition()) {
        return;
      }
      await tester.pump(step);
    }
    fail('Timed out waiting for $description.');
  }

  Future<void> pumpUntilVisible(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 80,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    await pumpUntil(
      tester,
      () {
        try {
          return finder.evaluate().isNotEmpty;
        } on StateError {
          return false;
        }
      },
      maxPumps: maxPumps,
      step: step,
      description: finder.description,
    );
  }

  Future<void> pumpAppReady(WidgetTester tester) async {
    await pumpUntilVisible(tester, find.text('Vibe Coding 101'));
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.text('Settings').first);
    await tester.pump();
    final loginLauncher = find.widgetWithText(OutlinedButton, 'Login');
    await pumpUntilVisible(tester, loginLauncher);
    await tester.tap(loginLauncher.first);
    await pumpUntilVisible(tester, find.byType(AlertDialog));

    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), 'demo@example.com');
    await tester.enterText(dialogFields.at(1), 'password123');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Login'),
      ),
    );
    await pumpUntilVisible(tester, find.text('Edit avatar'));
  }

  String calendarRangeLabel(WidgetTester tester) {
    final widget =
        tester.widget<Text>(find.byKey(const Key('activity-calendar-range-label')));
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }

  DateTime parseIsoDate(String value) => DateTime.parse(value);

  testWidgets('renders carousel and navigation tabs', (tester) async {
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await pumpAppReady(tester);

    expect(find.text('Front Page'), findsOneWidget);
    expect(find.text('Vibe Coding 101'), findsWidgets);
    expect(find.text('Learner'), findsOneWidget);
    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up),
    );
    await tester.scrollUntilVisible(
      find.text('Recent public notes'),
      240,
      scrollable: verticalScrollable.first,
    );
    await tester.pump();
    expect(find.text('Recent public notes'), findsOneWidget);
  });

  testWidgets('opens course note in reader dialog', (tester) async {
    final client = FakeClient();
    await tester.pumpWidget(NotechondriaApp(client: client));
    await pumpAppReady(tester);

    await tester.tap(find.text('Course').first);
    await tester.pump();
    await pumpUntilVisible(tester, find.byKey(const Key('course-scope-selector')));
    await tester.tap(find.byKey(const Key('course-scope-selector')));
    final publicCoursesOption = find.text('Public courses');
    await pumpUntilVisible(tester, publicCoursesOption);
    await tester.tap(publicCoursesOption.last);
    await tester.pump();
    await pumpUntilVisible(tester, find.byKey(const Key('course-public-search')));
    await tester.tap(find.text('Vibe Coding 101').last);
    await tester.pump();
    await pumpUntilVisible(tester, find.text('Course discussion'));
    expect(tester.takeException(), isNull);

    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up),
    );
    await tester.scrollUntilVisible(
      find.text('Project outcome'),
      240,
      scrollable: verticalScrollable.first,
    );
    await tester.pump();
    await tester.tap(find.text('Project outcome').first);
    await pumpUntilVisible(
      tester,
      find.textContaining('Repository layout and build order.'),
    );

    expect(find.text('Project outcome'), findsWidgets);
    expect(find.textContaining('Repository layout and build order.'), findsWidgets);
  });

  testWidgets('shows local draft creation affordance while signed out',
      (tester) async {
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await pumpAppReady(tester);

    await tester.tap(find.text('Learner').first);
    await pumpUntilVisible(tester, find.text('Local drafts'));

    expect(find.text('Local drafts'), findsOneWidget);
    expect(find.byKey(const Key('learner-add-note-fab')), findsOneWidget);
    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('learner-add-note-fab')),
    );
    expect(fab.shape, isA<CircleBorder>());
  });

  testWidgets('wide activity calendar supports drag and overlay navigation',
      (tester) async {
    final client = FakeClient();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(NotechondriaApp(client: client));
    await pumpAppReady(tester);
    await signIn(tester);

    await tester.tap(find.text('Activity').first);
    await tester.pump();
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('activity-calendar-range-label')),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('activity-calendar-drag-surface')),
    );

    expect(
      find.byKey(const Key('activity-calendar-previous-week')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('activity-calendar-next-week')),
      findsOneWidget,
    );
    expect(find.text('Previous week'), findsNothing);
    expect(find.text('Next week'), findsNothing);

    final initialRequestCount = client.requestedActivityWeekStarts.length;
    final initialStart = parseIsoDate(client.requestedActivityWeekStarts.last);
    final initialLabel = calendarRangeLabel(tester);

    await tester.drag(
      find.byKey(const Key('activity-calendar-drag-surface')),
      const Offset(-320, 0),
    );
    await tester.pump();
    await pumpUntil(
      tester,
      () => client.requestedActivityWeekStarts.length > initialRequestCount,
      description: 'activity week reload after drag',
    );
    await pumpUntil(
      tester,
      () => calendarRangeLabel(tester) != initialLabel,
      description: 'calendar range label update after drag',
    );

    final draggedStart = parseIsoDate(client.requestedActivityWeekStarts.last);
    expect(draggedStart, initialStart.add(const Duration(days: 1)));
    await tester.pump(const Duration(milliseconds: 260));

    final postDragRequestCount = client.requestedActivityWeekStarts.length;
    await tester.tap(find.byKey(const Key('activity-calendar-next-week')));
    await tester.pump();
    await pumpUntil(
      tester,
      () => client.requestedActivityWeekStarts.length > postDragRequestCount,
      description: 'activity week reload after next-week tap',
    );

    final weekJumpedStart =
        parseIsoDate(client.requestedActivityWeekStarts.last);
    expect(weekJumpedStart, draggedStart.add(const Duration(days: 7)));
    expect(tester.takeException(), isNull);
  });
}
