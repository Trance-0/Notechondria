import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements NotechondriaClient {
  FakeClient();

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
          {String? startDate}) async =>
      {
        'days': [
          {
            'date': '2026-03-21',
            'events': [
              {
                'title': 'Study block',
                'kind': 'calendar',
                'starts_at': '2026-03-21T14:00:00Z',
                'ends_at': '2026-03-21T15:00:00Z',
              }
            ]
          }
        ],
        'deadlines': [
          {
            'id': 22,
            'title': 'Essay draft',
            'description': 'Finish the argument outline.',
            'event_date': '2026-03-22',
            'starts_at': '2026-03-22T18:00:00Z',
            'ends_at': '2026-03-22T19:00:00Z',
            'difficulty_weight': 3,
            'is_completed': false,
            'urgency_score': 1.75,
          }
        ],
      };

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
        'user': {'email': email, 'username': 'demo'}
      };

  @override
  Future<void> logout(String token) async {}

  @override
  Future<Map<String, dynamic>> register(String email, String password) async =>
      {'message': 'Verification email sent.'};

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async => {
        'token': 'token',
        'user': {'email': email, 'username': 'demo'}
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
        'motto': 'Ship the thing.',
        'social_link': 'https://example.com',
        'editor_mode': 'P',
        'theme_preset': 'teal',
        'theme_mode': 'S',
        'api_base_url': 'http://localhost:9080/api/v1',
        'app_settings': {
          'theme_preset': 'teal',
          'theme_mode': 'S',
          'api_base_url': 'http://localhost:9080/api/v1',
          'log_preferences': {},
        },
        'app_settings_updated_at': '2026-03-21T12:00:00Z',
        'image_url': '',
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
            payload['api_base_url'] ?? 'http://localhost:9080/api/v1',
        'app_settings': payload['app_settings'] ??
            {
              'theme_preset': payload['theme_preset'] ?? 'teal',
              'theme_mode': payload['theme_mode'] ?? 'S',
              'api_base_url':
                  payload['api_base_url'] ?? 'http://localhost:9080/api/v1',
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
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpUntilVisible(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 80,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var index = 0; index < maxPumps; index++) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    fail('Timed out waiting for ${finder.description}.');
  }

  Future<void> pumpAppReady(WidgetTester tester) async {
    await pumpUntilVisible(tester, find.text('Vibe Coding 101'));
  }

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
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await pumpAppReady(tester);

    await tester.tap(find.text('Course'));
    await pumpUntilVisible(tester, find.text('Course previews'));
    expect(find.text('Course previews'), findsOneWidget);

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

    await tester.tap(find.text('Learner'));
    await pumpUntilVisible(tester, find.text('Local drafts'));

    expect(find.text('Local drafts'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
