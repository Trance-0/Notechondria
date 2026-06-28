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

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Notechondria'**
  String get appName;

  /// No description provided for @appNameEditor.
  ///
  /// In en, this message translates to:
  /// **'Notechondria Editor'**
  String get appNameEditor;

  /// No description provided for @appNamePlanner.
  ///
  /// In en, this message translates to:
  /// **'Notechondria Planner'**
  String get appNamePlanner;

  /// No description provided for @appNamePortal.
  ///
  /// In en, this message translates to:
  /// **'Notechondria Portal'**
  String get appNamePortal;

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

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @splashStartingEditor.
  ///
  /// In en, this message translates to:
  /// **'Starting Notechondria Editor'**
  String get splashStartingEditor;

  /// No description provided for @splashStartingPlanner.
  ///
  /// In en, this message translates to:
  /// **'Starting Notechondria Planner'**
  String get splashStartingPlanner;

  /// No description provided for @splashStartingPortal.
  ///
  /// In en, this message translates to:
  /// **'Starting Notechondria Portal'**
  String get splashStartingPortal;

  /// No description provided for @splashLoadingLocalWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Loading local workspace'**
  String get splashLoadingLocalWorkspace;

  /// No description provided for @splashLoadingLocalPlannerData.
  ///
  /// In en, this message translates to:
  /// **'Loading local planner data'**
  String get splashLoadingLocalPlannerData;

  /// No description provided for @splashLoadingLocalState.
  ///
  /// In en, this message translates to:
  /// **'Loading local state'**
  String get splashLoadingLocalState;

  /// No description provided for @splashRestoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring session'**
  String get splashRestoringSession;

  /// No description provided for @splashCompletingSignIn.
  ///
  /// In en, this message translates to:
  /// **'Completing sign-in'**
  String get splashCompletingSignIn;

  /// No description provided for @splashConnectingToServer.
  ///
  /// In en, this message translates to:
  /// **'Connecting to server'**
  String get splashConnectingToServer;

  /// No description provided for @splashLoadingPublicNotesData.
  ///
  /// In en, this message translates to:
  /// **'Loading public notes data'**
  String get splashLoadingPublicNotesData;

  /// No description provided for @splashLoadingCategories.
  ///
  /// In en, this message translates to:
  /// **'Loading categories'**
  String get splashLoadingCategories;

  /// No description provided for @splashLoadingNotes.
  ///
  /// In en, this message translates to:
  /// **'Loading notes'**
  String get splashLoadingNotes;

  /// No description provided for @localArchiveTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Notechondria archive'**
  String get localArchiveTypeLabel;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get commonSaving;

  /// No description provided for @commonUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get commonUploading;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get commonUnknown;

  /// No description provided for @commonUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get commonUser;

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

  /// No description provided for @navFrontPage.
  ///
  /// In en, this message translates to:
  /// **'Front page'**
  String get navFrontPage;

  /// No description provided for @navLearner.
  ///
  /// In en, this message translates to:
  /// **'Learner'**
  String get navLearner;

  /// No description provided for @navCourse.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get navCourse;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

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
  /// **'Private'**
  String get feedScopePrivate;

  /// No description provided for @feedScopePublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
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

  /// No description provided for @feedImportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Import markdown'**
  String get feedImportMarkdown;

  /// No description provided for @feedSearchCloud.
  ///
  /// In en, this message translates to:
  /// **'Search your cloud notes'**
  String get feedSearchCloud;

  /// No description provided for @feedSyncToCloud.
  ///
  /// In en, this message translates to:
  /// **'Sync to cloud'**
  String get feedSyncToCloud;

  /// No description provided for @feedLoadNotes.
  ///
  /// In en, this message translates to:
  /// **'Load notes'**
  String get feedLoadNotes;

  /// No description provided for @feedLocalDraftBadge.
  ///
  /// In en, this message translates to:
  /// **'Local draft'**
  String get feedLocalDraftBadge;

  /// No description provided for @feedBadgePublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get feedBadgePublic;

  /// No description provided for @feedBadgePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get feedBadgePrivate;

  /// No description provided for @feedScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get feedScopeAll;

  /// No description provided for @feedSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get feedSortNewest;

  /// No description provided for @feedSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get feedSortOldest;

  /// No description provided for @feedSortPopular.
  ///
  /// In en, this message translates to:
  /// **'Most popular'**
  String get feedSortPopular;

  /// No description provided for @feedWindow3Days.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get feedWindow3Days;

  /// No description provided for @feedWindow1Week.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get feedWindow1Week;

  /// No description provided for @feedWindow1Month.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get feedWindow1Month;

  /// No description provided for @feedWindow1Year.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get feedWindow1Year;

  /// No description provided for @feedWindowAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get feedWindowAllTime;

  /// No description provided for @feedFilterScope.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get feedFilterScope;

  /// No description provided for @feedFilterSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get feedFilterSort;

  /// No description provided for @feedFilterWindow.
  ///
  /// In en, this message translates to:
  /// **'Within'**
  String get feedFilterWindow;

  /// No description provided for @feedEmptyCloudSynced.
  ///
  /// In en, this message translates to:
  /// **'No synced cloud notes yet. Sync a local draft or create a new note.'**
  String get feedEmptyCloudSynced;

  /// No description provided for @feedEmptyLocalLogin.
  ///
  /// In en, this message translates to:
  /// **'No local drafts yet. Use the add button to create one and sync later after login.'**
  String get feedEmptyLocalLogin;

  /// No description provided for @feedCourseMetaHint.
  ///
  /// In en, this message translates to:
  /// **'Course metadata stays editable from the editor details panel'**
  String get feedCourseMetaHint;

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

  /// No description provided for @noteMetaCoverImage.
  ///
  /// In en, this message translates to:
  /// **'Cover image'**
  String get noteMetaCoverImage;

  /// No description provided for @noteMetaCoverHasHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown above the note in view mode.'**
  String get noteMetaCoverHasHelp;

  /// No description provided for @noteMetaCoverNoneHelp.
  ///
  /// In en, this message translates to:
  /// **'No cover yet — readers see a barcode generated from the note URL.'**
  String get noteMetaCoverNoneHelp;

  /// No description provided for @noteMetaCoverSyncFirst.
  ///
  /// In en, this message translates to:
  /// **'Sync this note to the cloud before uploading a cover image.'**
  String get noteMetaCoverSyncFirst;

  /// No description provided for @noteMetaReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get noteMetaReplace;

  /// No description provided for @noteMetaUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get noteMetaUpload;

  /// No description provided for @noteMetaDetails.
  ///
  /// In en, this message translates to:
  /// **'Note details'**
  String get noteMetaDetails;

  /// No description provided for @noteMetaNoCourse.
  ///
  /// In en, this message translates to:
  /// **'No assigned course'**
  String get noteMetaNoCourse;

  /// No description provided for @noteMetaAssignedCourse.
  ///
  /// In en, this message translates to:
  /// **'Assigned course / plan'**
  String get noteMetaAssignedCourse;

  /// No description provided for @noteMetaSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get noteMetaSection;

  /// No description provided for @noteMetaDescription.
  ///
  /// In en, this message translates to:
  /// **'Short description / comments'**
  String get noteMetaDescription;

  /// No description provided for @noteMetaPublicNote.
  ///
  /// In en, this message translates to:
  /// **'Public note'**
  String get noteMetaPublicNote;

  /// No description provided for @noteMetaPublicHelp.
  ///
  /// In en, this message translates to:
  /// **'Public notes appear in the recommendation feed.'**
  String get noteMetaPublicHelp;

  /// No description provided for @noteMetaPublicSyncFirst.
  ///
  /// In en, this message translates to:
  /// **'Sync this note to the cloud before making it public.'**
  String get noteMetaPublicSyncFirst;

  /// No description provided for @noteMetaVersionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get noteMetaVersionHistory;

  /// No description provided for @noteMetaNoVersions.
  ///
  /// In en, this message translates to:
  /// **'No saved versions yet.'**
  String get noteMetaNoVersions;

  /// No description provided for @noteMetaSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get noteMetaSaving;

  /// No description provided for @editorBlockParagraph.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get editorBlockParagraph;

  /// No description provided for @editorBlockHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get editorBlockHeading;

  /// No description provided for @editorBlockList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get editorBlockList;

  /// No description provided for @editorBlockCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get editorBlockCode;

  /// No description provided for @editorBlockQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get editorBlockQuote;

  /// No description provided for @editorBlockLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get editorBlockLink;

  /// No description provided for @editorBlockImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get editorBlockImage;

  /// No description provided for @editorBlockDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete block'**
  String get editorBlockDelete;

  /// No description provided for @editorBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get editorBold;

  /// No description provided for @editorItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get editorItalic;

  /// No description provided for @editorStrike.
  ///
  /// In en, this message translates to:
  /// **'Strike'**
  String get editorStrike;

  /// No description provided for @editorAddParagraph.
  ///
  /// In en, this message translates to:
  /// **'Add paragraph'**
  String get editorAddParagraph;

  /// No description provided for @editorAddList.
  ///
  /// In en, this message translates to:
  /// **'Add list'**
  String get editorAddList;

  /// No description provided for @editorAddCode.
  ///
  /// In en, this message translates to:
  /// **'Add code'**
  String get editorAddCode;

  /// No description provided for @editorHeadingTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Heading token (## or ###)'**
  String get editorHeadingTokenHint;

  /// No description provided for @editorBlockContentHint.
  ///
  /// In en, this message translates to:
  /// **'Write block content...'**
  String get editorBlockContentHint;

  /// No description provided for @editorModePlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get editorModePlain;

  /// No description provided for @editorModePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get editorModePreview;

  /// No description provided for @editorModeBlocks.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get editorModeBlocks;

  /// No description provided for @editorModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Editor mode'**
  String get editorModeLabel;

  /// No description provided for @editorNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get editorNotSaved;

  /// No description provided for @editorSavedAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {time}'**
  String editorSavedAt(String time);

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

  /// No description provided for @settingsDevRestoreTemplatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore remote template courses'**
  String get settingsDevRestoreTemplatesTitle;

  /// No description provided for @settingsDevRestoreTemplatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Admin-only. Calls the backend to re-seed the three-course template catalog (Inbox / Examples / Templates) with a welcome note in each.'**
  String get settingsDevRestoreTemplatesSubtitle;

  /// No description provided for @settingsDevImportJournalTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Apple Journal ZIP'**
  String get settingsDevImportJournalTitle;

  /// No description provided for @settingsDevImportJournalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Experimental local-only import. Creates local drafts in a selected category; cloud sync waits for a manual push.'**
  String get settingsDevImportJournalSubtitle;

  /// No description provided for @settingsDevClearLegacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear legacy shared storage'**
  String get settingsDevClearLegacyTitle;

  /// No description provided for @settingsDevClearLegacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Removes the pre-0.1.127 unprefixed browser-storage keys left behind when the apps moved to per-app namespaces. Shared across editor / planner / portal; your current notes and settings are unaffected.'**
  String get settingsDevClearLegacySubtitle;

  /// No description provided for @settingsDevCaption.
  ///
  /// In en, this message translates to:
  /// **'Requires a signed-in admin account. Non-admin sessions will see a server-side error in the banner above without changing any data.'**
  String get settingsDevCaption;

  /// No description provided for @settingsRestoreStarterTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore starter draft'**
  String get settingsRestoreStarterTitle;

  /// No description provided for @settingsRestoreStarterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-seeds the welcome draft in the uncategorized bucket. Safe to run any time — only fires when no notes exist locally.'**
  String get settingsRestoreStarterSubtitle;

  /// No description provided for @settingsLegacyTemplateCaption.
  ///
  /// In en, this message translates to:
  /// **'The legacy three-course template restore (admin-only, requires a cloud session) is now in the Developer section of the main Settings page.'**
  String get settingsLegacyTemplateCaption;

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

  /// No description provided for @settingsPortalPreferences.
  ///
  /// In en, this message translates to:
  /// **'Portal preferences'**
  String get settingsPortalPreferences;

  /// No description provided for @settingsPortalPreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme preset, theme mode, default editor.'**
  String get settingsPortalPreferencesSubtitle;

  /// No description provided for @settingsConnectedAccounts.
  ///
  /// In en, this message translates to:
  /// **'Connected accounts'**
  String get settingsConnectedAccounts;

  /// No description provided for @settingsPersonalInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Avatar, username, motto, social link.'**
  String get settingsPersonalInfoSubtitle;

  /// No description provided for @settingsSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Active sessions, change email, change password, agent skill.'**
  String get settingsSecuritySubtitle;

  /// No description provided for @settingsApiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'API base URL and MCP key.'**
  String get settingsApiSubtitle;

  /// No description provided for @settingsManageAccountPreferences.
  ///
  /// In en, this message translates to:
  /// **'Manage your account, preferences, and local data.'**
  String get settingsManageAccountPreferences;

  /// No description provided for @settingsLocalOnlyPreferences.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync to the cloud, or keep using local-only preferences below.'**
  String get settingsLocalOnlyPreferences;

  /// No description provided for @settingsCasdoorLinked.
  ///
  /// In en, this message translates to:
  /// **'Casdoor SSO linked.'**
  String get settingsCasdoorLinked;

  /// No description provided for @settingsNoThirdPartyLinked.
  ///
  /// In en, this message translates to:
  /// **'No third-party accounts linked.'**
  String get settingsNoThirdPartyLinked;

  /// No description provided for @settingsBackendOnlineSummary.
  ///
  /// In en, this message translates to:
  /// **'Online. API URL: {url}'**
  String settingsBackendOnlineSummary(String url);

  /// No description provided for @settingsBackendOfflineSummary.
  ///
  /// In en, this message translates to:
  /// **'Offline mode is on. API URL: {url}'**
  String settingsBackendOfflineSummary(String url);

  /// No description provided for @settingsLocalDataSummary.
  ///
  /// In en, this message translates to:
  /// **'{drafts} draft(s), {courses} course(s) on this device.'**
  String settingsLocalDataSummary(int drafts, int courses);

  /// No description provided for @settingsRecycleBinSummary.
  ///
  /// In en, this message translates to:
  /// **'{drafts} synced draft(s) recoverable, {notes} cloud note(s) trashed.'**
  String settingsRecycleBinSummary(int drafts, int notes);

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsChangeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get settingsChangeAvatar;

  /// No description provided for @settingsUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get settingsUsername;

  /// No description provided for @settingsFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get settingsFirstName;

  /// No description provided for @settingsLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get settingsLastName;

  /// No description provided for @settingsMotto.
  ///
  /// In en, this message translates to:
  /// **'Motto'**
  String get settingsMotto;

  /// No description provided for @settingsSocialLink.
  ///
  /// In en, this message translates to:
  /// **'Social link'**
  String get settingsSocialLink;

  /// No description provided for @settingsSocialLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'Must be a valid URL (https://...)'**
  String get settingsSocialLinkInvalid;

  /// No description provided for @settingsUncategorizedFolderName.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized folder name'**
  String get settingsUncategorizedFolderName;

  /// No description provided for @settingsUncategorizedFolderHelp.
  ///
  /// In en, this message translates to:
  /// **'Label for the bucket that holds notes with no category. Blank falls back to \"Inbox\".'**
  String get settingsUncategorizedFolderHelp;

  /// No description provided for @settingsAccountCasdoorNotice.
  ///
  /// In en, this message translates to:
  /// **'Account creation, password change, email change, and per-device session management live on the Casdoor user portal. Casdoor bind / unlink controls are on the Account page.'**
  String get settingsAccountCasdoorNotice;

  /// No description provided for @settingsApiBaseLockedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Locked while signed in. Sign out to switch the backend the portal talks to.'**
  String get settingsApiBaseLockedTooltip;

  /// No description provided for @settingsApiBaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Points the portal at a different Notechondria backend.'**
  String get settingsApiBaseTooltip;

  /// No description provided for @settingsEditorApiBaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Points the editor at a different Notechondria backend. The handshake probe verifies the URL before saving.'**
  String get settingsEditorApiBaseTooltip;

  /// No description provided for @settingsApiBaseApplyCaption.
  ///
  /// In en, this message translates to:
  /// **'Press Enter to apply the URL change. Stored locally and mirrored to the profile on login.'**
  String get settingsApiBaseApplyCaption;

  /// No description provided for @settingsApiBaseApplyLockedCaption.
  ///
  /// In en, this message translates to:
  /// **'Press Enter to apply the URL change. Stored locally and mirrored to your profile on login. Locked while signed in — sign out to switch backends.'**
  String get settingsApiBaseApplyLockedCaption;

  /// No description provided for @settingsMcpKeyCaption.
  ///
  /// In en, this message translates to:
  /// **'The MCP key authenticates the backend Model Context Protocol bridge. Rotate it if you suspect leakage.'**
  String get settingsMcpKeyCaption;

  /// No description provided for @settingsConnectedAccountsCaption.
  ///
  /// In en, this message translates to:
  /// **'Casdoor proxies third-party identities (Google, GitHub, etc.) — configure them on the Casdoor application\'s Providers tab.'**
  String get settingsConnectedAccountsCaption;

  /// No description provided for @plannerSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Planner settings'**
  String get plannerSettingsTitle;

  /// No description provided for @plannerSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'This app keeps planner-focused controls only: login/sync, deadline-ordering preferences, and debug output.'**
  String get plannerSettingsDescription;

  /// No description provided for @plannerLoginSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Login and sync'**
  String get plannerLoginSyncTitle;

  /// No description provided for @plannerLoginSyncHelp.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync course plans, module discussion roots, and planner deadlines. Local planner data remains usable while signed out.'**
  String get plannerLoginSyncHelp;

  /// No description provided for @plannerSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {identity}.'**
  String plannerSignedInAs(String identity);

  /// No description provided for @plannerPreferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Planner preferences'**
  String get plannerPreferencesTitle;

  /// No description provided for @plannerDeadlineTimeWeight.
  ///
  /// In en, this message translates to:
  /// **'Deadline time weight (a)'**
  String get plannerDeadlineTimeWeight;

  /// No description provided for @plannerDeadlineImportanceWeight.
  ///
  /// In en, this message translates to:
  /// **'Deadline importance weight (b)'**
  String get plannerDeadlineImportanceWeight;

  /// No description provided for @plannerDeadlineSortHelp.
  ///
  /// In en, this message translates to:
  /// **'Deadlines sort by (a × time pressure) × (b × importance). Importance uses the existing event weight.'**
  String get plannerDeadlineSortHelp;

  /// No description provided for @plannerSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save planner settings'**
  String get plannerSaveSettings;

  /// No description provided for @plannerDebugSummary.
  ///
  /// In en, this message translates to:
  /// **'{notes} local note(s), {courses} local course(s).'**
  String plannerDebugSummary(int notes, int courses);

  /// No description provided for @settingsThemeModeMatchSystem.
  ///
  /// In en, this message translates to:
  /// **'Match system'**
  String get settingsThemeModeMatchSystem;

  /// No description provided for @settingsEditorModePickerHelp.
  ///
  /// In en, this message translates to:
  /// **'Picks how new notes open by default. You can still switch modes per note from the editor toolbar.'**
  String get settingsEditorModePickerHelp;

  /// No description provided for @settingsThemePresetPickerHelp.
  ///
  /// In en, this message translates to:
  /// **'Each preset uses a different seed color for the Material 3 ColorScheme.'**
  String get settingsThemePresetPickerHelp;

  /// No description provided for @settingsThemeModePickerHelp.
  ///
  /// In en, this message translates to:
  /// **'Match system follows the device-level Light/Dark toggle. Light and Dark override the system choice.'**
  String get settingsThemeModePickerHelp;

  /// No description provided for @settingsOfflineModeSubtitleShort.
  ///
  /// In en, this message translates to:
  /// **'Skip every remote fetch on startup; render everything from the local cache.'**
  String get settingsOfflineModeSubtitleShort;

  /// No description provided for @settingsLocalDataCounts.
  ///
  /// In en, this message translates to:
  /// **'{drafts} local draft(s), {courses} local course(s).'**
  String settingsLocalDataCounts(int drafts, int courses);

  /// No description provided for @settingsDownloadLocalData.
  ///
  /// In en, this message translates to:
  /// **'Download local data'**
  String get settingsDownloadLocalData;

  /// No description provided for @settingsDownloadLocalDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exports drafts, courses, settings, and logs as a .nchron archive.'**
  String get settingsDownloadLocalDataSubtitle;

  /// No description provided for @settingsRestoreLocalArchive.
  ///
  /// In en, this message translates to:
  /// **'Restore from local archive'**
  String get settingsRestoreLocalArchive;

  /// No description provided for @settingsRestoreLocalArchiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Imports a previously-exported .nchron archive. Replaces existing local data after a confirm dialog.'**
  String get settingsRestoreLocalArchiveSubtitle;

  /// No description provided for @settingsPushLocalCloud.
  ///
  /// In en, this message translates to:
  /// **'Push local → cloud'**
  String get settingsPushLocalCloud;

  /// No description provided for @settingsPushLocalCloudSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload local drafts and courses to your cloud account. Requires sign-in.'**
  String get settingsPushLocalCloudSubtitle;

  /// No description provided for @settingsPullCloudLocal.
  ///
  /// In en, this message translates to:
  /// **'Pull cloud → local'**
  String get settingsPullCloudLocal;

  /// No description provided for @settingsPullCloudLocalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download notes and courses from the cloud to this device.'**
  String get settingsPullCloudLocalSubtitle;

  /// No description provided for @settingsClearLocalCache.
  ///
  /// In en, this message translates to:
  /// **'Clear local cache'**
  String get settingsClearLocalCache;

  /// No description provided for @settingsClearLocalCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drops cached API responses but keeps drafts and courses on disk.'**
  String get settingsClearLocalCacheSubtitle;

  /// No description provided for @settingsRemoveLocalData.
  ///
  /// In en, this message translates to:
  /// **'Remove local data'**
  String get settingsRemoveLocalData;

  /// No description provided for @settingsRemoveLocalDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wipes drafts, courses, settings, and logs from this device. Cloud copies are not touched.'**
  String get settingsRemoveLocalDataSubtitle;

  /// No description provided for @settingsRestoreTemplateCourses.
  ///
  /// In en, this message translates to:
  /// **'Restore template courses'**
  String get settingsRestoreTemplateCourses;

  /// No description provided for @settingsRestoreTemplateCoursesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Admin-only. Re-seeds the three-course template catalog (Inbox / Examples / Templates).'**
  String get settingsRestoreTemplateCoursesSubtitle;

  /// No description provided for @settingsRestoreTemplateCoursesCaption.
  ///
  /// In en, this message translates to:
  /// **'Requires a signed-in admin account. Non-admin sessions will see a server-side error in the banner above without changing any data.'**
  String get settingsRestoreTemplateCoursesCaption;

  /// No description provided for @settingsSyncedLocalDrafts.
  ///
  /// In en, this message translates to:
  /// **'Synced local drafts'**
  String get settingsSyncedLocalDrafts;

  /// No description provided for @settingsLocalRecycleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) waiting in the local recycle bin.'**
  String settingsLocalRecycleCount(int count);

  /// No description provided for @settingsCloudRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Cloud recycle bin'**
  String get settingsCloudRecycleBin;

  /// No description provided for @settingsCloudRecycleCount.
  ///
  /// In en, this message translates to:
  /// **'{count} soft-deleted note(s) on the server.'**
  String settingsCloudRecycleCount(int count);

  /// No description provided for @settingsCloudRecycleSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage deleted cloud notes.'**
  String get settingsCloudRecycleSignIn;

  /// No description provided for @settingsRecycleBinEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin is empty.'**
  String get settingsRecycleBinEmpty;

  /// No description provided for @settingsEmptyRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Empty recycle bin'**
  String get settingsEmptyRecycleBin;

  /// No description provided for @apiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKeyTitle;

  /// No description provided for @apiKeyNoKey.
  ///
  /// In en, this message translates to:
  /// **'(no API key — click Generate to create one)'**
  String get apiKeyNoKey;

  /// No description provided for @apiKeyRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get apiKeyRotate;

  /// No description provided for @apiKeyGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get apiKeyGenerate;

  /// No description provided for @apiKeyCopyNow.
  ///
  /// In en, this message translates to:
  /// **'Copy this key now — it will NOT be shown again:'**
  String get apiKeyCopyNow;

  /// No description provided for @apiKeySavedIt.
  ///
  /// In en, this message translates to:
  /// **'I have saved it'**
  String get apiKeySavedIt;

  /// No description provided for @apiKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'API key copied to clipboard.'**
  String get apiKeyCopied;

  /// No description provided for @apiKeyMcpEndpointCopied.
  ///
  /// In en, this message translates to:
  /// **'MCP endpoint copied to clipboard.'**
  String get apiKeyMcpEndpointCopied;

  /// No description provided for @apiKeyRotateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to rotate API key: Portal.Settings/api_key.rotate — {error}'**
  String apiKeyRotateFailed(String error);

  /// No description provided for @apiKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Use this key with MCP clients (e.g. Claude Desktop) by setting the Authorization header to \"Bearer ntc_<key>\".'**
  String get apiKeyHelp;

  /// No description provided for @apiKeyMcpEndpoint.
  ///
  /// In en, this message translates to:
  /// **'MCP endpoint:'**
  String get apiKeyMcpEndpoint;

  /// No description provided for @apiKeyCopyMcpEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Copy MCP endpoint'**
  String get apiKeyCopyMcpEndpoint;

  /// No description provided for @connectedAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected accounts'**
  String get connectedAccountsTitle;

  /// No description provided for @connectedAccountsShadow.
  ///
  /// In en, this message translates to:
  /// **'Casdoor is in shadow mode on this backend; no third-party accounts can be linked.'**
  String get connectedAccountsShadow;

  /// No description provided for @connectedAccountsManageCasdoor.
  ///
  /// In en, this message translates to:
  /// **'Manage Casdoor account'**
  String get connectedAccountsManageCasdoor;

  /// No description provided for @connectedAccountsUnavailableHelp.
  ///
  /// In en, this message translates to:
  /// **'If sign-in is unavailable, contact your Notechondria admin (Casdoor backend may be off).'**
  String get connectedAccountsUnavailableHelp;

  /// No description provided for @connectedAccountsCasdoorSso.
  ///
  /// In en, this message translates to:
  /// **'Casdoor SSO'**
  String get connectedAccountsCasdoorSso;

  /// No description provided for @connectedAccountsLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get connectedAccountsLinked;

  /// No description provided for @connectedAccountsNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get connectedAccountsNotLinked;

  /// No description provided for @connectedAccountsSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get connectedAccountsSwitch;

  /// No description provided for @connectedAccountsUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get connectedAccountsUnlink;

  /// No description provided for @connectedAccountsLinkCasdoor.
  ///
  /// In en, this message translates to:
  /// **'Link Casdoor'**
  String get connectedAccountsLinkCasdoor;

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

  /// No description provided for @editorDebugSummary.
  ///
  /// In en, this message translates to:
  /// **'{drafts} local draft(s), {categories} local category(ies).'**
  String editorDebugSummary(int drafts, int categories);

  /// No description provided for @editorLocalAttachments.
  ///
  /// In en, this message translates to:
  /// **'Local attachments: {size}'**
  String editorLocalAttachments(String size);

  /// No description provided for @editorAttachmentsOverLimit.
  ///
  /// In en, this message translates to:
  /// **'Attachments exceed 500 MB — sync to free up space.'**
  String get editorAttachmentsOverLimit;

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

  /// No description provided for @errorWorkOffline.
  ///
  /// In en, this message translates to:
  /// **'Work offline'**
  String get errorWorkOffline;

  /// No description provided for @frontWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back, {name}'**
  String frontWelcomeBack(String name);

  /// No description provided for @frontWelcomeGuest.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Notechondria'**
  String get frontWelcomeGuest;

  /// No description provided for @frontGreetingGuest.
  ///
  /// In en, this message translates to:
  /// **'guest'**
  String get frontGreetingGuest;

  /// No description provided for @frontHeroAuth.
  ///
  /// In en, this message translates to:
  /// **'Your notes, courses and schedule at a glance. Pick a course below or jump into the learner/planner workspaces.'**
  String get frontHeroAuth;

  /// No description provided for @frontHeroAnon.
  ///
  /// In en, this message translates to:
  /// **'Discover public courses and notes, or sign in to unlock your learner dashboard and heatmap.'**
  String get frontHeroAnon;

  /// No description provided for @frontRecentCourses.
  ///
  /// In en, this message translates to:
  /// **'Recent public courses'**
  String get frontRecentCourses;

  /// No description provided for @frontNoCourses.
  ///
  /// In en, this message translates to:
  /// **'No public courses yet.'**
  String get frontNoCourses;

  /// No description provided for @frontActivityHeatmap.
  ///
  /// In en, this message translates to:
  /// **'Activity heatmap'**
  String get frontActivityHeatmap;

  /// No description provided for @frontHeatmapLegend.
  ///
  /// In en, this message translates to:
  /// **'Past activity (blue) and upcoming planner load (teal).'**
  String get frontHeatmapLegend;

  /// No description provided for @frontRecentNotes.
  ///
  /// In en, this message translates to:
  /// **'Recent public notes'**
  String get frontRecentNotes;

  /// No description provided for @courseCreateLocal.
  ///
  /// In en, this message translates to:
  /// **'Create local course'**
  String get courseCreateLocal;

  /// No description provided for @courseTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Course title'**
  String get courseTitleLabel;

  /// No description provided for @courseDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get courseDescriptionLabel;

  /// No description provided for @courseSyncLocalData.
  ///
  /// In en, this message translates to:
  /// **'Sync local data'**
  String get courseSyncLocalData;

  /// No description provided for @courseBackTo.
  ///
  /// In en, this message translates to:
  /// **'Back to {title}'**
  String courseBackTo(String title);

  /// No description provided for @courseModuleDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Module discussion'**
  String get courseModuleDiscussion;

  /// No description provided for @courseBackToResults.
  ///
  /// In en, this message translates to:
  /// **'Back to course results'**
  String get courseBackToResults;

  /// No description provided for @courseSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get courseSubscribe;

  /// No description provided for @courseNoModules.
  ///
  /// In en, this message translates to:
  /// **'No modules have been mapped for this course yet.'**
  String get courseNoModules;

  /// No description provided for @courseDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Course discussion'**
  String get courseDiscussion;

  /// No description provided for @courseListTitle.
  ///
  /// In en, this message translates to:
  /// **'Course list'**
  String get courseListTitle;

  /// No description provided for @courseLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get courseLoadMore;

  /// No description provided for @activitySignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your deadlines, synced study sessions, and weekly calendar.'**
  String get activitySignInPrompt;

  /// No description provided for @activityNoWeekEvents.
  ///
  /// In en, this message translates to:
  /// **'No weekly events are available for the current view.'**
  String get activityNoWeekEvents;

  /// No description provided for @activityThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get activityThisWeek;

  /// No description provided for @activityPrevWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get activityPrevWeek;

  /// No description provided for @activityNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get activityNextWeek;

  /// No description provided for @activityZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get activityZoomIn;

  /// No description provided for @activityZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get activityZoomOut;

  /// No description provided for @activityRange3Day.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get activityRange3Day;

  /// No description provided for @activityRange1Week.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get activityRange1Week;

  /// No description provided for @activityRange1Month.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get activityRange1Month;

  /// No description provided for @activityCreateEvent.
  ///
  /// In en, this message translates to:
  /// **'Create event'**
  String get activityCreateEvent;

  /// No description provided for @activityImportIcal.
  ///
  /// In en, this message translates to:
  /// **'Import iCal'**
  String get activityImportIcal;

  /// No description provided for @activitySubscribeCalendar.
  ///
  /// In en, this message translates to:
  /// **'Subscribe calendar'**
  String get activitySubscribeCalendar;

  /// No description provided for @activityFabHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to create a new event. Long press or right click to import iCal or subscribe.'**
  String get activityFabHint;

  /// No description provided for @activityNoDeadlines.
  ///
  /// In en, this message translates to:
  /// **'No active deadlines yet. Use the add button to create one.'**
  String get activityNoDeadlines;

  /// No description provided for @activityNoUrgent.
  ///
  /// In en, this message translates to:
  /// **'No urgent deadlines remain in the current view.'**
  String get activityNoUrgent;

  /// No description provided for @activityWeekCalendar.
  ///
  /// In en, this message translates to:
  /// **'Week calendar'**
  String get activityWeekCalendar;

  /// No description provided for @activityNewEvent.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get activityNewEvent;

  /// No description provided for @activityEventTitle.
  ///
  /// In en, this message translates to:
  /// **'Event title'**
  String get activityEventTitle;

  /// No description provided for @activityDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get activityDifficulty;

  /// No description provided for @activityWeightN.
  ///
  /// In en, this message translates to:
  /// **'Weight {n}'**
  String activityWeightN(int n);

  /// No description provided for @activitySubscribeToCalendar.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to calendar'**
  String get activitySubscribeToCalendar;

  /// No description provided for @activityIcalUrl.
  ///
  /// In en, this message translates to:
  /// **'iCal URL'**
  String get activityIcalUrl;

  /// No description provided for @activitySubscribedCalendar.
  ///
  /// In en, this message translates to:
  /// **'Subscribed calendar'**
  String get activitySubscribedCalendar;

  /// No description provided for @mcpSkillCopied.
  ///
  /// In en, this message translates to:
  /// **'skill.md copied to clipboard.'**
  String get mcpSkillCopied;

  /// No description provided for @mcpSkillTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent skill (skill.md)'**
  String get mcpSkillTitle;

  /// No description provided for @mcpSkillDescription.
  ///
  /// In en, this message translates to:
  /// **'Personal playbook for MCP-connected agents. Use this to describe where to pull notes from (e.g. external sites like notenextra.trance-0.com), how to format imports, which files to export, and where to publish them. Sent verbatim as the `instructions` field of the MCP initialize response.'**
  String get mcpSkillDescription;

  /// No description provided for @mcpSkillHint.
  ///
  /// In en, this message translates to:
  /// **'# Import\n- Pull notes from notenextra.trance-0.com once a day...\n\n# Export\n- Mirror to GitHub Gist as YAML+markdown.\n\n# Format\n- Wrap math in \$...\$. Tag deadlines with #deadline.'**
  String get mcpSkillHint;

  /// No description provided for @mcpSkillUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'unsaved changes'**
  String get mcpSkillUnsavedChanges;

  /// No description provided for @githubSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Experimental — GitHub Sync'**
  String get githubSyncTitle;

  /// No description provided for @githubSyncDescription.
  ///
  /// In en, this message translates to:
  /// **'Push your full account (profile, settings, MCP skill, courses, notes, custom meta, planner events) to a GitHub repo you own so you can recover everything if our server is wiped. Static assets we host (avatars, attachments, cover images) are referenced by URL, not committed. See docs/integrations/github-sync.md for the full flow.'**
  String get githubSyncDescription;

  /// No description provided for @githubSyncInstall.
  ///
  /// In en, this message translates to:
  /// **'Install Notechondria GitHub App'**
  String get githubSyncInstall;

  /// No description provided for @githubSyncInstallHelp.
  ///
  /// In en, this message translates to:
  /// **'After approving the install, GitHub redirects back here and we persist your installation id automatically. The app stays installed until you remove it from your GitHub settings.'**
  String get githubSyncInstallHelp;

  /// No description provided for @githubSyncInstalled.
  ///
  /// In en, this message translates to:
  /// **'GitHub App installed.'**
  String get githubSyncInstalled;

  /// No description provided for @githubSyncInstalledOn.
  ///
  /// In en, this message translates to:
  /// **'GitHub App installed on @{account}.'**
  String githubSyncInstalledOn(String account);

  /// No description provided for @githubSyncNoRepos.
  ///
  /// In en, this message translates to:
  /// **'No repositories visible to this installation. Open GitHub settings → Applications → Notechondria data sync, and grant access to a repo.'**
  String get githubSyncNoRepos;

  /// No description provided for @githubSyncTargetRepo.
  ///
  /// In en, this message translates to:
  /// **'Sync target repository'**
  String get githubSyncTargetRepo;

  /// No description provided for @githubSyncIncludeAssets.
  ///
  /// In en, this message translates to:
  /// **'Include assets'**
  String get githubSyncIncludeAssets;

  /// No description provided for @githubSyncIncludeAssetsOn.
  ///
  /// In en, this message translates to:
  /// **'Avatar, cover images, and attachments are inlined under assets/. Subject to per-file (50 MB) and per-push (200 MB) caps.'**
  String get githubSyncIncludeAssetsOn;

  /// No description provided for @githubSyncIncludeAssetsOff.
  ///
  /// In en, this message translates to:
  /// **'Static assets stay referenced by URL only. Faster push, but a fresh server can\'t recover the bytes.'**
  String get githubSyncIncludeAssetsOff;

  /// No description provided for @githubSyncPushNow.
  ///
  /// In en, this message translates to:
  /// **'Push now'**
  String get githubSyncPushNow;

  /// No description provided for @githubSyncDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get githubSyncDisconnect;

  /// No description provided for @githubSyncLastPush.
  ///
  /// In en, this message translates to:
  /// **'Last push: {sha}'**
  String githubSyncLastPush(String sha);

  /// No description provided for @githubSyncLastPushAt.
  ///
  /// In en, this message translates to:
  /// **'Last push at {time}.'**
  String githubSyncLastPushAt(String time);

  /// No description provided for @githubSyncSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to enable GitHub Sync.'**
  String get githubSyncSignIn;

  /// No description provided for @githubSyncLoadStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot load GitHub Sync status: Frontend.GithubSync/status — {error}'**
  String githubSyncLoadStatusFailed(String error);

  /// No description provided for @githubSyncSelectRepositoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot select repository: Frontend.GithubSync/repository.select — {error}'**
  String githubSyncSelectRepositoryFailed(String error);

  /// No description provided for @githubSyncPushFailed.
  ///
  /// In en, this message translates to:
  /// **'GitHub Sync push failed: Frontend.GithubSync/push — {error}'**
  String githubSyncPushFailed(String error);

  /// No description provided for @githubSyncPushed.
  ///
  /// In en, this message translates to:
  /// **'Pushed to GitHub: Frontend.GithubSync/push — commit {sha}.'**
  String githubSyncPushed(String sha);

  /// No description provided for @githubSyncDisconnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot disconnect GitHub Sync: Frontend.GithubSync/disconnect — {error}'**
  String githubSyncDisconnectFailed(String error);

  /// No description provided for @githubSyncInstallMissingUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot install GitHub App: Frontend.GithubSync/install — no install_url configured.'**
  String get githubSyncInstallMissingUrl;

  /// No description provided for @githubSyncInstallInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Cannot install GitHub App: Frontend.GithubSync/install — install_url is not a valid http(s) URL.'**
  String get githubSyncInstallInvalidUrl;

  /// No description provided for @githubSyncInstallCompleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot complete GitHub App install: Frontend.GithubSync/install.callback — {error}'**
  String githubSyncInstallCompleteFailed(String error);

  /// No description provided for @githubSyncInstallUrlMissingHelp.
  ///
  /// In en, this message translates to:
  /// **'Operator note: GITHUB_DATA_SYNC_APP_INSTALL_URL is not configured on this backend. See docs/integrations/github-sync.md for the env-var contract.'**
  String get githubSyncInstallUrlMissingHelp;

  /// No description provided for @courseObjectives.
  ///
  /// In en, this message translates to:
  /// **'Objectives'**
  String get courseObjectives;

  /// No description provided for @courseAssignments.
  ///
  /// In en, this message translates to:
  /// **'Assignments'**
  String get courseAssignments;

  /// No description provided for @courseModule.
  ///
  /// In en, this message translates to:
  /// **'Module'**
  String get courseModule;

  /// No description provided for @courseModulesHeader.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get courseModulesHeader;

  /// No description provided for @courseModuleNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No public notes are available for this module yet.'**
  String get courseModuleNoNotes;

  /// No description provided for @courseNoDiscussion.
  ///
  /// In en, this message translates to:
  /// **'No public discussion notes are available for this course yet.'**
  String get courseNoDiscussion;

  /// No description provided for @courseNoteCount.
  ///
  /// In en, this message translates to:
  /// **'{count} note(s)'**
  String courseNoteCount(int count);
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
