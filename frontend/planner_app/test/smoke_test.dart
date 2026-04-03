import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/main.dart' as app;

void main() {
  testWidgets('planner app boots', (tester) async {
    app.main();
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
