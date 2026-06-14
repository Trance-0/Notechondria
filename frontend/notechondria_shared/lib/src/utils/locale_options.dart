import 'package:flutter/widgets.dart';

/// One selectable entry in the Language setting. [value] is the stable
/// string persisted in `app_settings['locale']`; [label] is shown in
/// the dropdown. Language names use their autonym (e.g. "简体中文") so a
/// user can always recognize their own language regardless of the
/// current UI language.
class LocaleOption {
  const LocaleOption(this.value, this.label);

  final String value;
  final String label;
}

/// Supported Language-setting choices. `system` follows the device
/// locale. Keep the locale codes in lockstep with the generated
/// `AppLocalizations.supportedLocales` and the ARB files in
/// `notechondria_shared/lib/l10n/`.
const List<LocaleOption> kLocaleOptions = [
  LocaleOption('system', 'System default'),
  LocaleOption('en', 'English'),
  LocaleOption('zh', '简体中文'),
];

/// Map a persisted `app_settings['locale']` value to a [Locale], or
/// null to follow the device locale (the `MaterialApp` then clamps the
/// device locale to its `supportedLocales`, falling back to the first
/// supported locale for unsupported device languages).
Locale? resolveLocale(String? stored) {
  switch (stored) {
    case 'en':
      return const Locale('en');
    case 'zh':
      return const Locale('zh');
    default:
      return null; // 'system' or unknown => follow device
  }
}
