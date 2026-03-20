import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('renders navigation tabs and front page content', (tester) async {
    await tester.pumpWidget(const NotechondriaApp());

    expect(find.text('Front Page'), findsOneWidget);
    expect(find.text('Recommended First Course'), findsOneWidget);
    expect(find.text('Learner'), findsOneWidget);
    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('changes course selection and updates learner and activity views', (tester) async {
    await tester.pumpWidget(const NotechondriaApp());

    await tester.tap(find.text('Course'));
    await tester.pumpAndSettle();

    expect(find.text('Course Selection'), findsOneWidget);

    await tester.tap(find.text('Python Foundations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data Structures Interview Plan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Learner'));
    await tester.pumpAndSettle();
    expect(find.text('Current focus: Data Structures Interview Plan'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Recent activity for Data Structures Interview Plan'), findsOneWidget);
  });
}
