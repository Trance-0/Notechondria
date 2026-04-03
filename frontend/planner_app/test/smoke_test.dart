import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planner_app/main.dart' as app;

void main() {
  testWidgets('planner app boots with starter offline content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Starter planning course'), findsWidgets);
  });
}
