import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

class FakeClient implements NotechondriaClient {
  List<Map<String, dynamic>> _notes = [
    {
      'id': 11,
      'title': 'Project outcome',
      'description': 'Repository layout and build order.',
      'excerpt': 'Repository layout and build order.',
      'preview_lines': ['Repository layout and build order.'],
      'editor_mode': 'P',
      'is_public': true,
      'last_edit': '2026-03-21T12:00:00Z',
      'date_created': '2026-03-20T12:00:00Z',
      'course_id': 7,
    }
  ];

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async => [
        {
          'id': 1,
          'title': 'Project outcome',
          'excerpt': 'Repository layout and build order.',
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId) async => [
        {
          'id': 11,
          'title': 'Project outcome',
          'excerpt': 'Repository layout and build order.',
        }
      ];

  @override
  Future<List<Map<String, dynamic>>> getCourses() async => [
        {
          'id': 7,
          'title': 'Vibe Coding 101',
        }
      ];

  @override
  Future<Map<String, dynamic>> getFrontPage({String? token}) async => {
        'default_course': {
          'id': 7,
          'title': 'Vibe Coding 101',
          'description': 'Seeded notes from CODEX.md',
          'cover_image_url': '',
        },
        'collections': [
          {
            'id': 7,
            'title': 'Vibe Coding 101',
            'description': 'Seeded notes from CODEX.md',
          }
        ],
        'recent_notes': [
          {
            'id': 11,
            'title': 'Project outcome',
            'excerpt': 'Repository layout and build order.',
            'is_public': true,
          }
        ],
        'recommended_notes': [
          {
            'id': 11,
            'title': 'Project outcome',
            'excerpt': 'Repository layout and build order.',
            'is_public': true,
          }
        ],
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
  Future<Map<String, dynamic>> getNoteDetail(int noteId) async => {
        'id': noteId,
        'title': 'Project outcome',
        'description': 'Repository layout and build order.',
        'content': '# Project outcome\n\nRepository layout and build order.',
        'metadata_json': '{}',
        'blocks': [
          {
            'block_type': 'T',
            'text': 'Project outcome',
          },
          {
            'block_type': 'N',
            'text': 'Repository layout and build order.',
          }
        ],
      };

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
      };

  @override
  Future<Map<String, dynamic>> login(String email, String password) async => {
        'token': 'token',
        'user': {'email': email}
      };

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      {'message': 'Password reset email sent.'};

  @override
  Future<Map<String, dynamic>> confirmPasswordReset(
          String email, String code, String password) async =>
      {'message': 'Password updated. You can now log in.'};

  @override
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token) async => [];

  @override
  Future<Map<String, dynamic>> listNotes(
      {String? token,
      String query = '',
      int offset = 0,
      int limit = 20}) async {
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
  Future<Map<String, dynamic>> createNote(
      String token, Map<String, dynamic> payload) async {
    final note = {
      'id': 99,
      'title': payload['title'],
      'description': payload['description'] ?? '',
      'content': payload['content'] ?? '',
      'metadata_json': payload['metadata_json'] ?? '{}',
      'preview_lines': ['New note'],
      'editor_mode': payload['editor_mode'] ?? 'P',
      'last_edit': '2026-03-21T12:00:00Z',
      'date_created': '2026-03-21T12:00:00Z',
      'course_id': payload['course_id'],
      'blocks': [
        {'block_type': 'T', 'text': payload['title']},
        {'block_type': 'N', 'text': payload['content'] ?? ''},
      ],
    };
    _notes = [note, ..._notes];
    return note;
  }

  @override
  Future<Map<String, dynamic>> updateNote(
          String token, int noteId, Map<String, dynamic> payload) async =>
      {
        'id': noteId,
        'title': payload['title'] ?? 'Project outcome',
        'description': payload['description'] ?? '',
        'content': payload['content'] ?? '',
        'metadata_json': payload['metadata_json'] ?? '{}',
        'preview_lines': ['Updated note'],
        'editor_mode': payload['editor_mode'] ?? 'P',
        'last_edit': '2026-03-21T12:10:00Z',
        'date_created': '2026-03-21T12:00:00Z',
        'course_id': payload['course_id'],
        'blocks': [
          {'block_type': 'T', 'text': payload['title'] ?? 'Project outcome'},
          {'block_type': 'N', 'text': payload['content'] ?? ''},
        ],
      };

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
  Future<Map<String, dynamic>> snapshotNote(String token, int noteId,
          {String reason = 'manual'}) async =>
      {
        'id': 1,
        'reason': reason,
      };

  @override
  Future<Map<String, dynamic>> restoreNoteVersion(
          String token, int noteId, int versionId) async =>
      await getNoteDetail(noteId);

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
        ]
      };

  @override
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token) async => [];

  @override
  Future<Map<String, dynamic>> startNoteSession(
          String token, Map<String, dynamic> payload) async =>
      {'id': 1, ...payload};

  @override
  Future<Map<String, dynamic>> updateNoteSession(
          String token, int sessionId, Map<String, dynamic> payload) async =>
      {'id': sessionId, ...payload};

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
  Future<void> logout(String token) async {}

  @override
  Future<Map<String, dynamic>> register(String email, String password) async =>
      {'message': 'Verification email sent.'};

  @override
  Future<Map<String, dynamic>> createPlannerEvent(
          String token, Map<String, dynamic> payload) async =>
      payload;

  @override
  Future<Map<String, dynamic>> updatePlannerEvent(
          String token, int eventId, Map<String, dynamic> payload) async =>
      payload;

  @override
  Future<Map<String, dynamic>> updateSettings(
          String token, Map<String, dynamic> payload) async =>
      {
        'email': 'demo@example.com',
        'username': payload['username'] ?? 'demo',
        'motto': payload['motto'],
        'social_link': payload['social_link'],
        'editor_mode': payload['editor_mode'] ?? 'P',
        'theme_preset': payload['theme_preset'] ?? 'teal',
        'theme_mode': payload['theme_mode'] ?? 'S',
        'api_base_url':
            payload['api_base_url'] ?? 'http://localhost:9080/api/v1',
      };

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async => {
        'token': 'token',
        'user': {'email': email}
      };
}

void main() {
  testWidgets('renders seeded front page and navigation tabs', (tester) async {
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await tester.pumpAndSettle();

    expect(find.text('Front Page'), findsOneWidget);
    expect(find.text('Vibe Coding 101'), findsWidgets);
    expect(find.text('Progress + plan heatmap'), findsOneWidget);
    expect(find.text('Recommended public notes'), findsOneWidget);
    expect(find.text('Learner'), findsOneWidget);
    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('opens course note in reader dialog', (tester) async {
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Course'));
    await tester.pumpAndSettle();
    expect(find.text('Collections'), findsOneWidget);

    await tester.tap(find.text('Project outcome').first);
    await tester.pumpAndSettle();

    expect(find.text('Project outcome'), findsWidgets);
    expect(find.text('Repository layout and build order.'), findsOneWidget);
  });

  testWidgets('opens recommended front-page note in reader dialog',
      (tester) async {
    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Project outcome').first);
    await tester.pumpAndSettle();

    expect(find.text('Project outcome'), findsWidgets);
    expect(find.text('Repository layout and build order.'), findsOneWidget);
  });

  testWidgets('uses sidebar navigation on wide layouts', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(NotechondriaApp(client: FakeClient()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Wide layout'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });
}
