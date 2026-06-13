import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  const steps = [
    TourStep(icon: Icons.edit_note, title: 'Step one', body: 'First body.'),
    TourStep(icon: Icons.folder, title: 'Step two', body: 'Second body.'),
    TourStep(icon: Icons.tune, title: 'Step three', body: 'Third body.'),
  ];

  Widget host(VoidCallback onOpen) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOnboardingTour(
                context,
                appTitle: 'Demo',
                steps: steps,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('opens on the first step and advances with Next',
      (tester) async {
    await tester.pumpWidget(host(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Step one'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step two'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Last step: Next becomes Done, Skip becomes Close.
    expect(find.text('Step three'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('Done closes the tour', (tester) async {
    await tester.pumpWidget(host(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Step three'), findsNothing);
  });

  testWidgets('Skip closes the tour from the first step', (tester) async {
    await tester.pumpWidget(host(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Step one'), findsNothing);
  });

  testWidgets('empty steps shows nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOnboardingTour(
                context,
                appTitle: 'Demo',
                steps: const [],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsNothing);
  });
}
