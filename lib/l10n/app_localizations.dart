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
  /// **'Google TV settings'**
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
  /// **'Remote'**
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

  /// App options panel: adds the app to Favorites (the dock)
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get appInfoAddToFavorites;

  /// App options panel: takes the app out of Favorites (the dock)
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
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

  /// Profiles page: row that opens Google TV's profile chooser; also a remote button action
  ///
  /// In en, this message translates to:
  /// **'Switch profile'**
  String get profilesSwitchProfile;

  /// Profiles page row, and the title of the parent PIN screens and of the remove/change dialog
  ///
  /// In en, this message translates to:
  /// **'Parent PIN'**
  String get parentPinTitle;

  /// Profiles page: shown next to Parent PIN when a PIN is set
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get parentPinOn;

  /// Profiles page: shown next to Parent PIN when no PIN is set
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get parentPinOff;

  /// PIN screen title: asks for the PIN before changing or removing it
  ///
  /// In en, this message translates to:
  /// **'Current parent PIN'**
  String get parentPinCurrent;

  /// Parent PIN dialog: button
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get parentPinRemove;

  /// Parent PIN dialog: button
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get parentPinChange;

  /// PIN screen title: choosing a new parent PIN
  ///
  /// In en, this message translates to:
  /// **'New parent PIN'**
  String get parentPinNew;

  /// PIN screen: under New parent PIN
  ///
  /// In en, this message translates to:
  /// **'Needed to change the launcher in Google TV kids profiles'**
  String get parentPinNewSubtitle;

  /// PIN screen title: confirming the new parent PIN
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN again'**
  String get parentPinConfirm;

  /// Dialog title in a kids profile when no parent PIN is set
  ///
  /// In en, this message translates to:
  /// **'Ask a parent'**
  String get parentPinAskTitle;

  /// Ask a parent dialog: {settings}, {profiles} and {parentPin} are the Settings, Profiles and Parent PIN titles
  ///
  /// In en, this message translates to:
  /// **'Launcher settings are locked in kids profiles. A parent can set a PIN in {settings} → {profiles} → {parentPin} from their own profile.'**
  String parentPinAskBody(String settings, String profiles, String parentPin);

  /// PIN screen in a kids profile: under Parent PIN
  ///
  /// In en, this message translates to:
  /// **'Kids profile: enter the parent PIN to change the launcher'**
  String get parentPinKidsSubtitle;

  /// PIN screen: small capitals above the digits after a wrong PIN
  ///
  /// In en, this message translates to:
  /// **'WRONG PIN'**
  String get parentPinWrong;

  /// PIN screen: small capitals above the digits
  ///
  /// In en, this message translates to:
  /// **'ENTER PIN'**
  String get parentPinEnter;

  /// Profile switch card: greets the profile Hearth is switching to
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}'**
  String profileSwitchGreeting(String name);

  /// Profile switch card: before Hearth knows the profile's name
  ///
  /// In en, this message translates to:
  /// **'Setting up this profile…'**
  String get profileSwitchSettingUp;

  /// A Google TV profile's name, marked as a kids profile (Profile Pairing and Hearth on other profiles)
  ///
  /// In en, this message translates to:
  /// **'{name} (kids)'**
  String profilesKidsName(String name);

  /// Hearth on other profiles: a Google TV profile's name, marked as an adult profile
  ///
  /// In en, this message translates to:
  /// **'{name} (adult)'**
  String profilesAdultName(String name);

  /// Profile Pairing: summary when the chosen app profile is unknown; the app's own profile picker shows
  ///
  /// In en, this message translates to:
  /// **'Show the picker'**
  String get pairingShowPicker;

  /// Profile Pairing: option and summary; the app always asks who's watching
  ///
  /// In en, this message translates to:
  /// **'Always show the picker'**
  String get pairingAlwaysShowPicker;

  /// Profile Pairing: summary; {profile} is the app profile Hearth matched by name
  ///
  /// In en, this message translates to:
  /// **'{profile} (matched by name)'**
  String pairingMatchedByName(String profile);

  /// Profile Pairing: summary when no app profile matches by name
  ///
  /// In en, this message translates to:
  /// **'No match yet: shows the picker'**
  String get pairingNoMatchYet;

  /// Profile Pairing page: warning row that opens Setup & permissions
  ///
  /// In en, this message translates to:
  /// **'Profile Pairing is off. Set it up'**
  String get pairingOffSetUp;

  /// Profile Pairing page: note at the bottom; {shortName} and {fullName} are example names
  ///
  /// In en, this message translates to:
  /// **'When Hearth opens one of these apps, it picks the app profile paired with the Google TV profile. Hearth matches names by itself (\"{shortName}\" goes with \"{fullName}\"); change any pairing here. Without a match, the app\'s own picker shows.'**
  String pairingFooter(String shortName, String fullName);

  /// Profile Pairing page: under an app that isn't installed
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get pairingAppNotInstalled;

  /// Profile Pairing page: under an app with pairing turned off
  ///
  /// In en, this message translates to:
  /// **'Off: the app\'s own picker shows'**
  String get pairingAppOff;

  /// Profile Pairing page: under an app whose profiles Hearth hasn't seen
  ///
  /// In en, this message translates to:
  /// **'Open it once from Hearth so Hearth can learn its profiles'**
  String get pairingAppNotSeen;

  /// Profile Pairing page: under an app, how many of its profiles Hearth has seen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 profile found} other{{count} profiles found}}'**
  String pairingAppProfilesFound(int count);

  /// Profile Pairing app page: option; {profile} is the app profile that matches
  ///
  /// In en, this message translates to:
  /// **'Match by name ({profile})'**
  String pairingMatchByName(String profile);

  /// Profile Pairing app page: option when no app profile matches yet
  ///
  /// In en, this message translates to:
  /// **'Match by name (no match yet)'**
  String get pairingMatchByNameNone;

  /// Profile Pairing app page: dialog title; {profile} is a Google TV profile, {app} a streaming app
  ///
  /// In en, this message translates to:
  /// **'{profile} in {app}'**
  String pairingProfileInApp(String profile, String app);

  /// Profile Pairing app page: switch; {app} is the streaming app
  ///
  /// In en, this message translates to:
  /// **'Pair profiles in {app}'**
  String pairingPairIn(String app);

  /// Profile Pairing app page: note when Hearth hasn't seen the app's profiles
  ///
  /// In en, this message translates to:
  /// **'Hearth hasn\'t seen this app\'s profiles yet. Open it once from Hearth, then come back.'**
  String get pairingAppNotSeenFooter;

  /// Profile Pairing app page: note; {profiles} lists the app's profile names
  ///
  /// In en, this message translates to:
  /// **'Profiles in this app: {profiles}. Google TV profiles appear here once Hearth has seen them.'**
  String pairingAppProfilesFooter(String profiles);

  /// Hearth on other profiles page: row, and the title of its confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Add Hearth to other profiles'**
  String get familyAppsAddTitle;

  /// Add Hearth to other profiles dialog: first paragraph
  ///
  /// In en, this message translates to:
  /// **'This puts Hearth and HearthTube on your kids\' profiles, so HearthTube works there and Hearth can pick the right profile in streaming services.'**
  String get familyAppsAddKids;

  /// Add Hearth to other profiles dialog: paragraph shown when adult profiles are included
  ///
  /// In en, this message translates to:
  /// **'It also installs them on the TV\'s other adult profiles, so another adult doesn\'t have to set it up themselves.'**
  String get familyAppsAddAdults;

  /// Add Hearth to other profiles dialog: paragraph
  ///
  /// In en, this message translates to:
  /// **'It only adds Hearth\'s own two apps, and you can undo it anytime with Remove below.'**
  String get familyAppsAddOnlyOwnApps;

  /// Add Hearth to other profiles dialog: paragraph about the Family Link notification
  ///
  /// In en, this message translates to:
  /// **'Each kid gets one Family Link \"app added\" notification.'**
  String get familyAppsAddFamilyLink;

  /// Add Hearth to other profiles dialog: paragraph; quotes Android's debugging prompt and its Always allow button
  ///
  /// In en, this message translates to:
  /// **'The first time, the TV asks \"Allow debugging?\" — choose Always allow; that\'s what lets Hearth do the setup.'**
  String get familyAppsAddApproval;

  /// Add Hearth to other profiles dialog: the button that goes ahead
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get familyAppsAdd;

  /// Hearth on other profiles page: row, and the title of its confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Remove Hearth from other profiles'**
  String get familyAppsRemoveTitle;

  /// Remove Hearth from other profiles dialog: first paragraph
  ///
  /// In en, this message translates to:
  /// **'This removes Hearth and HearthTube from your other profiles.'**
  String get familyAppsRemoveBody;

  /// Remove Hearth from other profiles dialog: second paragraph
  ///
  /// In en, this message translates to:
  /// **'If you plan to uninstall Hearth itself, run this first — otherwise its copies on the kids\' profiles can be stranded and need a computer to clear.'**
  String get familyAppsRemoveFirst;

  /// Hearth on other profiles page: row, and the title of its confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Uninstall Hearth'**
  String get familyAppsUninstallTitle;

  /// Uninstall Hearth dialog: first paragraph
  ///
  /// In en, this message translates to:
  /// **'This first removes Hearth and HearthTube from your other profiles, then uninstalls Hearth from this one.'**
  String get familyAppsUninstallBody;

  /// Uninstall Hearth dialog: second paragraph
  ///
  /// In en, this message translates to:
  /// **'Uninstalling here — rather than from Android\'s settings — makes sure nothing is left behind on the kids\' profiles.'**
  String get familyAppsUninstallWhyHere;

  /// Dialog title when Uninstall Hearth can't clean up the other profiles yet
  ///
  /// In en, this message translates to:
  /// **'Finish the one-time approval first'**
  String get familyAppsApprovalFirstTitle;

  /// Finish the one-time approval first dialog: first paragraph; quotes Android's debugging prompt
  ///
  /// In en, this message translates to:
  /// **'Hearth couldn\'t clean up the other profiles yet — it needs the one-time \"Allow debugging?\" approval on the TV.'**
  String get familyAppsApprovalFirstBody;

  /// Finish the one-time approval first dialog: second paragraph
  ///
  /// In en, this message translates to:
  /// **'Approve it, then try Uninstall again, so nothing is left on the kids\' profiles.'**
  String get familyAppsApprovalFirstRetry;

  /// Dialog title after Add Hearth to other profiles finished
  ///
  /// In en, this message translates to:
  /// **'Add done'**
  String get familyAppsAddDone;

  /// Dialog title after Remove Hearth from other profiles finished
  ///
  /// In en, this message translates to:
  /// **'Remove done'**
  String get familyAppsRemoveDone;

  /// Add done dialog: message
  ///
  /// In en, this message translates to:
  /// **'Done. Hearth and HearthTube are now on your other profiles — see the list below.'**
  String get familyAppsAdded;

  /// Remove done dialog: message
  ///
  /// In en, this message translates to:
  /// **'Done. Hearth and HearthTube have been removed from your other profiles.'**
  String get familyAppsRemoved;

  /// Add done / Remove done dialog: when the TV has no other profiles
  ///
  /// In en, this message translates to:
  /// **'There are no other profiles to set up yet.'**
  String get familyAppsNothingToSetUp;

  /// Dialog title when adding or removing failed for lack of approval
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t set up the profiles'**
  String get familyAppsFailedTitle;

  /// Couldn't set up the profiles dialog: first paragraph
  ///
  /// In en, this message translates to:
  /// **'Hearth needs a one-time approval on the TV before it can set up the other profiles.'**
  String get familyAppsFailedBody;

  /// Couldn't set up the profiles dialog: second paragraph; quotes Android's debugging prompt and its Always allow button
  ///
  /// In en, this message translates to:
  /// **'On the TV, choose Always allow when it asks to \"Allow debugging?\", then try again.'**
  String get familyAppsFailedRetry;

  /// Hearth on other profiles page: on/off row
  ///
  /// In en, this message translates to:
  /// **'Also set up other adult profiles'**
  String get familyAppsAlsoAdults;

  /// Hearth on other profiles page: shown next to Also set up other adult profiles when on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get familyAppsOn;

  /// Hearth on other profiles page: shown next to Also set up other adult profiles when off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get familyAppsOff;

  /// Hearth on other profiles page: the list when it's empty
  ///
  /// In en, this message translates to:
  /// **'No other profiles set up yet.'**
  String get familyAppsNoneYet;

  /// Hearth on other profiles page: list line; {app} is Hearth or HearthTube
  ///
  /// In en, this message translates to:
  /// **'{app}: installed'**
  String familyAppsAppInstalled(String app);

  /// Hearth on other profiles page: list line; kept means Hearth keeps it installed in a kids profile
  ///
  /// In en, this message translates to:
  /// **'{app}: installed, protected'**
  String familyAppsAppInstalledKept(String app);

  /// Hearth on other profiles page: list line; {app} is Hearth or HearthTube
  ///
  /// In en, this message translates to:
  /// **'{app}: not installed'**
  String familyAppsAppNotInstalled(String app);

  /// Hearth on other profiles page: list line; kept means Hearth keeps it installed in a kids profile
  ///
  /// In en, this message translates to:
  /// **'{app}: not installed, protected'**
  String familyAppsAppNotInstalledKept(String app);

  /// Hearth on other profiles page: heading for a kids profile whose name Hearth doesn't know
  ///
  /// In en, this message translates to:
  /// **'A kids profile'**
  String get familyAppsUnnamedKids;

  /// Hearth on other profiles page: heading for an adult profile whose name Hearth doesn't know
  ///
  /// In en, this message translates to:
  /// **'An adult profile'**
  String get familyAppsUnnamedAdult;

  /// Setup & permissions step: how to turn on an accessibility service in Android's settings; {service} is the service's name as Android shows it (in English)
  ///
  /// In en, this message translates to:
  /// **'On the next screen, scroll down to Services, select \"{service}\", then turn on Enable and confirm. Press Back until you\'re home again.'**
  String setupAccessibilityInstructions(String service);

  /// Setup & permissions step: warning under an accessibility step; {command} is an adb command
  ///
  /// In en, this message translates to:
  /// **'If Android says the setting is restricted, run this once from a computer:\n{command}'**
  String setupRestrictedWarning(String command);

  /// Setup & permissions step title: make Hearth the default launcher
  ///
  /// In en, this message translates to:
  /// **'Hearth as the home app'**
  String get setupDefaultLauncherTitle;

  /// Setup & permissions step: why it matters
  ///
  /// In en, this message translates to:
  /// **'Keeps kids profiles from blocking Hearth.'**
  String get setupDefaultLauncherWhy;

  /// Setup & permissions step: what to do in Android's settings
  ///
  /// In en, this message translates to:
  /// **'On the next screen, choose Hearth.'**
  String get setupDefaultLauncherInstructions;

  /// Setup & permissions step title: Hearth's accessibility service that makes Home open Hearth
  ///
  /// In en, this message translates to:
  /// **'Home Button Fix'**
  String get setupHomeFixTitle;

  /// Setup & permissions step: why it matters
  ///
  /// In en, this message translates to:
  /// **'The Home button opens Hearth instead of Google TV.'**
  String get setupHomeFixWhy;

  /// Setup & permissions step title
  ///
  /// In en, this message translates to:
  /// **'Notification access'**
  String get setupNotificationsTitle;

  /// Setup & permissions step: why it matters
  ///
  /// In en, this message translates to:
  /// **'Shows notifications and what\'s playing.'**
  String get setupNotificationsWhy;

  /// Setup & permissions step: what to do; {service} is the service's name as Android shows it (in English)
  ///
  /// In en, this message translates to:
  /// **'On the next screen, select \"{service}\" and allow it.'**
  String setupNotificationsInstructions(String service);

  /// Setup & permissions step title: permission to install apps
  ///
  /// In en, this message translates to:
  /// **'Installing updates'**
  String get setupInstallTitle;

  /// Setup & permissions step: why it matters
  ///
  /// In en, this message translates to:
  /// **'Lets Hearth update itself and install companion apps.'**
  String get setupInstallWhy;

  /// Setup & permissions step: what to do in Android's settings
  ///
  /// In en, this message translates to:
  /// **'On the next screen, turn on Hearth.'**
  String get setupInstallInstructions;

  /// Setup & permissions step: why Profile Pairing matters
  ///
  /// In en, this message translates to:
  /// **'Picks your profile in Netflix, Disney+, Apple TV, HBO Max and Paramount+.'**
  String get setupPairingWhy;

  /// Setup & permissions step title: Hearth's text-to-speech engine
  ///
  /// In en, this message translates to:
  /// **'Hearth voice'**
  String get setupVoiceTitle;

  /// Setup & permissions step: why Hearth voice matters
  ///
  /// In en, this message translates to:
  /// **'Lets Profile Pairing hear Netflix\'s profile screen. Other apps keep Google\'s voice.'**
  String get setupVoiceWhy;

  /// Setup & permissions step: what to do in Android's text-to-speech settings; {engine} is the engine's name as Android shows it (in English)
  ///
  /// In en, this message translates to:
  /// **'On the next screen, under Preferred engine, choose \"{engine}\", then OK on the warning (Hearth only listens to the streaming apps). Press Back to return.'**
  String setupVoiceInstructions(String engine);

  /// Setup & permissions step dialog: button that opens Android's settings screen
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get setupOpenSettings;

  /// Dialog when Android couldn't open a settings screen; an adb command follows
  ///
  /// In en, this message translates to:
  /// **'This TV wouldn\'t open that Settings screen. Run this once from a computer instead:'**
  String get setupAdbFallback;

  /// Setup & permissions page: under the title, how many required steps are done
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String setupProgress(int done, int total);

  /// Remote buttons page: row that starts remapping a button
  ///
  /// In en, this message translates to:
  /// **'Remap a button'**
  String get remoteButtonsRemapButton;

  /// Remote buttons page: name of a button Android gives no name; {keyCode} is its key code
  ///
  /// In en, this message translates to:
  /// **'Button {keyCode}'**
  String remoteButtonsButtonNumber(String keyCode);

  /// Remote buttons page: a press or hold that keeps the button's normal job
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get remoteButtonsNormal;

  /// Remote buttons page: dialog title while waiting for a button press
  ///
  /// In en, this message translates to:
  /// **'Press a remote button'**
  String get remoteButtonsCaptureTitle;

  /// Remote buttons page: dialog text while waiting for a button press
  ///
  /// In en, this message translates to:
  /// **'Press the button you want to remap. Press Back to cancel.'**
  String get remoteButtonsCaptureBody;

  /// Remote buttons page: dialog title when remapping can't start
  ///
  /// In en, this message translates to:
  /// **'Turn on Home Button Fix first'**
  String get remoteButtonsNeedsFixTitle;

  /// Remote buttons page: dialog text; {path} is where Setup & permissions is
  ///
  /// In en, this message translates to:
  /// **'Remapping needs Home Button Fix ({path}).'**
  String remoteButtonsNeedsFixBody(String path);

  /// Remote buttons page: dialog title for a button that can't be remapped
  ///
  /// In en, this message translates to:
  /// **'Can\'t remap that button'**
  String get remoteButtonsCantRemapTitle;

  /// Remote buttons page: dialog text for a button that can't be remapped
  ///
  /// In en, this message translates to:
  /// **'The arrows, OK, Back, Home and power keep their normal job.'**
  String get remoteButtonsCantRemapBody;

  /// Remote buttons page: option for what a short press does; {action} is the current action
  ///
  /// In en, this message translates to:
  /// **'Press: {action}'**
  String remoteButtonsPressOption(String action);

  /// Remote buttons page: option for what holding the button does; {action} is the current action
  ///
  /// In en, this message translates to:
  /// **'Hold: {action}'**
  String remoteButtonsHoldOption(String action);

  /// Remote buttons page: option that sets press to Hearth search and hold to Google's assistant
  ///
  /// In en, this message translates to:
  /// **'Tap for Hearth search, hold for Google'**
  String get remoteButtonsSearchPreset;

  /// Remote buttons page: option; the remap works only on Hearth's home screen
  ///
  /// In en, this message translates to:
  /// **'Only on Hearth\'s home screen: On'**
  String get remoteButtonsHomeOnlyOn;

  /// Remote buttons page: option; the remap works everywhere
  ///
  /// In en, this message translates to:
  /// **'Only on Hearth\'s home screen: Off'**
  String get remoteButtonsHomeOnlyOff;

  /// Remote buttons page: option that removes a button's remap
  ///
  /// In en, this message translates to:
  /// **'Restore normal button'**
  String get remoteButtonsRestore;

  /// Remote buttons page: title of the dialog that picks what a press or hold does
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get remoteButtonsActionTitle;

  /// Remote buttons page: action option
  ///
  /// In en, this message translates to:
  /// **'Open an app…'**
  String get remoteButtonsActionApp;

  /// Remote buttons page: action option
  ///
  /// In en, this message translates to:
  /// **'Switch to a TV input…'**
  String get remoteButtonsActionInput;

  /// Remote buttons page: action option
  ///
  /// In en, this message translates to:
  /// **'Switch profile (Google TV)'**
  String get remoteButtonsActionSwitchProfile;

  /// Remote buttons page: action option and its label
  ///
  /// In en, this message translates to:
  /// **'Hearth search (voice)'**
  String get remoteButtonsActionSearchVoice;

  /// Remote buttons page: action option and its label
  ///
  /// In en, this message translates to:
  /// **'Hearth search (keyboard)'**
  String get remoteButtonsActionSearchKeyboard;

  /// Remote buttons page: action option and its label; goes to Hearth's home screen
  ///
  /// In en, this message translates to:
  /// **'Hearth home'**
  String get remoteButtonsActionHome;

  /// Remote buttons page: action option and its label; puts the TV to sleep
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get remoteButtonsActionSleep;

  /// Remote buttons page: action option and its label; opens Android's settings
  ///
  /// In en, this message translates to:
  /// **'Android settings'**
  String get remoteButtonsActionAndroidSettings;

  /// Remote buttons page: title of the app list dialog
  ///
  /// In en, this message translates to:
  /// **'Open an app'**
  String get remoteButtonsPickAppTitle;

  /// Remote buttons page: title of the TV input list dialog
  ///
  /// In en, this message translates to:
  /// **'Switch to a TV input'**
  String get remoteButtonsPickInputTitle;

  /// Remote buttons page: dialog title when Home Assistant isn't set up
  ///
  /// In en, this message translates to:
  /// **'Connect Home Assistant first'**
  String get remoteButtonsHaConnectTitle;

  /// Remote buttons page: dialog text; {panel} is where the Dashboard panel page is, {row} its Set up from your phone row
  ///
  /// In en, this message translates to:
  /// **'Set up the Home Assistant panel ({panel} > {row}), then try again.'**
  String remoteButtonsHaConnectBody(String panel, String row);

  /// Remote buttons page: a Home Assistant scene to turn on; {name} is its name
  ///
  /// In en, this message translates to:
  /// **'Scene: {name}'**
  String remoteButtonsHaScene(String name);

  /// Remote buttons page: a Home Assistant script to run; {name} is its name
  ///
  /// In en, this message translates to:
  /// **'Run: {name}'**
  String remoteButtonsHaRun(String name);

  /// Remote buttons page: a Home Assistant button entity to press; {name} is its name
  ///
  /// In en, this message translates to:
  /// **'Press: {name}'**
  String remoteButtonsHaPress(String name);

  /// Remote buttons page: a Home Assistant light, switch or the like to toggle; {name} is its name
  ///
  /// In en, this message translates to:
  /// **'Toggle: {name}'**
  String remoteButtonsHaToggle(String name);

  /// Remote buttons page: a remapped button's row; {button} is its name, {press} and {hold} what a press and a hold do
  ///
  /// In en, this message translates to:
  /// **'{button}\nPress: {press}  ·  Hold: {hold}'**
  String remoteButtonsRowSummary(String button, String press, String hold);

  /// Remote buttons page: a remapped button's row when it only works on Hearth's home screen
  ///
  /// In en, this message translates to:
  /// **'{button}\nPress: {press}  ·  Hold: {hold}  ·  Home screen only'**
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold);

  /// Remote buttons page: note at the bottom; {path} is where Setup & permissions is
  ///
  /// In en, this message translates to:
  /// **'Needs Home Button Fix ({path}). A button with only a Hold action does that action on a press too. Hearth search opens HearthTube\'s own search while HearthTube is in front. Remaps pause while a kids screen time screen is showing.'**
  String remoteButtonsFooter(String path);

  /// TV & power page: row that opens Google TV's screensaver settings
  ///
  /// In en, this message translates to:
  /// **'Screensaver (Google Photos)'**
  String get tvPowerScreensaver;

  /// TV & power page: note under the screensaver row
  ///
  /// In en, this message translates to:
  /// **'Hearth uses Google TV\'s screensaver. Choose Google Photos (and which albums) or another source there.'**
  String get tvPowerScreensaverNote;

  /// TV & power page: row, and the title of its dialog
  ///
  /// In en, this message translates to:
  /// **'Sleep when idle'**
  String get tvPowerSleepWhenIdle;

  /// TV & power page: Sleep when idle is off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get tvPowerSleepOff;

  /// TV & power page: Sleep when idle option in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String tvPowerMinutes(int minutes);

  /// TV & power page: Sleep when idle option in hours
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}}'**
  String tvPowerHours(int hours);

  /// Sleep when idle dialog: note; {path} is where Setup & permissions is
  ///
  /// In en, this message translates to:
  /// **'Playing video or music counts as activity. Needs Home Button Fix ({path}).'**
  String tvPowerSleepNote(String path);

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get accentPurple;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get accentTeal;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get accentBlue;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentOrange;

  /// Accent colour swatch name on the Accent Color page (a deep pink)
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get accentPink;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get accentWhite;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get accentYellow;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get accentRed;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get accentCyan;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get accentIndigo;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Lime'**
  String get accentLime;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get accentAmber;

  /// Accent colour swatch name on the Accent Color page (a lighter pink than Pink)
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get accentRose;

  /// Accent colour swatch name on the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Ice Blue'**
  String get accentIceBlue;

  /// Label next to the current colour's dot at the bottom of the Accent Color page
  ///
  /// In en, this message translates to:
  /// **'Selected Accent'**
  String get accentSelected;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get cardStyleDefault;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get cardStylePremium;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get cardStyleGlow;

  /// Card style choice on the Card style page (a rounded square shape), also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Squircle'**
  String get cardStyleSquircle;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get cardStyleClassic;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get cardStyleMinimal;

  /// Card style choice on the Card style page, also shown next to Card style under Look
  ///
  /// In en, this message translates to:
  /// **'Capsule'**
  String get cardStyleCapsule;

  /// Switch on the Dock & labels page
  ///
  /// In en, this message translates to:
  /// **'Favorites dock'**
  String get dockFavoritesDock;

  /// Explanation under the Favorites dock switch on the Dock & labels page; "the theme" is the card style
  ///
  /// In en, this message translates to:
  /// **'Shows Favorites as a bar along the bottom of the home screen, with Continue Watching above it and your other sections below. Its corners follow the theme.'**
  String get dockFavoritesDockDescription;

  /// Switch on the Dock & labels page: a blurred, see-through dock
  ///
  /// In en, this message translates to:
  /// **'Frosted dock'**
  String get dockFrosted;

  /// Switch on the Dock & labels page
  ///
  /// In en, this message translates to:
  /// **'Dark dock'**
  String get dockDark;

  /// Switch on the Dock & labels page
  ///
  /// In en, this message translates to:
  /// **'Dock shadow'**
  String get dockShadow;

  /// Switch on the Dock & labels page
  ///
  /// In en, this message translates to:
  /// **'Blur wallpaper below the dock'**
  String get dockBlurWallpaperBelow;

  /// Switch on the Wallpaper page: the background follows the focused app
  ///
  /// In en, this message translates to:
  /// **'Match selected app'**
  String get wallpaperMatchSelectedApp;

  /// Switch on the Wallpaper page
  ///
  /// In en, this message translates to:
  /// **'Bing Photo of the Day'**
  String get wallpaperBingPhotoOfTheDay;

  /// Row on the Wallpaper page that fetches today's Bing photo again
  ///
  /// In en, this message translates to:
  /// **'Refresh Now'**
  String get wallpaperRefreshNow;

  /// Error under Refresh Now on the Wallpaper page
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach Bing. Check your network connection.'**
  String get wallpaperBingError;

  /// Row on the Weather settings page; pressing it switches the unit. {unit} is Celsius (°C) or Fahrenheit (°F)
  ///
  /// In en, this message translates to:
  /// **'Temperature Unit: {unit}'**
  String statusBarTemperatureUnitValue(String unit);

  /// Row on the Weather settings page that opens the location search, when no place is chosen
  ///
  /// In en, this message translates to:
  /// **'Weather location: not set'**
  String get weatherLocationNotSet;

  /// Row on the Weather settings page that opens the location search; {place} is the chosen city
  ///
  /// In en, this message translates to:
  /// **'Weather location: {place}'**
  String weatherLocationValue(String place);

  /// Hint on the Weather settings page when the built-in weather fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the weather. It will retry automatically.'**
  String get statusBarWeatherLoadFailed;

  /// Hint on the Weather settings page when no location is set and no weather is available. Open-Meteo, Breezy Weather and Gadgetbridge are names
  ///
  /// In en, this message translates to:
  /// **'Choose a weather location above (weather from Open-Meteo, free, no account). Without one, weather comes from the Breezy Weather app if it\'s installed with Gadgetbridge sharing on.'**
  String get statusBarWeatherSourceHint;

  /// Title of the dialog that searches for the weather's place
  ///
  /// In en, this message translates to:
  /// **'Weather location'**
  String get weatherLocationTitle;

  /// Hint in the search field of the Weather location dialog
  ///
  /// In en, this message translates to:
  /// **'City or town'**
  String get weatherLocationHint;

  /// Shown in the Weather location dialog when a search finds nothing
  ///
  /// In en, this message translates to:
  /// **'No places found'**
  String get weatherLocationNoResults;

  /// Error in the Weather location dialog when the search fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the weather service. Check the network connection.'**
  String get weatherLocationSearchError;

  /// Note at the bottom of the Weather location dialog; Open-Meteo.com is a name
  ///
  /// In en, this message translates to:
  /// **'Weather by Open-Meteo.com: free, no account. Only the chosen place\'s coordinates are sent.'**
  String get weatherLocationPrivacyNote;

  /// Button in the Weather location dialog that runs the search
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get weatherLocationSearch;

  /// Preview at the top of the Date and time format page when the saved pattern can't be used
  ///
  /// In en, this message translates to:
  /// **'Invalid format'**
  String get dateTimeInvalidFormat;

  /// Preview at the top of the Date and time format page when no format is chosen
  ///
  /// In en, this message translates to:
  /// **'Select formats below'**
  String get dateTimeSelectFormats;

  /// Choice on the Data Usage Period page: the status bar shows today's data usage
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get dataUsageDaily;

  /// Choice on the Data Usage Period page
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get dataUsageWeekly;

  /// Choice on the Data Usage Period page
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get dataUsageMonthly;

  /// Heading on the Continue Watching Apps page; {count} is how many apps are blocked
  ///
  /// In en, this message translates to:
  /// **'Blocked from Continue Watching ({count})'**
  String cwAppsBlockedHeading(int count);

  /// Status under a blocked app's name on the Continue Watching Apps page
  ///
  /// In en, this message translates to:
  /// **'Blocked from Continue Watching'**
  String get cwAppsBlockedFromContinueWatching;

  /// Small button on a blocked app's row on the Continue Watching Apps page
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get cwAppsUnblock;

  /// Row on the Continue Watching Apps page that unblocks every app
  ///
  /// In en, this message translates to:
  /// **'Unblock All Apps'**
  String get cwAppsUnblockAllApps;

  /// Card title on the Continue Watching Apps page when no app is blocked
  ///
  /// In en, this message translates to:
  /// **'No Blocked Apps'**
  String get cwAppsNoBlockedApps;

  /// Card text on the Continue Watching Apps page when no app is blocked
  ///
  /// In en, this message translates to:
  /// **'All supported apps can show items in Continue Watching.'**
  String get cwAppsNoBlockedAppsMessage;

  /// Heading on the Continue Watching Apps page, and the row on the Continue Watching page that opens it
  ///
  /// In en, this message translates to:
  /// **'Apps with Continue Watching'**
  String get cwAppsWithContinueWatching;

  /// Line under the Apps with Continue Watching heading; Watch Next is Android's name for the feature
  ///
  /// In en, this message translates to:
  /// **'Apps currently providing Watch Next items on your home screen'**
  String get cwAppsWithContinueWatchingHint;

  /// Card on the Continue Watching Apps page when no app provides items; SmartTube is an app name
  ///
  /// In en, this message translates to:
  /// **'No apps are currently providing Continue Watching items.\nWhen supported apps (such as SmartTube or streaming services) add items, they will appear here.'**
  String get cwAppsNoActiveApps;

  /// Under an app's name on the Continue Watching Apps page: how many items it shows in Continue Watching
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 active item} other{{count} active items}}'**
  String cwAppsActiveItems(int count);

  /// Heading on the Continue Watching Apps page above every installed app's switch
  ///
  /// In en, this message translates to:
  /// **'All Installed Apps'**
  String get cwAppsAllInstalledApps;

  /// Line under the All Installed Apps heading on the Continue Watching Apps page
  ///
  /// In en, this message translates to:
  /// **'Toggle off to block any app from adding items to Continue Watching'**
  String get cwAppsAllInstalledAppsHint;

  /// Under an app's name in All Installed Apps on the Continue Watching Apps page
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get cwAppsBlocked;

  /// Under an app's name in All Installed Apps on the Continue Watching Apps page
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get cwAppsAllowed;

  /// A choice on the Card Size page: the card height in dp and the size's name
  ///
  /// In en, this message translates to:
  /// **'{height} dp • {size}'**
  String cwCardSizeOption(int height, String size);

  /// Line under a choice on the Card Size page: the card's width and height in dp
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} dp'**
  String cwCardSizeDimensions(int width, int height);

  /// Next to Card Size on the Continue Watching page: the chosen card height
  ///
  /// In en, this message translates to:
  /// **'{height} dp'**
  String cwCardSizeDp(int height);

  /// Next to Card Size on the Continue Watching page, for a height that has a name
  ///
  /// In en, this message translates to:
  /// **'{height} dp ({size})'**
  String cwCardSizeDpNamed(int height, String size);

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Extra Small'**
  String get cwCardSizeExtraSmall;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Very Small'**
  String get cwCardSizeVerySmall;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get cwCardSizeSmall;

  /// Card size name on the Card Size page, also next to Card Size on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get cwCardSizeCompact;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Medium Small'**
  String get cwCardSizeMediumSmall;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get cwCardSizeMedium;

  /// Card size name on the Card Size page, for the default height
  ///
  /// In en, this message translates to:
  /// **'Standard (Default)'**
  String get cwCardSizeStandardDefault;

  /// Card size name next to Card Size on the Continue Watching page, for the default height
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get cwCardSizeStandard;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Medium Large'**
  String get cwCardSizeMediumLarge;

  /// Card size name on the Card Size page, also next to Card Size on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get cwCardSizeLarge;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Very Large'**
  String get cwCardSizeVeryLarge;

  /// Card size name on the Card Size page
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get cwCardSizeExtraLarge;

  /// Card size name on the Card Size page, the biggest
  ///
  /// In en, this message translates to:
  /// **'Huge'**
  String get cwCardSizeHuge;

  /// A choice on the Maximum Items page
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Item} other{{count} Items}}'**
  String cwMaxItemsCount(int count);

  /// Line under a choice on the Maximum Items page
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Display up to 1 recent item} other{Display up to {count} recent items}}'**
  String cwMaxItemsUpTo(int count);

  /// Line under the default choice on the Maximum Items page; {description} is that choice's line
  ///
  /// In en, this message translates to:
  /// **'{description} • Default'**
  String cwMaxItemsDefaultNote(String description);

  /// The no-limit choice on the Maximum Items page, also next to Maximum Items on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get cwUnlimited;

  /// Line under the Unlimited choice on the Maximum Items page
  ///
  /// In en, this message translates to:
  /// **'Display all available items'**
  String get cwMaxItemsAll;

  /// Next to Maximum Items on the Continue Watching page: the chosen maximum
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String cwMaxItemsLabel(int count);

  /// Switch on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Playback Progress Bar'**
  String get cwPlaybackProgressBar;

  /// Switch on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Playback Percentage'**
  String get cwPlaybackPercentage;

  /// Switch on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'Episode & Video Details'**
  String get cwEpisodeDetails;

  /// Next to Apps with Continue Watching on the Continue Watching page: how many apps are blocked
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 blocked} other{{count} blocked}}'**
  String cwBlockedCount(int count);

  /// Next to Apps with Continue Watching on the Continue Watching page when no app is blocked
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get cwManage;

  /// Row on the Continue Watching page that brings back programs hidden from the row
  ///
  /// In en, this message translates to:
  /// **'Restore Hidden Programs'**
  String get cwRestoreHiddenPrograms;

  /// Next to Restore Hidden Programs on the Continue Watching page: how many programs are hidden
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hidden} other{{count} hidden}}'**
  String cwHiddenCount(int count);

  /// Snackbar after Restore Hidden Programs on the Continue Watching page
  ///
  /// In en, this message translates to:
  /// **'All hidden programs restored'**
  String get cwHiddenProgramsRestored;

  /// Title of the dialog explaining how to grant Watch Next access with ADB
  ///
  /// In en, this message translates to:
  /// **'Watch Next Access (ADB Required)'**
  String get cwWatchNextAdbTitle;

  /// Text of the Watch Next ADB dialog, shown above the command to run; keep READ_WRITE_WATCH_NEXT_PROGRAMS as is
  ///
  /// In en, this message translates to:
  /// **'Android TV requires the READ_WRITE_WATCH_NEXT_PROGRAMS permission for launchers to read and display Continue Watching rows from installed apps.\n\nTo grant this permission, connect your TV via ADB and run:'**
  String get cwWatchNextAdbMessage;

  /// Shown on a tab of the Applications page that has no apps
  ///
  /// In en, this message translates to:
  /// **'No applications found'**
  String get appsNoApplicationsFound;

  /// Row on an app's details page in Settings that adds it to Favorites
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get appDetailsAddToFavorites;

  /// Row on an app's details page in Settings that takes it out of Favorites
  ///
  /// In en, this message translates to:
  /// **'Remove from Favorites'**
  String get appDetailsRemoveFromFavorites;

  /// Row on an app's details page in Settings that opens the category picker
  ///
  /// In en, this message translates to:
  /// **'Add to Category'**
  String get appDetailsAddToCategory;

  /// Last choice in the section name list on the New section page; picking it lets you type a name
  ///
  /// In en, this message translates to:
  /// **'Custom...'**
  String get sectionsCustomOption;

  /// Hint in the section name list on the New section page before a name is picked
  ///
  /// In en, this message translates to:
  /// **'Select a name'**
  String get sectionsSelectName;

  /// Label of the text field for a typed section name on the section page
  ///
  /// In en, this message translates to:
  /// **'Custom Name'**
  String get sectionsCustomName;

  /// Sort choice on the section page: most recently opened apps first
  ///
  /// In en, this message translates to:
  /// **'Last Used'**
  String get sectionsSortLastUsed;

  /// Hint at the bottom of the Sections page; the arrows are the remote's D-pad
  ///
  /// In en, this message translates to:
  /// **'Select with ◄ / ► then use ▲ / ▼ to reorder'**
  String get sectionsReorderHint;

  /// Shown in the Input Sources panel when the TV reports no inputs
  ///
  /// In en, this message translates to:
  /// **'No inputs detected'**
  String get inputsNoneDetected;

  /// Button at the top of the Notifications panel that dismisses every clearable notification
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get notifClearAll;

  /// Shown in the Notifications panel when there are no notifications
  ///
  /// In en, this message translates to:
  /// **'All caught up!'**
  String get notifAllCaughtUp;

  /// Tooltip of a notification's block button, and a row in its options dialog; {app} is the app's name
  ///
  /// In en, this message translates to:
  /// **'Block Notifications ({app})'**
  String notifBlockAppNotifications(String app);

  /// Row in a notification's options dialog that opens the app it came from
  ///
  /// In en, this message translates to:
  /// **'Open {app}'**
  String notifOpenApp(String app);

  /// Title of the dialog explaining how to grant notification access with ADB
  ///
  /// In en, this message translates to:
  /// **'Notification Access (ADB Required)'**
  String get notifAccessAdbTitle;

  /// Text of the notification access ADB dialog, shown above the command to run
  ///
  /// In en, this message translates to:
  /// **'Android TV does not provide a system settings screen for \"Notification Access\" (listening to notifications from other apps).\n\nNote: Enabling \"Show notifications\" in TV App Settings only controls outgoing notifications from this app, not Notification Access.\n\nTo grant Notification Access, connect your TV via ADB and run:'**
  String get notifAccessAdbMessage;

  /// Button in the notification access ADB dialog that opens Hearth's app info screen
  ///
  /// In en, this message translates to:
  /// **'Open App Info'**
  String get notifOpenAppInfo;

  /// Title of the dialog explaining how to allow popups over other apps with ADB
  ///
  /// In en, this message translates to:
  /// **'Overlay Permission'**
  String get notifOverlayPermissionTitle;

  /// Text of the overlay permission ADB dialog, shown above the command to run
  ///
  /// In en, this message translates to:
  /// **'On this device, the Overlay Permission settings screen could not be opened automatically.\n\nTo enable overlay popups, grant permission manually via ADB from a computer connected to the TV:'**
  String get notifOverlayAdbMessage;

  /// Heading on the Blocked Apps (notifications) page; {count} is how many apps are blocked
  ///
  /// In en, this message translates to:
  /// **'Blocked Apps ({count})'**
  String blockedNotificationsHeading(int count);

  /// Text sent along with the backup file when it's shared from the Backup & Restore page
  ///
  /// In en, this message translates to:
  /// **'Hearth Backup'**
  String get backupShareText;

  /// Title of the message when sharing a backup fails
  ///
  /// In en, this message translates to:
  /// **'Share Failed'**
  String get backupShareFailedTitle;

  /// Message when sharing a backup fails; {error} is the reason
  ///
  /// In en, this message translates to:
  /// **'Failed to share backup: {error}'**
  String backupShareFailed(String error);

  /// Title of the message after a backup is exported
  ///
  /// In en, this message translates to:
  /// **'Export Success'**
  String get backupExportSuccessTitle;

  /// Title of the message when exporting a backup fails
  ///
  /// In en, this message translates to:
  /// **'Export Failed'**
  String get backupExportFailedTitle;

  /// Title of the message after a backup is imported
  ///
  /// In en, this message translates to:
  /// **'Import Success'**
  String get backupImportSuccessTitle;

  /// Title of the message when importing a backup fails
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get backupImportFailedTitle;

  /// Button that confirms importing the chosen backup
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get backupImport;

  /// Shown in the Import Backup dialog when the list of backups can't be read; {error} is the reason
  ///
  /// In en, this message translates to:
  /// **'Error loading backups: {error}'**
  String backupLoadError(String error);

  /// Shown in the Import Backup dialog when there are no backups
  ///
  /// In en, this message translates to:
  /// **'No backup files found.'**
  String get backupNoFiles;

  /// Line under a backup's file name in the Import Backup dialog: when it was saved and its size
  ///
  /// In en, this message translates to:
  /// **'{date} ({size})'**
  String backupFileDetails(String date, String size);

  /// A backup file's size in bytes, in the Import Backup dialog
  ///
  /// In en, this message translates to:
  /// **'{size} B'**
  String backupSizeBytes(String size);

  /// A backup file's size in kilobytes, in the Import Backup dialog
  ///
  /// In en, this message translates to:
  /// **'{size} KB'**
  String backupSizeKilobytes(String size);

  /// A backup file's size in megabytes, in the Import Backup dialog
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String backupSizeMegabytes(String size);

  /// Title of Hearth's update dialog
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get updateCheckForUpdatesTitle;

  /// Under the title of the update dialog
  ///
  /// In en, this message translates to:
  /// **'Current version: {version}'**
  String updateCurrentVersion(String version);

  /// Shown in the update dialog while it checks
  ///
  /// In en, this message translates to:
  /// **'Checking GitHub for a new release…'**
  String get updateChecking;

  /// Shown in the update dialog when there's nothing newer
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version.'**
  String get updateUpToDate;

  /// Shown in the update dialog when a newer release exists; {version} is its tag
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available'**
  String updateVersionAvailable(String version);

  /// Under the progress bar in the update dialog
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloading(String percent);

  /// Shown in the update dialog after the download; "Install unknown apps" is the Android setting's name
  ///
  /// In en, this message translates to:
  /// **'Downloaded. If the installer didn\'t open, your device may need\n\"Install unknown apps\" permission granted for Hearth.'**
  String get updateDownloadedHint;

  /// Shown in the update dialog when an error has no message of its own
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get updateSomethingWentWrong;

  /// Button in the update dialog
  ///
  /// In en, this message translates to:
  /// **'Download & Install'**
  String get updateDownloadAndInstall;

  /// Button in the update dialog after the download, to open the installer again
  ///
  /// In en, this message translates to:
  /// **'Retry Install'**
  String get updateRetryInstall;

  /// Button in the update dialog after a check
  ///
  /// In en, this message translates to:
  /// **'Check Again'**
  String get updateCheckAgain;

  /// Title of the dialog on the Updates page before opening the "Install unknown apps" setting
  ///
  /// In en, this message translates to:
  /// **'Allow Hearth to install apps'**
  String get updatesInstallPermissionTitle;

  /// Text of the dialog on the Updates page before opening the "Install unknown apps" setting
  ///
  /// In en, this message translates to:
  /// **'On the next screen, find Hearth and turn it on, then press Back. The install continues when you\'re back here.'**
  String get updatesInstallPermissionMessage;

  /// Button in the install permission dialog on the Updates page
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get updatesOpenSettings;

  /// Next to a companion app on the Updates page when checking for its updates fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for updates'**
  String get updatesCheckFailed;

  /// Next to a companion app on the Updates page when Android's installer doesn't open
  ///
  /// In en, this message translates to:
  /// **'The installer didn\'t start'**
  String get updatesInstallerNotStarted;

  /// Next to Hearth on the Updates page; pressing the row opens the update dialog
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updatesCheckForUpdates;

  /// Switch on the Updates page
  ///
  /// In en, this message translates to:
  /// **'Update automatically'**
  String get updatesAutoUpdate;

  /// Line under the Update automatically switch on the Updates page
  ///
  /// In en, this message translates to:
  /// **'Hearth checks daily and installs updates to apps it installed, when they\'re not in use'**
  String get updatesAutoUpdateDescription;

  /// Switch on the Updates page: Hearth's and HearthTube's updates also offer pre-release (early test) builds
  ///
  /// In en, this message translates to:
  /// **'Include pre-releases'**
  String get updatesIncludePrereleases;

  /// Line under the Include pre-releases switch on the Updates page
  ///
  /// In en, this message translates to:
  /// **'Early test builds of Hearth and HearthTube. They may be unfinished.'**
  String get updatesIncludePrereleasesDescription;

  /// Note at the bottom of the Updates page
  ///
  /// In en, this message translates to:
  /// **'Installed from each app\'s GitHub releases. After Hearth installs or updates an app once, its updates install without asking, and the app leaves updating to Hearth.'**
  String get updatesFooter;

  /// Next to a companion app on the Updates page while it checks
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updatesChecking;

  /// Next to a companion app on the Updates page that isn't installed; pressing the row installs it
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get updatesInstall;

  /// Next to a companion app on the Updates page when a newer version exists
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String updatesUpdateTo(String version);

  /// Next to a companion app on the Updates page when it has the latest version
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get updatesUpToDate;

  /// Next to a companion app on the Updates page while its update downloads
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String updatesDownloadingPercent(int percent);

  /// Next to a companion app on the Updates page while it installs
  ///
  /// In en, this message translates to:
  /// **'Installing…'**
  String get updatesInstalling;

  /// Next to a companion app on the Updates page when something failed without a message
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get updatesError;

  /// Line under a companion app on the Updates page when it's installed: its description and installed version
  ///
  /// In en, this message translates to:
  /// **'{description} · {version}'**
  String updatesDescriptionWithVersion(String description, String version);

  /// Line under the version in the About dialog: the projects Hearth is built on. The placeholders are project and author names (launcher: the project Hearth started from, author: its author, original: the launcher that one came from, parts: a project Hearth took parts from)
  ///
  /// In en, this message translates to:
  /// **'Built on {launcher} by {author} and {original}, with parts of {parts}'**
  String aboutBuiltOn(String launcher, String author, String original, String parts);

  /// Description card in the About dialog
  ///
  /// In en, this message translates to:
  /// **'A private, family-friendly launcher for Google TV, with Google TV profiles and Home Assistant built in. Ad-free and tracker-free.'**
  String get aboutDescription;

  /// Button in the About dialog that opens Hearth's GitHub page
  ///
  /// In en, this message translates to:
  /// **'Hearth on GitHub'**
  String get aboutHearthOnGitHub;

  /// Heading above the projects Hearth builds on, in the About dialog
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCredits;

  /// Credit button in the About dialog for a fork of FLauncher; {author} is its author's handle
  ///
  /// In en, this message translates to:
  /// **'FLauncher fork · {author}'**
  String aboutFlauncherForkCredit(String author);

  /// Small print at the bottom of the About dialog
  ///
  /// In en, this message translates to:
  /// **'Free software under the GNU GPL v3, like the projects it builds on.'**
  String get aboutLicense;

  /// Hearth on other profiles: a profile's status, in green; Hearth and HearthTube are both there (and protected in a kids profile)
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get familyAppsStatusInstalled;

  /// Hearth on other profiles: a profile's status, in yellow; only some of Hearth's apps are there
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get familyAppsStatusPartial;

  /// Hearth on other profiles: a profile's status; neither of Hearth's apps is there
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get familyAppsStatusNotInstalled;

  /// Hearth on other profiles: a profile's status, in red; a kids profile has an app Google TV will remove at its next start
  ///
  /// In en, this message translates to:
  /// **'At risk'**
  String get familyAppsStatusAtRisk;

  /// Hearth on other profiles: shown under an At risk profile while it's selected
  ///
  /// In en, this message translates to:
  /// **'Google TV will remove the unprotected apps here the next time this profile starts. Use Add again to protect them.'**
  String get familyAppsAtRiskDetail;

  /// Profile Pairing: the row for a streaming app profile's saved PIN
  ///
  /// In en, this message translates to:
  /// **'Profile PIN'**
  String get profilePinRow;

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get profilePinNone;

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get profilePinSaved;

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Saved — not accepted last time'**
  String get profilePinRejected;

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Saved — paused (the app changed)'**
  String get profilePinPaused;

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Hearth can’t type PINs in {app} yet'**
  String profilePinUnsupported(String app);

  /// Title of the pad for a streaming app profile's PIN
  ///
  /// In en, this message translates to:
  /// **'{profile}’s PIN in {app}'**
  String profilePinEnterTitle(String profile, String app);

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Hearth types it behind the “logging in as” card when {app} asks. It stays on this TV, encrypted, and is never shown.'**
  String profilePinEnterSubtitle(String app);

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Set a parent PIN first ({settings} → {profiles} → {parentPin}): saving a profile’s PIN needs it.'**
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin);

  /// Profile Pairing: streaming app profile PIN
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the PIN.'**
  String get profilePinSaveFailed;

  /// Settings > Profiles: locking a grown-up profile with Google TV's profile lock
  ///
  /// In en, this message translates to:
  /// **'Lock Profile'**
  String get profileLockNow;

  /// Settings > Profiles: locking a grown-up profile with Google TV's profile lock
  ///
  /// In en, this message translates to:
  /// **'Lock when the TV sleeps'**
  String get profileLockOnSleep;

  /// Settings > Profiles: locking a grown-up profile with Google TV's profile lock
  ///
  /// In en, this message translates to:
  /// **'Every time'**
  String get profileLockEveryTime;

  /// Settings > Profiles: locking a grown-up profile with Google TV's profile lock
  ///
  /// In en, this message translates to:
  /// **'After {minutes} min asleep'**
  String profileLockAfterMinutes(int minutes);

  /// Settings > Profiles: locking a grown-up profile with Google TV's profile lock
  ///
  /// In en, this message translates to:
  /// **'Uses Google TV\'s own profile lock: turn it on for your account in Google TV Settings → Accounts & Sign In → your account → Profile lock.'**
  String get profileLockNeedsGoogleLock;

  /// About: heading over the Bing photo of the day's title and credit (shown only while it is the wallpaper)
  ///
  /// In en, this message translates to:
  /// **'WALLPAPER PHOTO'**
  String get aboutWallpaperPhoto;

  /// Hearth update dialog: the downloaded APK is another app
  ///
  /// In en, this message translates to:
  /// **'This download isn\'t an update for this Hearth'**
  String get updateErrorWrongApp;

  /// Notifications panel: open a notification, as a tap on it would
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get notifOpen;

  /// Notifications panel: remote keys under a notification that can be opened
  ///
  /// In en, this message translates to:
  /// **'OK: Open · Left: Dismiss · Right: More'**
  String get notifOpenHint;

  /// TV & power: switch that leaves Google TV's own home in front instead of Hearth
  ///
  /// In en, this message translates to:
  /// **'Use Google TV\'s home'**
  String get tvPowerGoogleTvHome;

  /// TV & power: explanation under the Use Google TV's home switch
  ///
  /// In en, this message translates to:
  /// **'Hearth stays out of the way until you turn this off. The Home button still opens Hearth.'**
  String get tvPowerGoogleTvHomeNote;

  /// Setup flow: top-right button that closes the flow; the home-screen chip offers to carry on
  ///
  /// In en, this message translates to:
  /// **'Finish later'**
  String get setupFlowFinishLater;

  /// Setup flow: progress strip label for the first, essential steps (the Home button and the home app)
  ///
  /// In en, this message translates to:
  /// **'Essentials'**
  String get setupFlowStripEssentials;

  /// Setup flow: first screen's title
  ///
  /// In en, this message translates to:
  /// **'Welcome to Hearth'**
  String get setupFlowWelcomeTitle;

  /// Setup flow: first screen, what Hearth is in one line
  ///
  /// In en, this message translates to:
  /// **'A home screen for the whole family: your apps, what you were watching, and the right profile in every streaming app.'**
  String get setupFlowWelcomeBody;

  /// Setup flow: first screen, small line at the bottom
  ///
  /// In en, this message translates to:
  /// **'Takes about 5 minutes. Skip anything.'**
  String get setupFlowWelcomeTime;

  /// Setup flow: first screen's main button
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get setupFlowGetStarted;

  /// Setup flow: first screen's button that closes the flow; the home-screen chip offers to carry on
  ///
  /// In en, this message translates to:
  /// **'Set up later'**
  String get setupFlowSetUpLater;

  /// Setup flow: first screen, link that opens the language choice; {language} is the current choice ("System Default", "English"...)
  ///
  /// In en, this message translates to:
  /// **'Language: {language}'**
  String setupFlowLanguageLink(String language);

  /// Setup flow: first screen, link that opens Backup & restore
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get setupFlowRestoreLink;

  /// Setup flow: the Home Button Fix step's title
  ///
  /// In en, this message translates to:
  /// **'Make the Home button open Hearth'**
  String get setupFlowHomeButtonTitle;

  /// Setup flow: the Home Button Fix step, before two bullet points of what else it gives
  ///
  /// In en, this message translates to:
  /// **'Google TV keeps its own home on the Home button. One switch in Android\'s settings fixes that, and also lets Hearth:'**
  String get setupFlowHomeButtonBody;

  /// Setup flow: the Home Button Fix step, first bullet of what else it gives
  ///
  /// In en, this message translates to:
  /// **'follow profile switches and kids\' bedtime'**
  String get setupFlowHomeButtonPoint1;

  /// Setup flow: the Home Button Fix step, second bullet of what else it gives
  ///
  /// In en, this message translates to:
  /// **'show pop-ups and turn the TV off when idle'**
  String get setupFlowHomeButtonPoint2;

  /// Setup flow: heading over the numbered steps to follow on Android's settings screen
  ///
  /// In en, this message translates to:
  /// **'On the next screen:'**
  String get setupFlowOnNextScreen;

  /// Setup flow: first step on Android's Accessibility screen; Services is Android's own heading there
  ///
  /// In en, this message translates to:
  /// **'Scroll down to Services'**
  String get setupFlowStepServices;

  /// Setup flow: second step on Android's Accessibility screen; {name} is the service's name as Android shows it (in English)
  ///
  /// In en, this message translates to:
  /// **'Select \"{name}\"'**
  String setupFlowStepSelect(String name);

  /// Setup flow: last step on Android's Accessibility screen; Enable and OK are Android's own labels
  ///
  /// In en, this message translates to:
  /// **'Turn on Enable, then OK'**
  String get setupFlowStepEnable;

  /// Setup flow: note under the Accessibility steps
  ///
  /// In en, this message translates to:
  /// **'Hearth comes back by itself when it\'s on. If Google TV asks who\'s watching, choose yourself.'**
  String get setupFlowComesBack;

  /// Setup flow: button that opens Android's Accessibility settings
  ///
  /// In en, this message translates to:
  /// **'Open Accessibility'**
  String get setupFlowOpenAccessibility;

  /// Setup flow: Home Button Fix is on; also a line in the final summary
  ///
  /// In en, this message translates to:
  /// **'The Home button now opens Hearth'**
  String get setupFlowHomeButtonDone;

  /// Setup flow: back from Android's settings, the switch still isn't on
  ///
  /// In en, this message translates to:
  /// **'It\'s not on yet'**
  String get setupFlowNotOnYetTitle;

  /// Setup flow: under "It's not on yet"
  ///
  /// In en, this message translates to:
  /// **'Try again, or skip and do it later in Settings.'**
  String get setupFlowNotOnYetBody;

  /// Setup flow: Android lists Home Button Fix as on, but the service isn't running
  ///
  /// In en, this message translates to:
  /// **'It\'s on but not running'**
  String get setupFlowStuckTitle;

  /// Setup flow: under "It's on but not running"
  ///
  /// In en, this message translates to:
  /// **'Android lists it as on, but it isn\'t running. Turn it off and on again.'**
  String get setupFlowStuckBody;

  /// Setup flow: asked once before skipping the Home Button Fix step
  ///
  /// In en, this message translates to:
  /// **'Skip the Home button?'**
  String get setupFlowSkipHomeButtonTitle;

  /// Setup flow: under "Skip the Home button?"
  ///
  /// In en, this message translates to:
  /// **'Without it, the Home button opens Google TV, and Hearth can\'t tell when a kids\' profile is in use.'**
  String get setupFlowSkipHomeButtonBody;

  /// Setup flow: button under "Skip the Home button?"
  ///
  /// In en, this message translates to:
  /// **'Skip anyway'**
  String get setupFlowSkipAnyway;

  /// Setup flow: button that skips a step
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get setupFlowSkip;

  /// Setup flow: button that goes on to the next screen
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get setupFlowNext;

  /// Setup flow: shown after an update switched Home Button Fix off
  ///
  /// In en, this message translates to:
  /// **'The update turned the Home button off'**
  String get setupFlowLostTitle;

  /// Setup flow: under "The update turned the Home button off"
  ///
  /// In en, this message translates to:
  /// **'Android switches it off after some updates. Turn it back on in one step.'**
  String get setupFlowLostBody;

  /// Setup flow: Android restricts Hearth's accessibility switch (installed from a downloaded file)
  ///
  /// In en, this message translates to:
  /// **'Android blocked this switch'**
  String get setupFlowBlockedTitle;

  /// Setup flow: under "Android blocked this switch"
  ///
  /// In en, this message translates to:
  /// **'If the switch was grey, it\'s because Hearth was installed from a downloaded file. The TV has no setting to allow it.'**
  String get setupFlowBlockedBody;

  /// Setup flow: heading over the adb commands to run from a computer
  ///
  /// In en, this message translates to:
  /// **'With a computer:'**
  String get setupFlowBlockedComputer;

  /// Setup flow: under the adb commands
  ///
  /// In en, this message translates to:
  /// **'Then turn the switch on. Hearth notices on its own.'**
  String get setupFlowBlockedComputerThen;

  /// Setup flow: Android blocked the switch and the TV's debugging is on; explains Hearth's own fix. "Allow debugging?" and Always allow are Android's own labels
  ///
  /// In en, this message translates to:
  /// **'Debugging is on, so Hearth can fix it itself. The TV will ask \"Allow debugging?\": choose Always allow, and Hearth will unblock its switch and turn it on.'**
  String get setupFlowBlockedSelfFixBody;

  /// Setup flow: button that skips the blocked switch for now
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get setupFlowSkipForNow;

  /// Setup flow: under the blocked switch's buttons, what still works without it
  ///
  /// In en, this message translates to:
  /// **'Apps, search and Continue Watching still work. The Home button, profiles, pop-ups and the sleep timer don\'t.'**
  String get setupFlowBlockedSkipLine;

  /// Setup flow: button (and dialog title) for Hearth running the fix itself over the TV's debugging
  ///
  /// In en, this message translates to:
  /// **'Let Hearth fix it'**
  String get setupFlowLetHearthFix;

  /// Setup flow: before Hearth runs a fix, shows the exact commands below this line
  ///
  /// In en, this message translates to:
  /// **'Hearth will run this on the TV, through its own debugging connection:'**
  String get setupFlowFixConfirmBody;

  /// Setup flow: under the commands of a fix; "Allow debugging?" and Always allow are Android's own labels
  ///
  /// In en, this message translates to:
  /// **'The first time, the TV asks \"Allow debugging?\". Choose Always allow. It only changes Hearth\'s own permissions.'**
  String get setupFlowFixConfirmApproval;

  /// Setup flow: button that runs the fix shown above it
  ///
  /// In en, this message translates to:
  /// **'Run it'**
  String get setupFlowFixRun;

  /// Setup flow: while Hearth runs a fix; "Allow debugging?" and Always allow are Android's own labels
  ///
  /// In en, this message translates to:
  /// **'Working on it. If the TV asks \"Allow debugging?\", choose Always allow.'**
  String get setupFlowFixWaiting;

  /// Setup flow: Hearth's own fix didn't run
  ///
  /// In en, this message translates to:
  /// **'Hearth couldn\'t do it'**
  String get setupFlowFixFailedTitle;

  /// Setup flow: why Hearth's own fix didn't run; "Allow debugging?", Always allow and Developer options are Android's own labels
  ///
  /// In en, this message translates to:
  /// **'Hearth couldn\'t reach the TV\'s debugging. If the TV asked \"Allow debugging?\", choose Always allow and try again. Debugging must stay on in Developer options.'**
  String get setupFlowFixFailedBody;

  /// Setup flow: the default home app step's title
  ///
  /// In en, this message translates to:
  /// **'Make Hearth your home app'**
  String get setupFlowHomeAppTitle;

  /// Setup flow: the default home app step
  ///
  /// In en, this message translates to:
  /// **'Android will show a list of home apps. Choose Hearth. It keeps kids\' profiles from blocking Hearth.'**
  String get setupFlowHomeAppBody;

  /// Setup flow: button that opens Android's home app choice
  ///
  /// In en, this message translates to:
  /// **'Choose Hearth'**
  String get setupFlowChooseHearth;

  /// Setup flow: Hearth is the default home app; also a line in the final summary
  ///
  /// In en, this message translates to:
  /// **'Hearth is your home app'**
  String get setupFlowHomeAppDone;

  /// Setup flow: back from Android's home app choice, Hearth isn't the home app
  ///
  /// In en, this message translates to:
  /// **'Not chosen yet'**
  String get setupFlowNotChosenTitle;

  /// Setup flow: last screen's title
  ///
  /// In en, this message translates to:
  /// **'Hearth is ready'**
  String get setupFlowFinishTitle;

  /// Setup flow: last screen; {where} is where the setup page is in Settings ("Settings > System > Set up Hearth")
  ///
  /// In en, this message translates to:
  /// **'Anything you skipped is in Settings, and you can run this again from {where}.'**
  String setupFlowFinishBody(String where);

  /// Setup flow: last screen, heading over what's on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get setupFlowFinishOn;

  /// Setup flow: last screen, heading over what was skipped
  ///
  /// In en, this message translates to:
  /// **'Set up later, in Settings'**
  String get setupFlowFinishLaterHeading;

  /// Setup flow: last screen, what else Settings has
  ///
  /// In en, this message translates to:
  /// **'More in Settings: remote buttons, sections, notifications and backup.'**
  String get setupFlowFinishMore;

  /// Setup flow: last screen's main button
  ///
  /// In en, this message translates to:
  /// **'Go to my home'**
  String get setupFlowGoHome;

  /// Settings > System: the page that runs the setup flow again and lists what Hearth needs from Android
  ///
  /// In en, this message translates to:
  /// **'Set up Hearth'**
  String get setupHearthTitle;

  /// Set up Hearth page: first row, opens the setup flow
  ///
  /// In en, this message translates to:
  /// **'Run setup again'**
  String get setupRunAgain;

  /// Setup: the group for the parent PIN, Profile Pairing and kids' profiles (a card in the setup flow, a heading on the Set up Hearth page)
  ///
  /// In en, this message translates to:
  /// **'Your family'**
  String get setupCardFamily;

  /// Setup: the group for Continue Watching and notifications (a card in the setup flow, a heading on the Set up Hearth page)
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get setupCardWatching;

  /// Home screen top bar: chip that opens the setup flow; {count} is how many steps or cards are left (1 or more)
  ///
  /// In en, this message translates to:
  /// **'Finish setting up · {count} left'**
  String setupChipLeft(int count);

  /// Home screen top bar: chip shown when Home Button Fix is off (skipped, or switched off by an update)
  ///
  /// In en, this message translates to:
  /// **'Home button needs a fix'**
  String get setupChipFix;

  /// Home screen: asked when OK is held on the setup chip
  ///
  /// In en, this message translates to:
  /// **'Hide this reminder?'**
  String get setupChipHideTitle;

  /// Home screen: under "Hide this reminder?"; {where} is where the setup page is in Settings
  ///
  /// In en, this message translates to:
  /// **'You can still run setup from {where}.'**
  String setupChipHideBody(String where);

  /// Home screen: button that hides the setup chip for good
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get setupChipHide;

  /// Setup flow: a feature card's heading over what the feature gives
  ///
  /// In en, this message translates to:
  /// **'What\'s included'**
  String get setupFlowCardIncluded;

  /// Setup flow: a feature card's heading over what turning it on takes (Android switches, time)
  ///
  /// In en, this message translates to:
  /// **'What it needs'**
  String get setupFlowCardNeeds;

  /// Setup flow: main button of a feature card or step
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get setupFlowTurnOn;

  /// Setup flow: what a feature card needs: Android asks one question (a permission dialog)
  ///
  /// In en, this message translates to:
  /// **'One question from Android'**
  String get setupFlowNeedsQuestion;

  /// Setup flow: what a feature card needs: one switch to turn on in Android's settings
  ///
  /// In en, this message translates to:
  /// **'One switch in Android\'s settings'**
  String get setupFlowNeedsOneSwitch;

  /// Setup flow: what a feature card needs: about one minute of the owner's time
  ///
  /// In en, this message translates to:
  /// **'About a minute'**
  String get setupFlowNeedsAboutAMinute;

  /// Setup flow: the Watching card's one-line benefit
  ///
  /// In en, this message translates to:
  /// **'Pick up where you left off, and see what\'s playing.'**
  String get setupFlowWatchingBenefit;

  /// Setup flow: Watching card, first thing it includes
  ///
  /// In en, this message translates to:
  /// **'Continue Watching on the home screen'**
  String get setupFlowWatchingIncluded1;

  /// Setup flow: Watching card, second thing it includes
  ///
  /// In en, this message translates to:
  /// **'Notifications and what\'s playing'**
  String get setupFlowWatchingIncluded2;

  /// Setup flow: info line on the Watching card; search needs no setup
  ///
  /// In en, this message translates to:
  /// **'Search already works: press Search on the home screen.'**
  String get setupFlowSearchWorks;

  /// Setup flow: Continue Watching step; Android then shows its permission dialog
  ///
  /// In en, this message translates to:
  /// **'Show what you were watching in your apps on the home screen. Android will ask once; choose Allow.'**
  String get setupFlowContinueBody;

  /// Setup flow: Continue Watching step, after Android allowed it
  ///
  /// In en, this message translates to:
  /// **'Continue Watching is on'**
  String get setupFlowContinueDone;

  /// Setup flow: Continue Watching step, after Android's dialog was declined
  ///
  /// In en, this message translates to:
  /// **'Android didn\'t allow it'**
  String get setupFlowContinueDeniedTitle;

  /// Setup flow: Continue Watching step, declined; {where} is where it is in Settings ("Settings > Home screen > Continue Watching")
  ///
  /// In en, this message translates to:
  /// **'You can turn it on later in {where}.'**
  String setupFlowContinueDeniedBody(String where);

  /// Setup flow: notification access step's title
  ///
  /// In en, this message translates to:
  /// **'What\'s playing and notifications'**
  String get setupFlowNotificationsTitle;

  /// Setup flow: notification access step; {name} is the service's name as Android shows it (in English)
  ///
  /// In en, this message translates to:
  /// **'See your notifications and what\'s playing. On the next screen, select \"{name}\" and allow it.'**
  String setupFlowNotificationsBody(String name);

  /// Setup flow: notification access step, once it's on
  ///
  /// In en, this message translates to:
  /// **'Notifications are on'**
  String get setupFlowNotificationsDone;

  /// Setup flow: TV & power screen's question (sleep when idle)
  ///
  /// In en, this message translates to:
  /// **'Turn the TV off when nobody\'s watching?'**
  String get setupFlowTvTitle;

  /// Setup flow: TV & power screen, how sleep when idle works
  ///
  /// In en, this message translates to:
  /// **'After this long with no remote presses. Playing video or music counts as watching.'**
  String get setupFlowTvBody;

  /// Setup flow: TV & power screen, shown when Home Button Fix is off (the sleep choices are greyed out)
  ///
  /// In en, this message translates to:
  /// **'This needs the Home button switch from the first steps: without it Hearth can\'t tell when the remote is used.'**
  String get setupFlowTvNeedsHomeButton;

  /// Setup flow: TV & power screen, switch that starts Hearth after the TV restarts
  ///
  /// In en, this message translates to:
  /// **'Start Hearth when the TV starts'**
  String get setupFlowStartOnBoot;

  /// Setup flow: TV & power screen, link to Google TV's screensaver settings
  ///
  /// In en, this message translates to:
  /// **'Choose screensaver photos'**
  String get setupFlowScreensaver;

  /// Setup flow: the Updates card's one-line benefit
  ///
  /// In en, this message translates to:
  /// **'Hearth keeps itself and its companion apps up to date.'**
  String get setupFlowUpdatesBenefit;

  /// Setup flow: Updates card, first thing it includes
  ///
  /// In en, this message translates to:
  /// **'Hearth updates itself'**
  String get setupFlowUpdatesIncluded1;

  /// Setup flow: Updates card, second thing it includes
  ///
  /// In en, this message translates to:
  /// **'HearthTube, a YouTube app made for Hearth'**
  String get setupFlowUpdatesIncluded2;

  /// Setup flow: Updates card, the step that opens Android's Install unknown apps screen
  ///
  /// In en, this message translates to:
  /// **'Allow Hearth to install updates'**
  String get setupFlowInstallTitle;

  /// Setup flow: Updates card, what to do on Android's Install unknown apps screen
  ///
  /// In en, this message translates to:
  /// **'On the next screen, find Hearth and turn it on, then press Back.'**
  String get setupFlowInstallBody;

  /// Setup flow: Updates card, once Hearth may install apps
  ///
  /// In en, this message translates to:
  /// **'Hearth can install updates'**
  String get setupFlowInstallDone;

  /// Setup flow: Updates card, the step that offers HearthTube
  ///
  /// In en, this message translates to:
  /// **'Install HearthTube?'**
  String get setupFlowTubeTitle;

  /// Setup flow: Updates card, what HearthTube is
  ///
  /// In en, this message translates to:
  /// **'A YouTube app made for Hearth: it follows your profiles, the clock style and kids\' bedtime.'**
  String get setupFlowTubeBody;

  /// Setup flow: Updates card, once HearthTube is installed
  ///
  /// In en, this message translates to:
  /// **'HearthTube is installed'**
  String get setupFlowTubeInstalled;

  /// Setup flow: the look card's name in the progress strip and on the last screen
  ///
  /// In en, this message translates to:
  /// **'Your home'**
  String get setupCardHome;

  /// Setup flow: the look screen's title
  ///
  /// In en, this message translates to:
  /// **'Pick a look'**
  String get setupFlowLookTitle;

  /// Setup flow: the look screen; {where} is where the look settings are ("Settings > Home screen > Look")
  ///
  /// In en, this message translates to:
  /// **'Each one shows behind this card as you move to it. You can change any part later in {where}.'**
  String setupFlowLookBody(String where);

  /// Look screen shown on a grown-up's first visit to their own profile, after the setup flow ran
  ///
  /// In en, this message translates to:
  /// **'Pick a look for your home'**
  String get setupFlowLookOtherTitle;

  /// Look screen on a grown-up's first visit to their own profile
  ///
  /// In en, this message translates to:
  /// **'Each profile has its own home. Choose how yours looks.'**
  String get setupFlowLookOtherBody;

  /// Look screen: Hearth's own look (purple, a purple-teal gradient); "Hearth" is the app's name
  ///
  /// In en, this message translates to:
  /// **'Hearth'**
  String get setupLookHearth;

  /// Look screen: the look with Bing's photo of the day as the wallpaper
  ///
  /// In en, this message translates to:
  /// **'Photo of the day'**
  String get setupLookPhoto;

  /// Look screen: the all-black, quiet look
  ///
  /// In en, this message translates to:
  /// **'Calm dark'**
  String get setupLookCalmDark;

  /// Look screen: the bright pink look with glowing cards
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get setupLookBold;

  /// Look screen: note under the look the home has now
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get setupFlowLookNow;

  /// Look screen: button that keeps the focused look
  ///
  /// In en, this message translates to:
  /// **'Use this look'**
  String get setupFlowLookUse;

  /// Look screen: button that leaves the home as it was
  ///
  /// In en, this message translates to:
  /// **'Keep current'**
  String get setupFlowLookKeep;

  /// Look screen: button that opens Settings' Look page
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get setupFlowLookCustomize;

  /// Setup flow: weather step's title
  ///
  /// In en, this message translates to:
  /// **'Show the weather?'**
  String get setupFlowWeatherTitle;

  /// Setup flow: weather step; Open-Meteo is the weather service's name
  ///
  /// In en, this message translates to:
  /// **'Choose your town. Only its location is sent, to Open-Meteo; no account.'**
  String get setupFlowWeatherBody;

  /// Setup flow: weather step's button that opens the town search
  ///
  /// In en, this message translates to:
  /// **'Choose town'**
  String get setupFlowWeatherChoose;

  /// Setup flow: weather step, once a town is chosen
  ///
  /// In en, this message translates to:
  /// **'The weather shows in the top bar'**
  String get setupFlowWeatherDone;

  /// Setup flow: the Your family card's one-line benefit
  ///
  /// In en, this message translates to:
  /// **'Streaming apps open on the right person, and kids can\'t change Hearth.'**
  String get setupFlowFamilyBenefit;

  /// Setup flow: Your family card, first thing it includes
  ///
  /// In en, this message translates to:
  /// **'A parent PIN, so kids can\'t change Hearth'**
  String get setupFlowFamilyIncluded1;

  /// Setup flow: Your family card, second thing it includes (Profile Pairing); app names stay as they are
  ///
  /// In en, this message translates to:
  /// **'The right profile in Netflix, Disney+, Apple TV, Max and Paramount+'**
  String get setupFlowFamilyIncluded2;

  /// Setup flow: Your family card, third thing it includes (shown when the TV has kids' profiles)
  ///
  /// In en, this message translates to:
  /// **'Hearth kept on your kids\' profiles'**
  String get setupFlowFamilyIncluded3;

  /// Setup flow: what the Your family card needs: a four-digit PIN the parent picks
  ///
  /// In en, this message translates to:
  /// **'Four digits you choose'**
  String get setupFlowNeedsPin;

  /// Setup flow: what a feature card needs: about two minutes
  ///
  /// In en, this message translates to:
  /// **'About 2 minutes'**
  String get setupFlowNeedsTwoMinutes;

  /// Setup flow: parent PIN step's title
  ///
  /// In en, this message translates to:
  /// **'Choose a parent PIN'**
  String get setupFlowPinTitle;

  /// Setup flow: parent PIN step
  ///
  /// In en, this message translates to:
  /// **'Kids need it to change Hearth. Pick four digits a child won\'t guess.'**
  String get setupFlowPinBody;

  /// Setup flow: parent PIN step's button that opens the PIN pad
  ///
  /// In en, this message translates to:
  /// **'Choose PIN'**
  String get setupFlowPinChoose;

  /// Setup flow: parent PIN step, once set
  ///
  /// In en, this message translates to:
  /// **'The parent PIN is set'**
  String get setupFlowPinDone;

  /// Setup flow: Profile Pairing step's title
  ///
  /// In en, this message translates to:
  /// **'Pick the right profile in streaming apps'**
  String get setupFlowPairingTitle;

  /// Setup flow: Profile Pairing step; {name} is the service's name as Android shows it (in English); app names stay as they are
  ///
  /// In en, this message translates to:
  /// **'Hearth chooses each person\'s profile in Netflix, Disney+, Apple TV, Max and Paramount+. It needs one more switch on the same Android screen: \"{name}\".'**
  String setupFlowPairingBody(String name);

  /// Setup flow: Profile Pairing step, once on
  ///
  /// In en, this message translates to:
  /// **'Profile Pairing is on'**
  String get setupFlowPairingDone;

  /// Setup flow: Profile Pairing step, once on; "Alex" and "Alex Morgan" are example names (keep or adapt), "Who's watching?" is the apps' profile screen
  ///
  /// In en, this message translates to:
  /// **'Hearth matches names by itself: \"Alex\" goes with \"Alex Morgan\". Each app\'s profiles appear after its \"Who\'s watching?\" screen has shown once.'**
  String get setupFlowPairingDoneBody;

  /// Setup flow: Profile Pairing step, button that opens Settings' Profile Pairing page
  ///
  /// In en, this message translates to:
  /// **'Check pairings'**
  String get setupFlowCheckPairings;

  /// Setup flow: Hearth voice step's title (shown when Netflix is installed)
  ///
  /// In en, this message translates to:
  /// **'One more step for Netflix'**
  String get setupFlowVoiceTitle;

  /// Setup flow: Hearth voice step; {name} is the voice engine's name as Android shows it (in English); "Preferred engine" is Android's label
  ///
  /// In en, this message translates to:
  /// **'Netflix reads its profile screen aloud, so Hearth listens through its own voice. On the next screen, under Preferred engine, choose \"{name}\", then OK. Other apps keep Google\'s voice.'**
  String setupFlowVoiceBody(String name);

  /// Setup flow: Hearth voice step, once it's the preferred engine
  ///
  /// In en, this message translates to:
  /// **'Hearth voice is on'**
  String get setupFlowVoiceDone;

  /// Setup flow: kids' profiles step's title
  ///
  /// In en, this message translates to:
  /// **'Keep Hearth on your kids\' profiles'**
  String get setupFlowKidsTitle;

  /// Setup flow: kids' profiles step; Family Link and its "app added" notice are Google's
  ///
  /// In en, this message translates to:
  /// **'Google TV removes apps it didn\'t install from kids\' profiles each time they start. Hearth can protect itself and HearthTube there. Each child gets one Family Link \"app added\" notice; undo anytime in Settings.'**
  String get setupFlowKidsBody;

  /// Setup flow: kids' profiles step, what the TV will ask; "Allow debugging?", Always allow and Allow are Android's labels
  ///
  /// In en, this message translates to:
  /// **'The TV will ask \"Allow debugging?\". Tick Always allow, then Allow. You only do this once.'**
  String get setupFlowKidsApprove;

  /// Setup flow: kids' profiles step's main button
  ///
  /// In en, this message translates to:
  /// **'Add to their profiles'**
  String get setupFlowKidsAdd;

  /// Setup flow: kids' profiles step, once Hearth was added
  ///
  /// In en, this message translates to:
  /// **'Hearth is on your kids\' profiles'**
  String get setupFlowKidsDone;

  /// Setup flow: kids' profiles step, once done: debugging stays on
  ///
  /// In en, this message translates to:
  /// **'Leave debugging on: Hearth needs it again for a new kids\' profile, and to remove or uninstall itself.'**
  String get setupFlowKidsKeepDebugging;

  /// Setup flow: kids' profiles step when the TV's debugging switch is off
  ///
  /// In en, this message translates to:
  /// **'Turn on debugging first'**
  String get setupFlowDebugTitle;

  /// Setup flow: how to turn on debugging; "Android TV OS build", Developer options and USB debugging are Android's labels
  ///
  /// In en, this message translates to:
  /// **'Hearth needs the TV\'s debugging switch to set up the kids\' profiles. On the next screen, select \"Android TV OS build\" seven times. Then in Settings > System > Developer options, turn on USB debugging, and come back. Leave it on: Hearth needs it again for a new kids\' profile.'**
  String get setupFlowDebugBody;

  /// Setup flow: button that opens Android's About screen
  ///
  /// In en, this message translates to:
  /// **'Open About'**
  String get setupFlowDebugOpen;

  /// Setup flow: the Home Assistant card's name
  ///
  /// In en, this message translates to:
  /// **'Smart home'**
  String get setupCardSmartHome;

  /// Setup flow: the Smart home card's one-line benefit
  ///
  /// In en, this message translates to:
  /// **'Doorbell and other alerts on the TV, and your Home Assistant dashboard one press away.'**
  String get setupFlowHaBenefit;

  /// Setup flow: Smart home card, first thing it includes
  ///
  /// In en, this message translates to:
  /// **'Doorbell and other alerts over any app'**
  String get setupFlowHaIncluded1;

  /// Setup flow: Smart home card, second thing it includes
  ///
  /// In en, this message translates to:
  /// **'Your dashboard, one press away'**
  String get setupFlowHaIncluded2;

  /// Setup flow: Smart home card, third thing it includes (TV status reporting)
  ///
  /// In en, this message translates to:
  /// **'What\'s on, sent to Home Assistant'**
  String get setupFlowHaIncluded3;

  /// Setup flow: what the Smart home card needs: a phone on the home Wi-Fi
  ///
  /// In en, this message translates to:
  /// **'A phone on the same Wi-Fi'**
  String get setupFlowNeedsPhone;

  /// Setup flow: what a feature card needs: a few minutes
  ///
  /// In en, this message translates to:
  /// **'A few minutes'**
  String get setupFlowNeedsFewMinutes;

  /// Setup flow: Smart home card's main button
  ///
  /// In en, this message translates to:
  /// **'I use Home Assistant'**
  String get setupFlowHaUse;

  /// Setup flow: Home Assistant pop-ups step's title
  ///
  /// In en, this message translates to:
  /// **'Home Assistant alerts'**
  String get setupFlowHaAlertsTitle;

  /// Setup flow: Home Assistant pop-ups step; the integration's name stays in English as Home Assistant shows it; {ip} is this TV's address
  ///
  /// In en, this message translates to:
  /// **'In Home Assistant, add \"Notifications for Android TV / Fire TV\" with this TV\'s address: {ip}. Then send a test.'**
  String setupFlowHaAlertsBody(String ip);

  /// Setup flow: Home Assistant pop-ups step, once on
  ///
  /// In en, this message translates to:
  /// **'Alerts are on'**
  String get setupFlowHaAlertsDone;

  /// Setup flow: Home Assistant dashboard step's title
  ///
  /// In en, this message translates to:
  /// **'Your dashboard on the TV'**
  String get setupFlowHaDashboardTitle;

  /// Setup flow: Home Assistant dashboard step
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone, paste your Home Assistant address and a token, then Send. Use a Home Assistant user made for the TV, not an admin.'**
  String get setupFlowHaDashboardBody;

  /// Setup flow: Home Assistant dashboard step, once the phone sent the sign-in
  ///
  /// In en, this message translates to:
  /// **'Your dashboard is set up'**
  String get setupFlowHaDashboardDone;

  /// Setup flow: Home Assistant TV status step's title
  ///
  /// In en, this message translates to:
  /// **'Tell Home Assistant what\'s on'**
  String get setupFlowHaStatusTitle;

  /// Setup flow: Home Assistant TV status step
  ///
  /// In en, this message translates to:
  /// **'The TV can send what\'s playing and the active profile to Home Assistant. On the same phone page, add the ID of a webhook automation from Home Assistant.'**
  String get setupFlowHaStatusBody;

  /// Setup flow: Home Assistant TV status step, when the phone sent no webhook ID
  ///
  /// In en, this message translates to:
  /// **'The phone didn\'t send a webhook ID. Fill in the last box on the page.'**
  String get setupFlowHaStatusNoWebhook;

  /// Setup flow: Home Assistant TV status step, once set up
  ///
  /// In en, this message translates to:
  /// **'The TV tells Home Assistant what\'s on'**
  String get setupFlowHaStatusDone;

  /// Home screen top bar: chip after an update added one setup card; {feature} is the card's name ("Smart home")
  ///
  /// In en, this message translates to:
  /// **'New in Hearth: {feature}'**
  String setupChipNewOne(String feature);

  /// Home screen top bar: chip after an update added several setup cards; {count} is how many (2 or more)
  ///
  /// In en, this message translates to:
  /// **'New in Hearth · {count}'**
  String setupChipNewMany(int count);

  /// Setup flow: kids' profiles step, when Hearth couldn't be kept on every kids' profile; the rows below say which
  ///
  /// In en, this message translates to:
  /// **'Hearth isn\'t on every kids\' profile yet'**
  String get setupFlowKidsNotAll;

  /// Setup flow: a card button that goes on to the next card without changing anything
  ///
  /// In en, this message translates to:
  /// **'Leave it as it is'**
  String get setupFlowLeaveAsIs;

  /// Setup flow: a card button that goes through the card's steps that aren't on yet
  ///
  /// In en, this message translates to:
  /// **'Set up what\'s missing'**
  String get setupFlowSetUpMissing;

  /// Setup flow: on a card that is a choice (the look, TV & power), choose it again
  ///
  /// In en, this message translates to:
  /// **'Choose again'**
  String get setupFlowChooseAgain;

  /// Weather forecast over the home: heading while it shows the coming hours, hour by hour
  ///
  /// In en, this message translates to:
  /// **'Hourly'**
  String get weatherForecastHourly;

  /// Weather forecast over the home: heading while it shows the coming days, day by day
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get weatherForecastDaily;

  /// Weather forecast: what OK on the weather does while the hours show (switch to daily)
  ///
  /// In en, this message translates to:
  /// **'OK: daily'**
  String get weatherForecastShowDaily;

  /// Weather forecast: what OK on the weather does while the days show (switch to hourly)
  ///
  /// In en, this message translates to:
  /// **'OK: hourly'**
  String get weatherForecastShowHourly;

  /// Weather forecast: the current hour's tile
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get weatherForecastNow;

  /// Weather forecast: today's tile among the days
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get weatherForecastToday;

  /// Weather forecast over the home: shown before the source has sent hours or days
  ///
  /// In en, this message translates to:
  /// **'The forecast isn\'t in yet'**
  String get weatherForecastNone;
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
