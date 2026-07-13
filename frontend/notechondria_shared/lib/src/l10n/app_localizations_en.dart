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
  String get appName => 'Notechondria';

  @override
  String get appNameEditor => 'Notechondria Editor';

  @override
  String get appNamePlanner => 'Notechondria Planner';

  @override
  String get appNamePortal => 'Notechondria Portal';

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
  String get commonOk => 'OK';

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
  String get commonLoading => 'Loading...';

  @override
  String get splashStartingEditor => 'Starting Notechondria Editor';

  @override
  String get splashStartingPlanner => 'Starting Notechondria Planner';

  @override
  String get splashStartingPortal => 'Starting Notechondria Portal';

  @override
  String get splashLoadingLocalWorkspace => 'Loading local workspace';

  @override
  String get splashLoadingLocalPlannerData => 'Loading local planner data';

  @override
  String get splashLoadingLocalState => 'Loading local state';

  @override
  String get splashRestoringSession => 'Restoring session';

  @override
  String get splashCompletingSignIn => 'Completing sign-in';

  @override
  String get splashConnectingToServer => 'Connecting to server';

  @override
  String get splashLoadingPublicNotesData => 'Loading public notes data';

  @override
  String get splashLoadingCategories => 'Loading categories';

  @override
  String get splashLoadingNotes => 'Loading notes';

  @override
  String get localArchiveTypeLabel => 'Notechondria archive';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonSaving => 'Saving...';

  @override
  String get commonUploading => 'Uploading...';

  @override
  String get commonUnknown => 'unknown';

  @override
  String get commonUser => 'User';

  @override
  String get navNavigation => 'Navigation';

  @override
  String get navAllNotes => 'All Notes';

  @override
  String get navCategories => 'Categories';

  @override
  String get navNewCategory => 'New category';

  @override
  String get navFrontPage => 'Front page';

  @override
  String get navLearner => 'Learner';

  @override
  String get navCourse => 'Course';

  @override
  String get navActivity => 'Activity';

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
  String get feedScopePrivate => 'Private';

  @override
  String get feedScopePublic => 'Public';

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
  String get feedImportMarkdown => 'Import markdown';

  @override
  String get feedSearchCloud => 'Search your cloud notes';

  @override
  String get feedSyncToCloud => 'Sync to cloud';

  @override
  String get feedLoadNotes => 'Load notes';

  @override
  String get feedLocalDraftBadge => 'Local draft';

  @override
  String get feedBadgePublic => 'Public';

  @override
  String get feedBadgePrivate => 'Private';

  @override
  String get feedScopeAll => 'All';

  @override
  String get feedSortNewest => 'Newest';

  @override
  String get feedSortOldest => 'Oldest';

  @override
  String get feedSortPopular => 'Most popular';

  @override
  String get feedWindow3Days => '3 days';

  @override
  String get feedWindow1Week => '1 week';

  @override
  String get feedWindow1Month => '1 month';

  @override
  String get feedWindow1Year => '1 year';

  @override
  String get feedWindowAllTime => 'All time';

  @override
  String get feedFilterScope => 'Show';

  @override
  String get feedFilterSort => 'Sort';

  @override
  String get feedFilterWindow => 'Within';

  @override
  String get feedEmptyCloudSynced =>
      'No synced cloud notes yet. Sync a local draft or create a new note.';

  @override
  String get feedEmptyLocalLogin =>
      'No local drafts yet. Use the add button to create one and sync later after login.';

  @override
  String get feedCourseMetaHint =>
      'Course metadata stays editable from the editor details panel';

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
  String get noteMetaCoverImage => 'Cover image';

  @override
  String get noteMetaCoverHasHelp => 'Shown above the note in view mode.';

  @override
  String get noteMetaCoverNoneHelp =>
      'No cover yet — readers see a barcode generated from the note URL.';

  @override
  String get noteMetaCoverSyncFirst =>
      'Sync this note to the cloud before uploading a cover image.';

  @override
  String get noteMetaReplace => 'Replace';

  @override
  String get noteMetaUpload => 'Upload';

  @override
  String get noteMetaDetails => 'Note details';

  @override
  String get noteMetaNoCourse => 'No assigned course';

  @override
  String get noteMetaAssignedCourse => 'Assigned course / plan';

  @override
  String get noteMetaSection => 'Section';

  @override
  String get noteMetaDescription => 'Short description / comments';

  @override
  String get noteMetaPublicNote => 'Public note';

  @override
  String get noteMetaPublicHelp =>
      'Public notes appear in the recommendation feed.';

  @override
  String get noteMetaPublicSyncFirst =>
      'Sync this note to the cloud before making it public.';

  @override
  String get noteMetaVersionHistory => 'Version history';

  @override
  String get noteMetaNoVersions => 'No saved versions yet.';

  @override
  String get noteMetaSaving => 'Saving...';

  @override
  String get editorBlockParagraph => 'Paragraph';

  @override
  String get editorBlockHeading => 'Heading';

  @override
  String get editorBlockList => 'List';

  @override
  String get editorBlockCode => 'Code';

  @override
  String get editorBlockQuote => 'Quote';

  @override
  String get editorBlockLink => 'Link';

  @override
  String get editorBlockImage => 'Image';

  @override
  String get editorBlockDelete => 'Delete block';

  @override
  String get editorBold => 'Bold';

  @override
  String get editorItalic => 'Italic';

  @override
  String get editorStrike => 'Strike';

  @override
  String get editorAddParagraph => 'Add paragraph';

  @override
  String get editorAddList => 'Add list';

  @override
  String get editorAddCode => 'Add code';

  @override
  String get editorHeadingTokenHint => 'Heading token (## or ###)';

  @override
  String get editorBlockContentHint => 'Write block content...';

  @override
  String get editorModePlain => 'Plain';

  @override
  String get editorModePreview => 'Preview';

  @override
  String get editorModeBlocks => 'Blocks';

  @override
  String get editorModeLabel => 'Editor mode';

  @override
  String get editorNotSaved => 'Not saved';

  @override
  String editorSavedAt(String time) {
    return 'Saved $time';
  }

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
  String get settingsDevRestoreTemplatesTitle =>
      'Restore remote template courses';

  @override
  String get settingsDevRestoreTemplatesSubtitle =>
      'Admin-only. Calls the backend to re-seed the three-course template catalog (Inbox / Examples / Templates) with a welcome note in each.';

  @override
  String get settingsDevImportJournalTitle => 'Import Apple Journal ZIP';

  @override
  String get settingsDevImportJournalSubtitle =>
      'Experimental local-only import. Creates local drafts in a selected category; cloud sync waits for a manual push.';

  @override
  String get settingsDevClearLegacyTitle => 'Clear legacy shared storage';

  @override
  String get settingsDevClearLegacySubtitle =>
      'Removes the pre-0.1.127 unprefixed browser-storage keys left behind when the apps moved to per-app namespaces. Shared across editor / planner / portal; your current notes and settings are unaffected.';

  @override
  String get settingsDevCaption =>
      'Requires a signed-in admin account. Non-admin sessions will see a server-side error in the banner above without changing any data.';

  @override
  String get settingsRestoreStarterTitle => 'Restore starter draft';

  @override
  String get settingsRestoreStarterSubtitle =>
      'Re-seeds the welcome draft in the uncategorized bucket. Safe to run any time — only fires when no notes exist locally.';

  @override
  String get settingsLegacyTemplateCaption =>
      'The legacy three-course template restore (admin-only, requires a cloud session) is now in the Developer section of the main Settings page.';

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
  String get settingsPortalPreferences => 'Portal preferences';

  @override
  String get settingsPortalPreferencesSubtitle =>
      'Theme preset, theme mode, default editor.';

  @override
  String get settingsConnectedAccounts => 'Connected accounts';

  @override
  String get settingsPersonalInfoSubtitle =>
      'Avatar, username, motto, social link.';

  @override
  String get settingsSecuritySubtitle =>
      'Active sessions, change email, change password, agent skill.';

  @override
  String get settingsApiSubtitle => 'API base URL and MCP key.';

  @override
  String get settingsManageAccountPreferences =>
      'Manage your account, preferences, and local data.';

  @override
  String get settingsLocalOnlyPreferences =>
      'Sign in to sync to the cloud, or keep using local-only preferences below.';

  @override
  String get settingsCasdoorLinked => 'Casdoor SSO linked.';

  @override
  String get settingsNoThirdPartyLinked => 'No third-party accounts linked.';

  @override
  String settingsBackendOnlineSummary(String url) {
    return 'Online. API URL: $url';
  }

  @override
  String settingsBackendOfflineSummary(String url) {
    return 'Offline mode is on. API URL: $url';
  }

  @override
  String settingsLocalDataSummary(int drafts, int courses) {
    return '$drafts draft(s), $courses course(s) on this device.';
  }

  @override
  String settingsRecycleBinSummary(int drafts, int notes) {
    return '$drafts synced draft(s) recoverable, $notes cloud note(s) trashed.';
  }

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsChangeAvatar => 'Change avatar';

  @override
  String get settingsUsername => 'Username';

  @override
  String get settingsFirstName => 'First name';

  @override
  String get settingsLastName => 'Last name';

  @override
  String get settingsMotto => 'Motto';

  @override
  String get settingsSocialLink => 'Social link';

  @override
  String get settingsSocialLinkInvalid => 'Must be a valid URL (https://...)';

  @override
  String get settingsUncategorizedFolderName => 'Uncategorized folder name';

  @override
  String get settingsUncategorizedFolderHelp =>
      'Label for the bucket that holds notes with no category. Blank falls back to \"Inbox\".';

  @override
  String get settingsAccountCasdoorNotice =>
      'Account creation, password change, email change, and per-device session management live on the Casdoor user portal. Casdoor bind / unlink controls are on the Account page.';

  @override
  String get settingsApiBaseLockedTooltip =>
      'Locked while signed in. Sign out to switch the backend the portal talks to.';

  @override
  String get settingsApiBaseTooltip =>
      'Points the portal at a different Notechondria backend.';

  @override
  String get settingsEditorApiBaseTooltip =>
      'Points the editor at a different Notechondria backend. The handshake probe verifies the URL before saving.';

  @override
  String get settingsApiBaseApplyCaption =>
      'Press Enter to apply the URL change. Stored locally and mirrored to the profile on login.';

  @override
  String get settingsApiBaseApplyLockedCaption =>
      'Press Enter to apply the URL change. Stored locally and mirrored to your profile on login. Locked while signed in — sign out to switch backends.';

  @override
  String get settingsMcpKeyCaption =>
      'The MCP key authenticates the backend Model Context Protocol bridge. Rotate it if you suspect leakage.';

  @override
  String get settingsConnectedAccountsCaption =>
      'Casdoor proxies third-party identities (Google, GitHub, etc.) — configure them on the Casdoor application\'s Providers tab.';

  @override
  String get plannerSettingsTitle => 'Planner settings';

  @override
  String get plannerSettingsDescription =>
      'This app keeps planner-focused controls only: login/sync, deadline-ordering preferences, and debug output.';

  @override
  String get plannerLoginSyncTitle => 'Login and sync';

  @override
  String get plannerLoginSyncHelp =>
      'Sign in to sync course plans, module discussion roots, and planner deadlines. Local planner data remains usable while signed out.';

  @override
  String plannerSignedInAs(String identity) {
    return 'Signed in as $identity.';
  }

  @override
  String get plannerPreferencesTitle => 'Planner preferences';

  @override
  String get plannerDeadlineTimeWeight => 'Deadline time weight (a)';

  @override
  String get plannerDeadlineImportanceWeight =>
      'Deadline importance weight (b)';

  @override
  String get plannerDeadlineSortHelp =>
      'Deadlines sort by (a × time pressure) × (b × importance). Importance uses the existing event weight.';

  @override
  String get plannerSaveSettings => 'Save planner settings';

  @override
  String plannerDebugSummary(int notes, int courses) {
    return '$notes local note(s), $courses local course(s).';
  }

  @override
  String get settingsThemeModeMatchSystem => 'Match system';

  @override
  String get settingsEditorModePickerHelp =>
      'Picks how new notes open by default. You can still switch modes per note from the editor toolbar.';

  @override
  String get settingsThemePresetPickerHelp =>
      'Each preset uses a different seed color for the Material 3 ColorScheme.';

  @override
  String get settingsThemeModePickerHelp =>
      'Match system follows the device-level Light/Dark toggle. Light and Dark override the system choice.';

  @override
  String get settingsOfflineModeSubtitleShort =>
      'Skip every remote fetch on startup; render everything from the local cache.';

  @override
  String settingsLocalDataCounts(int drafts, int courses) {
    return '$drafts local draft(s), $courses local course(s).';
  }

  @override
  String get settingsDownloadLocalData => 'Download local data';

  @override
  String get settingsDownloadLocalDataSubtitle =>
      'Exports drafts, courses, settings, and logs as a .nchron archive.';

  @override
  String get settingsRestoreLocalArchive => 'Restore from local archive';

  @override
  String get settingsRestoreLocalArchiveSubtitle =>
      'Imports a previously-exported .nchron archive. Replaces existing local data after a confirm dialog.';

  @override
  String get settingsPushLocalCloud => 'Push local → cloud';

  @override
  String get settingsPushLocalCloudSubtitle =>
      'Upload local drafts and courses to your cloud account. Requires sign-in.';

  @override
  String get settingsPullCloudLocal => 'Pull cloud → local';

  @override
  String get settingsPullCloudLocalSubtitle =>
      'Download notes and courses from the cloud to this device.';

  @override
  String get settingsClearLocalCache => 'Clear local cache';

  @override
  String get settingsClearLocalCacheSubtitle =>
      'Drops cached API responses but keeps drafts and courses on disk.';

  @override
  String get settingsRemoveLocalData => 'Remove local data';

  @override
  String get settingsRemoveLocalDataSubtitle =>
      'Wipes drafts, courses, settings, and logs from this device. Cloud copies are not touched.';

  @override
  String get settingsRestoreTemplateCourses => 'Restore template courses';

  @override
  String get settingsRestoreTemplateCoursesSubtitle =>
      'Admin-only. Re-seeds the three-course template catalog (Inbox / Examples / Templates).';

  @override
  String get settingsRestoreTemplateCoursesCaption =>
      'Requires a signed-in admin account. Non-admin sessions will see a server-side error in the banner above without changing any data.';

  @override
  String get settingsSyncedLocalDrafts => 'Synced local drafts';

  @override
  String settingsLocalRecycleCount(int count) {
    return '$count item(s) waiting in the local recycle bin.';
  }

  @override
  String get settingsCloudRecycleBin => 'Cloud recycle bin';

  @override
  String settingsCloudRecycleCount(int count) {
    return '$count soft-deleted note(s) on the server.';
  }

  @override
  String get settingsCloudRecycleSignIn =>
      'Sign in to manage deleted cloud notes.';

  @override
  String get settingsRecycleBinEmpty => 'Recycle bin is empty.';

  @override
  String get settingsEmptyRecycleBin => 'Empty recycle bin';

  @override
  String get apiKeyTitle => 'API key';

  @override
  String get apiKeyNoKey => '(no API key — click Generate to create one)';

  @override
  String get apiKeyRotate => 'Rotate';

  @override
  String get apiKeyGenerate => 'Generate';

  @override
  String get apiKeyCopyNow => 'Copy this key now — it will NOT be shown again:';

  @override
  String get apiKeySavedIt => 'I have saved it';

  @override
  String get apiKeyCopied => 'API key copied to clipboard.';

  @override
  String get apiKeyMcpEndpointCopied => 'MCP endpoint copied to clipboard.';

  @override
  String apiKeyRotateFailed(String error) {
    return 'Failed to rotate API key: Portal.Settings/api_key.rotate — $error';
  }

  @override
  String get apiKeyHelp =>
      'Use this key with MCP clients (e.g. Claude Desktop) by setting the Authorization header to \"Bearer ntc_<key>\".';

  @override
  String get apiKeyMcpEndpoint => 'MCP endpoint:';

  @override
  String get apiKeyCopyMcpEndpoint => 'Copy MCP endpoint';

  @override
  String get connectedAccountsTitle => 'Connected accounts';

  @override
  String get connectedAccountsShadow =>
      'Casdoor is in shadow mode on this backend; no third-party accounts can be linked.';

  @override
  String get connectedAccountsManageCasdoor => 'Manage Casdoor account';

  @override
  String get connectedAccountsUnavailableHelp =>
      'If sign-in is unavailable, contact your Notechondria admin (Casdoor backend may be off).';

  @override
  String get connectedAccountsCasdoorSso => 'Casdoor SSO';

  @override
  String get connectedAccountsLinked => 'Linked';

  @override
  String get connectedAccountsNotLinked => 'Not linked';

  @override
  String get connectedAccountsSwitch => 'Switch';

  @override
  String get connectedAccountsUnlink => 'Unlink';

  @override
  String get connectedAccountsLinkCasdoor => 'Link Casdoor';

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
  String editorDebugSummary(int drafts, int categories) {
    return '$drafts local draft(s), $categories local category(ies).';
  }

  @override
  String editorLocalAttachments(String size) {
    return 'Local attachments: $size';
  }

  @override
  String get editorAttachmentsOverLimit =>
      'Attachments exceed 500 MB — sync to free up space.';

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

  @override
  String get errorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get errorTimeout => 'The server took too long to respond. Try again.';

  @override
  String get errorServer => 'The server hit an error. Try again in a moment.';

  @override
  String get versionUpdateAvailable =>
      'A new version is available. Refresh to update.';

  @override
  String get versionDeploying =>
      'A new version is rolling out — some features may be briefly unavailable.';

  @override
  String get versionUnsupported =>
      'This app version is no longer supported. Refresh to update.';

  @override
  String get versionRefresh => 'Refresh';

  @override
  String get errorWorkOffline => 'Work offline';

  @override
  String frontWelcomeBack(String name) {
    return 'Welcome back, $name';
  }

  @override
  String get frontWelcomeGuest => 'Welcome to Notechondria';

  @override
  String get frontGreetingGuest => 'guest';

  @override
  String get frontHeroAuth =>
      'Your notes, courses and schedule at a glance. Pick a course below or jump into the learner/planner workspaces.';

  @override
  String get frontHeroAnon =>
      'Discover public courses and notes, or sign in to unlock your learner dashboard and heatmap.';

  @override
  String get frontRecentCourses => 'Recent public courses';

  @override
  String get frontNoCourses => 'No public courses yet.';

  @override
  String get frontActivityHeatmap => 'Activity heatmap';

  @override
  String get frontHeatmapLegend =>
      'Past activity (blue) and upcoming planner load (teal).';

  @override
  String get frontRecentNotes => 'Recent public notes';

  @override
  String get courseCreateLocal => 'Create local course';

  @override
  String get courseTitleLabel => 'Course title';

  @override
  String get courseDescriptionLabel => 'Description';

  @override
  String get courseSyncLocalData => 'Sync local data';

  @override
  String courseBackTo(String title) {
    return 'Back to $title';
  }

  @override
  String get courseModuleDiscussion => 'Module discussion';

  @override
  String get courseBackToResults => 'Back to course results';

  @override
  String get courseSubscribe => 'Subscribe';

  @override
  String get courseNoModules =>
      'No modules have been mapped for this course yet.';

  @override
  String get courseDiscussion => 'Course discussion';

  @override
  String get courseListTitle => 'Course list';

  @override
  String get courseLoadMore => 'Load more';

  @override
  String get activitySignInPrompt =>
      'Sign in to view your deadlines, synced study sessions, and weekly calendar.';

  @override
  String get activityNoWeekEvents =>
      'No weekly events are available for the current view.';

  @override
  String get activityThisWeek => 'This week';

  @override
  String get activityPrevWeek => 'Previous week';

  @override
  String get activityNextWeek => 'Next week';

  @override
  String get activityZoomIn => 'Zoom in';

  @override
  String get activityZoomOut => 'Zoom out';

  @override
  String get activityRange3Day => '3 days';

  @override
  String get activityRange1Week => '1 week';

  @override
  String get activityRange1Month => '1 month';

  @override
  String get activityCreateEvent => 'Create event';

  @override
  String get activityImportIcal => 'Import iCal';

  @override
  String get activitySubscribeCalendar => 'Subscribe calendar';

  @override
  String get activityFabHint =>
      'Tap to create a new event. Long press or right click to import iCal or subscribe.';

  @override
  String get activityNoDeadlines =>
      'No active deadlines yet. Use the add button to create one.';

  @override
  String get activityNoUrgent =>
      'No urgent deadlines remain in the current view.';

  @override
  String get activityWeekCalendar => 'Week calendar';

  @override
  String get activityNewEvent => 'New event';

  @override
  String get activityEventTitle => 'Event title';

  @override
  String get activityDifficulty => 'Difficulty';

  @override
  String activityWeightN(int n) {
    switch (n) {
      case 1:
        return 'Trivial';
      case 2:
        return 'Normal';
      case 3:
        return 'Important';
      case 4:
        return 'Significant';
      case 5:
        return 'Fatal';
      default:
        return 'Normal';
    }
  }

  @override
  String heatmapActivityValue(int value) {
    return '$value activity';
  }

  @override
  String heatmapPlannedValue(int value) {
    return 'planned load $value';
  }

  @override
  String get activitySubscribeToCalendar => 'Subscribe to calendar';

  @override
  String get activityIcalUrl => 'iCal URL';

  @override
  String get activitySubscribedCalendar => 'Subscribed calendar';

  @override
  String get activityImportSucceeded => 'Import succeeded';

  @override
  String get activityImportFailed => 'Import failed';

  @override
  String activityImportedCount(int count, String title) {
    return 'Imported $count event(s) from "$title":';
  }

  @override
  String get activityAllCourses => 'All courses';

  @override
  String get activityEditEvent => 'Edit event';

  @override
  String get activityRepeatLabel => 'Repeat';

  @override
  String get activityRepeatNever => 'Does not repeat';

  @override
  String get activityRepeatWeekly => 'Weekly';

  @override
  String get activityRepeatMonthly => 'Monthly';

  @override
  String get activityRepeatYearly => 'Yearly';

  @override
  String get activityRepeatIntervalLabel => 'Repeat every N period(s)';

  @override
  String get activityRepeatEndsLabel => 'Ends';

  @override
  String get activityRepeatEndNever => 'Never';

  @override
  String get activityRepeatEndOnDate => 'On date';

  @override
  String get activityRepeatEndAfter => 'After N occurrences';

  @override
  String get activityRepeatCountLabel => 'Number of occurrences';

  @override
  String get mcpSkillCopied => 'skill.md copied to clipboard.';

  @override
  String get mcpSkillTitle => 'Agent skill (skill.md)';

  @override
  String get mcpSkillDescription =>
      'Personal playbook for MCP-connected agents. Use this to describe where to pull notes from (e.g. external sites like notenextra.trance-0.com), how to format imports, which files to export, and where to publish them. Sent verbatim as the `instructions` field of the MCP initialize response.';

  @override
  String get mcpSkillHint =>
      '# Import\n- Pull notes from notenextra.trance-0.com once a day...\n\n# Export\n- Mirror to GitHub Gist as YAML+markdown.\n\n# Format\n- Wrap math in \$...\$. Tag deadlines with #deadline.';

  @override
  String get mcpSkillUnsavedChanges => 'unsaved changes';

  @override
  String get githubSyncTitle => 'Experimental — GitHub Sync';

  @override
  String get githubSyncDescription =>
      'Push your full account (profile, settings, MCP skill, courses, notes, custom meta, planner events) to a GitHub repo you own so you can recover everything if our server is wiped. Static assets we host (avatars, attachments, cover images) are referenced by URL, not committed. See docs/integrations/github-sync.md for the full flow.';

  @override
  String get githubSyncInstall => 'Install Notechondria GitHub App';

  @override
  String get githubSyncInstallHelp =>
      'After approving the install, GitHub redirects back here and we persist your installation id automatically. The app stays installed until you remove it from your GitHub settings.';

  @override
  String get githubSyncInstalled => 'GitHub App installed.';

  @override
  String githubSyncInstalledOn(String account) {
    return 'GitHub App installed on @$account.';
  }

  @override
  String get githubSyncNoRepos =>
      'No repositories visible to this installation. Open GitHub settings → Applications → Notechondria data sync, and grant access to a repo.';

  @override
  String get githubSyncTargetRepo => 'Sync target repository';

  @override
  String get githubSyncIncludeAssets => 'Include assets';

  @override
  String get githubSyncIncludeAssetsOn =>
      'Avatar, cover images, and attachments are inlined under assets/. Subject to per-file (50 MB) and per-push (200 MB) caps.';

  @override
  String get githubSyncIncludeAssetsOff =>
      'Static assets stay referenced by URL only. Faster push, but a fresh server can\'t recover the bytes.';

  @override
  String get githubSyncPushNow => 'Push now';

  @override
  String get githubSyncDisconnect => 'Disconnect';

  @override
  String githubSyncLastPush(String sha) {
    return 'Last push: $sha';
  }

  @override
  String githubSyncLastPushAt(String time) {
    return 'Last push at $time.';
  }

  @override
  String get githubSyncSignIn => 'Sign in to enable GitHub Sync.';

  @override
  String githubSyncLoadStatusFailed(String error) {
    return 'Cannot load GitHub Sync status: Frontend.GithubSync/status — $error';
  }

  @override
  String githubSyncSelectRepositoryFailed(String error) {
    return 'Cannot select repository: Frontend.GithubSync/repository.select — $error';
  }

  @override
  String githubSyncPushFailed(String error) {
    return 'GitHub Sync push failed: Frontend.GithubSync/push — $error';
  }

  @override
  String githubSyncPushed(String sha) {
    return 'Pushed to GitHub: Frontend.GithubSync/push — commit $sha.';
  }

  @override
  String githubSyncDisconnectFailed(String error) {
    return 'Cannot disconnect GitHub Sync: Frontend.GithubSync/disconnect — $error';
  }

  @override
  String get githubSyncInstallMissingUrl =>
      'Cannot install GitHub App: Frontend.GithubSync/install — no install_url configured.';

  @override
  String get githubSyncInstallInvalidUrl =>
      'Cannot install GitHub App: Frontend.GithubSync/install — install_url is not a valid http(s) URL.';

  @override
  String githubSyncInstallCompleteFailed(String error) {
    return 'Cannot complete GitHub App install: Frontend.GithubSync/install.callback — $error';
  }

  @override
  String get githubSyncInstallUrlMissingHelp =>
      'Operator note: GITHUB_DATA_SYNC_APP_INSTALL_URL is not configured on this backend. See docs/integrations/github-sync.md for the env-var contract.';

  @override
  String get courseObjectives => 'Objectives';

  @override
  String get courseAssignments => 'Assignments';

  @override
  String get courseModule => 'Module';

  @override
  String get courseModulesHeader => 'Modules';

  @override
  String get courseModuleNoNotes =>
      'No public notes are available for this module yet.';

  @override
  String get courseNoDiscussion =>
      'No public discussion notes are available for this course yet.';

  @override
  String courseNoteCount(int count) {
    return '$count note(s)';
  }
}
