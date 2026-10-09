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
  String get familyAppsIntro => 'Put Hearth and HearthTube on your other Google TV profiles. On kids\' profiles this is needed for HearthTube to work and for Hearth to pick the right profile in Netflix, Disney+ and other apps. On adult profiles it\'s just a convenience, so they don\'t have to install them by hand.';

  @override
  String get familyAppsAddTitle => 'Add Hearth to other profiles';

  @override
  String get familyAppsAddKids => 'This puts Hearth and HearthTube on your kids\' profiles, so HearthTube works there and Hearth can pick the right profile in apps like Netflix and Disney+.';

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
    return '$app: installed, kept';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: not installed';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: not installed, kept';
  }

  @override
  String get familyAppsUnnamedKids => 'A kids profile';

  @override
  String get familyAppsUnnamedAdult => 'An adult profile';
}
