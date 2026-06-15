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
