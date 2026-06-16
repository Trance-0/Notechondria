import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:editor_app/main.dart';

/// Reproduces the user report: "the setting is saved but no change in
/// UI language." Boots the editor with `locale: zh` already persisted
/// and asserts the live MaterialApp resolves the Chinese locale (the
/// startup path: load_local_state -> onLocaleChanged -> _locale ->
/// MaterialApp.locale).
void main() {
  testWidgets('persisted locale=zh boots the app in Chinese', (tester) async {
    SharedPreferences.setMockInitialValues({
      'notechondria.editor.local_settings': jsonEncode({
        'offline_mode': true,
        'locale': 'zh',
      }),
    });

    await tester.pumpWidget(const NotechondriaApp(
      initialIndex: 1,
      title: 'Notechondria Editor',
      visibleIndices: <int>[1, 4],
    ));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final ctx = tester.element(find.byType(Navigator).first);
    expect(Localizations.localeOf(ctx), const Locale('zh'),
        reason: 'MaterialApp should resolve the persisted zh locale');
    expect(AppLocalizations.of(ctx).settingsEditorTitle, '编辑器设置');

    // The "All Notes" navigation label renders in Chinese — proving the
    // localized widgets (not just the delegate) actually switched. It is
    // the compact AppBar title or the wide sidebar item depending on the
    // test surface, so accept one or more matches.
    expect(find.text('全部笔记'), findsWidgets,
        reason: 'navigation should render Chinese, not "All Notes"');
    expect(find.text('All Notes'), findsNothing);
  });
}
