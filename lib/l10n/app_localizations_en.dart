import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutFlauncher => 'About Hearth';

  @override
  String get addSection => 'Add section';

  @override
  String get alphabetical => 'Alphabetical';

  @override
  String get appCardHighlightAnimation => 'App card highlight animation';

  @override
  String get appInfo => 'Application info';

  @override
  String get appKeyClick => 'Click sound on key press';

  @override
  String get applications => 'Applications';

  @override
  String get autoHideAppBar => 'Automatically hide status bar';

  @override
  String get backButtonAction => 'Back button action';

  @override
  String get category => 'Category';

  @override
  String get columnCount => 'Column count';

  @override
  String get date => 'Date';

  @override
  String get dateAndTimeFormat => 'Date and time format';

  @override
  String get delete => 'Delete';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Do nothing';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Show screensaver';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Show clock';

  @override
  String get dialogTextNoFileExplorer => 'Please install a file explorer in order to pick a picture.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Category)';
  }

  @override
  String get gradient => 'Gradient';

  @override
  String get favoriteApps => 'Favorite Apps';

  @override
  String get grid => 'Grid';

  @override
  String get height => 'Height';

  @override
  String get hide => 'Hide';

  @override
  String get hiddenApplications => 'Hidden Apps';

  @override
  String get launcherSections => 'Sections';

  @override
  String get layout => 'Layout';

  @override
  String get loading => 'Loading';

  @override
  String get manual => 'Manual';

  @override
  String get modifySection => 'Modify section';

  @override
  String get name => 'Name';

  @override
  String get newSection => 'New section';

  @override
  String get nonTvApplications => 'Non-TV Apps';

  @override
  String get open => 'Open';

  @override
  String get picture => 'Picture';

  @override
  String removeFrom(String name) {
    return 'Remove from $name';
  }

  @override
  String get reorder => 'Reorder';

  @override
  String get row => 'Row';

  @override
  String get rowHeight => 'Row height';

  @override
  String get save => 'Save';

  @override
  String get spacer => 'Spacer';

  @override
  String get statusBar => 'Status bar';

  @override
  String get show => 'Show';

  @override
  String get showCategoryTitles => 'Show category titles';

  @override
  String get showCategoryAppCount => 'Show app count in categories';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Hide highlight outline on homescreen';

  @override
  String get appSelectorTransitionAnimation => 'App selector transition animation';

  @override
  String get sort => 'Sort';

  @override
  String get systemSettings => 'System settings';

  @override
  String get textEmptyCategory => 'This category is empty.';

  @override
  String get time => 'Time';

  @override
  String get tvApplications => 'TV Apps';

  @override
  String get type => 'Type';

  @override
  String get uninstall => 'Uninstall';

  @override
  String get wallpaper => 'Wallpaper';

  @override
  String get withEllipsisAddTo => 'Add to...';

  @override
  String get timeBasedWallpaper => 'Time based wallpaper';

  @override
  String get pickDayWallpaper => 'Pick day wallpaper';

  @override
  String get pickNightWallpaper => 'Pick night wallpaper';

  @override
  String get inputs => 'Inputs';

  @override
  String get inputSources => 'Input Sources';

  @override
  String get backupAndRestore => 'Backup & Restore';

  @override
  String get exportBackup => 'Export Backup';

  @override
  String get importBackup => 'Import Backup';

  @override
  String exportSuccess(String path) {
    return 'Backup exported successfully to $path';
  }

  @override
  String get importSuccess => 'Backup imported successfully';

  @override
  String get importConfirm => 'Are you sure you want to import the backup? This will overwrite your current settings and layout.';

  @override
  String importError(String error) {
    return 'Failed to import backup: $error';
  }

  @override
  String exportError(String error) {
    return 'Failed to export backup: $error';
  }

  @override
  String get shareBackup => 'Share Backup';

  @override
  String get notificationBell => 'Notification Bell';

  @override
  String get autoHideNotificationBell => 'Auto-hide Notification Bell';

  @override
  String get continueWatching => 'Continue Watching';

  @override
  String get showContinueWatchingOnHome => 'Show Continue Watching on Home';

  @override
  String get permissionDeniedContinueWatching => 'Permission required to show Continue Watching';

  @override
  String get system => 'System';

  @override
  String get accentColor => 'Accent Color';

  @override
  String get dataUsagePeriod => 'Data Usage Period';

  @override
  String get notificationAccess => 'Notification Access';

  @override
  String get watchNextAccess => 'Watch Next Access';

  @override
  String get granted => 'Granted';

  @override
  String get permissionRequired => 'Permission Required';

  @override
  String get systemWidePopupAlert => 'System-wide Popup Alert';

  @override
  String get overlayPermissionRequired => 'Overlay Permission Required';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get showAppNamesBelowIcons => 'Show App Names Below Icons';

  @override
  String get dataUsage => 'Data Usage';

  @override
  String get networkIndicator => 'Network Indicator';

  @override
  String get startOnBoot => 'Start on boot (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Language';

  @override
  String get systemDefault => 'System Default';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Spanish';

  @override
  String get ukrainian => 'Ukrainian';

  @override
  String get chinese => 'Chinese';

  @override
  String get french => 'French';

  @override
  String get german => 'German';

  @override
  String get japanese => 'Japanese';

  @override
  String get portuguese => 'Portuguese';

  @override
  String get russian => 'Russian';

  @override
  String get italian => 'Italian';

  @override
  String get hindi => 'Hindi';

  @override
  String get korean => 'Korean';

  @override
  String get arabic => 'Arabic';

  @override
  String get turkish => 'Turkish';

  @override
  String get hidePersistentNotifications => 'Hide Persistent Notifications';

  @override
  String get blockedNotificationApps => 'Blocked Apps';

  @override
  String get blockAppNotifications => 'Block Notifications';

  @override
  String get unblockAppNotifications => 'Unblock Notifications';

  @override
  String get noBlockedApps => 'No blocked apps';

  @override
  String get persistentNotification => 'Persistent';

  @override
  String get unblockAll => 'Unblock All';

  @override
  String get weather => 'Weather';

  @override
  String get showWeatherWarnings => 'Show Weather & Rain Warnings';

  @override
  String get temperatureUnit => 'Temperature Unit';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Notifications';

  @override
  String get continueWatchingDescription => 'Show recently watched movies and TV shows from supported apps on your home screen';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get openApp => 'Open';

  @override
  String get noBlockedAppsDesc => 'All applications are currently allowed to show notifications';

  @override
  String get notificationsAllowed => 'Notifications Allowed';

  @override
  String get notificationsBlocked => 'Notifications Blocked';

  @override
  String get dpadDismissHint => 'Left: Dismiss • OK: Options';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get profilesTitle => 'Profiles';

  @override
  String get homeScreenTitle => 'Home screen';

  @override
  String get remoteAndSearchTitle => 'Remote & search';

  @override
  String get parentSettingsTitle => 'Parent settings';

  @override
  String get tvPowerTitle => 'TV & power';

  @override
  String get setupPermissionsTitle => 'Setup & permissions';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get familyAppsTitle => 'Hearth on other profiles';

  @override
  String get cardStyleTitle => 'Card style';

  @override
  String get dockLabelsTitle => 'Dock & labels';

  @override
  String get animationsSoundTitle => 'Animations & sound';

  @override
  String get haPanelTitle => 'Dashboard panel';

  @override
  String get lookTitle => 'Look';

  @override
  String get remoteButtonsTitle => 'Remote buttons';

  @override
  String get profilePairingTitle => 'Profile Pairing';

  @override
  String get haTvStatusTitle => 'TV status';

  @override
  String get continueWatchingAppsTitle => 'Continue Watching Apps';

  @override
  String get cardSizeTitle => 'Card Size';

  @override
  String get maxItemsTitle => 'Maximum Items';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get tryAgain => 'Try again';

  @override
  String get notNow => 'Not now';

  @override
  String get done => 'Done';

  @override
  String get remove => 'Remove';

  @override
  String get homeNothingToWatch => 'Nothing to watch right now';

  @override
  String get errorScreenTitle => 'Something went wrong';

  @override
  String get appInfoAddToCategory => 'Add to Category';

  @override
  String get appInfoAddToFavorites => 'Add to Fav';

  @override
  String get appInfoRemoveFromFavorites => 'Remove from Fav';

  @override
  String get appInfoSetCustomBanner => 'Set Custom Banner';

  @override
  String get appInfoClearCustomBanner => 'Clear Custom Banner';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Failed to set banner: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Failed to clear banner: $error';
  }

  @override
  String get cwGridAll => 'All';

  @override
  String get cwRowSeeAll => 'See all';

  @override
  String cwRowInProgress(int count) {
    return '$count in progress';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '$hours h $minutes min left';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '$minutes min left';
  }

  @override
  String get watchNextInfoRemove => 'Remove from Continue Watching';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Hide all from $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Play / Resume';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Open $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'App Info';

  @override
  String get dataWidgetGrantPermission => 'Grant Usage Permission';

  @override
  String dataWidgetDaily(String usage) {
    return 'Daily: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Weekly: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Monthly: $usage';
  }

  @override
  String weatherWidgetTemperatureWithWarning(String temperature, String warning) {
    return '$temperature • $warning';
  }

  @override
  String weatherTextRain(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Rain today',
        'tomorrow': 'Rain tomorrow',
        'other': 'Rain on $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Snow today',
        'tomorrow': 'Snow tomorrow',
        'other': 'Snow on $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Storm today',
        'tomorrow': 'Storm tomorrow',
        'other': 'Storm on $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$percent% $forecast';
  }

  @override
  String searchWatchOn(String apps) {
    return 'Watch on $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Rent or buy on $app';
  }

  @override
  String get searchMoreWaysToWatch => 'More ways to watch (Google TV)';

  @override
  String get searchListening => 'Listening…';

  @override
  String get searchHint => 'Search films and shows';

  @override
  String get searchEntryHelp => 'Type, use the mic, or type on your phone with the Google TV app.';

  @override
  String get searchTabWatchNow => 'Watch now';

  @override
  String get searchTabRentOrBuy => 'Rent or buy';

  @override
  String get searchTabOtherApps => 'Other apps';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Rent or buy · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Where to watch: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'On $services (not on this TV)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Nothing here for “$query”.';
  }

  @override
  String get searchGridTmdbNotice => 'Where to watch from TMDB (via JustWatch). This product uses the TMDB API but is not endorsed or certified by TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps or $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Ask Google “$query”';
  }

  @override
  String get searchAskGoogleDetail => 'For questions, the weather and anything else that isn\'t a show';

  @override
  String searchSearchingFor(String query) {
    return 'Searching for “$query”…';
  }

  @override
  String get searchFailed => 'Couldn\'t search right now. Check the internet connection.';

  @override
  String searchNothingFound(String query) {
    return 'Nothing found for “$query”';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Nothing for “$query” in your apps right now';
  }

  @override
  String get searchSeeMoreResults => 'See where else it\'s available in More results.';

  @override
  String get searchMoreResults => 'More results';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles',
      one: '1 title',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Ask Google';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => 'Film';

  @override
  String get searchKindSeries => 'Series';
}
