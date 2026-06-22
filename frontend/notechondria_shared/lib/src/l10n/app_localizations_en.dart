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
  String get commonGotIt => 'Got it';

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
  String get noteUntitled => 'Untitled note';

  @override
  String get noteOptions => 'Options';

  @override
  String get noteCopyLink => 'Copy link';

  @override
  String get noteLinkCopied => 'Link copied to clipboard';

  @override
  String get noteExportMarkdown => 'Export markdown';

  @override
  String get noteMoreActions => 'More actions';

  @override
  String get noteEditMeta => 'Edit note meta';

  @override
  String get noteSwitchPlainText => 'Switch editor: Plain text';

  @override
  String get noteSwitchLiveMarkdown => 'Switch editor: Live markdown';

  @override
  String get noteViewAttachments => 'View attachments';

  @override
  String get noteTitleHint => 'Title';

  @override
  String get noteWriteHint => 'Write your note...';

  @override
  String get noteAttachFile => 'Attach file';

  @override
  String get privateNoteTitle => 'Private note';

  @override
  String privateNoteBody(String link) {
    return 'This shared note is private. Sign in from Settings > Account, then reopen this link:\n\n$link';
  }

  @override
  String get privateNoteSignInError =>
      'This note is private. Sign in to view it — open Settings → Account to log in, then the link will load.';

  @override
  String get privateNoteOpenSettings => 'Open settings';

  @override
  String noteLoadError(String reason) {
    return 'Could not load note: $reason';
  }

  @override
  String get prefsDefaultEditor => 'Default editor';

  @override
  String get prefsEditorPlain => 'Plain text editor';

  @override
  String get prefsEditorMarkdown => 'Live markdown editor';

  @override
  String get prefsThemePreset => 'Theme preset';

  @override
  String get prefsThemeMode => 'Theme mode';

  @override
  String get prefsThemeModeSystem => 'System';

  @override
  String get prefsThemeModeLight => 'Light';

  @override
  String get prefsThemeModeDark => 'Dark';

  @override
  String get prefsLanguage => 'Language';

  @override
  String get prefsOfflineMode => 'Offline mode';

  @override
  String get prefsOfflineModeSubtitle =>
      'Skip remote fetches at startup. The app renders from the local cache only — sign-in and explicit cloud pulls still work on demand.';

  @override
  String get prefsViewTutorial => 'View tutorial';

  @override
  String get prefsViewTutorialSubtitle => 'Replay the quick intro tour.';

  @override
  String get prefsApiBaseUrl => 'API base URL';

  @override
  String get prefsApiBaseLockTooltip =>
      'Log out before changing the API base URL. A logged-in token is only valid against its issuing backend.';

  @override
  String get prefsApiBaseLocked => 'Locked while signed in. Log out to change.';

  @override
  String get prefsApiBaseHelper =>
      'Include the `/api/v1` suffix. The app will auto-append it if missing, but pasting the full URL is safer.';

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

  @override
  String get storageUsageTitle => 'Storage usage';

  @override
  String get storageBackend => 'Backend';

  @override
  String get storageBackendStorage => 'Backend storage';

  @override
  String get storageLocalDataUsed => 'Local data used';

  @override
  String get storageBrowserStorage => 'Browser storage';

  @override
  String get storageSpaceLeft => 'Space left';

  @override
  String get storageNotReported => 'not reported by this platform';

  @override
  String get storageBreakdown => 'Breakdown';

  @override
  String get storageNoLocalData => 'No local data stored yet.';

  @override
  String get storageSuggestions => 'Suggestions';

  @override
  String get storageAttachments => 'Attachments';

  @override
  String get storageOffline => 'offline';

  @override
  String storageQuotaUsed(String used, String quota) {
    return '$used of $quota used';
  }

  @override
  String storageFree(String amount) {
    return '$amount free';
  }

  @override
  String storageSuggestQuota(int percent) {
    return 'You are using $percent% of this browser\'s storage for this site. Free space by clearing the cache or exporting and removing old local notes.';
  }

  @override
  String storageSuggestAttachments(String size) {
    return 'Attachments take up $size. Sign in and push to the cloud, then clear local data to reclaim space, or export a backup first.';
  }

  @override
  String storageSuggestLocalTotal(String size) {
    return 'Local data is $size. Consider exporting a backup and clearing data you have already synced to the cloud.';
  }

  @override
  String get installBannerAtRisk =>
      'Your notes are saved only in this browser and can be cleared after about a week of inactivity. Sign in to back them up, or add Notechondria to your Home Screen for durable storage.';

  @override
  String get installBannerTip =>
      'Tip: add Notechondria to your Home Screen for an app-like experience and storage the browser won’t evict. On iPhone: Share → Add to Home Screen.';

  @override
  String whatsNewTitle(String appTitle) {
    return 'What\'s new in $appTitle';
  }

  @override
  String get authAccount => 'Account';

  @override
  String get authDescPrimary =>
      'Sign in via the Notechondria SSO. Account creation and password reset are handled on the Casdoor side; use the link below to register or contact the administrator if your password needs to be reset.';

  @override
  String get authDescFallback =>
      'Sign in with your existing account. Account creation and password resets have moved to the Casdoor SSO; contact the administrator if you cannot sign in.';

  @override
  String get authContinueCasdoor => 'Continue with Casdoor SSO';

  @override
  String get authSignUpCasdoor => 'No account? Sign up via Casdoor';

  @override
  String get authHideFallback => 'Hide email / password fallback';

  @override
  String get authUseEmailPassword => 'Use email / password instead';

  @override
  String get authLogin => 'Login';

  @override
  String get authForgotPassword =>
      'Forgot password? Contact the administrator to reset it. Self-service password reset has moved to Casdoor for accounts that have been migrated.';

  @override
  String get authEmailOrUsername => 'Email or username';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String authSigningInTo(String host) {
    return 'Signing in to $host';
  }

  @override
  String get authWorking => 'Working...';

  @override
  String get authPhaseSending => 'Sending request to backend';

  @override
  String get authPhaseWaiting => 'Waiting for backend response';

  @override
  String get authPhaseApplying => 'Applying response';

  @override
  String get linkTitle => 'Link Casdoor identity';

  @override
  String get linkSignedInAs => 'Casdoor signed you in as:';

  @override
  String get linkChooseIntro =>
      'This Casdoor identity is not yet linked to a Notechondria account. Choose how you want to proceed:';

  @override
  String get linkBindButton => 'Bind to my existing account';

  @override
  String get linkBindDesc =>
      'You already have a Notechondria account. Sign in once with your legacy username/email + password to link this Casdoor identity to it. After linking, future Casdoor sign-ins land on the same account.';

  @override
  String get linkCreateButton => 'Create a new Notechondria account';

  @override
  String get linkCreateDesc =>
      'No prior Notechondria account. Pick a password — your new account will be created with the username and email shown above. The same password works for the email/password fallback path when Casdoor is unreachable.';

  @override
  String get linkBindPaneDesc =>
      'Sign in to your existing Notechondria account once so we can link it to this Casdoor identity. Username or email + the password you set previously.';

  @override
  String get linkUsernameOrEmailLabel => 'Notechondria username or email';

  @override
  String get linkPasswordLabel => 'Notechondria password';

  @override
  String get linkCreatePaneDesc =>
      'Pick a password for your new Notechondria account. Casdoor will keep handling SSO; the password is for the legacy email/password fallback (when auth.trance-0.com is unreachable).';

  @override
  String get linkNewPasswordLabel => 'New password';

  @override
  String get linkConfirmPasswordLabel => 'Confirm password';

  @override
  String get linkBindAction => 'Bind account';

  @override
  String get linkCreateAction => 'Create account';

  @override
  String get linkErrBindRequired =>
      'Both username/email and password are required to bind.';

  @override
  String get linkErrPasswordShort => 'Pick a password of 8 characters or more.';

  @override
  String get linkErrPasswordMismatch =>
      'Passwords do not match. Re-type the same password in both fields.';

  @override
  String get clearAllLocalDataTile => 'Clear all local data';

  @override
  String get clearAllLocalDataTileSubtitle =>
      'Wipes drafts, categories, settings, and logs from this device. Cloud copies are not touched.';

  @override
  String get clearAllLocalDataTitle => 'Clear all local data?';

  @override
  String get clearAllLocalDataMessage =>
      'This removes every local draft and local category from this device. Notes already synced to the cloud are not affected.';

  @override
  String get clearAllLocalDataConfirm => 'Clear all';

  @override
  String get tourEditorWelcomeTitle => 'Welcome to Notechondria Editor';

  @override
  String get tourEditorWelcomeBody =>
      'Write markdown notes that work offline and sync to the cloud when you sign in.';

  @override
  String get tourEditorCategoriesTitle => 'Organize with categories';

  @override
  String get tourEditorCategoriesBody =>
      'Group notes into categories from the sidebar. Notes without one stay in your Inbox.';

  @override
  String get tourEditorSyncTitle => 'Yours, on every device';

  @override
  String get tourEditorSyncBody =>
      'Notes save on this device as you type. Sign in to back them up and sync across devices.';

  @override
  String get tourEditorToolsTitle => 'Settings & tools';

  @override
  String get tourEditorToolsBody =>
      'Themes, sync, import/export, and the debug log live in Settings. On phones, open the menu from the top-left.';

  @override
  String get tourPlannerWelcomeTitle => 'Welcome to Notechondria Planner';

  @override
  String get tourPlannerWelcomeBody =>
      'Track courses, deadlines, and your study activity in one place.';

  @override
  String get tourPlannerCoursesTitle => 'Courses & deadlines';

  @override
  String get tourPlannerCoursesBody =>
      'Add courses and planner events; upcoming deadlines surface on your dashboard.';

  @override
  String get tourPlannerAnywhereTitle => 'Plan anywhere';

  @override
  String get tourPlannerAnywhereBody =>
      'Works offline. Sign in to sync your plan across devices.';

  @override
  String get tourPlannerToolsTitle => 'Settings & tools';

  @override
  String get tourPlannerToolsBody =>
      'Themes, sync, and tools live in Settings. On phones, open the menu from the top-left.';

  @override
  String get tourPortalWelcomeTitle => 'Welcome to Notechondria';

  @override
  String get tourPortalWelcomeBody =>
      'Your hub for notes, planning, and public courses.';

  @override
  String get tourPortalExploreTitle => 'Explore public notes';

  @override
  String get tourPortalExploreBody =>
      'Browse public courses and notes right from the front page.';

  @override
  String get tourPortalAppsTitle => 'Open the apps';

  @override
  String get tourPortalAppsBody =>
      'Jump into the Editor or Planner anytime. Sign in to sync your own work.';
}
