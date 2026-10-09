import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get aboutFlauncher => 'Hearth के बारे में';

  @override
  String get addSection => 'अनुभाग जोड़ें';

  @override
  String get alphabetical => 'वर्णानुक्रम';

  @override
  String get appCardHighlightAnimation => 'ऐप कार्ड हाइलाइट एनिमेशन';

  @override
  String get appInfo => 'ऐप जानकारी';

  @override
  String get appKeyClick => 'कुंजी दबाने पर क्लिक ध्वनि';

  @override
  String get applications => 'एप्लिकेशन';

  @override
  String get autoHideAppBar => 'स्टेटस बार को स्वचालित रूप से छिपाएं';

  @override
  String get backButtonAction => 'बैक बटन एक्शन';

  @override
  String get category => 'श्रेणी';

  @override
  String get columnCount => 'कॉलम संख्या';

  @override
  String get date => 'दिनांक';

  @override
  String get dateAndTimeFormat => 'दिनांक और समय प्रारूप';

  @override
  String get delete => 'हटाएं';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'कुछ न करें';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'स्क्रीनसेवर दिखाएं';

  @override
  String get dialogOptionBackButtonActionShowClock => 'घड़ी दिखाएं';

  @override
  String get dialogTextNoFileExplorer => 'कृपया चित्र चुनने के लिए फ़ाइल एक्सप्लोरर इंस्टॉल करें।';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (श्रेणी)';
  }

  @override
  String get gradient => 'ग्रेडिएंट';

  @override
  String get favoriteApps => 'पसंदीदा ऐप्स';

  @override
  String get grid => 'ग्रिड';

  @override
  String get height => 'ऊंचाई';

  @override
  String get hide => 'छिपाएं';

  @override
  String get hiddenApplications => 'छिपे हुए ऐप्स';

  @override
  String get launcherSections => 'अनुभाग';

  @override
  String get layout => 'लेआउट';

  @override
  String get loading => 'लोड हो रहा है';

  @override
  String get manual => 'मैनुअल';

  @override
  String get modifySection => 'अनुभाग संशोधित करें';

  @override
  String get name => 'नाम';

  @override
  String get newSection => 'नया अनुभाग';

  @override
  String get nonTvApplications => 'गैर-टीवी ऐप्स';

  @override
  String get open => 'खोलें';

  @override
  String get picture => 'चित्र';

  @override
  String removeFrom(String name) {
    return '$name से हटाएं';
  }

  @override
  String get reorder => 'पुन: व्यवस्थित करें';

  @override
  String get row => 'पंक्ति';

  @override
  String get rowHeight => 'पंक्ति की ऊंचाई';

  @override
  String get save => 'सहेजें';

  @override
  String get spacer => 'स्पेसर';

  @override
  String get statusBar => 'स्टेटस बार';

  @override
  String get show => 'दिखाएं';

  @override
  String get showCategoryTitles => 'श्रेणी शीर्षक दिखाएं';

  @override
  String get showCategoryAppCount => 'श्रेणियों में ऐप की संख्या दिखाएं';

  @override
  String get hideHighlightOutlineOnHomescreen => 'होम स्क्रीन पर हाइलाइट आउटलाइन छिपाएं';

  @override
  String get appSelectorTransitionAnimation => 'ऐप सेलेक्टर ट्रांज़िशन एनिमेशन';

  @override
  String get sort => 'क्रमबद्ध करें';

  @override
  String get systemSettings => 'सिस्टम सेटिंग्स';

  @override
  String get textEmptyCategory => 'यह श्रेणी खाली है।';

  @override
  String get time => 'समय';

  @override
  String get tvApplications => 'टीवी ऐप्स';

  @override
  String get type => 'प्रकार';

  @override
  String get uninstall => 'अनइंस्टॉल करें';

  @override
  String get wallpaper => 'वॉलपेपर';

  @override
  String get withEllipsisAddTo => 'इसमें जोड़ें...';

  @override
  String get timeBasedWallpaper => 'समय आधारित वॉलपेपर';

  @override
  String get pickDayWallpaper => 'दिन का वॉलपेपर चुनें';

  @override
  String get pickNightWallpaper => 'रात का वॉलपेपर चुनें';

  @override
  String get inputs => 'इनपुट';

  @override
  String get inputSources => 'इनपुट स्रोत';

  @override
  String get backupAndRestore => 'बैकअप और पुनर्स्थापना';

  @override
  String get exportBackup => 'बैकअप निर्यात करें';

  @override
  String get importBackup => 'बैकअप आयात करें';

  @override
  String exportSuccess(String path) {
    return 'बैकअप सफलतापूर्वक $path में निर्यात किया गया';
  }

  @override
  String get importSuccess => 'बैकअप सफलतापूर्वक आयात किया गया';

  @override
  String get importConfirm => 'क्या आप वाकई बैकअप आयात करना चाहते हैं? यह आपकी वर्तमान सेटिंग्स और लेआउट को ओवरराइट कर देगा।';

  @override
  String importError(String error) {
    return 'बैकअप आयात करने में विफल: $error';
  }

  @override
  String exportError(String error) {
    return 'बैकअप निर्यात करने में विफल: $error';
  }

  @override
  String get shareBackup => 'बैकअप साझा करें';

  @override
  String get notificationBell => 'सूचना घंटी';

  @override
  String get autoHideNotificationBell => 'सूचना घंटी को स्वचालित रूप से छिपाएं';

  @override
  String get continueWatching => 'देखना जारी रखें';

  @override
  String get showContinueWatchingOnHome => 'होम पर \'देखना जारी रखें\' दिखाएं';

  @override
  String get permissionDeniedContinueWatching => '\'देखना जारी रखें\' दिखाने के लिए अनुमति आवश्यक है';

  @override
  String get system => 'सिस्टम';

  @override
  String get accentColor => 'एक्सेंट रंग';

  @override
  String get dataUsagePeriod => 'डेटा उपयोग अवधि';

  @override
  String get notificationAccess => 'सूचना पहुंच';

  @override
  String get watchNextAccess => 'Watch Next पहुंच';

  @override
  String get granted => 'प्रदान किया गया';

  @override
  String get permissionRequired => 'अनुमति आवश्यक है';

  @override
  String get systemWidePopupAlert => 'सिस्टम-वाइड पॉपअप अलर्ट';

  @override
  String get overlayPermissionRequired => 'ओवरले अनुमति आवश्यक है';

  @override
  String get enabled => 'सक्षम';

  @override
  String get disabled => 'अक्षम';

  @override
  String get showAppNamesBelowIcons => 'आइकन के नीचे ऐप नाम दिखाएं';

  @override
  String get dataUsage => 'डेटा उपयोग';

  @override
  String get networkIndicator => 'नेटवर्क संकेतक';

  @override
  String get startOnBoot => 'बूट पर शुरू करें (Google TV / Fire TV)';

  @override
  String get appLanguage => 'भाषा';

  @override
  String get systemDefault => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get english => 'अंग्रेज़ी';

  @override
  String get spanish => 'स्पेनिश';

  @override
  String get ukrainian => 'यूक्रेनियन';

  @override
  String get chinese => 'चीनी';

  @override
  String get french => 'फ्रेंच';

  @override
  String get german => 'जर्मन';

  @override
  String get japanese => 'जापानी';

  @override
  String get portuguese => 'पुर्तगाली';

  @override
  String get russian => 'रूसी';

  @override
  String get italian => 'इतालवी';

  @override
  String get hindi => 'हिन्दी';

  @override
  String get korean => 'कोरियाई';

  @override
  String get arabic => 'अरबी';

  @override
  String get turkish => 'तुर्की';

  @override
  String get hidePersistentNotifications => 'स्थायी सूचनाएं छिपाएं';

  @override
  String get blockedNotificationApps => 'अवरुद्ध ऐप्स';

  @override
  String get blockAppNotifications => 'सूचनाएं अवरुद्ध करें';

  @override
  String get unblockAppNotifications => 'सूचनाएं अनब्लॉक करें';

  @override
  String get noBlockedApps => 'कोई अवरुद्ध ऐप नहीं';

  @override
  String get persistentNotification => 'स्थायी';

  @override
  String get unblockAll => 'सभी अनब्लॉक करें';

  @override
  String get weather => 'मौसम';

  @override
  String get showWeatherWarnings => 'मौसम और बारिश की चेतावनी दिखाएं';

  @override
  String get temperatureUnit => 'तापमान इकाई';

  @override
  String get celsius => 'सेल्सियस (°C)';

  @override
  String get fahrenheit => 'फ़ारेनहाइट (°F)';

  @override
  String get notifications => 'सूचनाएं';

  @override
  String get continueWatchingDescription => 'होम स्क्रीन पर हाल ही में देखी गई फिल्में और टीवी शो दिखाएं';

  @override
  String get dismiss => 'हटाएं';

  @override
  String get openApp => 'खोलें';

  @override
  String get noBlockedAppsDesc => 'सभी ऐप्स को वर्तमान में सूचनाएं दिखाने की अनुमति है';

  @override
  String get notificationsAllowed => 'सूचनाएं चालू हैं';

  @override
  String get notificationsBlocked => 'सूचनाएं अवरुद्ध हैं';

  @override
  String get dpadDismissHint => 'बायां: हटाएं • ठीक है: विकल्प';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get profilesTitle => 'प्रोफ़ाइल';

  @override
  String get homeScreenTitle => 'होम स्क्रीन';

  @override
  String get remoteAndSearchTitle => 'रिमोट और खोज';

  @override
  String get parentSettingsTitle => 'अभिभावक सेटिंग्स';

  @override
  String get tvPowerTitle => 'टीवी और पावर';

  @override
  String get setupPermissionsTitle => 'सेटअप और अनुमतियाँ';

  @override
  String get updatesTitle => 'अपडेट';

  @override
  String get familyAppsTitle => 'अन्य प्रोफ़ाइल पर Hearth';

  @override
  String get cardStyleTitle => 'कार्ड शैली';

  @override
  String get dockLabelsTitle => 'डॉक और लेबल';

  @override
  String get animationsSoundTitle => 'एनिमेशन और ध्वनि';

  @override
  String get haPanelTitle => 'डैशबोर्ड पैनल';

  @override
  String get lookTitle => 'रूप';

  @override
  String get remoteButtonsTitle => 'रिमोट बटन';

  @override
  String get profilePairingTitle => 'प्रोफ़ाइल पेयरिंग';

  @override
  String get haTvStatusTitle => 'टीवी की स्थिति';

  @override
  String get continueWatchingAppsTitle => 'देखना जारी रखें ऐप्स';

  @override
  String get cardSizeTitle => 'कार्ड का आकार';

  @override
  String get maxItemsTitle => 'अधिकतम आइटम';
}
