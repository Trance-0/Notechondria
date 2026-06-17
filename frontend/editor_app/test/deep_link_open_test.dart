import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:editor_app/main.dart';

/// Regression guard for the share-link cold-open bug: a URL like
/// `.../editor/#/notes/<uuid>` landed on the editor home instead of
/// opening the note. Root cause: Flutter's default hash URL strategy
/// rewrites the unmatched initial route `#/notes/<uuid>` back to `#/`
/// during the first frame, so the fragment was gone by the time
/// `_bootstrapApp` read `Uri.base.fragment` after the async boot.
///
/// The fix snapshots the fragment in `main()` (into `bootInitialFragment`)
/// before `runApp`. The flutter_test environment has an EMPTY
/// `Uri.base.fragment` — exactly the clobbered production state — so this
/// test only passes if the boot-snapshot path is the one driving the
/// deep link.
class _DeepLinkFakeClient implements NotechondriaClient {
  _DeepLinkFakeClient(this.uuid);

  final String uuid;
  int getNoteByUuidCalls = 0;

  @override
  Future<Map<String, dynamic>> getNoteByUuid(String requested,
      {String? token}) async {
    getNoteByUuidCalls++;
    return <String, dynamic>{
      'id': 42,
      'uuid': requested,
      'title': 'Shared Note Title',
      'content': 'Hello from the shared note.',
      'description': '',
      'editor_mode': 'P',
      'is_public': true,
      'can_edit': false,
      'author': <String, dynamic>{'username': 'someone'},
      'course': <String, dynamic>{},
      'last_edit': '',
      'cover_image_url': '',
      'metadata': '{}',
    };
  }

  // The signed-out cold boot fires an unawaited Casdoor probe; keep it
  // quiet so it doesn't hit noSuchMethod.
  @override
  Future<Map<String, dynamic>> getCasdoorConfig() async =>
      <String, dynamic>{'configured': false};

  // Any other client call during the offline cold boot is unexpected —
  // fail loudly so the test surfaces it rather than hanging.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'Unexpected client call in deep-link test: '
      '${invocation.memberName}',
    );
  }
}

void main() {
  testWidgets('boot fragment #/notes/<uuid> opens the note viewer',
      (tester) async {
    const uuid = 'a1e2ea37-a1a8-4f64-81b7-6252c84d033e';
    // Offline so the cold boot stays local and fast; the deep-link open
    // path runs regardless of offline mode.
    SharedPreferences.setMockInitialValues({
      'notechondria.editor.local_settings':
          '{"offline_mode":true,"locale":"en"}',
    });
    // Simulate the pristine launch URL captured by main().
    bootInitialFragment = '/notes/$uuid';
    addTearDown(() => bootInitialFragment = '');

    final client = _DeepLinkFakeClient(uuid);
    await tester.pumpWidget(NotechondriaApp(
      client: client,
      initialIndex: 1,
      title: 'Notechondria Editor',
      visibleIndices: const <int>[1, 4],
    ));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(client.getNoteByUuidCalls, greaterThan(0),
        reason: 'the deep link should fetch the note by uuid');
    expect(find.text('Shared Note Title'), findsWidgets,
        reason: 'the note viewer dialog should be open on the shared note');
  });
}
