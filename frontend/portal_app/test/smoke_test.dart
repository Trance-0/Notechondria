import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portal_app/main.dart' as app;

void main() {
  testWidgets('portal app boots with front page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Front page'), findsWidgets);
  });
}
