import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get aboutFlauncher => 'Hearth Hakkında';

  @override
  String get addSection => 'Bölüm ekle';

  @override
  String get alphabetical => 'Alfabetik';

  @override
  String get appCardHighlightAnimation => 'Uygulama kartı vurgulama animasyonu';

  @override
  String get appInfo => 'Uygulama bilgisi';

  @override
  String get appKeyClick => 'Tuşa basıldığında tıklama sesi';

  @override
  String get applications => 'Uygulamalar';

  @override
  String get autoHideAppBar => 'Durum çubuğunu otomatik gizle';

  @override
  String get backButtonAction => 'Geri düğmesi eylemi';

  @override
  String get category => 'Kategori';

  @override
  String get columnCount => 'Sütun sayısı';

  @override
  String get date => 'Tarih';

  @override
  String get dateAndTimeFormat => 'Tarih ve saat biçimi';

  @override
  String get delete => 'Sil';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Hiçbir şey yapma';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Ekran koruyucuyu göster';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Saati göster';

  @override
  String get dialogTextNoFileExplorer => 'Resim seçmek için lütfen bir dosya gezgini yükleyin.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Kategori)';
  }

  @override
  String get gradient => 'Gradyan';

  @override
  String get favoriteApps => 'Favori Uygulamalar';

  @override
  String get grid => 'Izgara';

  @override
  String get height => 'Yükseklik';

  @override
  String get hide => 'Gizle';

  @override
  String get hiddenApplications => 'Gizli Uygulamalar';

  @override
  String get launcherSections => 'Bölümler';

  @override
  String get layout => 'Düzen';

  @override
  String get loading => 'Yükleniyor';

  @override
  String get manual => 'Manuel';

  @override
  String get modifySection => 'Bölümü değiştir';

  @override
  String get name => 'Ad';

  @override
  String get newSection => 'Yeni bölüm';

  @override
  String get nonTvApplications => 'TV Dışı Uygulamalar';

  @override
  String get open => 'Aç';

  @override
  String get picture => 'Resim';

  @override
  String removeFrom(String name) {
    return '$name öğesinden kaldır';
  }

  @override
  String get reorder => 'Yeniden sırala';

  @override
  String get row => 'Satır';

  @override
  String get rowHeight => 'Satır yüksekliği';

  @override
  String get save => 'Kaydet';

  @override
  String get spacer => 'Ayırıcı';

  @override
  String get statusBar => 'Durum çubuğu';

  @override
  String get show => 'Göster';

  @override
  String get showCategoryTitles => 'Kategori başlıklarını göster';

  @override
  String get showCategoryAppCount => 'Kategorilerde uygulama sayısını göster';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Ana ekranda vurgu anahattını gizle';

  @override
  String get appSelectorTransitionAnimation => 'Uygulama seçici geçiş animasyonu';

  @override
  String get sort => 'Sırala';

  @override
  String get systemSettings => 'Sistem ayarları';

  @override
  String get textEmptyCategory => 'Bu kategori boş.';

  @override
  String get time => 'Saat';

  @override
  String get tvApplications => 'TV Uygulamaları';

  @override
  String get type => 'Tür';

  @override
  String get uninstall => 'Kaldır';

  @override
  String get wallpaper => 'Duvar kağıdı';

  @override
  String get withEllipsisAddTo => 'Şuraya ekle...';

  @override
  String get timeBasedWallpaper => 'Zamana dayalı duvar kağıdı';

  @override
  String get pickDayWallpaper => 'Gündüz duvar kağıdını seç';

  @override
  String get pickNightWallpaper => 'Gece duvar kağıdını seç';

  @override
  String get inputs => 'Girişler';

  @override
  String get inputSources => 'Giriş Kaynakları';

  @override
  String get backupAndRestore => 'Yedekleme ve Geri Yükleme';

  @override
  String get exportBackup => 'Yedeği Dışa Aktar';

  @override
  String get importBackup => 'Yedeği İçe Aktar';

  @override
  String exportSuccess(String path) {
    return 'Yedek başarıyla $path konumuna dışa aktarıldı';
  }

  @override
  String get importSuccess => 'Yedek başarıyla içe aktarıldı';

  @override
  String get importConfirm => 'Yedeği içe aktarmak istediğinizden emin misiniz? Bu işlem mevcut ayarlarınızın ve düzeninizin üzerine yazacaktır.';

  @override
  String importError(String error) {
    return 'Yedek içe aktarılamadı: $error';
  }

  @override
  String exportError(String error) {
    return 'Yedek dışa aktarılamadı: $error';
  }

  @override
  String get shareBackup => 'Yedeği Paylaş';

  @override
  String get notificationBell => 'Bildirim Zili';

  @override
  String get autoHideNotificationBell => 'Bildirim Zilini otomatik gizle';

  @override
  String get continueWatching => 'İzlemeye Devam Et';

  @override
  String get showContinueWatchingOnHome => 'Ana Ekranda İzlemeye Devam Et\'i göster';

  @override
  String get permissionDeniedContinueWatching => 'İzlemeye Devam Et\'i göstermek için izin gerekli';

  @override
  String get system => 'Sistem';

  @override
  String get accentColor => 'Vurgu Rengi';

  @override
  String get dataUsagePeriod => 'Veri Kullanım Dönemi';

  @override
  String get notificationAccess => 'Bildirim Erişimi';

  @override
  String get watchNextAccess => 'Watch Next Erişimi';

  @override
  String get granted => 'Verildi';

  @override
  String get permissionRequired => 'İzin Gerekli';

  @override
  String get systemWidePopupAlert => 'Sistem Geneli Açılır Pencere Uyarısı';

  @override
  String get overlayPermissionRequired => 'Kaplama İzni Gerekli';

  @override
  String get enabled => 'Etkin';

  @override
  String get disabled => 'Devre Dışı';

  @override
  String get showAppNamesBelowIcons => 'Uygulama adlarını simgelerin altında göster';

  @override
  String get dataUsage => 'Veri Kullanımı';

  @override
  String get networkIndicator => 'Ağ Göstergesi';

  @override
  String get startOnBoot => 'Açılışta başlat (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Dil';

  @override
  String get systemDefault => 'Sistem Varsayılanı';

  @override
  String get english => 'İngilizce';

  @override
  String get spanish => 'İspanyolca';

  @override
  String get ukrainian => 'Ukraynaca';

  @override
  String get chinese => 'Çince';

  @override
  String get french => 'Fransızca';

  @override
  String get german => 'Almanca';

  @override
  String get japanese => 'Japonca';

  @override
  String get portuguese => 'Portekizce';

  @override
  String get russian => 'Rusça';

  @override
  String get italian => 'İtalyanca';

  @override
  String get hindi => 'Hintçe';

  @override
  String get korean => 'Korece';

  @override
  String get arabic => 'Arapça';

  @override
  String get turkish => 'Türkçe';

  @override
  String get hidePersistentNotifications => 'Kalıcı Bildirimleri Gizle';

  @override
  String get blockedNotificationApps => 'Engellenen Uygulamalar';

  @override
  String get blockAppNotifications => 'Bildirimleri Engelle';

  @override
  String get unblockAppNotifications => 'Bildirim Engelini Kaldır';

  @override
  String get noBlockedApps => 'Engellenen uygulama yok';

  @override
  String get persistentNotification => 'Kalıcı';

  @override
  String get unblockAll => 'Tümünün Engelini Kaldır';

  @override
  String get weather => 'Hava Durumu';

  @override
  String get showWeatherWarnings => 'Hava Durumu ve Yağmur Uyarılarını Göster';

  @override
  String get temperatureUnit => 'Sıcaklık Birimi';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Bildirimler';

  @override
  String get continueWatchingDescription => 'Son izlenen filmleri ve dizileri ana ekranda göster';

  @override
  String get dismiss => 'Kapat';

  @override
  String get openApp => 'Aç';

  @override
  String get noBlockedAppsDesc => 'Şu anda tüm uygulamaların bildirim göstermesine izin veriliyor';

  @override
  String get notificationsAllowed => 'Bildirimlere İzin Verildi';

  @override
  String get notificationsBlocked => 'Bildirimler Engellendi';

  @override
  String get dpadDismissHint => 'Sol: Kapat • Tamam: Seçenekler';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get profilesTitle => 'Profiller';

  @override
  String get homeScreenTitle => 'Ana ekran';

  @override
  String get remoteAndSearchTitle => 'Kumanda ve arama';

  @override
  String get parentSettingsTitle => 'Ebeveyn ayarları';

  @override
  String get tvPowerTitle => 'TV ve güç';

  @override
  String get setupPermissionsTitle => 'Kurulum ve izinler';

  @override
  String get updatesTitle => 'Güncellemeler';

  @override
  String get familyAppsTitle => 'Diğer profillerde Hearth';

  @override
  String get cardStyleTitle => 'Kart stili';

  @override
  String get dockLabelsTitle => 'Dock ve etiketler';

  @override
  String get animationsSoundTitle => 'Animasyonlar ve ses';

  @override
  String get haPanelTitle => 'Pano paneli';

  @override
  String get lookTitle => 'Görünüm';

  @override
  String get remoteButtonsTitle => 'Kumanda tuşları';

  @override
  String get profilePairingTitle => 'Profil eşleştirme';

  @override
  String get haTvStatusTitle => 'TV durumu';

  @override
  String get continueWatchingAppsTitle => 'İzlemeye Devam Et uygulamaları';

  @override
  String get cardSizeTitle => 'Kart boyutu';

  @override
  String get maxItemsTitle => 'En fazla öğe';

  @override
  String get ok => 'Tamam';

  @override
  String get cancel => 'İptal';

  @override
  String get close => 'Kapat';

  @override
  String get tryAgain => 'Tekrar dene';

  @override
  String get notNow => 'Şimdi değil';

  @override
  String get done => 'Bitti';

  @override
  String get remove => 'Kaldır';

  @override
  String get homeNothingToWatch => 'Şu anda izlenecek bir şey yok';

  @override
  String get errorScreenTitle => 'Bir şeyler ters gitti';

  @override
  String get appInfoAddToCategory => 'Kategoriye ekle';

  @override
  String get appInfoAddToFavorites => 'Favorilere ekle';

  @override
  String get appInfoRemoveFromFavorites => 'Favorilerden kaldır';

  @override
  String get appInfoSetCustomBanner => 'Özel afiş ayarla';

  @override
  String get appInfoClearCustomBanner => 'Özel afişi kaldır';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Afiş ayarlanamadı: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Afiş kaldırılamadı: $error';
  }

  @override
  String get cwGridAll => 'Tümü';

  @override
  String get cwRowSeeAll => 'Tümünü gör';

  @override
  String cwRowInProgress(int count) {
    return '$count devam ediyor';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '$hours sa $minutes dk kaldı';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '$minutes dk kaldı';
  }

  @override
  String get watchNextInfoRemove => 'İzlemeye Devam Et\'ten kaldır';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return '$appName içeriklerinin tümünü gizle';
  }

  @override
  String get watchNextInfoPlayResume => 'Oynat / Devam et';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '$appName uygulamasını aç';
  }

  @override
  String get watchNextInfoAppInfo => 'Uygulama bilgisi';

  @override
  String get dataWidgetGrantPermission => 'Kullanım izni ver';

  @override
  String dataWidgetDaily(String usage) {
    return 'Günlük: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Haftalık: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Aylık: $usage';
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
        'today': 'Bugün yağmur',
        'tomorrow': 'Yarın yağmur',
        'other': '$day yağmur',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Bugün kar',
        'tomorrow': 'Yarın kar',
        'other': '$day kar',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Bugün fırtına',
        'tomorrow': 'Yarın fırtına',
        'other': '$day fırtına',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$forecast (%$percent)';
  }

  @override
  String searchWatchOn(String apps) {
    return '$apps üzerinde izle';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return '$app üzerinde kirala veya satın al';
  }

  @override
  String get searchMoreWaysToWatch => 'Diğer izleme yolları (Google TV)';

  @override
  String get searchListening => 'Dinleniyor…';

  @override
  String get searchHint => 'Film ve dizi ara';

  @override
  String get searchEntryHelp => 'Yazın, mikrofonu kullanın veya Google TV uygulamasıyla telefonunuzdan yazın.';

  @override
  String get searchTabWatchNow => 'Şimdi izle';

  @override
  String get searchTabRentOrBuy => 'Kirala veya satın al';

  @override
  String get searchTabOtherApps => 'Diğer uygulamalar';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Kirala veya satın al · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Nerede izlenir: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return '$services üzerinde (bu TV\'de yok)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sonuç',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Burada “$query” için bir şey yok.';
  }

  @override
  String get searchGridTmdbNotice => 'İzleme bilgileri TMDB\'den (JustWatch aracılığıyla). Bu ürün TMDB API\'sini kullanır ancak TMDB tarafından onaylanmamış veya sertifikalandırılmamıştır.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps veya $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Google\'a sor: “$query”';
  }

  @override
  String get searchAskGoogleDetail => 'Sorular, hava durumu ve dizi olmayan her şey için';

  @override
  String searchSearchingFor(String query) {
    return '“$query” aranıyor…';
  }

  @override
  String get searchFailed => 'Şu anda arama yapılamıyor. İnternet bağlantısını kontrol edin.';

  @override
  String searchNothingFound(String query) {
    return '“$query” için sonuç bulunamadı';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Şu anda uygulamalarınızda “$query” için bir şey yok';
  }

  @override
  String get searchSeeMoreResults => 'Başka nerede bulunduğunu Daha fazla sonuç bölümünde görün.';

  @override
  String get searchMoreResults => 'Daha fazla sonuç';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count içerik',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Google\'a sor';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => 'Film';

  @override
  String get searchKindSeries => 'Dizi';

  @override
  String get gradientNamePitchBlack => 'Simsiyah';

  @override
  String get gradientNameGreatWhale => 'Büyük Balina';

  @override
  String get gradientNameViciousStance => 'Sert Duruş';

  @override
  String get gradientNameTeenNotebook => 'Genç Defteri';

  @override
  String get gradientNameOldHat => 'Eski Şapka';

  @override
  String get gradientNameBurningSpring => 'Yanan Bahar';

  @override
  String get gradientNameDesertHump => 'Çöl Tepesi';

  @override
  String get gradientNameFarawayRiver => 'Uzak Nehir';

  @override
  String get gradientNameSaintPetersburg => 'Sankt-Peterburg';

  @override
  String get gradientNameAfricanField => 'Afrika Tarlası';

  @override
  String get gradientNameGrassShampoo => 'Çim Şampuanı';

  @override
  String get updateErrorNoApk => 'Hiçbir sürümde bu cihaz için APK yok';

  @override
  String get updateErrorCheckFailed => 'Güncellemeler denetlenemedi';

  @override
  String get updateErrorDownloadFailed => 'Güncelleme indirilemedi';

  @override
  String get serviceHearthTubeDescription => 'Hearth için YouTube; Hearth profilinizi takip eder';

  @override
  String get haSummaryOn => 'Açık';

  @override
  String get haSummaryOff => 'Kapalı';

  @override
  String get haSummaryReporting => 'Bildiriliyor';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Ana Ekran Tuşu Düzeltmesi\'ni açın ($path); açılır pencereleri o gösterir.';
  }

  @override
  String get haNotificationsShow => 'Home Assistant bildirimlerini göster';

  @override
  String get haNotificationsSendTest => 'Test bildirimi gönder';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Home Assistant\'ta $host ana bilgisayarıyla \"Notifications for Android TV / Fire TV\" entegrasyonunu ekleyin. Ardından otomasyonlardan ona bildirim gönderin; örneğin kapı zili için veya çamaşır bittiğinde.\n\nYalnızca ev ağınızdaki cihazlar gönderebilir (bağlantı noktası 7676). Açılır pencereler her uygulamanın üzerinde görünür ve Ana Ekran Tuşu Düzeltmesi\'nin ($path) açık olmasını gerektirir.';
  }

  @override
  String get haNotificationsThisTvIp => '(bu TV\'nin IP adresi)';

  @override
  String get haPanelSaved => 'Kaydedildi';

  @override
  String get haPanelSavedNoToken => 'Kaydedildi. Oturum açmak için bir erişim belirteci ekleyin.';

  @override
  String get haPanelReceived => 'Adres ve belirteç telefonunuzdan alındı';

  @override
  String get haPanelRightEdge => 'Sağ kenarda sağa basmak paneli açar';

  @override
  String get haSetUpFromPhone => 'Telefonunuzdan kurun';

  @override
  String get haPanelTokenLabel => 'Uzun ömürlü erişim belirteci';

  @override
  String get haPanelTokenSavedHint => 'Kaydedildi (değiştirmek için yenisini yazın)';

  @override
  String get haPanelDashboardLabel => 'Pano';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Yalnızca bu profil için açık. Panel, $tvStatus altındaki adresten bir panoyu belirteçle oturum açarak gösterir. Belirteci Home Assistant\'ta bu TV için oluşturulmuş yönetici olmayan bir kullanıcıyla oturum açmışken oluşturun (profil sayfası, Güvenlik sekmesi).';
  }

  @override
  String get haStatusReportingOff => 'Durum bildirimi kapalı';

  @override
  String get haStatusSaved => 'Kaydedildi: Home Assistant\'a bildiriliyor';

  @override
  String get haStatusAddressLabel => 'Home Assistant adresi';

  @override
  String get haStatusWebhookLabel => 'Webhook kimliği';

  @override
  String get haStatusNowPlayingOn => 'Şimdi oynatılıyor: açık';

  @override
  String get haStatusNowPlayingOff => 'Şimdi oynatılıyor: bildirim erişimini açın';

  @override
  String get haStatusHelp => 'TV, Home Assistant\'a ekranda ne olduğunu gönderir: uygulama, oynatılan içerik, Google TV profili ve çocukların ekran süresi. Yalnızca yukarıdaki adrese, değişiklik oldukça gönderir.';

  @override
  String get haPhoneSetupNoNetwork => 'Bu TV ev ağında değil, bu yüzden telefon ona ulaşamıyor.';

  @override
  String get haPhoneSetupScan => 'Aynı Wi-Fi ağındaki bir telefonla tarayın, Home Assistant adresini ve erişim belirtecini yapıştırıp Send\'e dokunun. Sayfa yalnızca bu pencere açıkken çalışır.';

  @override
  String get profilesSwitchProfile => 'Profil değiştir';

  @override
  String get parentPinTitle => 'Ebeveyn PIN\'i';

  @override
  String get parentPinOn => 'Açık';

  @override
  String get parentPinOff => 'Kapalı';

  @override
  String get parentPinCurrent => 'Mevcut ebeveyn PIN\'i';

  @override
  String get parentPinRemove => 'PIN\'i kaldır';

  @override
  String get parentPinChange => 'PIN\'i değiştir';

  @override
  String get parentPinNew => 'Yeni ebeveyn PIN\'i';

  @override
  String get parentPinNewSubtitle => 'Google TV çocuk profillerinde başlatıcıyı değiştirmek için gerekir';

  @override
  String get parentPinConfirm => 'PIN\'i yeniden girin';

  @override
  String get parentPinAskTitle => 'Bir ebeveyne sor';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Çocuk profillerinde başlatıcı ayarları kilitlidir. Bir ebeveyn kendi profilinden $settings → $profiles → $parentPin bölümünde PIN belirleyebilir.';
  }

  @override
  String get parentPinKidsSubtitle => 'Çocuk profili: başlatıcıyı değiştirmek için ebeveyn PIN\'ini girin';

  @override
  String get parentPinWrong => 'YANLIŞ PIN';

  @override
  String get parentPinEnter => 'PIN GİRİN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Merhaba $name';
  }

  @override
  String get profileSwitchSettingUp => 'Bu profil hazırlanıyor…';

  @override
  String profilesKidsName(String name) {
    return '$name (çocuk)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (yetişkin)';
  }

  @override
  String get pairingShowPicker => 'Seçiciyi göster';

  @override
  String get pairingAlwaysShowPicker => 'Seçiciyi her zaman göster';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (adla eşleşti)';
  }

  @override
  String get pairingNoMatchYet => 'Henüz eşleşme yok: seçici gösterilir';

  @override
  String get pairingOffSetUp => 'Profil eşleştirme kapalı. Kurun';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Hearth bu uygulamalardan birini açtığında Google TV profiliyle eşleştirilmiş uygulama profilini seçer. Hearth adları kendisi eşleştirir (\"$shortName\", \"$fullName\" ile eşleşir); herhangi bir eşleştirmeyi buradan değiştirebilirsiniz. Eşleşme yoksa uygulamanın kendi seçicisi gösterilir.';
  }

  @override
  String get pairingAppNotInstalled => 'Yüklü değil';

  @override
  String get pairingAppOff => 'Kapalı: uygulamanın kendi seçicisi gösterilir';

  @override
  String get pairingAppNotSeen => 'Hearth\'ün profilleri öğrenmesi için bir kez Hearth\'ten açın';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profil bulundu',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Adla eşleştir ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Adla eşleştir (henüz eşleşme yok)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$app içinde $profile';
  }

  @override
  String pairingPairIn(String app) {
    return '$app içinde profilleri eşleştir';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth bu uygulamanın profillerini henüz görmedi. Bir kez Hearth\'ten açın, sonra geri gelin.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Bu uygulamadaki profiller: $profiles. Google TV profilleri, Hearth onları gördüğünde burada görünür.';
  }

  @override
  String get familyAppsIntro => 'Hearth ve HearthTube\'u diğer Google TV profillerinize de yükleyin. Çocuk profillerinde bu, HearthTube\'un çalışması ve Hearth\'ün Netflix, Disney+ ve diğer uygulamalarda doğru profili seçmesi için gereklidir. Yetişkin profillerinde ise yalnızca kolaylık sağlar; elle yüklemek gerekmez.';

  @override
  String get familyAppsAddTitle => 'Hearth\'ü diğer profillere ekle';

  @override
  String get familyAppsAddKids => 'Bu, Hearth ve HearthTube\'u çocuklarınızın profillerine yükler; böylece HearthTube orada çalışır ve Hearth, Netflix ve Disney+ gibi uygulamalarda doğru profili seçebilir.';

  @override
  String get familyAppsAddAdults => 'Ayrıca bunları TV\'deki diğer yetişkin profillerine de yükler; böylece başka bir yetişkinin kendisi kurması gerekmez.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Yalnızca Hearth\'ün kendi iki uygulamasını ekler; aşağıdaki Kaldır ile istediğiniz zaman geri alabilirsiniz.';

  @override
  String get familyAppsAddFamilyLink => 'Her çocuk bir Family Link \"uygulama eklendi\" bildirimi alır.';

  @override
  String get familyAppsAddApproval => 'İlk seferde TV \"Hata ayıklamaya izin verilsin mi?\" diye sorar; Her zaman izin ver\'i seçin. Hearth\'ün kurulumu yapmasını sağlayan budur.';

  @override
  String get familyAppsAdd => 'Ekle';

  @override
  String get familyAppsRemoveTitle => 'Hearth\'ü diğer profillerden kaldır';

  @override
  String get familyAppsRemoveBody => 'Bu, Hearth ve HearthTube\'u diğer profillerinizden kaldırır.';

  @override
  String get familyAppsRemoveFirst => 'Hearth\'ün kendisini kaldırmayı planlıyorsanız önce bunu çalıştırın; aksi halde çocuk profillerindeki kopyaları ortada kalabilir ve temizlemek için bilgisayar gerekebilir.';

  @override
  String get familyAppsUninstallTitle => 'Hearth\'ü kaldır';

  @override
  String get familyAppsUninstallBody => 'Bu önce Hearth ve HearthTube\'u diğer profillerinizden kaldırır, ardından Hearth\'ü bu profilden kaldırır.';

  @override
  String get familyAppsUninstallWhyHere => 'Android ayarları yerine buradan kaldırmak, çocuk profillerinde hiçbir şey kalmamasını sağlar.';

  @override
  String get familyAppsApprovalFirstTitle => 'Önce tek seferlik onayı tamamlayın';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth diğer profilleri henüz temizleyemedi; TV\'de tek seferlik \"Hata ayıklamaya izin verilsin mi?\" onayı gerekiyor.';

  @override
  String get familyAppsApprovalFirstRetry => 'Onaylayın, ardından çocuk profillerinde hiçbir şey kalmaması için Kaldır\'ı yeniden deneyin.';

  @override
  String get familyAppsAddDone => 'Ekleme tamamlandı';

  @override
  String get familyAppsRemoveDone => 'Kaldırma tamamlandı';

  @override
  String get familyAppsAdded => 'Tamam. Hearth ve HearthTube artık diğer profillerinizde; aşağıdaki listeye bakın.';

  @override
  String get familyAppsRemoved => 'Tamam. Hearth ve HearthTube diğer profillerinizden kaldırıldı.';

  @override
  String get familyAppsNothingToSetUp => 'Henüz kurulacak başka profil yok.';

  @override
  String get familyAppsFailedTitle => 'Profiller kurulamadı';

  @override
  String get familyAppsFailedBody => 'Hearth\'ün diğer profilleri kurabilmesi için TV\'de tek seferlik bir onay gerekir.';

  @override
  String get familyAppsFailedRetry => 'TV \"Hata ayıklamaya izin verilsin mi?\" diye sorduğunda Her zaman izin ver\'i seçin, sonra yeniden deneyin.';

  @override
  String get familyAppsAlsoAdults => 'Diğer yetişkin profillerini de kur';

  @override
  String get familyAppsOn => 'Açık';

  @override
  String get familyAppsOff => 'Kapalı';

  @override
  String get familyAppsNoneYet => 'Henüz başka profil kurulmadı.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: yüklü';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: yüklü, korunuyor';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: yüklü değil';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: yüklü değil, korunuyor';
  }

  @override
  String get familyAppsUnnamedKids => 'Bir çocuk profili';

  @override
  String get familyAppsUnnamedAdult => 'Bir yetişkin profili';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'Sonraki ekranda Hizmetler\'e kaydırın, \"$service\" öğesini seçin, ardından Etkinleştir\'i açıp onaylayın. Ana ekrana dönene kadar Geri\'ye basın.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Android ayarın kısıtlandığını söylerse bunu bir bilgisayardan bir kez çalıştırın:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Ana ekran uygulaması olarak Hearth';

  @override
  String get setupDefaultLauncherWhy => 'Çocuk profillerinin Hearth\'ü engellemesini önler.';

  @override
  String get setupDefaultLauncherInstructions => 'Sonraki ekranda Hearth\'ü seçin.';

  @override
  String get setupHomeFixTitle => 'Ana Ekran Tuşu Düzeltmesi';

  @override
  String get setupHomeFixWhy => 'Ana ekran tuşu Google TV yerine Hearth\'ü açar.';

  @override
  String get setupNotificationsTitle => 'Bildirim erişimi';

  @override
  String get setupNotificationsWhy => 'Bildirimleri ve oynatılan içeriği gösterir.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'Sonraki ekranda \"$service\" öğesini seçip izin verin.';
  }

  @override
  String get setupInstallTitle => 'Güncellemeleri yükleme';

  @override
  String get setupInstallWhy => 'Hearth\'ün kendini güncellemesine ve yardımcı uygulamaları yüklemesine izin verir.';

  @override
  String get setupInstallInstructions => 'Sonraki ekranda Hearth\'ü açın.';

  @override
  String get setupPairingWhy => 'Netflix, Disney+, Apple TV, HBO Max ve Paramount+\'ta profilinizi seçer.';

  @override
  String get setupVoiceTitle => 'Hearth sesi';

  @override
  String get setupVoiceWhy => 'Profil eşleştirmenin Netflix\'in profil ekranını duymasını sağlar. Diğer uygulamalar Google\'ın sesini kullanmaya devam eder.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'Sonraki ekranda Tercih edilen motor altında \"$engine\" seçin, ardından uyarıda Tamam\'a basın (Hearth yalnızca yayın uygulamalarını dinler). Dönmek için Geri\'ye basın.';
  }

  @override
  String get setupOpenSettings => 'Ayarları aç';

  @override
  String get setupAdbFallback => 'Bu TV o ayar ekranını açmadı. Bunun yerine bunu bir bilgisayardan bir kez çalıştırın:';

  @override
  String setupProgress(int done, int total) {
    return '$total adımdan $done tamamlandı';
  }

  @override
  String get setupOptional => 'İsteğe bağlı';

  @override
  String get homeButtonFixOffTitle => 'Ana Ekran Tuşu Düzeltmesi kapalı';

  @override
  String get homeButtonFixOffBody => 'Hearth\'ün erişilebilirlik hizmeti durdu; bu genellikle bir güncellemeden sonra olur. Yeniden açılana kadar ana ekran tuşu Hearth yerine Google TV\'yi açabilir ve profil değişiklikleri izlenmez.';

  @override
  String get homeButtonFixStuck => 'Android onu hâlâ açık gösteriyor ama çalışmıyor. Yeniden başlatmak için Erişilebilirlik ayarlarında Hearth\'ü kapatıp yeniden açın.';

  @override
  String get homeButtonFixRestricted => 'Oradaki Hearth anahtarı griyse, bu güncelleme bir indirmeden yüklendiği için Android onu engelliyor. TV\'ye bağlı bir bilgisayardan bunu çalıştırın, ardından Hearth\'ü açın:';

  @override
  String get homeButtonFixDontRemind => 'Bana hatırlatma';

  @override
  String get homeButtonFixOpenSettings => 'Erişilebilirlik ayarlarını aç';
}
