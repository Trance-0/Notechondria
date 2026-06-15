// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'English';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsEditorTitle => 'Editor settings';

  @override
  String get settingsEditorSubtitle =>
      'Default editor mode, theme preset, theme mode.';

  @override
  String get settingsViewTutorial => 'View tutorial';

  @override
  String get settingsViewTutorialSubtitle => 'Replay the quick intro tour.';

  @override
  String get settingsBackendTitle => 'Backend settings';

  @override
  String get settingsLocalDataTitle => 'Local data';

  @override
  String get settingsLocalDataSubtitle =>
      'Download or restore the local archive, reset the starter categories.';

  @override
  String get settingsRecycleBinTitle => 'Recycle bin';

  @override
  String get settingsDeveloperTitle => 'Developer';

  @override
  String get settingsDeveloperSubtitle =>
      'Admin-only actions: restore the remote three-course template catalog.';

  @override
  String get settingsPersonalInfoTitle => 'Personal information';

  @override
  String get settingsSecurityTitle => 'Sign in & security';

  @override
  String get settingsApiTitle => 'API settings';

  @override
  String get settingsImmediateSaveCaption =>
      'Each change is saved and persisted immediately — no Save button needed in this menu.';

  @override
  String get settingsDefaultEditorMode => 'Default editor mode';

  @override
  String get settingsThemePreset => 'Theme preset';

  @override
  String get settingsThemeMode => 'Theme mode';

  @override
  String get debugLogTitle => 'Debug log';

  @override
  String get debugCopyLogs => 'Copy logs';

  @override
  String get debugFilters => 'Filters';

  @override
  String get debugAllSources => 'All sources';

  @override
  String get debugNoLogs => 'No frontend logs captured yet.';

  @override
  String debugNoEntriesAtLevel(String level) {
    return 'No entries at $level or above.';
  }

  @override
  String get logLevelError => 'Error';

  @override
  String get logLevelWarning => 'Warning';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelDebug => 'Debug';
}
