import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/locale_options.dart';

/// Shared theme-preset catalog. Keys are persisted; values are display
/// labels surfaced in the preset dropdown.
const Map<String, String> kThemePresetEntries = {
  'teal': 'Teal',
  'amber': 'Amber',
  'blue': 'Blue',
  'rose': 'Rose',
  'mint': 'Mint',
  'slate': 'Slate',
  'emerald': 'Emerald',
  'orange': 'Orange',
  'indigo': 'Indigo',
  'red': 'Red',
  'cyan': 'Cyan',
  'lime': 'Lime',
};

/// Editor-mode catalog. 'B' (block editor) was removed in 0.1.x but legacy
/// settings may still hold it; settings code is expected to remap 'B' -> 'G'
/// before binding the value here.
const List<MapEntry<String, String>> kEditorModes = [
  MapEntry('P', 'Plain text editor'),
  MapEntry('G', 'Live markdown editor'),
];

/// Renders the four preference rows shared by every Notechondria app:
/// default editor, theme preset, theme mode, and API base URL. Every
/// caller wraps this widget in their own enclosing Card / section header
/// so layout chrome stays per-app.
///
/// Apps that need extra app-specific rows pass an [extrasBuilder] that
/// returns a widget rendered between the theme row and the API base URL
/// field (used by planner for deadline-weight fields).
class AppPreferencesCard extends StatelessWidget {
  const AppPreferencesCard({
    super.key,
    required this.editorMode,
    required this.themePreset,
    required this.themeMode,
    required this.apiBaseController,
    required this.isAuthenticated,
    required this.onEditorModeChanged,
    required this.onThemePresetChanged,
    required this.onThemeModeChanged,
    this.offlineMode,
    this.onOfflineModeChanged,
    this.apiBaseHintText,
    this.apiBaseHelperText,
    this.extrasBuilder,
    this.onReplayTour,
    this.currentLocale,
    this.onLocaleChanged,
  });

  final String editorMode;
  final String themePreset;
  final String themeMode;
  final TextEditingController apiBaseController;
  final bool isAuthenticated;

  final ValueChanged<String> onEditorModeChanged;
  final ValueChanged<String> onThemePresetChanged;
  final ValueChanged<String> onThemeModeChanged;

  /// When non-null, renders an offline-mode toggle row. The flag
  /// controls whether the host app attempts remote fetches during
  /// bootstrap; callers are expected to persist the value and
  /// gate their own `_loadInitialData` on it.
  final bool? offlineMode;
  final ValueChanged<bool>? onOfflineModeChanged;

  final String? apiBaseHintText;

  /// Helper text shown under the API base field when the user is not
  /// signed in. When signed in, the field is locked and displays a
  /// fixed "Locked while signed in" message regardless of this value.
  final String? apiBaseHelperText;

  /// App-specific rows rendered between the theme row and the API base
  /// URL field. Planner uses this for deadline-weight TextFields.
  final WidgetBuilder? extrasBuilder;

  /// When non-null, renders a "View tutorial" row that replays the
  /// first-run onboarding tour. Null hides the row.
  final VoidCallback? onReplayTour;

  /// Persisted Language value ('system' | 'en' | 'zh'). When both this
  /// and [onLocaleChanged] are non-null, a Language dropdown is rendered
  /// after the theme row. Apps that don't expose an in-app Language
  /// picker (and just follow the device locale) leave both null.
  final String? currentLocale;
  final ValueChanged<String>? onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: editorMode,
          items: kEditorModes
              .map((entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.key == 'P'
                        ? l10n.prefsEditorPlain
                        : l10n.prefsEditorMarkdown),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) onEditorModeChanged(value);
          },
          decoration: InputDecoration(
            labelText: l10n.prefsDefaultEditor,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: themePreset,
                items: kThemePresetEntries.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onThemePresetChanged(value);
                },
                decoration: InputDecoration(
                  labelText: l10n.prefsThemePreset,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: themeMode,
                items: [
                  DropdownMenuItem(
                      value: 'S', child: Text(l10n.prefsThemeModeSystem)),
                  DropdownMenuItem(
                      value: 'L', child: Text(l10n.prefsThemeModeLight)),
                  DropdownMenuItem(
                      value: 'D', child: Text(l10n.prefsThemeModeDark)),
                ],
                onChanged: (value) {
                  if (value != null) onThemeModeChanged(value);
                },
                decoration: InputDecoration(
                  labelText: l10n.prefsThemeMode,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (currentLocale != null && onLocaleChanged != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: kLocaleOptions.any((o) => o.value == currentLocale)
                ? currentLocale
                : 'system',
            items: [
              for (final opt in kLocaleOptions)
                DropdownMenuItem<String>(
                  value: opt.value,
                  child: Text(opt.value == 'system'
                      ? l10n.settingsLanguageSystem
                      : opt.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) onLocaleChanged!(value);
            },
            decoration: InputDecoration(
              labelText: l10n.prefsLanguage,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (offlineMode != null && onOfflineModeChanged != null) ...[
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: offlineMode!,
            onChanged: onOfflineModeChanged,
            title: Text(l10n.prefsOfflineMode),
            subtitle: Text(l10n.prefsOfflineModeSubtitle),
            contentPadding: EdgeInsets.zero,
          ),
        ],
        if (extrasBuilder != null) ...[
          const SizedBox(height: 12),
          extrasBuilder!(context),
        ],
        if (onReplayTour != null) ...[
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.school_outlined),
            title: Text(l10n.prefsViewTutorial),
            subtitle: Text(l10n.prefsViewTutorialSubtitle),
            onTap: onReplayTour,
          ),
        ],
        const SizedBox(height: 12),
        Tooltip(
          message: isAuthenticated ? l10n.prefsApiBaseLockTooltip : '',
          child: TextField(
            controller: apiBaseController,
            enabled: !isAuthenticated,
            decoration: InputDecoration(
              labelText: l10n.prefsApiBaseUrl,
              // Default hint shows a full example so users know both
              // the scheme and the required `/api/v1` suffix. Callers
              // can override via `apiBaseHintText` if they ship a
              // host-specific default.
              hintText:
                  apiBaseHintText ?? 'https://your-backend.example.com/api/v1',
              helperText: isAuthenticated
                  ? l10n.prefsApiBaseLocked
                  : (apiBaseHelperText ?? l10n.prefsApiBaseHelper),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
