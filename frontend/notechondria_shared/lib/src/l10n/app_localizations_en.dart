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
  String get commonSave => 'Save';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonExport => 'Export';

  @override
  String get commonRestore => 'Restore';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonChange => 'Change';

  @override
  String get commonChoose => 'Choose';

  @override
  String get navNavigation => 'Navigation';

  @override
  String get navAllNotes => 'All Notes';

  @override
  String get navCategories => 'Categories';

  @override
  String get navNewCategory => 'New category';

  @override
  String get navSettings => 'Settings';

  @override
  String get categoryUnsubscribe => 'Unsubscribe';

  @override
  String get categoryEditTitle => 'Edit category';

  @override
  String get categorySubscribedTitle => 'Subscribed category';

  @override
  String get categoryNameLabel => 'Category name';

  @override
  String get categoryIconLabel => 'Icon:';

  @override
  String get categoryDeleteHelp =>
      'Deleting moves all notes to the default category.';

  @override
  String get categorySubscribedHelp =>
      'This category is published by another user. Renaming, icon changes and deletion are only available to the owner. You can still unsubscribe to remove it from your sidebar.';

  @override
  String get feedSearchLocalDrafts => 'Search local drafts';

  @override
  String get feedSearchPrivate => 'Search your private notes';

  @override
  String get feedSearchPublic => 'Search your public notes';

  @override
  String get feedSearchNotes => 'Search your notes';

  @override
  String get feedYourPrivateNotes => 'Your private notes';

  @override
  String get feedYourPublicNotes => 'Your public notes';

  @override
  String get feedRecentNotes => 'Recent notes';

  @override
  String get feedPublicNotes => 'Public notes';

  @override
  String get feedEmptyAnon =>
      'No notes yet. Use the add button to create a local draft.';

  @override
  String get feedEmptyPrivate => 'No private notes yet.';

  @override
  String get feedEmptyPublic => 'No public notes yet.';

  @override
  String get feedEmptyPersonal =>
      'No cloud notes yet. Use the add button to create one.';

  @override
  String get feedScopePersonal => 'Personal notes';

  @override
  String get feedScopePrivate => 'Private notes';

  @override
  String get feedScopePublic => 'Public notes';

  @override
  String get feedScopeLocalOnly => 'Local drafts only';

  @override
  String get feedComposerCreate => 'Create note';

  @override
  String get feedComposerImport => 'Import markdown or zip';

  @override
  String get feedShowLabel => 'Show:';

  @override
  String get feedLocalCategoryWarning =>
      'Local categories only contain local drafts. Switch to a synced category to filter cloud notes.';

  @override
  String get feedUnsyncedDrafts => 'Unsynced local drafts';

  @override
  String get feedSyncAll => 'Sync all';

  @override
  String get feedSyncHelp =>
      'Local drafts stay private by default. Sync uploads them as private cloud notes.';

  @override
  String get feedLocalDrafts => 'Local drafts';

  @override
  String get feedEmptyCloudMatch =>
      'No matching cloud notes yet. Sync a local draft or create a new note.';

  @override
  String get feedLoadPublicNotes => 'Load public notes';

  @override
  String get feedEmptyLocalCategory =>
      'No local drafts in this offline category yet. Use the add button to create one.';

  @override
  String get feedEmptyLocal =>
      'No local drafts yet. Use the add button to create one.';

  @override
  String get feedFabImport => 'Create note. Long press to import markdown.';

  @override
  String get feedFabImportLocal =>
      'Create a local draft. Long press to import markdown.';

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
