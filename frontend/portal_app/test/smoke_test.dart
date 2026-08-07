import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portal_app/main.dart' as app;
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  testWidgets('portal app boots with front page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Front page'), findsWidgets);
  });

  group('note-conflict line diff (#31)', () {
    test('identical text yields only equal rows', () {
      final rows = diffLines('a\nb\nc', 'a\nb\nc');
      expect(rows.every((r) => r.kind == DiffLineKind.equal), isTrue);
      expect(rows.map((r) => r.left).toList(), ['a', 'b', 'c']);
    });
    test('a replaced line is a changed row (old left, new right)', () {
      final rows = diffLines('a\nB\nc', 'a\nX\nc');
      final changed = rows.where((r) => r.kind == DiffLineKind.changed).toList();
      expect(changed.length, 1);
      expect(changed.single.left, 'B');
      expect(changed.single.right, 'X');
      // The unchanged lines survive as equal rows.
      expect(rows.where((r) => r.kind == DiffLineKind.equal).length, 2);
    });
    test('remote-only lines are added; local-only lines are removed', () {
      final added = diffLines('a\nc', 'a\nb\nc');
      expect(added.where((r) => r.kind == DiffLineKind.added).single.right, 'b');
      final removed = diffLines('a\nb\nc', 'a\nc');
      expect(
          removed.where((r) => r.kind == DiffLineKind.removed).single.left, 'b');
    });
    test('CRLF vs LF alone is not a difference', () {
      final rows = diffLines('a\r\nb', 'a\nb');
      expect(rows.every((r) => r.kind == DiffLineKind.equal), isTrue);
    });
    test('empty local vs non-empty remote is all added', () {
      final rows = diffLines('', 'x\ny');
      expect(rows.map((r) => r.kind).toSet(), {DiffLineKind.added});
      expect(rows.map((r) => r.right).toList(), ['x', 'y']);
    });
  });

  group('cross-user offline-cache ownership (#13)', () {
    test('unrecorded owner is claimed by the current user', () {
      final d = resolveLocalDataOwner(recordedOwner: null, currentUser: 'alice');
      expect(d.status, LocalDataOwnership.claimed);
      expect(d.owner, 'alice');
      expect(d.isForeign, isFalse);
    });
    test('empty recorded owner is claimed', () {
      final d = resolveLocalDataOwner(recordedOwner: '', currentUser: 'alice');
      expect(d.status, LocalDataOwnership.claimed);
      expect(d.owner, 'alice');
    });
    test('same user (case/space-insensitive) is sameUser', () {
      final d =
          resolveLocalDataOwner(recordedOwner: ' Alice ', currentUser: 'alice');
      expect(d.status, LocalDataOwnership.sameUser);
      expect(d.isForeign, isFalse);
    });
    test('different user is flagged foreign with the prior owner', () {
      final d =
          resolveLocalDataOwner(recordedOwner: 'alice', currentUser: 'bob');
      expect(d.status, LocalDataOwnership.foreignUser);
      expect(d.isForeign, isTrue);
      expect(d.priorOwner, 'alice');
      // The owner stamp is NOT reassigned to bob — that would let alice's
      // cache sync as bob's.
      expect(d.owner, 'alice');
    });
    test('empty current user is a no-op (nothing to decide)', () {
      final d = resolveLocalDataOwner(recordedOwner: 'alice', currentUser: '');
      expect(d.status, LocalDataOwnership.sameUser);
    });
  });

}
