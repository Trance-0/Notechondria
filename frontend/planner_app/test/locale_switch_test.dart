import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:planner_app/main.dart';

/// Verifies the planner Language setting end-to-end: with `locale: zh`
/// persisted, the live MaterialApp resolves the Chinese locale (the
/// startup path: load_local_state -> onLocaleChanged -> _locale ->
/// MaterialApp.locale). Mirrors the editor's locale_switch_test.
void main() {
  testWidgets('persisted locale=zh boots the planner in Chinese',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'notechondria.planner.local_settings': jsonEncode({
        'offline_mode': true,
        'locale': 'zh',
      }),
    });

    await tester.pumpWidget(const NotechondriaApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final ctx = tester.element(find.byType(Navigator).first);
    expect(Localizations.localeOf(ctx), const Locale('zh'),
        reason: 'MaterialApp should resolve the persisted zh locale');
    expect(AppLocalizations.of(ctx).prefsLanguage, '语言');
  });
}
