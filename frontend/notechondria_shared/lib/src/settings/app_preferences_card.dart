import 'package:flutter/material.dart';

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
    this.apiBaseHintText,
    this.apiBaseHelperText,
    this.extrasBuilder,
  });

  final String editorMode;
  final String themePreset;
  final String themeMode;
  final TextEditingController apiBaseController;
  final bool isAuthenticated;

  final ValueChanged<String> onEditorModeChanged;
  final ValueChanged<String> onThemePresetChanged;
  final ValueChanged<String> onThemeModeChanged;

  final String? apiBaseHintText;

  /// Helper text shown under the API base field when the user is not
  /// signed in. When signed in, the field is locked and displays a
  /// fixed "Locked while signed in" message regardless of this value.
  final String? apiBaseHelperText;

  /// App-specific rows rendered between the theme row and the API base
  /// URL field. Planner uses this for deadline-weight TextFields.
  final WidgetBuilder? extrasBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: editorMode,
          items: kEditorModes
              .map((entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) onEditorModeChanged(value);
          },
          decoration: const InputDecoration(
            labelText: 'Default editor',
            border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Theme preset',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: themeMode,
                items: const [
                  DropdownMenuItem(value: 'S', child: Text('System')),
                  DropdownMenuItem(value: 'L', child: Text('Light')),
                  DropdownMenuItem(value: 'D', child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value != null) onThemeModeChanged(value);
                },
                decoration: const InputDecoration(
                  labelText: 'Theme mode',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        if (extrasBuilder != null) ...[
          const SizedBox(height: 12),
          extrasBuilder!(context),
        ],
        const SizedBox(height: 12),
        Tooltip(
          message: isAuthenticated
              ? 'Log out before changing the API base URL. A logged-in '
                  'token is only valid against its issuing backend.'
              : '',
          child: TextField(
            controller: apiBaseController,
            enabled: !isAuthenticated,
            decoration: InputDecoration(
              labelText: 'API base URL',
              hintText: apiBaseHintText,
              helperText: isAuthenticated
                  ? 'Locked while signed in. Log out to change.'
                  : apiBaseHelperText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
