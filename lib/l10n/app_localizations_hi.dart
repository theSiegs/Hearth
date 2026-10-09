import 'package:intl/intl.dart' as intl;

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
  String get systemSettings => 'Google TV सेटिंग्स';

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
  String get remoteAndSearchTitle => 'रिमोट';

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

  @override
  String get ok => 'ठीक है';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get close => 'बंद करें';

  @override
  String get tryAgain => 'फिर से कोशिश करें';

  @override
  String get notNow => 'अभी नहीं';

  @override
  String get done => 'हो गया';

  @override
  String get remove => 'हटाएँ';

  @override
  String get homeNothingToWatch => 'अभी देखने के लिए कुछ नहीं है';

  @override
  String get errorScreenTitle => 'कुछ गलत हो गया';

  @override
  String get appInfoAddToCategory => 'श्रेणी में जोड़ें';

  @override
  String get appInfoAddToFavorites => 'पसंदीदा में जोड़ें';

  @override
  String get appInfoRemoveFromFavorites => 'पसंदीदा से हटाएं';

  @override
  String get appInfoSetCustomBanner => 'कस्टम बैनर सेट करें';

  @override
  String get appInfoClearCustomBanner => 'कस्टम बैनर हटाएं';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'बैनर सेट नहीं हो सका: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'बैनर हटाया नहीं जा सका: $error';
  }

  @override
  String get cwGridAll => 'सभी';

  @override
  String get cwRowSeeAll => 'सभी देखें';

  @override
  String cwRowInProgress(int count) {
    return '$count जारी';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '$hours घं $minutes मि बाकी';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '$minutes मि बाकी';
  }

  @override
  String get watchNextInfoRemove => 'देखना जारी रखें से हटाएं';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return '$appName से सभी छिपाएं';
  }

  @override
  String get watchNextInfoPlayResume => 'चलाएं / फिर से शुरू करें';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '$appName खोलें';
  }

  @override
  String get watchNextInfoAppInfo => 'ऐप जानकारी';

  @override
  String get dataWidgetGrantPermission => 'उपयोग अनुमति दें';

  @override
  String dataWidgetDaily(String usage) {
    return 'दैनिक: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'साप्ताहिक: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'मासिक: $usage';
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
        'today': 'आज बारिश',
        'tomorrow': 'कल बारिश',
        'other': '$day को बारिश',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'आज बर्फ़बारी',
        'tomorrow': 'कल बर्फ़बारी',
        'other': '$day को बर्फ़बारी',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'आज तूफ़ान',
        'tomorrow': 'कल तूफ़ान',
        'other': '$day को तूफ़ान',
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
    return '$apps पर देखें';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return '$app पर किराये पर लें या खरीदें';
  }

  @override
  String get searchMoreWaysToWatch => 'देखने के और तरीके (Google TV)';

  @override
  String get searchListening => 'सुन रहा है…';

  @override
  String get searchHint => 'फ़िल्में और शो खोजें';

  @override
  String get searchEntryHelp => 'टाइप करें, माइक इस्तेमाल करें, या Google TV ऐप से अपने फ़ोन पर टाइप करें।';

  @override
  String get searchTabWatchNow => 'अभी देखें';

  @override
  String get searchTabRentOrBuy => 'किराये पर लें या खरीदें';

  @override
  String get searchTabOtherApps => 'अन्य ऐप्स';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'किराये पर लें या खरीदें · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'कहां देखें: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return '$services पर (इस टीवी पर नहीं)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count परिणाम',
      one: '$count परिणाम',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'यहां “$query” के लिए कुछ नहीं है।';
  }

  @override
  String get searchGridTmdbNotice => 'कहां देखें की जानकारी TMDB से (JustWatch के ज़रिए)। यह उत्पाद TMDB API का उपयोग करता है, लेकिन TMDB द्वारा समर्थित या प्रमाणित नहीं है।';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps या $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Google से पूछें: “$query”';
  }

  @override
  String get searchAskGoogleDetail => 'सवालों, मौसम और शो के अलावा किसी भी चीज़ के लिए';

  @override
  String searchSearchingFor(String query) {
    return '“$query” खोजा जा रहा है…';
  }

  @override
  String get searchFailed => 'अभी खोज नहीं हो सकी। इंटरनेट कनेक्शन जांचें।';

  @override
  String searchNothingFound(String query) {
    return '“$query” के लिए कुछ नहीं मिला';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'अभी आपके ऐप्स में “$query” के लिए कुछ नहीं है';
  }

  @override
  String get searchSeeMoreResults => 'यह और कहां उपलब्ध है, और परिणाम में देखें।';

  @override
  String get searchMoreResults => 'और परिणाम';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count टाइटल',
      one: '$count टाइटल',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Google से पूछें';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => 'फ़िल्म';

  @override
  String get searchKindSeries => 'सीरीज़';

  @override
  String get gradientNamePitchBlack => 'गहरा काला';

  @override
  String get gradientNameGreatWhale => 'विशाल व्हेल';

  @override
  String get gradientNameViciousStance => 'उग्र मुद्रा';

  @override
  String get gradientNameTeenNotebook => 'किशोर नोटबुक';

  @override
  String get gradientNameOldHat => 'पुरानी टोपी';

  @override
  String get gradientNameBurningSpring => 'दहकता वसंत';

  @override
  String get gradientNameDesertHump => 'रेगिस्तानी टीला';

  @override
  String get gradientNameFarawayRiver => 'दूर की नदी';

  @override
  String get gradientNameSaintPetersburg => 'सेंट पीटर्सबर्ग';

  @override
  String get gradientNameAfricanField => 'अफ़्रीकी मैदान';

  @override
  String get gradientNameGrassShampoo => 'घास शैम्पू';

  @override
  String get updateErrorNoApk => 'किसी भी रिलीज़ में इस डिवाइस के लिए APK नहीं है';

  @override
  String get updateErrorCheckFailed => 'अपडेट की जांच नहीं हो सकी';

  @override
  String get updateErrorDownloadFailed => 'अपडेट डाउनलोड नहीं हो सका';

  @override
  String get serviceHearthTubeDescription => 'Hearth के लिए YouTube; आपकी Hearth प्रोफ़ाइल के साथ चलता है';

  @override
  String get haSummaryOn => 'चालू';

  @override
  String get haSummaryOff => 'बंद';

  @override
  String get haSummaryReporting => 'रिपोर्ट हो रही है';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'होम बटन फ़िक्स चालू करें ($path); यही पॉप-अप दिखाता है।';
  }

  @override
  String get haNotificationsShow => 'Home Assistant की सूचनाएं दिखाएं';

  @override
  String get haNotificationsSendTest => 'परीक्षण सूचना भेजें';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Home Assistant में, होस्ट $host के साथ \"Notifications for Android TV / Fire TV\" इंटीग्रेशन जोड़ें। फिर ऑटोमेशन से उसे सूचनाएं भेजें, जैसे दरवाज़े की घंटी के लिए या कपड़े धुल जाने पर।\n\nकेवल आपके होम नेटवर्क के डिवाइस ही इन्हें भेज सकते हैं (पोर्ट 7676)। पॉप-अप किसी भी ऐप के ऊपर दिखते हैं और इनके लिए होम बटन फ़िक्स ($path) चालू होना चाहिए।';
  }

  @override
  String get haNotificationsThisTvIp => '(इस टीवी का IP पता)';

  @override
  String get haPanelSaved => 'सहेजा गया';

  @override
  String get haPanelSavedNoToken => 'सहेजा गया। साइन इन करने के लिए एक्सेस टोकन जोड़ें।';

  @override
  String get haPanelReceived => 'आपके फ़ोन से पता और टोकन मिल गया';

  @override
  String get haPanelRightEdge => 'दाएं किनारे पर दायां बटन दबाने से पैनल खुलता है';

  @override
  String get haSetUpFromPhone => 'अपने फ़ोन से सेट अप करें';

  @override
  String get haPanelTokenLabel => 'लंबे समय तक चलने वाला एक्सेस टोकन';

  @override
  String get haPanelTokenSavedHint => 'सहेजा गया (बदलने के लिए नया टाइप करें)';

  @override
  String get haPanelDashboardLabel => 'डैशबोर्ड';

  @override
  String haPanelHelp(String tvStatus) {
    return 'केवल इस प्रोफ़ाइल के लिए चालू। पैनल $tvStatus में दिए गए पते से डैशबोर्ड दिखाता है, टोकन से साइन इन करके। Home Assistant में इस टीवी के लिए बनाए गए गैर-एडमिन उपयोगकर्ता से लॉग इन करके टोकन बनाएं (प्रोफ़ाइल पेज, सुरक्षा टैब)।';
  }

  @override
  String get haStatusReportingOff => 'स्थिति रिपोर्टिंग बंद है';

  @override
  String get haStatusSaved => 'सहेजा गया: Home Assistant को रिपोर्ट हो रहा है';

  @override
  String get haStatusAddressLabel => 'Home Assistant का पता';

  @override
  String get haStatusWebhookLabel => 'वेबहुक ID';

  @override
  String get haStatusNowPlayingOn => 'अभी चल रहा है: चालू';

  @override
  String get haStatusNowPlayingOff => 'अभी चल रहा है: सूचना पहुंच चालू करें';

  @override
  String get haStatusHelp => 'टीवी Home Assistant को बताता है कि क्या चल रहा है: ऐप, क्या प्ले हो रहा है, Google TV प्रोफ़ाइल, और बच्चों का स्क्रीन टाइम। यह केवल ऊपर दिए गए पते पर, बदलाव होने पर भेजता है।';

  @override
  String get haPhoneSetupNoNetwork => 'यह टीवी होम नेटवर्क पर नहीं है, इसलिए फ़ोन इस तक नहीं पहुंच सकता।';

  @override
  String get haPhoneSetupScan => 'उसी Wi-Fi पर किसी फ़ोन से स्कैन करें, Home Assistant का पता और एक्सेस टोकन पेस्ट करें, और Send पर टैप करें। यह पेज तभी काम करता है जब तक यह खुला है।';

  @override
  String get profilesSwitchProfile => 'प्रोफ़ाइल बदलें';

  @override
  String get parentPinTitle => 'अभिभावक PIN';

  @override
  String get parentPinOn => 'चालू';

  @override
  String get parentPinOff => 'बंद';

  @override
  String get parentPinCurrent => 'वर्तमान अभिभावक PIN';

  @override
  String get parentPinRemove => 'PIN हटाएँ';

  @override
  String get parentPinChange => 'PIN बदलें';

  @override
  String get parentPinNew => 'नया अभिभावक PIN';

  @override
  String get parentPinNewSubtitle => 'Google TV की बच्चों की प्रोफ़ाइल में लॉन्चर बदलने के लिए ज़रूरी';

  @override
  String get parentPinConfirm => 'PIN फिर से दर्ज करें';

  @override
  String get parentPinAskTitle => 'माता-पिता से पूछें';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'बच्चों की प्रोफ़ाइल में लॉन्चर सेटिंग्स लॉक रहती हैं। माता-पिता अपनी प्रोफ़ाइल से $settings → $profiles → $parentPin में PIN सेट कर सकते हैं।';
  }

  @override
  String get parentPinKidsSubtitle => 'बच्चों की प्रोफ़ाइल: लॉन्चर बदलने के लिए अभिभावक PIN दर्ज करें';

  @override
  String get parentPinWrong => 'गलत PIN';

  @override
  String get parentPinEnter => 'PIN दर्ज करें';

  @override
  String profileSwitchGreeting(String name) {
    return 'नमस्ते, $name';
  }

  @override
  String get profileSwitchSettingUp => 'यह प्रोफ़ाइल सेट हो रही है…';

  @override
  String profilesKidsName(String name) {
    return '$name (बच्चे)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (वयस्क)';
  }

  @override
  String get pairingShowPicker => 'चुनने की स्क्रीन दिखाएं';

  @override
  String get pairingAlwaysShowPicker => 'हमेशा चुनने की स्क्रीन दिखाएं';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (नाम से मिलान)';
  }

  @override
  String get pairingNoMatchYet => 'अभी कोई मिलान नहीं: चुनने की स्क्रीन दिखती है';

  @override
  String get pairingOffSetUp => 'प्रोफ़ाइल पेयरिंग बंद है। इसे सेट अप करें';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'जब Hearth इनमें से कोई ऐप खोलता है, तो वह Google TV प्रोफ़ाइल से जुड़ी ऐप प्रोफ़ाइल चुनता है। Hearth नामों का मिलान खुद करता है (\"$shortName\" का मेल \"$fullName\" से); कोई भी पेयरिंग यहां बदलें। मिलान न होने पर ऐप की अपनी चुनने की स्क्रीन दिखती है।';
  }

  @override
  String get pairingAppNotInstalled => 'इंस्टॉल नहीं है';

  @override
  String get pairingAppOff => 'बंद: ऐप की अपनी चुनने की स्क्रीन दिखती है';

  @override
  String get pairingAppNotSeen => 'इसे एक बार Hearth से खोलें ताकि Hearth इसकी प्रोफ़ाइल जान सके';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count प्रोफ़ाइल मिलीं',
      one: '1 प्रोफ़ाइल मिली',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'नाम से मिलान ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'नाम से मिलान (अभी कोई मिलान नहीं)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$app में $profile';
  }

  @override
  String pairingPairIn(String app) {
    return '$app में प्रोफ़ाइल पेयर करें';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth ने अभी इस ऐप की प्रोफ़ाइल नहीं देखी हैं। इसे एक बार Hearth से खोलें, फिर वापस आएं।';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'इस ऐप की प्रोफ़ाइल: $profiles। Google TV प्रोफ़ाइल यहां तब दिखती हैं जब Hearth उन्हें देख लेता है।';
  }

  @override
  String get familyAppsAddTitle => 'अन्य प्रोफ़ाइल में Hearth जोड़ें';

  @override
  String get familyAppsAddKids => 'इससे Hearth और HearthTube आपके बच्चों की प्रोफ़ाइल पर आ जाते हैं, ताकि वहाँ HearthTube काम करे और Hearth स्ट्रीमिंग सेवाओं में सही प्रोफ़ाइल चुन सके।';

  @override
  String get familyAppsAddAdults => 'यह इन्हें टीवी की अन्य वयस्क प्रोफ़ाइल पर भी इंस्टॉल करता है, ताकि किसी दूसरे वयस्क को खुद सेट अप न करना पड़े।';

  @override
  String get familyAppsAddOnlyOwnApps => 'यह केवल Hearth के अपने दो ऐप जोड़ता है, और आप नीचे दिए \"हटाएँ\" से इसे कभी भी पलट सकते हैं।';

  @override
  String get familyAppsAddFamilyLink => 'हर बच्चे को Family Link की एक \"ऐप जोड़ा गया\" सूचना मिलती है।';

  @override
  String get familyAppsAddApproval => 'पहली बार टीवी पूछता है \"डीबगिंग की अनुमति दें?\" — \"हमेशा अनुमति दें\" चुनें; इसी से Hearth सेटअप कर पाता है।';

  @override
  String get familyAppsAdd => 'जोड़ें';

  @override
  String get familyAppsRemoveTitle => 'अन्य प्रोफ़ाइल से Hearth हटाएँ';

  @override
  String get familyAppsRemoveBody => 'इससे Hearth और HearthTube आपकी अन्य प्रोफ़ाइल से हट जाते हैं।';

  @override
  String get familyAppsRemoveFirst => 'अगर आप Hearth को ही अनइंस्टॉल करना चाहते हैं, तो पहले यह चलाएं — वरना बच्चों की प्रोफ़ाइल पर इसकी कॉपियां अटकी रह सकती हैं और उन्हें हटाने के लिए कंप्यूटर चाहिए होगा।';

  @override
  String get familyAppsUninstallTitle => 'Hearth अनइंस्टॉल करें';

  @override
  String get familyAppsUninstallBody => 'यह पहले Hearth और HearthTube को आपकी अन्य प्रोफ़ाइल से हटाता है, फिर इस प्रोफ़ाइल से Hearth अनइंस्टॉल करता है।';

  @override
  String get familyAppsUninstallWhyHere => 'Android की सेटिंग्स के बजाय यहां से अनइंस्टॉल करने पर बच्चों की प्रोफ़ाइल पर कुछ भी नहीं छूटता।';

  @override
  String get familyAppsApprovalFirstTitle => 'पहले एक बार की अनुमति पूरी करें';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth अभी अन्य प्रोफ़ाइल साफ़ नहीं कर सका — इसके लिए टीवी पर एक बार \"डीबगिंग की अनुमति दें?\" की मंज़ूरी चाहिए।';

  @override
  String get familyAppsApprovalFirstRetry => 'इसे मंज़ूर करें, फिर दोबारा अनइंस्टॉल करें, ताकि बच्चों की प्रोफ़ाइल पर कुछ न बचे।';

  @override
  String get familyAppsAddDone => 'जोड़ना पूरा हुआ';

  @override
  String get familyAppsRemoveDone => 'हटाना पूरा हुआ';

  @override
  String get familyAppsAdded => 'हो गया। Hearth और HearthTube अब आपकी अन्य प्रोफ़ाइल पर हैं — नीचे दी गई सूची देखें।';

  @override
  String get familyAppsRemoved => 'हो गया। Hearth और HearthTube आपकी अन्य प्रोफ़ाइल से हटा दिए गए हैं।';

  @override
  String get familyAppsNothingToSetUp => 'अभी सेट अप करने के लिए कोई अन्य प्रोफ़ाइल नहीं है।';

  @override
  String get familyAppsFailedTitle => 'प्रोफ़ाइल सेट अप नहीं हो सकीं';

  @override
  String get familyAppsFailedBody => 'अन्य प्रोफ़ाइल सेट अप करने से पहले Hearth को टीवी पर एक बार की अनुमति चाहिए।';

  @override
  String get familyAppsFailedRetry => 'टीवी जब \"डीबगिंग की अनुमति दें?\" पूछे, तो \"हमेशा अनुमति दें\" चुनें, फिर दोबारा कोशिश करें।';

  @override
  String get familyAppsAlsoAdults => 'अन्य वयस्क प्रोफ़ाइल भी सेट अप करें';

  @override
  String get familyAppsOn => 'चालू';

  @override
  String get familyAppsOff => 'बंद';

  @override
  String get familyAppsNoneYet => 'अभी कोई अन्य प्रोफ़ाइल सेट अप नहीं है।';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: इंस्टॉल है';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: इंस्टॉल है, सुरक्षित';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: इंस्टॉल नहीं है';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: इंस्टॉल नहीं है, सुरक्षित';
  }

  @override
  String get familyAppsUnnamedKids => 'बच्चों की एक प्रोफ़ाइल';

  @override
  String get familyAppsUnnamedAdult => 'एक वयस्क प्रोफ़ाइल';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'अगली स्क्रीन पर नीचे \"सेवाएं\" तक स्क्रॉल करें, \"$service\" चुनें, फिर \"चालू करें\" चालू करके पुष्टि करें। होम पर लौटने तक \"वापस\" दबाएं।';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'अगर Android कहे कि सेटिंग प्रतिबंधित है, तो किसी कंप्यूटर से इसे एक बार चलाएं:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth को होम ऐप बनाएं';

  @override
  String get setupDefaultLauncherWhy => 'बच्चों की प्रोफ़ाइल को Hearth ब्लॉक करने से रोकता है।';

  @override
  String get setupDefaultLauncherInstructions => 'अगली स्क्रीन पर Hearth चुनें।';

  @override
  String get setupHomeFixTitle => 'होम बटन फ़िक्स';

  @override
  String get setupHomeFixWhy => 'होम बटन Google TV की जगह Hearth खोलता है।';

  @override
  String get setupNotificationsTitle => 'सूचना पहुंच';

  @override
  String get setupNotificationsWhy => 'सूचनाएं और अभी क्या चल रहा है, दिखाता है।';

  @override
  String setupNotificationsInstructions(String service) {
    return 'अगली स्क्रीन पर \"$service\" चुनें और उसे अनुमति दें।';
  }

  @override
  String get setupInstallTitle => 'अपडेट इंस्टॉल करना';

  @override
  String get setupInstallWhy => 'Hearth को खुद अपडेट होने और साथी ऐप्स इंस्टॉल करने देता है।';

  @override
  String get setupInstallInstructions => 'अगली स्क्रीन पर Hearth चालू करें।';

  @override
  String get setupPairingWhy => 'Netflix, Disney+, Apple TV, HBO Max और Paramount+ में आपकी प्रोफ़ाइल चुनता है।';

  @override
  String get setupVoiceTitle => 'Hearth आवाज़';

  @override
  String get setupVoiceWhy => 'प्रोफ़ाइल पेयरिंग को Netflix की प्रोफ़ाइल स्क्रीन सुनने देता है। अन्य ऐप्स में Google की आवाज़ रहती है।';

  @override
  String setupVoiceInstructions(String engine) {
    return 'अगली स्क्रीन पर \"पसंदीदा इंजन\" में \"$engine\" चुनें, फिर चेतावनी पर \"ठीक है\" दबाएं (Hearth सिर्फ़ स्ट्रीमिंग ऐप्स को सुनता है)। लौटने के लिए \"वापस\" दबाएं।';
  }

  @override
  String get setupOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get setupAdbFallback => 'इस टीवी ने वह सेटिंग्स स्क्रीन नहीं खोली। इसके बजाय किसी कंप्यूटर से इसे एक बार चलाएं:';

  @override
  String setupProgress(int done, int total) {
    return '$total में से $done पूरे';
  }

  @override
  String get setupOptional => 'वैकल्पिक';

  @override
  String get homeButtonFixOffTitle => 'होम बटन फ़िक्स बंद है';

  @override
  String get homeButtonFixOffBody => 'Hearth की सुलभता सेवा रुक गई है, आमतौर पर किसी अपडेट के बाद। जब तक यह फिर से चालू न हो, होम बटन Hearth की जगह Google TV खोल सकता है, और प्रोफ़ाइल बदलने पर ध्यान नहीं दिया जाता।';

  @override
  String get homeButtonFixStuck => 'Android इसे अब भी चालू दिखाता है, लेकिन यह चल नहीं रही। इसे फिर से शुरू करने के लिए सुलभता सेटिंग्स में Hearth को बंद करके फिर चालू करें।';

  @override
  String get homeButtonFixRestricted => 'अगर वहां Hearth का स्विच धूसर है, तो Android उसे रोक रहा है क्योंकि यह अपडेट डाउनलोड से इंस्टॉल हुआ था। टीवी से जुड़े किसी कंप्यूटर से यह चलाएं, फिर Hearth चालू करें:';

  @override
  String get homeButtonFixDontRemind => 'मुझे याद न दिलाएं';

  @override
  String get homeButtonFixOpenSettings => 'सुलभता सेटिंग्स खोलें';

  @override
  String get remoteButtonsRemapButton => 'बटन रीमैप करें';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'बटन $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'सामान्य';

  @override
  String get remoteButtonsCaptureTitle => 'रिमोट का कोई बटन दबाएं';

  @override
  String get remoteButtonsCaptureBody => 'जिस बटन को रीमैप करना है, उसे दबाएं। रद्द करने के लिए \"वापस\" दबाएं।';

  @override
  String get remoteButtonsNeedsFixTitle => 'पहले होम बटन फ़िक्स चालू करें';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'रीमैप करने के लिए होम बटन फ़िक्स ज़रूरी है ($path)।';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'यह बटन रीमैप नहीं हो सकता';

  @override
  String get remoteButtonsCantRemapBody => 'तीर, OK, वापस, होम और पावर बटन अपना सामान्य काम करते रहते हैं।';

  @override
  String remoteButtonsPressOption(String action) {
    return 'दबाएं: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'दबाए रखें: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Hearth खोज के लिए दबाएं, Google के लिए दबाए रखें';

  @override
  String get remoteButtonsHomeOnlyOn => 'केवल Hearth की होम स्क्रीन पर: चालू';

  @override
  String get remoteButtonsHomeOnlyOff => 'केवल Hearth की होम स्क्रीन पर: बंद';

  @override
  String get remoteButtonsRestore => 'सामान्य बटन बहाल करें';

  @override
  String get remoteButtonsActionTitle => 'कार्रवाई';

  @override
  String get remoteButtonsActionApp => 'कोई ऐप खोलें…';

  @override
  String get remoteButtonsActionInput => 'किसी टीवी इनपुट पर जाएं…';

  @override
  String get remoteButtonsActionSwitchProfile => 'प्रोफ़ाइल बदलें (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth खोज (आवाज़)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth खोज (कीबोर्ड)';

  @override
  String get remoteButtonsActionHome => 'Hearth होम';

  @override
  String get remoteButtonsActionSleep => 'स्लीप';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android सेटिंग्स';

  @override
  String get remoteButtonsPickAppTitle => 'कोई ऐप खोलें';

  @override
  String get remoteButtonsPickInputTitle => 'किसी टीवी इनपुट पर जाएं';

  @override
  String get remoteButtonsHaConnectTitle => 'पहले Home Assistant कनेक्ट करें';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Home Assistant पैनल सेट अप करें ($panel > $row), फिर दोबारा कोशिश करें।';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'सीन: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'चलाएं: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'दबाएं: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'टॉगल: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nदबाएं: $press  ·  दबाए रखें: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nदबाएं: $press  ·  दबाए रखें: $hold  ·  केवल होम स्क्रीन';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'होम बटन फ़िक्स ज़रूरी है ($path)। जिस बटन पर सिर्फ़ \"दबाए रखें\" की कार्रवाई है, वह सामान्य दबाने पर भी वही करता है। HearthTube सामने होने पर Hearth खोज, HearthTube की अपनी खोज खोलती है। बच्चों की स्क्रीन टाइम स्क्रीन दिखने के दौरान रीमैप रुके रहते हैं।';
  }

  @override
  String get tvPowerScreensaver => 'स्क्रीनसेवर (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth, Google TV का स्क्रीनसेवर इस्तेमाल करता है। वहां Google Photos (और कौन-से एल्बम) या कोई दूसरा स्रोत चुनें।';

  @override
  String get tvPowerSleepWhenIdle => 'निष्क्रिय होने पर स्लीप';

  @override
  String get tvPowerSleepOff => 'बंद';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours घंटे',
      one: '1 घंटा',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'वीडियो या संगीत चलाना गतिविधि माना जाता है। होम बटन फ़िक्स ज़रूरी है ($path)।';
  }

  @override
  String get accentPurple => 'बैंगनी';

  @override
  String get accentTeal => 'हरा-नीला';

  @override
  String get accentBlue => 'नीला';

  @override
  String get accentOrange => 'नारंगी';

  @override
  String get accentPink => 'गुलाबी';

  @override
  String get accentGreen => 'हरा';

  @override
  String get accentWhite => 'सफ़ेद';

  @override
  String get accentYellow => 'पीला';

  @override
  String get accentRed => 'लाल';

  @override
  String get accentCyan => 'सियान';

  @override
  String get accentIndigo => 'इंडिगो';

  @override
  String get accentLime => 'लाइम';

  @override
  String get accentAmber => 'एम्बर';

  @override
  String get accentRose => 'हल्का गुलाबी';

  @override
  String get accentIceBlue => 'बर्फ़ीला नीला';

  @override
  String get accentSelected => 'चुना गया एक्सेंट रंग';

  @override
  String get cardStyleDefault => 'डिफ़ॉल्ट';

  @override
  String get cardStylePremium => 'प्रीमियम';

  @override
  String get cardStyleGlow => 'ग्लो';

  @override
  String get cardStyleSquircle => 'स्क्विर्कल';

  @override
  String get cardStyleClassic => 'क्लासिक';

  @override
  String get cardStyleMinimal => 'मिनिमल';

  @override
  String get cardStyleCapsule => 'कैप्सूल';

  @override
  String get dockFavoritesDock => 'पसंदीदा डॉक';

  @override
  String get dockFavoritesDockDescription => 'पसंदीदा को होम स्क्रीन के नीचे एक बार के रूप में दिखाता है, ऊपर \'देखना जारी रखें\' और नीचे आपके अन्य अनुभाग। इसके कोने कार्ड शैली के अनुसार होते हैं।';

  @override
  String get dockFrosted => 'फ्रॉस्टेड डॉक';

  @override
  String get dockDark => 'गहरा डॉक';

  @override
  String get dockShadow => 'डॉक की छाया';

  @override
  String get dockBlurWallpaperBelow => 'डॉक के नीचे वॉलपेपर धुंधला करें';

  @override
  String get wallpaperMatchSelectedApp => 'चुने गए ऐप से मिलाएं';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing दिन की फ़ोटो';

  @override
  String get wallpaperRefreshNow => 'अभी रीफ़्रेश करें';

  @override
  String get wallpaperBingError => 'Bing तक नहीं पहुंच सके। अपना नेटवर्क कनेक्शन जांचें।';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'तापमान इकाई: $unit';
  }

  @override
  String get weatherLocationNotSet => 'मौसम का स्थान: सेट नहीं है';

  @override
  String weatherLocationValue(String place) {
    return 'मौसम का स्थान: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'मौसम लोड नहीं हो सका। यह अपने आप फिर से कोशिश करेगा।';

  @override
  String get statusBarWeatherSourceHint => 'ऊपर मौसम का स्थान चुनें (मौसम Open-Meteo से, मुफ़्त, बिना खाते के)। इसके बिना, मौसम Breezy Weather ऐप से आता है, यदि वह Gadgetbridge शेयरिंग चालू करके इंस्टॉल है।';

  @override
  String get weatherLocationTitle => 'मौसम का स्थान';

  @override
  String get weatherLocationHint => 'शहर या कस्बा';

  @override
  String get weatherLocationNoResults => 'कोई स्थान नहीं मिला';

  @override
  String get weatherLocationSearchError => 'मौसम सेवा तक नहीं पहुंच सके। नेटवर्क कनेक्शन जांचें।';

  @override
  String get weatherLocationPrivacyNote => 'मौसम Open-Meteo.com से: मुफ़्त, बिना खाते के। केवल चुने गए स्थान के निर्देशांक भेजे जाते हैं।';

  @override
  String get weatherLocationSearch => 'खोजें';

  @override
  String get dateTimeInvalidFormat => 'अमान्य फ़ॉर्मैट';

  @override
  String get dateTimeSelectFormats => 'नीचे फ़ॉर्मैट चुनें';

  @override
  String get dataUsageDaily => 'दैनिक';

  @override
  String get dataUsageWeekly => 'साप्ताहिक';

  @override
  String get dataUsageMonthly => 'मासिक';

  @override
  String cwAppsBlockedHeading(int count) {
    return '\'देखना जारी रखें\' से अवरुद्ध ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => '\'देखना जारी रखें\' से अवरुद्ध';

  @override
  String get cwAppsUnblock => 'अनब्लॉक करें';

  @override
  String get cwAppsUnblockAllApps => 'सभी ऐप्स अनब्लॉक करें';

  @override
  String get cwAppsNoBlockedApps => 'कोई अवरुद्ध ऐप नहीं';

  @override
  String get cwAppsNoBlockedAppsMessage => 'सभी समर्थित ऐप्स \'देखना जारी रखें\' में आइटम दिखा सकते हैं।';

  @override
  String get cwAppsWithContinueWatching => '\'देखना जारी रखें\' वाले ऐप्स';

  @override
  String get cwAppsWithContinueWatchingHint => 'वे ऐप्स जो अभी आपकी होम स्क्रीन पर Watch Next आइटम दे रहे हैं';

  @override
  String get cwAppsNoActiveApps => 'अभी कोई ऐप \'देखना जारी रखें\' आइटम नहीं दे रहा है।\nजब समर्थित ऐप्स (जैसे SmartTube या स्ट्रीमिंग सेवाएं) आइटम जोड़ेंगे, वे यहां दिखेंगे।';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count सक्रिय आइटम',
      one: '1 सक्रिय आइटम',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'सभी इंस्टॉल किए गए ऐप्स';

  @override
  String get cwAppsAllInstalledAppsHint => 'किसी ऐप को \'देखना जारी रखें\' में आइटम जोड़ने से रोकने के लिए बंद करें';

  @override
  String get cwAppsBlocked => 'अवरुद्ध';

  @override
  String get cwAppsAllowed => 'अनुमति है';

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
  String get cwCardSizeExtraSmall => 'अति छोटा';

  @override
  String get cwCardSizeVerySmall => 'बहुत छोटा';

  @override
  String get cwCardSizeSmall => 'छोटा';

  @override
  String get cwCardSizeCompact => 'कॉम्पैक्ट';

  @override
  String get cwCardSizeMediumSmall => 'मध्यम छोटा';

  @override
  String get cwCardSizeMedium => 'मध्यम';

  @override
  String get cwCardSizeStandardDefault => 'मानक (डिफ़ॉल्ट)';

  @override
  String get cwCardSizeStandard => 'मानक';

  @override
  String get cwCardSizeMediumLarge => 'मध्यम बड़ा';

  @override
  String get cwCardSizeLarge => 'बड़ा';

  @override
  String get cwCardSizeVeryLarge => 'बहुत बड़ा';

  @override
  String get cwCardSizeExtraLarge => 'अति बड़ा';

  @override
  String get cwCardSizeHuge => 'विशाल';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम',
      one: '1 आइटम',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'अधिकतम $count हाल के आइटम दिखाएं',
      one: 'अधिकतम 1 हाल का आइटम दिखाएं',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • डिफ़ॉल्ट';
  }

  @override
  String get cwUnlimited => 'असीमित';

  @override
  String get cwMaxItemsAll => 'सभी उपलब्ध आइटम दिखाएं';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम',
      one: '1 आइटम',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'प्लेबैक प्रोग्रेस बार';

  @override
  String get cwPlaybackPercentage => 'प्लेबैक प्रतिशत';

  @override
  String get cwEpisodeDetails => 'एपिसोड और वीडियो विवरण';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count अवरुद्ध',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'प्रबंधित करें';

  @override
  String get cwRestoreHiddenPrograms => 'छिपे हुए कार्यक्रम वापस लाएं';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count छिपे हुए',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'सभी छिपे हुए कार्यक्रम वापस आ गए';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next पहुंच (ADB आवश्यक)';

  @override
  String get cwWatchNextAdbMessage => 'लॉन्चर को इंस्टॉल किए गए ऐप्स की \'देखना जारी रखें\' पंक्तियां पढ़ने और दिखाने के लिए Android TV को READ_WRITE_WATCH_NEXT_PROGRAMS अनुमति चाहिए।\n\nयह अनुमति देने के लिए, अपने टीवी को ADB से कनेक्ट करें और चलाएं:';

  @override
  String get appsNoApplicationsFound => 'कोई ऐप नहीं मिला';

  @override
  String get appDetailsAddToFavorites => 'पसंदीदा में जोड़ें';

  @override
  String get appDetailsRemoveFromFavorites => 'पसंदीदा से हटाएं';

  @override
  String get appDetailsAddToCategory => 'श्रेणी में जोड़ें';

  @override
  String get sectionsCustomOption => 'कस्टम...';

  @override
  String get sectionsSelectName => 'एक नाम चुनें';

  @override
  String get sectionsCustomName => 'कस्टम नाम';

  @override
  String get sectionsSortLastUsed => 'अंतिम उपयोग';

  @override
  String get sectionsReorderHint => '◄ / ► से चुनें, फिर क्रम बदलने के लिए ▲ / ▼ का उपयोग करें';

  @override
  String get inputsNoneDetected => 'कोई इनपुट नहीं मिला';

  @override
  String get notifClearAll => 'सभी साफ़ करें';

  @override
  String get notifAllCaughtUp => 'सब देख लिया!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'सूचनाएं अवरुद्ध करें ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return '$app खोलें';
  }

  @override
  String get notifAccessAdbTitle => 'सूचना पहुंच (ADB आवश्यक)';

  @override
  String get notifAccessAdbMessage => 'Android TV में \"सूचना पहुंच\" (अन्य ऐप्स की सूचनाएं सुनना) के लिए कोई सिस्टम सेटिंग स्क्रीन नहीं है।\n\nध्यान दें: टीवी ऐप सेटिंग्स में \"सूचनाएं दिखाएं\" चालू करने से केवल इस ऐप से जाने वाली सूचनाएं नियंत्रित होती हैं, सूचना पहुंच नहीं।\n\nसूचना पहुंच देने के लिए, अपने टीवी को ADB से कनेक्ट करें और चलाएं:';

  @override
  String get notifOpenAppInfo => 'ऐप जानकारी खोलें';

  @override
  String get notifOverlayPermissionTitle => 'ओवरले अनुमति';

  @override
  String get notifOverlayAdbMessage => 'इस डिवाइस पर ओवरले अनुमति सेटिंग स्क्रीन अपने आप नहीं खुल सकी।\n\nओवरले पॉपअप चालू करने के लिए, टीवी से जुड़े कंप्यूटर से ADB के ज़रिए मैन्युअल रूप से अनुमति दें:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'अवरुद्ध ऐप्स ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'अभी के लिए Google TV इस्तेमाल करें';

  @override
  String get backupShareText => 'Hearth बैकअप';

  @override
  String get backupShareFailedTitle => 'साझा करना विफल';

  @override
  String backupShareFailed(String error) {
    return 'बैकअप साझा करने में विफल: $error';
  }

  @override
  String get backupExportSuccessTitle => 'निर्यात सफल';

  @override
  String get backupExportFailedTitle => 'निर्यात विफल';

  @override
  String get backupImportSuccessTitle => 'आयात सफल';

  @override
  String get backupImportFailedTitle => 'आयात विफल';

  @override
  String get backupImport => 'आयात करें';

  @override
  String backupLoadError(String error) {
    return 'बैकअप लोड करने में त्रुटि: $error';
  }

  @override
  String get backupNoFiles => 'कोई बैकअप फ़ाइल नहीं मिली।';

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
  String get updateCheckForUpdatesTitle => 'अपडेट की जांच करें';

  @override
  String updateCurrentVersion(String version) {
    return 'वर्तमान संस्करण: $version';
  }

  @override
  String get updateChecking => 'GitHub पर नई रिलीज़ खोजी जा रही है…';

  @override
  String get updateUpToDate => 'आपके पास नवीनतम संस्करण है।';

  @override
  String updateVersionAvailable(String version) {
    return 'संस्करण $version उपलब्ध है';
  }

  @override
  String updateDownloading(String percent) {
    return 'डाउनलोड हो रहा है… $percent%';
  }

  @override
  String get updateDownloadedHint => 'डाउनलोड हो गया। अगर इंस्टॉलर नहीं खुला, तो आपके डिवाइस पर Hearth को\n\"अज्ञात ऐप्स इंस्टॉल करें\" अनुमति देनी पड़ सकती है।';

  @override
  String get updateSomethingWentWrong => 'कुछ गलत हो गया';

  @override
  String get updateDownloadAndInstall => 'डाउनलोड और इंस्टॉल करें';

  @override
  String get updateRetryInstall => 'फिर से इंस्टॉल करें';

  @override
  String get updateCheckAgain => 'फिर से जांचें';

  @override
  String get updatesInstallPermissionTitle => 'Hearth को ऐप्स इंस्टॉल करने दें';

  @override
  String get updatesInstallPermissionMessage => 'अगली स्क्रीन पर Hearth ढूंढें और उसे चालू करें, फिर वापस दबाएं। यहां लौटने पर इंस्टॉल जारी रहेगा।';

  @override
  String get updatesOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get updatesCheckFailed => 'अपडेट की जांच नहीं हो सकी';

  @override
  String get updatesInstallerNotStarted => 'इंस्टॉलर शुरू नहीं हुआ';

  @override
  String get updatesCheckForUpdates => 'अपडेट की जांच करें';

  @override
  String get updatesAutoUpdate => 'अपने आप अपडेट करें';

  @override
  String get updatesAutoUpdateDescription => 'Hearth रोज़ जांच करता है और अपने इंस्टॉल किए ऐप्स के अपडेट तब इंस्टॉल करता है जब वे इस्तेमाल में न हों';

  @override
  String get updatesFooter => 'हर ऐप की GitHub रिलीज़ से इंस्टॉल। Hearth के किसी ऐप को एक बार इंस्टॉल या अपडेट करने के बाद, उसके अपडेट बिना पूछे इंस्टॉल होते हैं, और ऐप अपडेट करना Hearth पर छोड़ देता है।';

  @override
  String get updatesChecking => 'जांच हो रही है…';

  @override
  String get updatesInstall => 'इंस्टॉल करें';

  @override
  String updatesUpdateTo(String version) {
    return '$version पर अपडेट करें';
  }

  @override
  String get updatesUpToDate => 'अप टू डेट';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'डाउनलोड हो रहा है $percent%';
  }

  @override
  String get updatesInstalling => 'इंस्टॉल हो रहा है…';

  @override
  String get updatesError => 'त्रुटि';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutForkOf(String launcher, String author, String parts) {
    return '$author के $launcher का फ़ोर्क, $parts के कुछ हिस्सों के साथ';
  }

  @override
  String get aboutDescription => 'Google TV के लिए एक निजी, परिवार के अनुकूल लॉन्चर, जिसमें Google TV प्रोफ़ाइल और Home Assistant शामिल हैं। विज्ञापन-मुक्त और ट्रैकर-मुक्त।';

  @override
  String get aboutHearthOnGitHub => 'GitHub पर Hearth';

  @override
  String get aboutCredits => 'श्रेय';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher फ़ोर्क · $author';
  }

  @override
  String get aboutLicense => 'GNU GPL v3 के तहत मुक्त सॉफ़्टवेयर, उन प्रोजेक्ट्स की तरह जिन पर यह बना है।';

  @override
  String get familyAppsStatusInstalled => 'इंस्टॉल है';

  @override
  String get familyAppsStatusPartial => 'आंशिक';

  @override
  String get familyAppsStatusNotInstalled => 'इंस्टॉल नहीं है';

  @override
  String get familyAppsStatusAtRisk => 'जोखिम में';

  @override
  String get familyAppsAtRiskDetail => 'इस प्रोफ़ाइल के अगली बार शुरू होने पर Google TV यहाँ के असुरक्षित ऐप्स हटा देगा। उन्हें सुरक्षित करने के लिए फिर से जोड़ें का उपयोग करें।';

  @override
  String get profilePinRow => 'प्रोफ़ाइल PIN';

  @override
  String get profilePinNone => 'कोई नहीं';

  @override
  String get profilePinSaved => 'सहेजा गया';

  @override
  String get profilePinRejected => 'सहेजा गया — पिछली बार स्वीकार नहीं हुआ';

  @override
  String get profilePinPaused => 'सहेजा गया — रुका हुआ (ऐप बदल गया)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth अभी $app में PIN टाइप नहीं कर सकता';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$app में $profile का PIN';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'जब $app पूछता है, Hearth इसे “इस रूप में लॉग इन” कार्ड के पीछे टाइप करता है। यह इस टीवी पर एन्क्रिप्ट होकर रहता है और कभी दिखाया नहीं जाता।';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'पहले पैरेंट PIN सेट करें ($settings → $profiles → $parentPin): प्रोफ़ाइल का PIN सहेजने के लिए यह ज़रूरी है।';
  }

  @override
  String get profilePinSaveFailed => 'PIN सहेजा नहीं जा सका।';
}
