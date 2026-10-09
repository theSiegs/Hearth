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
  String get systemSettings => 'Google TV settings';

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
  String get remoteAndSearchTitle => 'Remote';

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
  String get appInfoAddToFavorites => 'Add to Favorites';

  @override
  String get appInfoRemoveFromFavorites => 'Remove from Favorites';

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

  @override
  String get gradientNamePitchBlack => 'Pitch Black';

  @override
  String get gradientNameGreatWhale => 'Great Whale';

  @override
  String get gradientNameViciousStance => 'Vicious Stance';

  @override
  String get gradientNameTeenNotebook => 'Teen Notebook';

  @override
  String get gradientNameOldHat => 'Old Hat';

  @override
  String get gradientNameBurningSpring => 'Burning Spring';

  @override
  String get gradientNameDesertHump => 'Desert Hump';

  @override
  String get gradientNameFarawayRiver => 'Faraway River';

  @override
  String get gradientNameSaintPetersburg => 'Saint Petersburg';

  @override
  String get gradientNameAfricanField => 'African Field';

  @override
  String get gradientNameGrassShampoo => 'Grass Shampoo';

  @override
  String get updateErrorNoApk => 'No release has an APK for this device';

  @override
  String get updateErrorCheckFailed => 'Couldn\'t check for updates';

  @override
  String get updateErrorDownloadFailed => 'Couldn\'t download the update';

  @override
  String get serviceHearthTubeDescription => 'YouTube for Hearth; follows your Hearth profile';

  @override
  String get haSummaryOn => 'On';

  @override
  String get haSummaryOff => 'Off';

  @override
  String get haSummaryReporting => 'Reporting';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Turn on Home Button Fix ($path); it shows the pop-ups.';
  }

  @override
  String get haNotificationsShow => 'Show Home Assistant notifications';

  @override
  String get haNotificationsSendTest => 'Send a test notification';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'In Home Assistant, add the \"Notifications for Android TV / Fire TV\" integration with host $host. Then send notifications to it from automations, for example for the doorbell or when the laundry is done.\n\nOnly devices on your home network can send them (port 7676). Pop-ups appear over any app and need Home Button Fix ($path) to be on.';
  }

  @override
  String get haNotificationsThisTvIp => '(this TV\'s IP address)';

  @override
  String get haPanelSaved => 'Saved';

  @override
  String get haPanelSavedNoToken => 'Saved. Add an access token to sign in.';

  @override
  String get haPanelReceived => 'Received the address and token from your phone';

  @override
  String get haPanelRightEdge => 'Right at the right edge opens the panel';

  @override
  String get haSetUpFromPhone => 'Set up from your phone';

  @override
  String get haPanelTokenLabel => 'Long-lived access token';

  @override
  String get haPanelTokenSavedHint => 'Saved (type a new one to replace it)';

  @override
  String get haPanelDashboardLabel => 'Dashboard';

  @override
  String haPanelHelp(String tvStatus) {
    return 'On for this profile only. The panel shows a dashboard from the address under $tvStatus, signed in with the token. Create the token in Home Assistant while logged in as a non-admin user made for this TV (profile page, Security tab).';
  }

  @override
  String get haStatusReportingOff => 'Status reporting is off';

  @override
  String get haStatusSaved => 'Saved: reporting to Home Assistant';

  @override
  String get haStatusAddressLabel => 'Home Assistant address';

  @override
  String get haStatusWebhookLabel => 'Webhook ID';

  @override
  String get haStatusNowPlayingOn => 'Now playing: on';

  @override
  String get haStatusNowPlayingOff => 'Now playing: turn on notification access';

  @override
  String get haStatusHelp => 'The TV sends Home Assistant what\'s on: the app, what\'s playing, the Google TV profile, and kids screen time. It only sends to the address above, as changes happen.';

  @override
  String get haPhoneSetupNoNetwork => 'This TV isn\'t on the home network, so the phone can\'t reach it.';

  @override
  String get haPhoneSetupScan => 'Scan with a phone on the same Wi-Fi, paste the Home Assistant address and access token, and tap Send. The page only works while this is open.';

  @override
  String get profilesSwitchProfile => 'Switch profile';

  @override
  String get parentPinTitle => 'Parent PIN';

  @override
  String get parentPinOn => 'On';

  @override
  String get parentPinOff => 'Off';

  @override
  String get parentPinCurrent => 'Current parent PIN';

  @override
  String get parentPinRemove => 'Remove PIN';

  @override
  String get parentPinChange => 'Change PIN';

  @override
  String get parentPinNew => 'New parent PIN';

  @override
  String get parentPinNewSubtitle => 'Needed to change the launcher in Google TV kids profiles';

  @override
  String get parentPinConfirm => 'Enter the PIN again';

  @override
  String get parentPinAskTitle => 'Ask a parent';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Launcher settings are locked in kids profiles. A parent can set a PIN in $settings → $profiles → $parentPin from their own profile.';
  }

  @override
  String get parentPinKidsSubtitle => 'Kids profile: enter the parent PIN to change the launcher';

  @override
  String get parentPinWrong => 'WRONG PIN';

  @override
  String get parentPinEnter => 'ENTER PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Hi, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Setting up this profile…';

  @override
  String profilesKidsName(String name) {
    return '$name (kids)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (adult)';
  }

  @override
  String get pairingShowPicker => 'Show the picker';

  @override
  String get pairingAlwaysShowPicker => 'Always show the picker';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (matched by name)';
  }

  @override
  String get pairingNoMatchYet => 'No match yet: shows the picker';

  @override
  String get pairingOffSetUp => 'Profile Pairing is off. Set it up';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'When Hearth opens one of these apps, it picks the app profile paired with the Google TV profile. Hearth matches names by itself (\"$shortName\" goes with \"$fullName\"); change any pairing here. Without a match, the app\'s own picker shows.';
  }

  @override
  String get pairingAppNotInstalled => 'Not installed';

  @override
  String get pairingAppOff => 'Off: the app\'s own picker shows';

  @override
  String get pairingAppNotSeen => 'Open it once from Hearth so Hearth can learn its profiles';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profiles found',
      one: '1 profile found',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Match by name ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Match by name (no match yet)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile in $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Pair profiles in $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth hasn\'t seen this app\'s profiles yet. Open it once from Hearth, then come back.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Profiles in this app: $profiles. Google TV profiles appear here once Hearth has seen them.';
  }

  @override
  String get familyAppsAddTitle => 'Add Hearth to other profiles';

  @override
  String get familyAppsAddKids => 'This puts Hearth and HearthTube on your kids\' profiles, so HearthTube works there and Hearth can pick the right profile in streaming services.';

  @override
  String get familyAppsAddAdults => 'It also installs them on the TV\'s other adult profiles, so another adult doesn\'t have to set it up themselves.';

  @override
  String get familyAppsAddOnlyOwnApps => 'It only adds Hearth\'s own two apps, and you can undo it anytime with Remove below.';

  @override
  String get familyAppsAddFamilyLink => 'Each kid gets one Family Link \"app added\" notification.';

  @override
  String get familyAppsAddApproval => 'The first time, the TV asks \"Allow debugging?\" — choose Always allow; that\'s what lets Hearth do the setup.';

  @override
  String get familyAppsAdd => 'Add';

  @override
  String get familyAppsRemoveTitle => 'Remove Hearth from other profiles';

  @override
  String get familyAppsRemoveBody => 'This removes Hearth and HearthTube from your other profiles.';

  @override
  String get familyAppsRemoveFirst => 'If you plan to uninstall Hearth itself, run this first — otherwise its copies on the kids\' profiles can be stranded and need a computer to clear.';

  @override
  String get familyAppsUninstallTitle => 'Uninstall Hearth';

  @override
  String get familyAppsUninstallBody => 'This first removes Hearth and HearthTube from your other profiles, then uninstalls Hearth from this one.';

  @override
  String get familyAppsUninstallWhyHere => 'Uninstalling here — rather than from Android\'s settings — makes sure nothing is left behind on the kids\' profiles.';

  @override
  String get familyAppsApprovalFirstTitle => 'Finish the one-time approval first';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth couldn\'t clean up the other profiles yet — it needs the one-time \"Allow debugging?\" approval on the TV.';

  @override
  String get familyAppsApprovalFirstRetry => 'Approve it, then try Uninstall again, so nothing is left on the kids\' profiles.';

  @override
  String get familyAppsAddDone => 'Add done';

  @override
  String get familyAppsRemoveDone => 'Remove done';

  @override
  String get familyAppsAdded => 'Done. Hearth and HearthTube are now on your other profiles — see the list below.';

  @override
  String get familyAppsRemoved => 'Done. Hearth and HearthTube have been removed from your other profiles.';

  @override
  String get familyAppsNothingToSetUp => 'There are no other profiles to set up yet.';

  @override
  String get familyAppsFailedTitle => 'Couldn\'t set up the profiles';

  @override
  String get familyAppsFailedBody => 'Hearth needs a one-time approval on the TV before it can set up the other profiles.';

  @override
  String get familyAppsFailedRetry => 'On the TV, choose Always allow when it asks to \"Allow debugging?\", then try again.';

  @override
  String get familyAppsAlsoAdults => 'Also set up other adult profiles';

  @override
  String get familyAppsOn => 'On';

  @override
  String get familyAppsOff => 'Off';

  @override
  String get familyAppsNoneYet => 'No other profiles set up yet.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: installed';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: installed, protected';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: not installed';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: not installed, protected';
  }

  @override
  String get familyAppsUnnamedKids => 'A kids profile';

  @override
  String get familyAppsUnnamedAdult => 'An adult profile';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'On the next screen, scroll down to Services, select \"$service\", then turn on Enable and confirm. Press Back until you\'re home again.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'If Android says the setting is restricted, run this once from a computer:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth as the home app';

  @override
  String get setupDefaultLauncherWhy => 'Keeps kids profiles from blocking Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'On the next screen, choose Hearth.';

  @override
  String get setupHomeFixTitle => 'Home Button Fix';

  @override
  String get setupHomeFixWhy => 'The Home button opens Hearth instead of Google TV.';

  @override
  String get setupNotificationsTitle => 'Notification access';

  @override
  String get setupNotificationsWhy => 'Shows notifications and what\'s playing.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'On the next screen, select \"$service\" and allow it.';
  }

  @override
  String get setupInstallTitle => 'Installing updates';

  @override
  String get setupInstallWhy => 'Lets Hearth update itself and install companion apps.';

  @override
  String get setupInstallInstructions => 'On the next screen, turn on Hearth.';

  @override
  String get setupPairingWhy => 'Picks your profile in Netflix, Disney+, Apple TV, HBO Max and Paramount+.';

  @override
  String get setupVoiceTitle => 'Hearth voice';

  @override
  String get setupVoiceWhy => 'Lets Profile Pairing hear Netflix\'s profile screen. Other apps keep Google\'s voice.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'On the next screen, under Preferred engine, choose \"$engine\", then OK on the warning (Hearth only listens to the streaming apps). Press Back to return.';
  }

  @override
  String get setupOpenSettings => 'Open Settings';

  @override
  String get setupAdbFallback => 'This TV wouldn\'t open that Settings screen. Run this once from a computer instead:';

  @override
  String setupProgress(int done, int total) {
    return '$done of $total done';
  }

  @override
  String get setupOptional => 'Optional';

  @override
  String get homeButtonFixOffTitle => 'Home Button Fix is off';

  @override
  String get homeButtonFixOffBody => 'Hearth\'s accessibility service has stopped, usually after an update. Until it is back on, the Home button may open Google TV instead of Hearth, and profile switches aren\'t followed.';

  @override
  String get homeButtonFixStuck => 'Android still lists it as on, but it isn\'t running. Turn Hearth off and on again in Accessibility settings to restart it.';

  @override
  String get homeButtonFixRestricted => 'If Hearth\'s switch there is greyed out, Android is blocking it because this update was installed from a download. Run this from a computer connected to the TV, then turn Hearth on:';

  @override
  String get homeButtonFixDontRemind => 'Don\'t remind me';

  @override
  String get homeButtonFixOpenSettings => 'Open Accessibility settings';

  @override
  String get remoteButtonsRemapButton => 'Remap a button';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Button $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normal';

  @override
  String get remoteButtonsCaptureTitle => 'Press a remote button';

  @override
  String get remoteButtonsCaptureBody => 'Press the button you want to remap. Press Back to cancel.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Turn on Home Button Fix first';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Remapping needs Home Button Fix ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Can\'t remap that button';

  @override
  String get remoteButtonsCantRemapBody => 'The arrows, OK, Back, Home and power keep their normal job.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Press: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Hold: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Tap for Hearth search, hold for Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Only on Hearth\'s home screen: On';

  @override
  String get remoteButtonsHomeOnlyOff => 'Only on Hearth\'s home screen: Off';

  @override
  String get remoteButtonsRestore => 'Restore normal button';

  @override
  String get remoteButtonsActionTitle => 'Action';

  @override
  String get remoteButtonsActionApp => 'Open an app…';

  @override
  String get remoteButtonsActionInput => 'Switch to a TV input…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Switch profile (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth search (voice)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth search (keyboard)';

  @override
  String get remoteButtonsActionHome => 'Hearth home';

  @override
  String get remoteButtonsActionSleep => 'Sleep';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android settings';

  @override
  String get remoteButtonsPickAppTitle => 'Open an app';

  @override
  String get remoteButtonsPickInputTitle => 'Switch to a TV input';

  @override
  String get remoteButtonsHaConnectTitle => 'Connect Home Assistant first';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Set up the Home Assistant panel ($panel > $row), then try again.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Scene: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Run: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Press: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Toggle: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nPress: $press  ·  Hold: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nPress: $press  ·  Hold: $hold  ·  Home screen only';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Needs Home Button Fix ($path). A button with only a Hold action does that action on a press too. Hearth search opens HearthTube\'s own search while HearthTube is in front. Remaps pause while a kids screen time screen is showing.';
  }

  @override
  String get tvPowerScreensaver => 'Screensaver (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth uses Google TV\'s screensaver. Choose Google Photos (and which albums) or another source there.';

  @override
  String get tvPowerSleepWhenIdle => 'Sleep when idle';

  @override
  String get tvPowerSleepOff => 'Off';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'Playing video or music counts as activity. Needs Home Button Fix ($path).';
  }

  @override
  String get accentPurple => 'Purple';

  @override
  String get accentTeal => 'Teal';

  @override
  String get accentBlue => 'Blue';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentPink => 'Pink';

  @override
  String get accentGreen => 'Green';

  @override
  String get accentWhite => 'White';

  @override
  String get accentYellow => 'Yellow';

  @override
  String get accentRed => 'Red';

  @override
  String get accentCyan => 'Cyan';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentLime => 'Lime';

  @override
  String get accentAmber => 'Amber';

  @override
  String get accentRose => 'Rose';

  @override
  String get accentIceBlue => 'Ice Blue';

  @override
  String get accentSelected => 'Selected Accent';

  @override
  String get cardStyleDefault => 'Default';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Glow';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Classic';

  @override
  String get cardStyleMinimal => 'Minimal';

  @override
  String get cardStyleCapsule => 'Capsule';

  @override
  String get dockFavoritesDock => 'Favorites dock';

  @override
  String get dockFavoritesDockDescription => 'Shows Favorites as a bar along the bottom of the home screen, with Continue Watching above it and your other sections below. Its corners follow the theme.';

  @override
  String get dockFrosted => 'Frosted dock';

  @override
  String get dockDark => 'Dark dock';

  @override
  String get dockShadow => 'Dock shadow';

  @override
  String get dockBlurWallpaperBelow => 'Blur wallpaper below the dock';

  @override
  String get wallpaperMatchSelectedApp => 'Match selected app';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing Photo of the Day';

  @override
  String get wallpaperRefreshNow => 'Refresh Now';

  @override
  String get wallpaperBingError => 'Couldn\'t reach Bing. Check your network connection.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Temperature Unit: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Weather location: not set';

  @override
  String weatherLocationValue(String place) {
    return 'Weather location: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Couldn\'t load the weather. It will retry automatically.';

  @override
  String get statusBarWeatherSourceHint => 'Choose a weather location above (weather from Open-Meteo, free, no account). Without one, weather comes from the Breezy Weather app if it\'s installed with Gadgetbridge sharing on.';

  @override
  String get weatherLocationTitle => 'Weather location';

  @override
  String get weatherLocationHint => 'City or town';

  @override
  String get weatherLocationNoResults => 'No places found';

  @override
  String get weatherLocationSearchError => 'Couldn\'t reach the weather service. Check the network connection.';

  @override
  String get weatherLocationPrivacyNote => 'Weather by Open-Meteo.com: free, no account. Only the chosen place\'s coordinates are sent.';

  @override
  String get weatherLocationSearch => 'Search';

  @override
  String get dateTimeInvalidFormat => 'Invalid format';

  @override
  String get dateTimeSelectFormats => 'Select formats below';

  @override
  String get dataUsageDaily => 'Daily';

  @override
  String get dataUsageWeekly => 'Weekly';

  @override
  String get dataUsageMonthly => 'Monthly';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Blocked from Continue Watching ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Blocked from Continue Watching';

  @override
  String get cwAppsUnblock => 'Unblock';

  @override
  String get cwAppsUnblockAllApps => 'Unblock All Apps';

  @override
  String get cwAppsNoBlockedApps => 'No Blocked Apps';

  @override
  String get cwAppsNoBlockedAppsMessage => 'All supported apps can show items in Continue Watching.';

  @override
  String get cwAppsWithContinueWatching => 'Apps with Continue Watching';

  @override
  String get cwAppsWithContinueWatchingHint => 'Apps currently providing Watch Next items on your home screen';

  @override
  String get cwAppsNoActiveApps => 'No apps are currently providing Continue Watching items.\nWhen supported apps (such as SmartTube or streaming services) add items, they will appear here.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active items',
      one: '1 active item',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'All Installed Apps';

  @override
  String get cwAppsAllInstalledAppsHint => 'Toggle off to block any app from adding items to Continue Watching';

  @override
  String get cwAppsBlocked => 'Blocked';

  @override
  String get cwAppsAllowed => 'Allowed';

  @override
  String cwCardSizeOption(int height, String size) {
    return '$height dp • $size';
  }

  @override
  String cwCardSizeDimensions(int width, int height) {
    return '$width × $height dp';
  }

  @override
  String cwCardSizeDp(int height) {
    return '$height dp';
  }

  @override
  String cwCardSizeDpNamed(int height, String size) {
    return '$height dp ($size)';
  }

  @override
  String get cwCardSizeExtraSmall => 'Extra Small';

  @override
  String get cwCardSizeVerySmall => 'Very Small';

  @override
  String get cwCardSizeSmall => 'Small';

  @override
  String get cwCardSizeCompact => 'Compact';

  @override
  String get cwCardSizeMediumSmall => 'Medium Small';

  @override
  String get cwCardSizeMedium => 'Medium';

  @override
  String get cwCardSizeStandardDefault => 'Standard (Default)';

  @override
  String get cwCardSizeStandard => 'Standard';

  @override
  String get cwCardSizeMediumLarge => 'Medium Large';

  @override
  String get cwCardSizeLarge => 'Large';

  @override
  String get cwCardSizeVeryLarge => 'Very Large';

  @override
  String get cwCardSizeExtraLarge => 'Extra Large';

  @override
  String get cwCardSizeHuge => 'Huge';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Items',
      one: '1 Item',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Display up to $count recent items',
      one: 'Display up to 1 recent item',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Default';
  }

  @override
  String get cwUnlimited => 'Unlimited';

  @override
  String get cwMaxItemsAll => 'Display all available items';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Playback Progress Bar';

  @override
  String get cwPlaybackPercentage => 'Playback Percentage';

  @override
  String get cwEpisodeDetails => 'Episode & Video Details';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocked',
      one: '1 blocked',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Manage';

  @override
  String get cwRestoreHiddenPrograms => 'Restore Hidden Programs';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden',
      one: '1 hidden',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'All hidden programs restored';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next Access (ADB Required)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV requires the READ_WRITE_WATCH_NEXT_PROGRAMS permission for launchers to read and display Continue Watching rows from installed apps.\n\nTo grant this permission, connect your TV via ADB and run:';

  @override
  String get appsNoApplicationsFound => 'No applications found';

  @override
  String get appDetailsAddToFavorites => 'Add to Favorites';

  @override
  String get appDetailsRemoveFromFavorites => 'Remove from Favorites';

  @override
  String get appDetailsAddToCategory => 'Add to Category';

  @override
  String get sectionsCustomOption => 'Custom...';

  @override
  String get sectionsSelectName => 'Select a name';

  @override
  String get sectionsCustomName => 'Custom Name';

  @override
  String get sectionsSortLastUsed => 'Last Used';

  @override
  String get sectionsReorderHint => 'Select with ◄ / ► then use ▲ / ▼ to reorder';

  @override
  String get inputsNoneDetected => 'No inputs detected';

  @override
  String get notifClearAll => 'Clear All';

  @override
  String get notifAllCaughtUp => 'All caught up!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Block Notifications ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Open $app';
  }

  @override
  String get notifAccessAdbTitle => 'Notification Access (ADB Required)';

  @override
  String get notifAccessAdbMessage => 'Android TV does not provide a system settings screen for \"Notification Access\" (listening to notifications from other apps).\n\nNote: Enabling \"Show notifications\" in TV App Settings only controls outgoing notifications from this app, not Notification Access.\n\nTo grant Notification Access, connect your TV via ADB and run:';

  @override
  String get notifOpenAppInfo => 'Open App Info';

  @override
  String get notifOverlayPermissionTitle => 'Overlay Permission';

  @override
  String get notifOverlayAdbMessage => 'On this device, the Overlay Permission settings screen could not be opened automatically.\n\nTo enable overlay popups, grant permission manually via ADB from a computer connected to the TV:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Blocked Apps ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'Use Google TV for now';

  @override
  String get backupShareText => 'Hearth Backup';

  @override
  String get backupShareFailedTitle => 'Share Failed';

  @override
  String backupShareFailed(String error) {
    return 'Failed to share backup: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Export Success';

  @override
  String get backupExportFailedTitle => 'Export Failed';

  @override
  String get backupImportSuccessTitle => 'Import Success';

  @override
  String get backupImportFailedTitle => 'Import Failed';

  @override
  String get backupImport => 'Import';

  @override
  String backupLoadError(String error) {
    return 'Error loading backups: $error';
  }

  @override
  String get backupNoFiles => 'No backup files found.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date ($size)';
  }

  @override
  String backupSizeBytes(String size) {
    return '$size B';
  }

  @override
  String backupSizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String backupSizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String get updateCheckForUpdatesTitle => 'Check for Updates';

  @override
  String updateCurrentVersion(String version) {
    return 'Current version: $version';
  }

  @override
  String get updateChecking => 'Checking GitHub for a new release…';

  @override
  String get updateUpToDate => 'You\'re on the latest version.';

  @override
  String updateVersionAvailable(String version) {
    return 'Version $version is available';
  }

  @override
  String updateDownloading(String percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateDownloadedHint => 'Downloaded. If the installer didn\'t open, your device may need\n\"Install unknown apps\" permission granted for Hearth.';

  @override
  String get updateSomethingWentWrong => 'Something went wrong';

  @override
  String get updateDownloadAndInstall => 'Download & Install';

  @override
  String get updateRetryInstall => 'Retry Install';

  @override
  String get updateCheckAgain => 'Check Again';

  @override
  String get updatesInstallPermissionTitle => 'Allow Hearth to install apps';

  @override
  String get updatesInstallPermissionMessage => 'On the next screen, find Hearth and turn it on, then press Back. The install continues when you\'re back here.';

  @override
  String get updatesOpenSettings => 'Open Settings';

  @override
  String get updatesCheckFailed => 'Couldn\'t check for updates';

  @override
  String get updatesInstallerNotStarted => 'The installer didn\'t start';

  @override
  String get updatesCheckForUpdates => 'Check for updates';

  @override
  String get updatesAutoUpdate => 'Update automatically';

  @override
  String get updatesAutoUpdateDescription => 'Hearth checks daily and installs updates to apps it installed, when they\'re not in use';

  @override
  String get updatesIncludePrereleases => 'Include pre-releases';

  @override
  String get updatesIncludePrereleasesDescription => 'Early test builds of Hearth and HearthTube. They may be unfinished.';

  @override
  String get updatesFooter => 'Installed from each app\'s GitHub releases. After Hearth installs or updates an app once, its updates install without asking, and the app leaves updating to Hearth.';

  @override
  String get updatesChecking => 'Checking…';

  @override
  String get updatesInstall => 'Install';

  @override
  String updatesUpdateTo(String version) {
    return 'Update to $version';
  }

  @override
  String get updatesUpToDate => 'Up to date';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get updatesInstalling => 'Installing…';

  @override
  String get updatesError => 'Error';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'Built on $launcher by $author and $original, with parts of $parts';
  }

  @override
  String get aboutDescription => 'A private, family-friendly launcher for Google TV, with Google TV profiles and Home Assistant built in. Ad-free and tracker-free.';

  @override
  String get aboutHearthOnGitHub => 'Hearth on GitHub';

  @override
  String get aboutCredits => 'Credits';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher fork · $author';
  }

  @override
  String get aboutLicense => 'Free software under the GNU GPL v3, like the projects it builds on.';

  @override
  String get familyAppsStatusInstalled => 'Installed';

  @override
  String get familyAppsStatusPartial => 'Partial';

  @override
  String get familyAppsStatusNotInstalled => 'Not installed';

  @override
  String get familyAppsStatusAtRisk => 'At risk';

  @override
  String get familyAppsAtRiskDetail => 'Google TV will remove the unprotected apps here the next time this profile starts. Use Add again to protect them.';

  @override
  String get profilePinRow => 'Profile PIN';

  @override
  String get profilePinNone => 'None';

  @override
  String get profilePinSaved => 'Saved';

  @override
  String get profilePinRejected => 'Saved — not accepted last time';

  @override
  String get profilePinPaused => 'Saved — paused (the app changed)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth can’t type PINs in $app yet';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$profile’s PIN in $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'Hearth types it behind the “logging in as” card when $app asks. It stays on this TV, encrypted, and is never shown.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Set a parent PIN first ($settings → $profiles → $parentPin): saving a profile’s PIN needs it.';
  }

  @override
  String get profilePinSaveFailed => 'Couldn’t save the PIN.';

  @override
  String get profileLockNow => 'Lock Profile';

  @override
  String get profileLockOnSleep => 'Lock when the TV sleeps';

  @override
  String get profileLockEveryTime => 'Every time';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'After $minutes min asleep';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Uses Google TV\'s own profile lock: turn it on for your account in Google TV Settings → Accounts & Sign In → your account → Profile lock.';

  @override
  String get aboutWallpaperPhoto => 'WALLPAPER PHOTO';

  @override
  String get updateErrorWrongApp => 'This download isn\'t an update for this Hearth';
}
