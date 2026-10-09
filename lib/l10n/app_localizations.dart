import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('uk'),
    Locale('zh')
  ];

  /// No description provided for @aboutFlauncher.
  ///
  /// In en, this message translates to:
  /// **'About Hearth'**
  String get aboutFlauncher;

  /// No description provided for @addSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get addSection;

  /// No description provided for @alphabetical.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get alphabetical;

  /// No description provided for @appCardHighlightAnimation.
  ///
  /// In en, this message translates to:
  /// **'App card highlight animation'**
  String get appCardHighlightAnimation;

  /// No description provided for @appInfo.
  ///
  /// In en, this message translates to:
  /// **'Application info'**
  String get appInfo;

  /// No description provided for @appKeyClick.
  ///
  /// In en, this message translates to:
  /// **'Click sound on key press'**
  String get appKeyClick;

  /// No description provided for @applications.
  ///
  /// In en, this message translates to:
  /// **'Applications'**
  String get applications;

  /// No description provided for @autoHideAppBar.
  ///
  /// In en, this message translates to:
  /// **'Automatically hide status bar'**
  String get autoHideAppBar;

  /// No description provided for @backButtonAction.
  ///
  /// In en, this message translates to:
  /// **'Back button action'**
  String get backButtonAction;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @columnCount.
  ///
  /// In en, this message translates to:
  /// **'Column count'**
  String get columnCount;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @dateAndTimeFormat.
  ///
  /// In en, this message translates to:
  /// **'Date and time format'**
  String get dateAndTimeFormat;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @dialogOptionBackButtonActionDoNothing.
  ///
  /// In en, this message translates to:
  /// **'Do nothing'**
  String get dialogOptionBackButtonActionDoNothing;

  /// No description provided for @dialogOptionBackButtonActionShowScreensaver.
  ///
  /// In en, this message translates to:
  /// **'Show screensaver'**
  String get dialogOptionBackButtonActionShowScreensaver;

  /// No description provided for @dialogOptionBackButtonActionShowClock.
  ///
  /// In en, this message translates to:
  /// **'Show clock'**
  String get dialogOptionBackButtonActionShowClock;

  /// No description provided for @dialogTextNoFileExplorer.
  ///
  /// In en, this message translates to:
  /// **'Please install a file explorer in order to pick a picture.'**
  String get dialogTextNoFileExplorer;

  /// No description provided for @disambiguateCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} (Category)'**
  String disambiguateCategoryTitle(String title);

  /// No description provided for @gradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get gradient;

  /// No description provided for @favoriteApps.
  ///
  /// In en, this message translates to:
  /// **'Favorite Apps'**
  String get favoriteApps;

  /// No description provided for @grid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get grid;

  /// No description provided for @height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get height;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @hiddenApplications.
  ///
  /// In en, this message translates to:
  /// **'Hidden Apps'**
  String get hiddenApplications;

  /// No description provided for @launcherSections.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get launcherSections;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @modifySection.
  ///
  /// In en, this message translates to:
  /// **'Modify section'**
  String get modifySection;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @newSection.
  ///
  /// In en, this message translates to:
  /// **'New section'**
  String get newSection;

  /// No description provided for @nonTvApplications.
  ///
  /// In en, this message translates to:
  /// **'Non-TV Apps'**
  String get nonTvApplications;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @picture.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get picture;

  /// No description provided for @removeFrom.
  ///
  /// In en, this message translates to:
  /// **'Remove from {name}'**
  String removeFrom(String name);

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @row.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get row;

  /// No description provided for @rowHeight.
  ///
  /// In en, this message translates to:
  /// **'Row height'**
  String get rowHeight;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @spacer.
  ///
  /// In en, this message translates to:
  /// **'Spacer'**
  String get spacer;

  /// No description provided for @statusBar.
  ///
  /// In en, this message translates to:
  /// **'Status bar'**
  String get statusBar;

  /// No description provided for @show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// No description provided for @showCategoryTitles.
  ///
  /// In en, this message translates to:
  /// **'Show category titles'**
  String get showCategoryTitles;

  /// No description provided for @showCategoryAppCount.
  ///
  /// In en, this message translates to:
  /// **'Show app count in categories'**
  String get showCategoryAppCount;

  /// No description provided for @hideHighlightOutlineOnHomescreen.
  ///
  /// In en, this message translates to:
  /// **'Hide highlight outline on homescreen'**
  String get hideHighlightOutlineOnHomescreen;

  /// No description provided for @appSelectorTransitionAnimation.
  ///
  /// In en, this message translates to:
  /// **'App selector transition animation'**
  String get appSelectorTransitionAnimation;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System settings'**
  String get systemSettings;

  /// No description provided for @textEmptyCategory.
  ///
  /// In en, this message translates to:
  /// **'This category is empty.'**
  String get textEmptyCategory;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @tvApplications.
  ///
  /// In en, this message translates to:
  /// **'TV Apps'**
  String get tvApplications;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @uninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get uninstall;

  /// No description provided for @wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get wallpaper;

  /// No description provided for @withEllipsisAddTo.
  ///
  /// In en, this message translates to:
  /// **'Add to...'**
  String get withEllipsisAddTo;

  /// No description provided for @timeBasedWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Time based wallpaper'**
  String get timeBasedWallpaper;

  /// No description provided for @pickDayWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Pick day wallpaper'**
  String get pickDayWallpaper;

  /// No description provided for @pickNightWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Pick night wallpaper'**
  String get pickNightWallpaper;

  /// No description provided for @inputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get inputs;

  /// No description provided for @inputSources.
  ///
  /// In en, this message translates to:
  /// **'Input Sources'**
  String get inputSources;

  /// No description provided for @backupAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupAndRestore;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// No description provided for @importBackup.
  ///
  /// In en, this message translates to:
  /// **'Import Backup'**
  String get importBackup;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully to {path}'**
  String exportSuccess(String path);

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup imported successfully'**
  String get importSuccess;

  /// No description provided for @importConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to import the backup? This will overwrite your current settings and layout.'**
  String get importConfirm;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Failed to import backup: {error}'**
  String importError(String error);

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Failed to export backup: {error}'**
  String exportError(String error);

  /// No description provided for @shareBackup.
  ///
  /// In en, this message translates to:
  /// **'Share Backup'**
  String get shareBackup;

  /// No description provided for @notificationBell.
  ///
  /// In en, this message translates to:
  /// **'Notification Bell'**
  String get notificationBell;

  /// No description provided for @autoHideNotificationBell.
  ///
  /// In en, this message translates to:
  /// **'Auto-hide Notification Bell'**
  String get autoHideNotificationBell;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue Watching'**
  String get continueWatching;

  /// No description provided for @showContinueWatchingOnHome.
  ///
  /// In en, this message translates to:
  /// **'Show Continue Watching on Home'**
  String get showContinueWatchingOnHome;

  /// No description provided for @permissionDeniedContinueWatching.
  ///
  /// In en, this message translates to:
  /// **'Permission required to show Continue Watching'**
  String get permissionDeniedContinueWatching;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// No description provided for @dataUsagePeriod.
  ///
  /// In en, this message translates to:
  /// **'Data Usage Period'**
  String get dataUsagePeriod;

  /// No description provided for @notificationAccess.
  ///
  /// In en, this message translates to:
  /// **'Notification Access'**
  String get notificationAccess;

  /// Continue Watching settings: the row that opens the Watch Next permission (the Android TV feature name stays untranslated)
  ///
  /// In en, this message translates to:
  /// **'Watch Next Access'**
  String get watchNextAccess;

  /// No description provided for @granted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get granted;

  /// No description provided for @permissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Permission Required'**
  String get permissionRequired;

  /// No description provided for @systemWidePopupAlert.
  ///
  /// In en, this message translates to:
  /// **'System-wide Popup Alert'**
  String get systemWidePopupAlert;

  /// No description provided for @overlayPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Overlay Permission Required'**
  String get overlayPermissionRequired;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @showAppNamesBelowIcons.
  ///
  /// In en, this message translates to:
  /// **'Show App Names Below Icons'**
  String get showAppNamesBelowIcons;

  /// No description provided for @dataUsage.
  ///
  /// In en, this message translates to:
  /// **'Data Usage'**
  String get dataUsage;

  /// No description provided for @networkIndicator.
  ///
  /// In en, this message translates to:
  /// **'Network Indicator'**
  String get networkIndicator;

  /// No description provided for @startOnBoot.
  ///
  /// In en, this message translates to:
  /// **'Start on boot (Google TV / Fire TV)'**
  String get startOnBoot;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get appLanguage;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @ukrainian.
  ///
  /// In en, this message translates to:
  /// **'Ukrainian'**
  String get ukrainian;

  /// No description provided for @chinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get chinese;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get japanese;

  /// No description provided for @portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get portuguese;

  /// No description provided for @russian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get russian;

  /// No description provided for @italian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get italian;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get hindi;

  /// No description provided for @korean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get korean;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @turkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get turkish;

  /// No description provided for @hidePersistentNotifications.
  ///
  /// In en, this message translates to:
  /// **'Hide Persistent Notifications'**
  String get hidePersistentNotifications;

  /// No description provided for @blockedNotificationApps.
  ///
  /// In en, this message translates to:
  /// **'Blocked Apps'**
  String get blockedNotificationApps;

  /// No description provided for @blockAppNotifications.
  ///
  /// In en, this message translates to:
  /// **'Block Notifications'**
  String get blockAppNotifications;

  /// No description provided for @unblockAppNotifications.
  ///
  /// In en, this message translates to:
  /// **'Unblock Notifications'**
  String get unblockAppNotifications;

  /// No description provided for @noBlockedApps.
  ///
  /// In en, this message translates to:
  /// **'No blocked apps'**
  String get noBlockedApps;

  /// No description provided for @persistentNotification.
  ///
  /// In en, this message translates to:
  /// **'Persistent'**
  String get persistentNotification;

  /// No description provided for @unblockAll.
  ///
  /// In en, this message translates to:
  /// **'Unblock All'**
  String get unblockAll;

  /// No description provided for @weather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get weather;

  /// No description provided for @showWeatherWarnings.
  ///
  /// In en, this message translates to:
  /// **'Show Weather & Rain Warnings'**
  String get showWeatherWarnings;

  /// No description provided for @temperatureUnit.
  ///
  /// In en, this message translates to:
  /// **'Temperature Unit'**
  String get temperatureUnit;

  /// No description provided for @celsius.
  ///
  /// In en, this message translates to:
  /// **'Celsius (°C)'**
  String get celsius;

  /// No description provided for @fahrenheit.
  ///
  /// In en, this message translates to:
  /// **'Fahrenheit (°F)'**
  String get fahrenheit;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @continueWatchingDescription.
  ///
  /// In en, this message translates to:
  /// **'Show recently watched movies and TV shows from supported apps on your home screen'**
  String get continueWatchingDescription;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @openApp.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openApp;

  /// No description provided for @noBlockedAppsDesc.
  ///
  /// In en, this message translates to:
  /// **'All applications are currently allowed to show notifications'**
  String get noBlockedAppsDesc;

  /// No description provided for @notificationsAllowed.
  ///
  /// In en, this message translates to:
  /// **'Notifications Allowed'**
  String get notificationsAllowed;

  /// No description provided for @notificationsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Notifications Blocked'**
  String get notificationsBlocked;

  /// No description provided for @dpadDismissHint.
  ///
  /// In en, this message translates to:
  /// **'Left: Dismiss • OK: Options'**
  String get dpadDismissHint;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get profilesTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Home screen'**
  String get homeScreenTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Remote & search'**
  String get remoteAndSearchTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Parent settings'**
  String get parentSettingsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'TV & power'**
  String get tvPowerTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Setup & permissions'**
  String get setupPermissionsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updatesTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Hearth on other profiles'**
  String get familyAppsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Card style'**
  String get cardStyleTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Dock & labels'**
  String get dockLabelsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Animations & sound'**
  String get animationsSoundTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Dashboard panel'**
  String get haPanelTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get lookTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Remote buttons'**
  String get remoteButtonsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Profile Pairing'**
  String get profilePairingTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'TV status'**
  String get haTvStatusTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Continue Watching Apps'**
  String get continueWatchingAppsTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Card Size'**
  String get cardSizeTitle;

  /// Settings page title, also its row in the page that opens it
  ///
  /// In en, this message translates to:
  /// **'Maximum Items'**
  String get maxItemsTitle;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Shared button or action label
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Home screen card when the profile can open no apps at all (a kids profile at bedtime, or before apps are approved)
  ///
  /// In en, this message translates to:
  /// **'Nothing to watch right now'**
  String get homeNothingToWatch;

  /// Heading shown in place of a part of the screen that failed to draw; the error's own text follows in English
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorScreenTitle;

  /// App options panel (long press on an app): opens the list of sections to add the app to
  ///
  /// In en, this message translates to:
  /// **'Add to Category'**
  String get appInfoAddToCategory;

  /// App options panel: adds the app to Favorites (the dock); Fav is short for Favorites
  ///
  /// In en, this message translates to:
  /// **'Add to Fav'**
  String get appInfoAddToFavorites;

  /// App options panel: takes the app out of Favorites (the dock); Fav is short for Favorites
  ///
  /// In en, this message translates to:
  /// **'Remove from Fav'**
  String get appInfoRemoveFromFavorites;

  /// App options panel: picks a picture to show on the app's card instead of its own banner
  ///
  /// In en, this message translates to:
  /// **'Set Custom Banner'**
  String get appInfoSetCustomBanner;

  /// App options panel: goes back to the app's own banner
  ///
  /// In en, this message translates to:
  /// **'Clear Custom Banner'**
  String get appInfoClearCustomBanner;

  /// Snackbar when the custom banner couldn't be saved; error is the system's reason
  ///
  /// In en, this message translates to:
  /// **'Failed to set banner: {error}'**
  String appInfoSetBannerFailed(String error);

  /// Snackbar when the custom banner couldn't be removed; error is the system's reason
  ///
  /// In en, this message translates to:
  /// **'Failed to clear banner: {error}'**
  String appInfoClearBannerFailed(String error);

  /// Continue Watching's See all page: the first pill, which shows programs from every app
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get cwGridAll;

  /// Card at the end of the Continue Watching row that opens every program in a grid
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get cwRowSeeAll;

  /// Under See all at the end of the Continue Watching row: how many programs are part-watched
  ///
  /// In en, this message translates to:
  /// **'{count} in progress'**
  String cwRowInProgress(int count);

  /// Continue Watching, under the focused program's name: time left to watch, an hour or more
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min left'**
  String cwRowHoursMinutesLeft(int hours, int minutes);

  /// Continue Watching, under the focused program's name: time left to watch, under an hour
  ///
  /// In en, this message translates to:
  /// **'{minutes} min left'**
  String cwRowMinutesLeft(int minutes);

  /// Options panel of a Continue Watching program (long press): hides this program from the row
  ///
  /// In en, this message translates to:
  /// **'Remove from Continue Watching'**
  String get watchNextInfoRemove;

  /// Options panel of a Continue Watching program: hides every program from that app
  ///
  /// In en, this message translates to:
  /// **'Hide all from {appName}'**
  String watchNextInfoHideAllFrom(String appName);

  /// Options panel of a Continue Watching program: plays it from where it was left
  ///
  /// In en, this message translates to:
  /// **'Play / Resume'**
  String get watchNextInfoPlayResume;

  /// Options panel of a Continue Watching program: opens the app it's from
  ///
  /// In en, this message translates to:
  /// **'Open {appName}'**
  String watchNextInfoOpenApp(String appName);

  /// Options panel of a Continue Watching program: opens Android's info page for the app it's from
  ///
  /// In en, this message translates to:
  /// **'App Info'**
  String get watchNextInfoAppInfo;

  /// Top bar's data usage button when Hearth may not read usage stats yet
  ///
  /// In en, this message translates to:
  /// **'Grant Usage Permission'**
  String get dataWidgetGrantPermission;

  /// Top bar: data used today; usage is an amount like 5.00 MB, shown in bold
  ///
  /// In en, this message translates to:
  /// **'Daily: {usage}'**
  String dataWidgetDaily(String usage);

  /// Top bar: data used this week; usage is an amount like 5.00 MB, shown in bold
  ///
  /// In en, this message translates to:
  /// **'Weekly: {usage}'**
  String dataWidgetWeekly(String usage);

  /// Top bar: data used this month; usage is an amount like 5.00 MB, shown in bold
  ///
  /// In en, this message translates to:
  /// **'Monthly: {usage}'**
  String dataWidgetMonthly(String usage);

  /// Top bar weather: the temperature (like 27°C) and the coming rain, snow or storm (like 80% Rain today)
  ///
  /// In en, this message translates to:
  /// **'{temperature} • {warning}'**
  String weatherWidgetTemperatureWithWarning(String temperature, String warning);

  /// Top bar weather warning: rain expected. when is today, tomorrow or other; for other, day is the weekday's short name (Mon, Tue...)
  ///
  /// In en, this message translates to:
  /// **'{when, select, today{Rain today} tomorrow{Rain tomorrow} other{Rain on {day}}}'**
  String weatherTextRain(String when, String day);

  /// Top bar weather warning: snow expected. when is today, tomorrow or other; for other, day is the weekday's short name (Mon, Tue...)
  ///
  /// In en, this message translates to:
  /// **'{when, select, today{Snow today} tomorrow{Snow tomorrow} other{Snow on {day}}}'**
  String weatherTextSnow(String when, String day);

  /// Top bar weather warning: a thunderstorm expected. when is today, tomorrow or other; for other, day is the weekday's short name (Mon, Tue...)
  ///
  /// In en, this message translates to:
  /// **'{when, select, today{Storm today} tomorrow{Storm tomorrow} other{Storm on {day}}}'**
  String weatherTextStorm(String when, String day);

  /// Top bar weather warning with its chance: percent is a number, forecast is one of the weatherText warnings
  ///
  /// In en, this message translates to:
  /// **'{percent}% {forecast}'**
  String weatherTextChance(int percent, String forecast);

  /// Search: button in the choice of apps for a title, and the detail line under the focused result; apps is one app name, or several joined by searchAppsOr
  ///
  /// In en, this message translates to:
  /// **'Watch on {apps}'**
  String searchWatchOn(String apps);

  /// Search: button in the choice of stores for a title that can only be rented or bought
  ///
  /// In en, this message translates to:
  /// **'Rent or buy on {app}'**
  String searchRentOrBuyOn(String app);

  /// Search: last button in the choice of apps for a title; opens the title's Google TV page
  ///
  /// In en, this message translates to:
  /// **'More ways to watch (Google TV)'**
  String get searchMoreWaysToWatch;

  /// Search box hint while the microphone is listening
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get searchListening;

  /// Search box hint
  ///
  /// In en, this message translates to:
  /// **'Search films and shows'**
  String get searchHint;

  /// Search: help line under the search box
  ///
  /// In en, this message translates to:
  /// **'Type, use the mic, or type on your phone with the Google TV app.'**
  String get searchEntryHelp;

  /// Search results page: pill for titles included in an app on this TV
  ///
  /// In en, this message translates to:
  /// **'Watch now'**
  String get searchTabWatchNow;

  /// Search results page: pill for titles that can be rented or bought in a store on this TV
  ///
  /// In en, this message translates to:
  /// **'Rent or buy'**
  String get searchTabRentOrBuy;

  /// Search results page: pill for titles only on apps that aren't on this TV
  ///
  /// In en, this message translates to:
  /// **'Other apps'**
  String get searchTabOtherApps;

  /// Search results page, Rent or buy pill: a card's detail line; apps is a list of store names
  ///
  /// In en, this message translates to:
  /// **'Rent or buy · {apps}'**
  String searchGridRentOrBuyApps(String apps);

  /// Search results page, Other apps pill: a card's detail line when no service is known
  ///
  /// In en, this message translates to:
  /// **'Where to watch: Google TV'**
  String get searchGridWhereToWatchGoogleTv;

  /// Search results page, Other apps pill: a card's detail line; services is one or two streaming service names
  ///
  /// In en, this message translates to:
  /// **'On {services} (not on this TV)'**
  String searchGridElsewhere(String services);

  /// Search results page: how many titles were found, beside the search
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String searchGridResults(int count);

  /// Search results page: the selected pill has no titles; query is what was searched
  ///
  /// In en, this message translates to:
  /// **'Nothing here for “{query}”.'**
  String searchGridNothingHere(String query);

  /// Search results page: attribution at the bottom, which TMDB's terms ask for
  ///
  /// In en, this message translates to:
  /// **'Where to watch from TMDB (via JustWatch). This product uses the TMDB API but is not endorsed or certified by TMDB.'**
  String get searchGridTmdbNotice;

  /// Search: the last of several app names; apps is the others, joined by searchListSeparator (A, B or C)
  ///
  /// In en, this message translates to:
  /// **'{apps} or {last}'**
  String searchAppsOr(String apps, String last);

  /// Search: what goes between names in a list of apps or services (Netflix, Disney+)
  ///
  /// In en, this message translates to:
  /// **', '**
  String get searchListSeparator;

  /// Search results row, heading while Ask Google is focused; query is what was searched
  ///
  /// In en, this message translates to:
  /// **'Ask Google “{query}”'**
  String searchAskGoogleQuery(String query);

  /// Search results row, under the heading while Ask Google is focused
  ///
  /// In en, this message translates to:
  /// **'For questions, the weather and anything else that isn\'t a show'**
  String get searchAskGoogleDetail;

  /// Search results row heading while the search runs; query is what was searched
  ///
  /// In en, this message translates to:
  /// **'Searching for “{query}”…'**
  String searchSearchingFor(String query);

  /// Search results row heading when the search couldn't be done
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search right now. Check the internet connection.'**
  String get searchFailed;

  /// Search results row heading when the search found no titles; query is what was searched
  ///
  /// In en, this message translates to:
  /// **'Nothing found for “{query}”'**
  String searchNothingFound(String query);

  /// Search results row heading when titles were found but none is watchable in this TV's apps
  ///
  /// In en, this message translates to:
  /// **'Nothing for “{query}” in your apps right now'**
  String searchNothingInYourApps(String query);

  /// Search results row, under searchNothingInYourApps; More results is the searchMoreResults card
  ///
  /// In en, this message translates to:
  /// **'See where else it\'s available in More results.'**
  String get searchSeeMoreResults;

  /// Search results row: card that opens every result in a grid
  ///
  /// In en, this message translates to:
  /// **'More results'**
  String get searchMoreResults;

  /// Search results row, under More results: how many titles were found
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 title} other{{count} titles}}'**
  String searchTitles(int count);

  /// Search results row: last card, which hands the same words to Google TV's own search
  ///
  /// In en, this message translates to:
  /// **'Ask Google'**
  String get searchAskGoogle;

  /// Search results row, under Ask Google: what was searched, in the language's quotation marks
  ///
  /// In en, this message translates to:
  /// **'“{query}”'**
  String searchQuoted(String query);

  /// Search: kind of title on a result card, after its year (2014 · Film)
  ///
  /// In en, this message translates to:
  /// **'Film'**
  String get searchKindFilm;

  /// Search: kind of title on a result card, after its year (2022 · Series)
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get searchKindSeries;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Pitch Black'**
  String get gradientNamePitchBlack;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Great Whale'**
  String get gradientNameGreatWhale;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Vicious Stance'**
  String get gradientNameViciousStance;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Teen Notebook'**
  String get gradientNameTeenNotebook;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Old Hat'**
  String get gradientNameOldHat;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Burning Spring'**
  String get gradientNameBurningSpring;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Desert Hump'**
  String get gradientNameDesertHump;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Faraway River'**
  String get gradientNameFarawayRiver;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Saint Petersburg'**
  String get gradientNameSaintPetersburg;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'African Field'**
  String get gradientNameAfricanField;

  /// Name of a background gradient, under its swatch in the gradient wallpaper picker
  ///
  /// In en, this message translates to:
  /// **'Grass Shampoo'**
  String get gradientNameGrassShampoo;

  /// Hearth update dialog: the update check found no release built for this TV
  ///
  /// In en, this message translates to:
  /// **'No release has an APK for this device'**
  String get updateErrorNoApk;

  /// Hearth update dialog: GitHub couldn't be reached or answered with an error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates'**
  String get updateErrorCheckFailed;

  /// Hearth update dialog: the new version's APK couldn't be downloaded
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the update'**
  String get updateErrorDownloadFailed;

  /// Updates page: the line under HearthTube, a companion app
  ///
  /// In en, this message translates to:
  /// **'YouTube for Hearth; follows your Hearth profile'**
  String get serviceHearthTubeDescription;

  /// Home Assistant page: shown next to Notifications or Dashboard panel when it is on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get haSummaryOn;

  /// Home Assistant page: shown next to a feature that is off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get haSummaryOff;

  /// Home Assistant page: shown next to TV status while the TV reports to Home Assistant
  ///
  /// In en, this message translates to:
  /// **'Reporting'**
  String get haSummaryReporting;

  /// Home Assistant notifications page: the test pop-up could not show; {path} is where Setup & permissions is
  ///
  /// In en, this message translates to:
  /// **'Turn on Home Button Fix ({path}); it shows the pop-ups.'**
  String haNotificationsNeedsFix(String path);

  /// Home Assistant notifications page: the on/off switch
  ///
  /// In en, this message translates to:
  /// **'Show Home Assistant notifications'**
  String get haNotificationsShow;

  /// Home Assistant notifications page: row that shows a test pop-up
  ///
  /// In en, this message translates to:
  /// **'Send a test notification'**
  String get haNotificationsSendTest;

  /// Home Assistant notifications page: how to set it up; {host} is the TV's IP address, {path} is where Setup & permissions is. The integration's name stays in English, as Home Assistant shows it
  ///
  /// In en, this message translates to:
  /// **'In Home Assistant, add the \"Notifications for Android TV / Fire TV\" integration with host {host}. Then send notifications to it from automations, for example for the doorbell or when the laundry is done.\n\nOnly devices on your home network can send them (port 7676). Pop-ups appear over any app and need Home Button Fix ({path}) to be on.'**
  String haNotificationsHelp(String host, String path);

  /// Home Assistant notifications page: stands in for the host while the TV's IP address is unknown
  ///
  /// In en, this message translates to:
  /// **'(this TV\'s IP address)'**
  String get haNotificationsThisTvIp;

  /// Dashboard panel page: shown after Save
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get haPanelSaved;

  /// Dashboard panel page: shown after Save while no token is saved
  ///
  /// In en, this message translates to:
  /// **'Saved. Add an access token to sign in.'**
  String get haPanelSavedNoToken;

  /// Dashboard panel page: shown after the phone sent its setup
  ///
  /// In en, this message translates to:
  /// **'Received the address and token from your phone'**
  String get haPanelReceived;

  /// Dashboard panel page: switch; pressing Right on the remote at the screen's right edge slides the panel in
  ///
  /// In en, this message translates to:
  /// **'Right at the right edge opens the panel'**
  String get haPanelRightEdge;

  /// Dashboard panel page: row that opens the QR code dialog, and that dialog's title
  ///
  /// In en, this message translates to:
  /// **'Set up from your phone'**
  String get haSetUpFromPhone;

  /// Dashboard panel page: text field label (Home Assistant's name for the token)
  ///
  /// In en, this message translates to:
  /// **'Long-lived access token'**
  String get haPanelTokenLabel;

  /// Dashboard panel page: hint in the token field once a token is saved
  ///
  /// In en, this message translates to:
  /// **'Saved (type a new one to replace it)'**
  String get haPanelTokenSavedHint;

  /// Dashboard panel page: text field label for the Home Assistant dashboard path
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get haPanelDashboardLabel;

  /// Dashboard panel page: note at the bottom; {tvStatus} is the TV status page's title
  ///
  /// In en, this message translates to:
  /// **'On for this profile only. The panel shows a dashboard from the address under {tvStatus}, signed in with the token. Create the token in Home Assistant while logged in as a non-admin user made for this TV (profile page, Security tab).'**
  String haPanelHelp(String tvStatus);

  /// TV status page: shown after Save with the address or webhook empty
  ///
  /// In en, this message translates to:
  /// **'Status reporting is off'**
  String get haStatusReportingOff;

  /// TV status page: shown after Save with an address and webhook
  ///
  /// In en, this message translates to:
  /// **'Saved: reporting to Home Assistant'**
  String get haStatusSaved;

  /// TV status page: text field label
  ///
  /// In en, this message translates to:
  /// **'Home Assistant address'**
  String get haStatusAddressLabel;

  /// TV status page: text field label
  ///
  /// In en, this message translates to:
  /// **'Webhook ID'**
  String get haStatusWebhookLabel;

  /// TV status page: row when notification access lets the TV report what's playing
  ///
  /// In en, this message translates to:
  /// **'Now playing: on'**
  String get haStatusNowPlayingOn;

  /// TV status page: row that opens the notification access screen
  ///
  /// In en, this message translates to:
  /// **'Now playing: turn on notification access'**
  String get haStatusNowPlayingOff;

  /// TV status page: note at the bottom
  ///
  /// In en, this message translates to:
  /// **'The TV sends Home Assistant what\'s on: the app, what\'s playing, the Google TV profile, and kids screen time. It only sends to the address above, as changes happen.'**
  String get haStatusHelp;

  /// Set up from your phone dialog: shown when the TV has no local network address
  ///
  /// In en, this message translates to:
  /// **'This TV isn\'t on the home network, so the phone can\'t reach it.'**
  String get haPhoneSetupNoNetwork;

  /// Set up from your phone dialog: under the QR code. Send is the button on the phone's page, which is in English
  ///
  /// In en, this message translates to:
  /// **'Scan with a phone on the same Wi-Fi, paste the Home Assistant address and access token, and tap Send. The page only works while this is open.'**
  String get haPhoneSetupScan;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'de', 'en', 'es', 'fr', 'hi', 'it', 'ja', 'ko', 'pt', 'ru', 'tr', 'uk', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
    case 'hi': return AppLocalizationsHi();
    case 'it': return AppLocalizationsIt();
    case 'ja': return AppLocalizationsJa();
    case 'ko': return AppLocalizationsKo();
    case 'pt': return AppLocalizationsPt();
    case 'ru': return AppLocalizationsRu();
    case 'tr': return AppLocalizationsTr();
    case 'uk': return AppLocalizationsUk();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
