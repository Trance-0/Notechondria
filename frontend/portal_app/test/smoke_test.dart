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
