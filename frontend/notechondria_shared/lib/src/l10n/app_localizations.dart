import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @languageName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get commonExport;

  /// No description provided for @commonRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get commonRestore;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get commonChange;

  /// No description provided for @commonChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get commonChoose;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @navNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navNavigation;

  /// No description provided for @navAllNotes.
  ///
  /// In en, this message translates to:
  /// **'All Notes'**
  String get navAllNotes;

  /// No description provided for @navCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// No description provided for @navNewCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get navNewCategory;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @categoryUnsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get categoryUnsubscribe;

  /// No description provided for @categoryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEditTitle;

  /// No description provided for @categorySubscribedTitle.
  ///
  /// In en, this message translates to:
  /// **'Subscribed category'**
  String get categorySubscribedTitle;

  /// No description provided for @categoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryNameLabel;

  /// No description provided for @categoryIconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon:'**
  String get categoryIconLabel;

  /// No description provided for @categoryDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Deleting moves all notes to the default category.'**
  String get categoryDeleteHelp;

  /// No description provided for @categorySubscribedHelp.
  ///
  /// In en, this message translates to:
  /// **'This category is published by another user. Renaming, icon changes and deletion are only available to the owner. You can still unsubscribe to remove it from your sidebar.'**
  String get categorySubscribedHelp;

  /// No description provided for @feedSearchLocalDrafts.
  ///
  /// In en, this message translates to:
  /// **'Search local drafts'**
  String get feedSearchLocalDrafts;

  /// No description provided for @feedSearchPrivate.
  ///
  /// In en, this message translates to:
  /// **'Search your private notes'**
  String get feedSearchPrivate;

  /// No description provided for @feedSearchPublic.
  ///
  /// In en, this message translates to:
  /// **'Search your public notes'**
  String get feedSearchPublic;

  /// No description provided for @feedSearchNotes.
  ///
  /// In en, this message translates to:
  /// **'Search your notes'**
  String get feedSearchNotes;

  /// No description provided for @feedYourPrivateNotes.
  ///
  /// In en, this message translates to:
  /// **'Your private notes'**
  String get feedYourPrivateNotes;

  /// No description provided for @feedYourPublicNotes.
  ///
  /// In en, this message translates to:
  /// **'Your public notes'**
  String get feedYourPublicNotes;

  /// No description provided for @feedRecentNotes.
  ///
  /// In en, this message translates to:
  /// **'Recent notes'**
  String get feedRecentNotes;

  /// No description provided for @feedPublicNotes.
  ///
  /// In en, this message translates to:
  /// **'Public notes'**
  String get feedPublicNotes;

  /// No description provided for @feedEmptyAnon.
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Use the add button to create a local draft.'**
  String get feedEmptyAnon;

  /// No description provided for @feedEmptyPrivate.
  ///
  /// In en, this message translates to:
  /// **'No private notes yet.'**
  String get feedEmptyPrivate;

  /// No description provided for @feedEmptyPublic.
  ///
  /// In en, this message translates to:
  /// **'No public notes yet.'**
  String get feedEmptyPublic;

  /// No description provided for @feedEmptyPersonal.
  ///
  /// In en, this message translates to:
  /// **'No cloud notes yet. Use the add button to create one.'**
  String get feedEmptyPersonal;

  /// No description provided for @feedScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal notes'**
  String get feedScopePersonal;

  /// No description provided for @feedScopePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private notes'**
  String get feedScopePrivate;

  /// No description provided for @feedScopePublic.
  ///
  /// In en, this message translates to:
  /// **'Public notes'**
  String get feedScopePublic;

  /// No description provided for @feedScopeLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Local drafts only'**
  String get feedScopeLocalOnly;

  /// No description provided for @feedComposerCreate.
  ///
  /// In en, this message translates to:
  /// **'Create note'**
  String get feedComposerCreate;

  /// No description provided for @feedComposerImport.
  ///
  /// In en, this message translates to:
  /// **'Import markdown or zip'**
  String get feedComposerImport;

  /// No description provided for @feedShowLabel.
  ///
  /// In en, this message translates to:
  /// **'Show:'**
  String get feedShowLabel;

  /// No description provided for @feedLocalCategoryWarning.
  ///
  /// In en, this message translates to:
  /// **'Local categories only contain local drafts. Switch to a synced category to filter cloud notes.'**
  String get feedLocalCategoryWarning;

  /// No description provided for @feedUnsyncedDrafts.
  ///
  /// In en, this message translates to:
  /// **'Unsynced local drafts'**
  String get feedUnsyncedDrafts;

  /// No description provided for @feedSyncAll.
  ///
  /// In en, this message translates to:
  /// **'Sync all'**
  String get feedSyncAll;

  /// No description provided for @feedSyncHelp.
  ///
  /// In en, this message translates to:
  /// **'Local drafts stay private by default. Sync uploads them as private cloud notes.'**
  String get feedSyncHelp;

  /// No description provided for @feedLocalDrafts.
  ///
  /// In en, this message translates to:
  /// **'Local drafts'**
  String get feedLocalDrafts;

  /// No description provided for @feedEmptyCloudMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching cloud notes yet. Sync a local draft or create a new note.'**
  String get feedEmptyCloudMatch;

  /// No description provided for @feedLoadPublicNotes.
  ///
  /// In en, this message translates to:
  /// **'Load public notes'**
  String get feedLoadPublicNotes;

  /// No description provided for @feedEmptyLocalCategory.
  ///
  /// In en, this message translates to:
  /// **'No local drafts in this offline category yet. Use the add button to create one.'**
  String get feedEmptyLocalCategory;

  /// No description provided for @feedEmptyLocal.
  ///
  /// In en, this message translates to:
  /// **'No local drafts yet. Use the add button to create one.'**
  String get feedEmptyLocal;

  /// No description provided for @feedFabImport.
  ///
  /// In en, this message translates to:
  /// **'Create note. Long press to import markdown.'**
  String get feedFabImport;

  /// No description provided for @feedFabImportLocal.
  ///
  /// In en, this message translates to:
  /// **'Create a local draft. Long press to import markdown.'**
  String get feedFabImportLocal;

  /// No description provided for @noteUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled note'**
  String get noteUntitled;

  /// No description provided for @noteOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get noteOptions;

  /// No description provided for @noteCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get noteCopyLink;

  /// No description provided for @noteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get noteLinkCopied;

  /// No description provided for @noteExportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export markdown'**
  String get noteExportMarkdown;

  /// No description provided for @noteMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get noteMoreActions;

  /// No description provided for @noteEditMeta.
  ///
  /// In en, this message translates to:
  /// **'Edit note meta'**
  String get noteEditMeta;

  /// No description provided for @noteSwitchPlainText.
  ///
  /// In en, this message translates to:
  /// **'Switch editor: Plain text'**
  String get noteSwitchPlainText;

  /// No description provided for @noteSwitchLiveMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Switch editor: Live markdown'**
  String get noteSwitchLiveMarkdown;

  /// No description provided for @noteViewAttachments.
  ///
  /// In en, this message translates to:
  /// **'View attachments'**
  String get noteViewAttachments;

  /// No description provided for @noteTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get noteTitleHint;

  /// No description provided for @noteWriteHint.
  ///
  /// In en, this message translates to:
  /// **'Write your note...'**
  String get noteWriteHint;

  /// No description provided for @noteAttachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get noteAttachFile;

  /// No description provided for @privateNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Private note'**
  String get privateNoteTitle;

  /// No description provided for @privateNoteBody.
  ///
  /// In en, this message translates to:
  /// **'This shared note is private. Sign in from Settings > Account, then reopen this link:\n\n{link}'**
  String privateNoteBody(String link);

  /// No description provided for @privateNoteSignInError.
  ///
  /// In en, this message translates to:
  /// **'This note is private. Sign in to view it — open Settings → Account to log in, then the link will load.'**
  String get privateNoteSignInError;

  /// No description provided for @privateNoteOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get privateNoteOpenSettings;

  /// No description provided for @noteLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load note: {reason}'**
  String noteLoadError(String reason);

  /// No description provided for @prefsDefaultEditor.
  ///
  /// In en, this message translates to:
  /// **'Default editor'**
  String get prefsDefaultEditor;

  /// No description provided for @prefsEditorPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain text editor'**
  String get prefsEditorPlain;

  /// No description provided for @prefsEditorMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Live markdown editor'**
  String get prefsEditorMarkdown;

  /// No description provided for @prefsThemePreset.
  ///
  /// In en, this message translates to:
  /// **'Theme preset'**
  String get prefsThemePreset;

  /// No description provided for @prefsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get prefsThemeMode;

  /// No description provided for @prefsThemeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get prefsThemeModeSystem;

  /// No description provided for @prefsThemeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get prefsThemeModeLight;

  /// No description provided for @prefsThemeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get prefsThemeModeDark;

  /// No description provided for @prefsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get prefsLanguage;

  /// No description provided for @prefsOfflineMode.
  ///
  /// In en, this message translates to:
  /// **'Offline mode'**
  String get prefsOfflineMode;

  /// No description provided for @prefsOfflineModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Skip remote fetches at startup. The app renders from the local cache only — sign-in and explicit cloud pulls still work on demand.'**
  String get prefsOfflineModeSubtitle;

  /// No description provided for @prefsViewTutorial.
  ///
  /// In en, this message translates to:
  /// **'View tutorial'**
  String get prefsViewTutorial;

  /// No description provided for @prefsViewTutorialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replay the quick intro tour.'**
  String get prefsViewTutorialSubtitle;

  /// No description provided for @prefsApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get prefsApiBaseUrl;

  /// No description provided for @prefsApiBaseLockTooltip.
  ///
  /// In en, this message translates to:
  /// **'Log out before changing the API base URL. A logged-in token is only valid against its issuing backend.'**
  String get prefsApiBaseLockTooltip;

  /// No description provided for @prefsApiBaseLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked while signed in. Log out to change.'**
  String get prefsApiBaseLocked;

  /// No description provided for @prefsApiBaseHelper.
  ///
  /// In en, this message translates to:
  /// **'Include the `/api/v1` suffix. The app will auto-append it if missing, but pasting the full URL is safer.'**
  String get prefsApiBaseHelper;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Editor settings'**
  String get settingsEditorTitle;

  /// No description provided for @settingsEditorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Default editor mode, theme preset, theme mode.'**
  String get settingsEditorSubtitle;

  /// No description provided for @settingsViewTutorial.
  ///
  /// In en, this message translates to:
  /// **'View tutorial'**
  String get settingsViewTutorial;

  /// No description provided for @settingsViewTutorialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replay the quick intro tour.'**
  String get settingsViewTutorialSubtitle;

  /// No description provided for @settingsBackendTitle.
  ///
  /// In en, this message translates to:
  /// **'Backend settings'**
  String get settingsBackendTitle;

  /// No description provided for @settingsLocalDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Local data'**
  String get settingsLocalDataTitle;

  /// No description provided for @settingsLocalDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download or restore the local archive, reset the starter categories.'**
  String get settingsLocalDataSubtitle;

  /// No description provided for @settingsRecycleBinTitle.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin'**
  String get settingsRecycleBinTitle;

  /// No description provided for @settingsDeveloperTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get settingsDeveloperTitle;

  /// No description provided for @settingsDeveloperSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Admin-only actions: restore the remote three-course template catalog.'**
  String get settingsDeveloperSubtitle;

  /// No description provided for @settingsPersonalInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal information'**
  String get settingsPersonalInfoTitle;

  /// No description provided for @settingsSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in & security'**
  String get settingsSecurityTitle;

  /// No description provided for @settingsApiTitle.
  ///
  /// In en, this message translates to:
  /// **'API settings'**
  String get settingsApiTitle;

  /// No description provided for @settingsImmediateSaveCaption.
  ///
  /// In en, this message translates to:
  /// **'Each change is saved and persisted immediately — no Save button needed in this menu.'**
  String get settingsImmediateSaveCaption;

  /// No description provided for @settingsDefaultEditorMode.
  ///
  /// In en, this message translates to:
  /// **'Default editor mode'**
  String get settingsDefaultEditorMode;

  /// No description provided for @settingsThemePreset.
  ///
  /// In en, this message translates to:
  /// **'Theme preset'**
  String get settingsThemePreset;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get settingsThemeMode;

  /// No description provided for @debugLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Debug log'**
  String get debugLogTitle;

  /// No description provided for @debugCopyLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get debugCopyLogs;

  /// No description provided for @debugFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get debugFilters;

  /// No description provided for @debugAllSources.
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get debugAllSources;

  /// No description provided for @debugNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No frontend logs captured yet.'**
  String get debugNoLogs;

  /// No description provided for @debugNoEntriesAtLevel.
  ///
  /// In en, this message translates to:
  /// **'No entries at {level} or above.'**
  String debugNoEntriesAtLevel(String level);

  /// No description provided for @logLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// No description provided for @logLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logLevelWarning;

  /// No description provided for @logLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logLevelInfo;

  /// No description provided for @logLevelDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logLevelDebug;

  /// No description provided for @storageUsageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage usage'**
  String get storageUsageTitle;

  /// No description provided for @storageBackend.
  ///
  /// In en, this message translates to:
  /// **'Backend'**
  String get storageBackend;

  /// No description provided for @storageBackendStorage.
  ///
  /// In en, this message translates to:
  /// **'Backend storage'**
  String get storageBackendStorage;

  /// No description provided for @storageLocalDataUsed.
  ///
  /// In en, this message translates to:
  /// **'Local data used'**
  String get storageLocalDataUsed;

  /// No description provided for @storageBrowserStorage.
  ///
  /// In en, this message translates to:
  /// **'Browser storage'**
  String get storageBrowserStorage;

  /// No description provided for @storageSpaceLeft.
  ///
  /// In en, this message translates to:
  /// **'Space left'**
  String get storageSpaceLeft;

  /// No description provided for @storageNotReported.
  ///
  /// In en, this message translates to:
  /// **'not reported by this platform'**
  String get storageNotReported;

  /// No description provided for @storageBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get storageBreakdown;

  /// No description provided for @storageNoLocalData.
  ///
  /// In en, this message translates to:
  /// **'No local data stored yet.'**
  String get storageNoLocalData;

  /// No description provided for @storageSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get storageSuggestions;

  /// No description provided for @storageAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get storageAttachments;

  /// No description provided for @storageOffline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get storageOffline;

  /// No description provided for @storageQuotaUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} of {quota} used'**
  String storageQuotaUsed(String used, String quota);

  /// No description provided for @storageFree.
  ///
  /// In en, this message translates to:
  /// **'{amount} free'**
  String storageFree(String amount);

  /// No description provided for @storageSuggestQuota.
  ///
  /// In en, this message translates to:
  /// **'You are using {percent}% of this browser\'s storage for this site. Free space by clearing the cache or exporting and removing old local notes.'**
  String storageSuggestQuota(int percent);

  /// No description provided for @storageSuggestAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments take up {size}. Sign in and push to the cloud, then clear local data to reclaim space, or export a backup first.'**
  String storageSuggestAttachments(String size);

  /// No description provided for @storageSuggestLocalTotal.
  ///
  /// In en, this message translates to:
  /// **'Local data is {size}. Consider exporting a backup and clearing data you have already synced to the cloud.'**
  String storageSuggestLocalTotal(String size);

  /// No description provided for @installBannerAtRisk.
  ///
  /// In en, this message translates to:
  /// **'Your notes are saved only in this browser and can be cleared after about a week of inactivity. Sign in to back them up, or add Notechondria to your Home Screen for durable storage.'**
  String get installBannerAtRisk;

  /// No description provided for @installBannerTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: add Notechondria to your Home Screen for an app-like experience and storage the browser won’t evict. On iPhone: Share → Add to Home Screen.'**
  String get installBannerTip;

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new in {appTitle}'**
  String whatsNewTitle(String appTitle);

  /// No description provided for @authAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get authAccount;

  /// No description provided for @authDescPrimary.
  ///
  /// In en, this message translates to:
  /// **'Sign in via the Notechondria SSO. Account creation and password reset are handled on the Casdoor side; use the link below to register or contact the administrator if your password needs to be reset.'**
  String get authDescPrimary;

  /// No description provided for @authDescFallback.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your existing account. Account creation and password resets have moved to the Casdoor SSO; contact the administrator if you cannot sign in.'**
  String get authDescFallback;

  /// No description provided for @authContinueCasdoor.
  ///
  /// In en, this message translates to:
  /// **'Continue with Casdoor SSO'**
  String get authContinueCasdoor;

  /// No description provided for @authSignUpCasdoor.
  ///
  /// In en, this message translates to:
  /// **'No account? Sign up via Casdoor'**
  String get authSignUpCasdoor;

  /// No description provided for @authHideFallback.
  ///
  /// In en, this message translates to:
  /// **'Hide email / password fallback'**
  String get authHideFallback;

  /// No description provided for @authUseEmailPassword.
  ///
  /// In en, this message translates to:
  /// **'Use email / password instead'**
  String get authUseEmailPassword;

  /// No description provided for @authLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLogin;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password? Contact the administrator to reset it. Self-service password reset has moved to Casdoor for accounts that have been migrated.'**
  String get authForgotPassword;

  /// No description provided for @authEmailOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get authEmailOrUsername;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authSigningInTo.
  ///
  /// In en, this message translates to:
  /// **'Signing in to {host}'**
  String authSigningInTo(String host);

  /// No description provided for @authWorking.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get authWorking;

  /// No description provided for @authPhaseSending.
  ///
  /// In en, this message translates to:
  /// **'Sending request to backend'**
  String get authPhaseSending;

  /// No description provided for @authPhaseWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for backend response'**
  String get authPhaseWaiting;

  /// No description provided for @authPhaseApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying response'**
  String get authPhaseApplying;

  /// No description provided for @linkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link Casdoor identity'**
  String get linkTitle;

  /// No description provided for @linkSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Casdoor signed you in as:'**
  String get linkSignedInAs;

  /// No description provided for @linkChooseIntro.
  ///
  /// In en, this message translates to:
  /// **'This Casdoor identity is not yet linked to a Notechondria account. Choose how you want to proceed:'**
  String get linkChooseIntro;

  /// No description provided for @linkBindButton.
  ///
  /// In en, this message translates to:
  /// **'Bind to my existing account'**
  String get linkBindButton;

  /// No description provided for @linkBindDesc.
  ///
  /// In en, this message translates to:
  /// **'You already have a Notechondria account. Sign in once with your legacy username/email + password to link this Casdoor identity to it. After linking, future Casdoor sign-ins land on the same account.'**
  String get linkBindDesc;

  /// No description provided for @linkCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create a new Notechondria account'**
  String get linkCreateButton;

  /// No description provided for @linkCreateDesc.
  ///
  /// In en, this message translates to:
  /// **'No prior Notechondria account. Pick a password — your new account will be created with the username and email shown above. The same password works for the email/password fallback path when Casdoor is unreachable.'**
  String get linkCreateDesc;

  /// No description provided for @linkBindPaneDesc.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your existing Notechondria account once so we can link it to this Casdoor identity. Username or email + the password you set previously.'**
  String get linkBindPaneDesc;

  /// No description provided for @linkUsernameOrEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Notechondria username or email'**
  String get linkUsernameOrEmailLabel;

  /// No description provided for @linkPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Notechondria password'**
  String get linkPasswordLabel;

  /// No description provided for @linkCreatePaneDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick a password for your new Notechondria account. Casdoor will keep handling SSO; the password is for the legacy email/password fallback (when auth.trance-0.com is unreachable).'**
  String get linkCreatePaneDesc;

  /// No description provided for @linkNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get linkNewPasswordLabel;

  /// No description provided for @linkConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get linkConfirmPasswordLabel;

  /// No description provided for @linkBindAction.
  ///
  /// In en, this message translates to:
  /// **'Bind account'**
  String get linkBindAction;

  /// No description provided for @linkCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get linkCreateAction;

  /// No description provided for @linkErrBindRequired.
  ///
  /// In en, this message translates to:
  /// **'Both username/email and password are required to bind.'**
  String get linkErrBindRequired;

  /// No description provided for @linkErrPasswordShort.
  ///
  /// In en, this message translates to:
  /// **'Pick a password of 8 characters or more.'**
  String get linkErrPasswordShort;

  /// No description provided for @linkErrPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match. Re-type the same password in both fields.'**
  String get linkErrPasswordMismatch;

  /// No description provided for @clearAllLocalDataTile.
  ///
  /// In en, this message translates to:
  /// **'Clear all local data'**
  String get clearAllLocalDataTile;

  /// No description provided for @clearAllLocalDataTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wipes drafts, categories, settings, and logs from this device. Cloud copies are not touched.'**
  String get clearAllLocalDataTileSubtitle;

  /// No description provided for @clearAllLocalDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear all local data?'**
  String get clearAllLocalDataTitle;

  /// No description provided for @clearAllLocalDataMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes every local draft and local category from this device. Notes already synced to the cloud are not affected.'**
  String get clearAllLocalDataMessage;

  /// No description provided for @clearAllLocalDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllLocalDataConfirm;

  /// No description provided for @tourEditorWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Notechondria Editor'**
  String get tourEditorWelcomeTitle;

  /// No description provided for @tourEditorWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Write markdown notes that work offline and sync to the cloud when you sign in.'**
  String get tourEditorWelcomeBody;

  /// No description provided for @tourEditorCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Organize with categories'**
  String get tourEditorCategoriesTitle;

  /// No description provided for @tourEditorCategoriesBody.
  ///
  /// In en, this message translates to:
  /// **'Group notes into categories from the sidebar. Notes without one stay in your Inbox.'**
  String get tourEditorCategoriesBody;

  /// No description provided for @tourEditorSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Yours, on every device'**
  String get tourEditorSyncTitle;

  /// No description provided for @tourEditorSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Notes save on this device as you type. Sign in to back them up and sync across devices.'**
  String get tourEditorSyncBody;

  /// No description provided for @tourEditorToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings & tools'**
  String get tourEditorToolsTitle;

  /// No description provided for @tourEditorToolsBody.
  ///
  /// In en, this message translates to:
  /// **'Themes, sync, import/export, and the debug log live in Settings. On phones, open the menu from the top-left.'**
  String get tourEditorToolsBody;

  /// No description provided for @tourPlannerWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Notechondria Planner'**
  String get tourPlannerWelcomeTitle;

  /// No description provided for @tourPlannerWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Track courses, deadlines, and your study activity in one place.'**
  String get tourPlannerWelcomeBody;

  /// No description provided for @tourPlannerCoursesTitle.
  ///
  /// In en, this message translates to:
  /// **'Courses & deadlines'**
  String get tourPlannerCoursesTitle;

  /// No description provided for @tourPlannerCoursesBody.
  ///
  /// In en, this message translates to:
  /// **'Add courses and planner events; upcoming deadlines surface on your dashboard.'**
  String get tourPlannerCoursesBody;

  /// No description provided for @tourPlannerAnywhereTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan anywhere'**
  String get tourPlannerAnywhereTitle;

  /// No description provided for @tourPlannerAnywhereBody.
  ///
  /// In en, this message translates to:
  /// **'Works offline. Sign in to sync your plan across devices.'**
  String get tourPlannerAnywhereBody;

  /// No description provided for @tourPlannerToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings & tools'**
  String get tourPlannerToolsTitle;

  /// No description provided for @tourPlannerToolsBody.
  ///
  /// In en, this message translates to:
  /// **'Themes, sync, and tools live in Settings. On phones, open the menu from the top-left.'**
  String get tourPlannerToolsBody;

  /// No description provided for @tourPortalWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Notechondria'**
  String get tourPortalWelcomeTitle;

  /// No description provided for @tourPortalWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Your hub for notes, planning, and public courses.'**
  String get tourPortalWelcomeBody;

  /// No description provided for @tourPortalExploreTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore public notes'**
  String get tourPortalExploreTitle;

  /// No description provided for @tourPortalExploreBody.
  ///
  /// In en, this message translates to:
  /// **'Browse public courses and notes right from the front page.'**
  String get tourPortalExploreBody;

  /// No description provided for @tourPortalAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Open the apps'**
  String get tourPortalAppsTitle;

  /// No description provided for @tourPortalAppsBody.
  ///
  /// In en, this message translates to:
  /// **'Jump into the Editor or Planner anytime. Sign in to sync your own work.'**
  String get tourPortalAppsBody;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. Try again.'**
  String get errorTimeout;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'The server hit an error. Try again in a moment.'**
  String get errorServer;

  /// No description provided for @versionUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A new version is available. Refresh to update.'**
  String get versionUpdateAvailable;

  /// No description provided for @versionDeploying.
  ///
  /// In en, this message translates to:
  /// **'A new version is rolling out — some features may be briefly unavailable.'**
  String get versionDeploying;

  /// No description provided for @versionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This app version is no longer supported. Refresh to update.'**
  String get versionUnsupported;

  /// No description provided for @versionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get versionRefresh;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
