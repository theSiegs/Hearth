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
  String get systemSettings => 'Google TV ayarları';

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
  String get remoteAndSearchTitle => 'Kumanda';

  @override
  String get parentSettingsTitle => 'Ebeveyn ayarları';

  @override
  String get tvPowerTitle => 'TV ve güç';

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
  String get familyAppsAddTitle => 'Hearth\'ü diğer profillere ekle';

  @override
  String get familyAppsAddKids => 'Bu, Hearth ve HearthTube\'u çocuklarınızın profillerine ekler; böylece HearthTube orada çalışır ve Hearth yayın hizmetlerinde doğru profili seçebilir.';

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
  String get remoteButtonsRemapButton => 'Bir tuşu yeniden ata';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Tuş $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normal';

  @override
  String get remoteButtonsCaptureTitle => 'Kumandada bir tuşa basın';

  @override
  String get remoteButtonsCaptureBody => 'Yeniden atamak istediğiniz tuşa basın. İptal etmek için Geri\'ye basın.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Önce Ana Ekran Tuşu Düzeltmesi\'ni açın';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Yeniden atama için Ana Ekran Tuşu Düzeltmesi gerekir ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Bu tuş yeniden atanamaz';

  @override
  String get remoteButtonsCantRemapBody => 'Yön tuşları, Tamam, Geri, Ana ekran ve güç tuşu normal işlevlerini korur.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Basma: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Basılı tutma: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Hearth araması için bas, Google için basılı tut';

  @override
  String get remoteButtonsHomeOnlyOn => 'Yalnızca Hearth ana ekranında: Açık';

  @override
  String get remoteButtonsHomeOnlyOff => 'Yalnızca Hearth ana ekranında: Kapalı';

  @override
  String get remoteButtonsRestore => 'Normal tuşu geri yükle';

  @override
  String get remoteButtonsActionTitle => 'Eylem';

  @override
  String get remoteButtonsActionApp => 'Bir uygulama aç…';

  @override
  String get remoteButtonsActionInput => 'Bir TV girişine geç…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Profil değiştir (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth araması (ses)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth araması (klavye)';

  @override
  String get remoteButtonsActionHome => 'Hearth ana ekranı';

  @override
  String get remoteButtonsActionSleep => 'Uyku';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android ayarları';

  @override
  String get remoteButtonsPickAppTitle => 'Bir uygulama aç';

  @override
  String get remoteButtonsPickInputTitle => 'Bir TV girişine geç';

  @override
  String get remoteButtonsHaConnectTitle => 'Önce Home Assistant\'ı bağlayın';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Home Assistant panelini kurun ($panel > $row), sonra yeniden deneyin.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Sahne: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Çalıştır: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Bas: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Aç/Kapat: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nBasma: $press  ·  Basılı tutma: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nBasma: $press  ·  Basılı tutma: $hold  ·  Yalnızca ana ekran';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Ana Ekran Tuşu Düzeltmesi gerekir ($path). Yalnızca basılı tutma eylemi olan bir tuş, normal basışta da o eylemi yapar. HearthTube öndeyken Hearth araması HearthTube\'un kendi aramasını açar. Çocuk ekran süresi ekranı gösterilirken yeniden atamalar duraklar.';
  }

  @override
  String get tvPowerScreensaver => 'Ekran koruyucu (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth, Google TV\'nin ekran koruyucusunu kullanır. Orada Google Photos\'u (ve hangi albümleri) ya da başka bir kaynağı seçin.';

  @override
  String get tvPowerSleepWhenIdle => 'Boşta kalınca uyku';

  @override
  String get tvPowerSleepOff => 'Kapalı';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes dk';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours saat',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'Video veya müzik oynatmak etkinlik sayılır. Ana Ekran Tuşu Düzeltmesi gerekir ($path).';
  }

  @override
  String get accentPurple => 'Mor';

  @override
  String get accentTeal => 'Petrol mavisi';

  @override
  String get accentBlue => 'Mavi';

  @override
  String get accentOrange => 'Turuncu';

  @override
  String get accentPink => 'Pembe';

  @override
  String get accentGreen => 'Yeşil';

  @override
  String get accentWhite => 'Beyaz';

  @override
  String get accentYellow => 'Sarı';

  @override
  String get accentRed => 'Kırmızı';

  @override
  String get accentCyan => 'Camgöbeği';

  @override
  String get accentIndigo => 'Çivit mavisi';

  @override
  String get accentLime => 'Limon yeşili';

  @override
  String get accentAmber => 'Kehribar';

  @override
  String get accentRose => 'Gül pembesi';

  @override
  String get accentIceBlue => 'Buz mavisi';

  @override
  String get accentSelected => 'Seçili vurgu rengi';

  @override
  String get cardStyleDefault => 'Varsayılan';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Parıltı';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Klasik';

  @override
  String get cardStyleMinimal => 'Minimal';

  @override
  String get cardStyleCapsule => 'Kapsül';

  @override
  String get dockFavoritesDock => 'Favoriler dock\'u';

  @override
  String get dockFavoritesDockDescription => 'Favorileri ana ekranın altında bir çubuk olarak gösterir; üstünde İzlemeye Devam Et, altında diğer bölümleriniz yer alır. Köşeleri kart stiline uyar.';

  @override
  String get dockFrosted => 'Buzlu dock';

  @override
  String get dockDark => 'Koyu dock';

  @override
  String get dockShadow => 'Dock gölgesi';

  @override
  String get dockBlurWallpaperBelow => 'Dock\'un altındaki duvar kağıdını bulanıklaştır';

  @override
  String get wallpaperMatchSelectedApp => 'Seçili uygulamaya uydur';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing Günün Fotoğrafı';

  @override
  String get wallpaperRefreshNow => 'Şimdi yenile';

  @override
  String get wallpaperBingError => 'Bing\'e ulaşılamadı. Ağ bağlantınızı kontrol edin.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Sıcaklık Birimi: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Hava durumu konumu: ayarlanmadı';

  @override
  String weatherLocationValue(String place) {
    return 'Hava durumu konumu: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Hava durumu yüklenemedi. Otomatik olarak yeniden denenecek.';

  @override
  String get statusBarWeatherSourceHint => 'Yukarıdan bir hava durumu konumu seçin (hava durumu Open-Meteo\'dan, ücretsiz, hesap gerekmez). Seçilmezse hava durumu, Gadgetbridge paylaşımı açık olarak yüklüyse Breezy Weather uygulamasından gelir.';

  @override
  String get weatherLocationTitle => 'Hava durumu konumu';

  @override
  String get weatherLocationHint => 'Şehir veya kasaba';

  @override
  String get weatherLocationNoResults => 'Yer bulunamadı';

  @override
  String get weatherLocationSearchError => 'Hava durumu hizmetine ulaşılamadı. Ağ bağlantısını kontrol edin.';

  @override
  String get weatherLocationPrivacyNote => 'Hava durumu Open-Meteo.com\'dan: ücretsiz, hesap gerekmez. Yalnızca seçilen yerin koordinatları gönderilir.';

  @override
  String get weatherLocationSearch => 'Ara';

  @override
  String get dateTimeInvalidFormat => 'Geçersiz biçim';

  @override
  String get dateTimeSelectFormats => 'Aşağıdan biçimleri seçin';

  @override
  String get dataUsageDaily => 'Günlük';

  @override
  String get dataUsageWeekly => 'Haftalık';

  @override
  String get dataUsageMonthly => 'Aylık';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'İzlemeye Devam Et\'ten engellenenler ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'İzlemeye Devam Et\'ten engellendi';

  @override
  String get cwAppsUnblock => 'Engeli kaldır';

  @override
  String get cwAppsUnblockAllApps => 'Tüm uygulamaların engelini kaldır';

  @override
  String get cwAppsNoBlockedApps => 'Engellenen uygulama yok';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Desteklenen tüm uygulamalar İzlemeye Devam Et\'te öğe gösterebilir.';

  @override
  String get cwAppsWithContinueWatching => 'İzlemeye Devam Et içeren uygulamalar';

  @override
  String get cwAppsWithContinueWatchingHint => 'Şu anda ana ekranınıza Watch Next öğeleri sağlayan uygulamalar';

  @override
  String get cwAppsNoActiveApps => 'Şu anda hiçbir uygulama İzlemeye Devam Et öğesi sağlamıyor.\nDesteklenen uygulamalar (SmartTube veya yayın hizmetleri gibi) öğe eklediğinde burada görünür.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etkin öğe',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Tüm yüklü uygulamalar';

  @override
  String get cwAppsAllInstalledAppsHint => 'Bir uygulamanın İzlemeye Devam Et\'e öğe eklemesini engellemek için kapatın';

  @override
  String get cwAppsBlocked => 'Engellendi';

  @override
  String get cwAppsAllowed => 'İzin verildi';

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
  String get cwCardSizeExtraSmall => 'Ekstra küçük';

  @override
  String get cwCardSizeVerySmall => 'Çok küçük';

  @override
  String get cwCardSizeSmall => 'Küçük';

  @override
  String get cwCardSizeCompact => 'Kompakt';

  @override
  String get cwCardSizeMediumSmall => 'Orta küçük';

  @override
  String get cwCardSizeMedium => 'Orta';

  @override
  String get cwCardSizeStandardDefault => 'Standart (varsayılan)';

  @override
  String get cwCardSizeStandard => 'Standart';

  @override
  String get cwCardSizeMediumLarge => 'Orta büyük';

  @override
  String get cwCardSizeLarge => 'Büyük';

  @override
  String get cwCardSizeVeryLarge => 'Çok büyük';

  @override
  String get cwCardSizeExtraLarge => 'Ekstra büyük';

  @override
  String get cwCardSizeHuge => 'Dev';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'En fazla $count son öğeyi göster',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Varsayılan';
  }

  @override
  String get cwUnlimited => 'Sınırsız';

  @override
  String get cwMaxItemsAll => 'Tüm mevcut öğeleri göster';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Oynatma ilerleme çubuğu';

  @override
  String get cwPlaybackPercentage => 'Oynatma yüzdesi';

  @override
  String get cwEpisodeDetails => 'Bölüm ve video ayrıntıları';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count engellendi',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Yönet';

  @override
  String get cwRestoreHiddenPrograms => 'Gizli programları geri yükle';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gizli',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'Tüm gizli programlar geri yüklendi';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next Erişimi (ADB gerekli)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV, başlatıcıların yüklü uygulamalardaki İzlemeye Devam Et satırlarını okuyup göstermesi için READ_WRITE_WATCH_NEXT_PROGRAMS iznini gerektirir.\n\nBu izni vermek için TV\'nize ADB ile bağlanın ve şunu çalıştırın:';

  @override
  String get appsNoApplicationsFound => 'Uygulama bulunamadı';

  @override
  String get appDetailsAddToFavorites => 'Favorilere ekle';

  @override
  String get appDetailsRemoveFromFavorites => 'Favorilerden kaldır';

  @override
  String get appDetailsAddToCategory => 'Kategoriye ekle';

  @override
  String get sectionsCustomOption => 'Özel...';

  @override
  String get sectionsSelectName => 'Bir ad seçin';

  @override
  String get sectionsCustomName => 'Özel ad';

  @override
  String get sectionsSortLastUsed => 'Son kullanılan';

  @override
  String get sectionsReorderHint => '◄ / ► ile seçin, ardından sıralamak için ▲ / ▼ kullanın';

  @override
  String get inputsNoneDetected => 'Giriş algılanmadı';

  @override
  String get notifClearAll => 'Tümünü temizle';

  @override
  String get notifAllCaughtUp => 'Hepsini gördünüz!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Bildirimleri Engelle ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return '$app uygulamasını aç';
  }

  @override
  String get notifAccessAdbTitle => 'Bildirim Erişimi (ADB gerekli)';

  @override
  String get notifAccessAdbMessage => 'Android TV, \"Bildirim Erişimi\" (diğer uygulamaların bildirimlerini dinleme) için bir sistem ayarları ekranı sunmaz.\n\nNot: TV Uygulama Ayarları\'nda \"Bildirimleri göster\"i açmak yalnızca bu uygulamanın gönderdiği bildirimleri kontrol eder, Bildirim Erişimi\'ni değil.\n\nBildirim Erişimi vermek için TV\'nize ADB ile bağlanın ve şunu çalıştırın:';

  @override
  String get notifOpenAppInfo => 'Uygulama bilgisini aç';

  @override
  String get notifOverlayPermissionTitle => 'Kaplama İzni';

  @override
  String get notifOverlayAdbMessage => 'Bu cihazda Kaplama İzni ayarları ekranı otomatik olarak açılamadı.\n\nKaplama açılır pencerelerini etkinleştirmek için TV\'ye bağlı bir bilgisayardan ADB ile izni elle verin:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Engellenen Uygulamalar ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'Şimdilik Google TV\'yi kullan';

  @override
  String get backupShareText => 'Hearth Yedeği';

  @override
  String get backupShareFailedTitle => 'Paylaşılamadı';

  @override
  String backupShareFailed(String error) {
    return 'Yedek paylaşılamadı: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Dışa aktarma başarılı';

  @override
  String get backupExportFailedTitle => 'Dışa aktarma başarısız';

  @override
  String get backupImportSuccessTitle => 'İçe aktarma başarılı';

  @override
  String get backupImportFailedTitle => 'İçe aktarma başarısız';

  @override
  String get backupImport => 'İçe aktar';

  @override
  String backupLoadError(String error) {
    return 'Yedekler yüklenirken hata: $error';
  }

  @override
  String get backupNoFiles => 'Yedek dosyası bulunamadı.';

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
  String get updateCheckForUpdatesTitle => 'Güncellemeleri denetle';

  @override
  String updateCurrentVersion(String version) {
    return 'Geçerli sürüm: $version';
  }

  @override
  String get updateChecking => 'GitHub\'da yeni sürüm aranıyor…';

  @override
  String get updateUpToDate => 'En son sürümü kullanıyorsunuz.';

  @override
  String updateVersionAvailable(String version) {
    return '$version sürümü kullanılabilir';
  }

  @override
  String updateDownloading(String percent) {
    return 'İndiriliyor… %$percent';
  }

  @override
  String get updateDownloadedHint => 'İndirildi. Yükleyici açılmadıysa cihazınızda Hearth\'e\n\"Bilinmeyen uygulamaları yükle\" izni vermeniz gerekebilir.';

  @override
  String get updateSomethingWentWrong => 'Bir şeyler ters gitti';

  @override
  String get updateDownloadAndInstall => 'İndir ve yükle';

  @override
  String get updateRetryInstall => 'Yüklemeyi yeniden dene';

  @override
  String get updateCheckAgain => 'Yeniden denetle';

  @override
  String get updatesInstallPermissionTitle => 'Hearth\'ün uygulama yüklemesine izin verin';

  @override
  String get updatesInstallPermissionMessage => 'Sonraki ekranda Hearth\'ü bulup açın, ardından Geri\'ye basın. Buraya döndüğünüzde yükleme devam eder.';

  @override
  String get updatesOpenSettings => 'Ayarları aç';

  @override
  String get updatesCheckFailed => 'Güncellemeler denetlenemedi';

  @override
  String get updatesInstallerNotStarted => 'Yükleyici başlamadı';

  @override
  String get updatesCheckForUpdates => 'Güncellemeleri denetle';

  @override
  String get updatesAutoUpdate => 'Otomatik güncelle';

  @override
  String get updatesAutoUpdateDescription => 'Hearth her gün denetler ve yüklediği uygulamaların güncellemelerini, kullanılmadıkları sırada yükler';

  @override
  String get updatesIncludePrereleases => 'Ön sürümleri dahil et';

  @override
  String get updatesIncludePrereleasesDescription => 'Hearth ve HearthTube\'un erken test sürümleri. Tamamlanmamış olabilirler.';

  @override
  String get updatesFooter => 'Her uygulamanın GitHub sürümlerinden yüklenir. Hearth bir uygulamayı bir kez yükledikten veya güncelledikten sonra güncellemeleri sormadan yüklenir ve uygulama güncellemeyi Hearth\'e bırakır.';

  @override
  String get updatesChecking => 'Denetleniyor…';

  @override
  String get updatesInstall => 'Yükle';

  @override
  String updatesUpdateTo(String version) {
    return '$version sürümüne güncelle';
  }

  @override
  String get updatesUpToDate => 'Güncel';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'İndiriliyor %$percent';
  }

  @override
  String get updatesInstalling => 'Yükleniyor…';

  @override
  String get updatesError => 'Hata';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return '$author tarafından geliştirilen $launcher ve $original temel alınarak, $parts parçalarıyla';
  }

  @override
  String get aboutDescription => 'Google TV için gizliliğe önem veren, aile dostu bir başlatıcı; Google TV profilleri ve Home Assistant yerleşik. Reklamsız ve izleyicisiz.';

  @override
  String get aboutHearthOnGitHub => 'GitHub\'da Hearth';

  @override
  String get aboutCredits => 'Katkıda bulunanlar';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher çatalı · $author';
  }

  @override
  String get aboutLicense => 'Temel aldığı projeler gibi GNU GPL v3 kapsamında özgür yazılımdır.';

  @override
  String get familyAppsStatusInstalled => 'Yüklü';

  @override
  String get familyAppsStatusPartial => 'Kısmi';

  @override
  String get familyAppsStatusNotInstalled => 'Yüklü değil';

  @override
  String get familyAppsStatusAtRisk => 'Risk altında';

  @override
  String get familyAppsAtRiskDetail => 'Google TV, bu profil bir sonraki açılışında buradaki korumasız uygulamaları kaldıracak. Korumak için Ekle\'yi yeniden kullanın.';

  @override
  String get profilePinRow => 'Profil PIN’i';

  @override
  String get profilePinNone => 'Yok';

  @override
  String get profilePinSaved => 'Kayıtlı';

  @override
  String get profilePinRejected => 'Kayıtlı — son seferde kabul edilmedi';

  @override
  String get profilePinPaused => 'Kayıtlı — duraklatıldı (uygulama değişti)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth henüz $app içinde PIN yazamıyor';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$profile için $app PIN’i';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return '$app sorduğunda Hearth onu “Giriş yapılıyor” kartının arkasında yazar. Bu TV’de şifreli kalır ve asla gösterilmez.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Önce bir ebeveyn PIN’i belirleyin ($settings → $profiles → $parentPin): profil PIN’i kaydetmek için gerekir.';
  }

  @override
  String get profilePinSaveFailed => 'PIN kaydedilemedi.';

  @override
  String get profileLockNow => 'Profili kilitle';

  @override
  String get profileLockOnSleep => 'TV uykuya geçtiğinde kilitle';

  @override
  String get profileLockEveryTime => 'Her seferinde';

  @override
  String profileLockAfterMinutes(int minutes) {
    return '$minutes dk uykudan sonra';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Google TV\'nin kendi profil kilidini kullanır: Google TV Ayarları → Hesaplar ve Oturum Açma → hesabınız → Profil kilidi\'nden hesabınız için açın.';

  @override
  String get aboutWallpaperPhoto => 'DUVAR KAĞIDI FOTOĞRAFI';

  @override
  String get updateErrorWrongApp => 'Bu indirme bu Hearth için bir güncelleme değil';

  @override
  String get setupFlowFinishLater => 'Sonra bitir';

  @override
  String get setupFlowStripEssentials => 'Temel';

  @override
  String get setupFlowWelcomeTitle => 'Hearth\'e hoş geldiniz';

  @override
  String get setupFlowWelcomeBody => 'Tüm aile için bir ana ekran: uygulamalarınız, izlemekte olduklarınız ve her yayın uygulamasında doğru profil.';

  @override
  String get setupFlowWelcomeTime => 'Yaklaşık 5 dakika sürer. İstediğinizi atlayabilirsiniz.';

  @override
  String get setupFlowGetStarted => 'Başlayın';

  @override
  String get setupFlowSetUpLater => 'Sonra kur';

  @override
  String setupFlowLanguageLink(String language) {
    return 'Dil: $language';
  }

  @override
  String get setupFlowRestoreLink => 'Yedekten geri yükle';

  @override
  String get setupFlowHomeButtonTitle => 'Ana Sayfa düğmesi Hearth\'ü açsın';

  @override
  String get setupFlowHomeButtonBody => 'Google TV, Ana Sayfa düğmesinde kendi ana ekranını tutar. Android ayarlarındaki tek bir anahtar bunu düzeltir ve Hearth\'ün şunları yapmasını da sağlar:';

  @override
  String get setupFlowHomeButtonPoint1 => 'profil değişikliklerini ve çocukların yatma saatini izlemesini';

  @override
  String get setupFlowHomeButtonPoint2 => 'açılır bildirimler göstermesini ve boştayken TV\'yi kapatmasını';

  @override
  String get setupFlowOnNextScreen => 'Sonraki ekranda:';

  @override
  String get setupFlowStepServices => 'Hizmetler\'e kaydırın';

  @override
  String setupFlowStepSelect(String name) {
    return '\"$name\" öğesini seçin';
  }

  @override
  String get setupFlowStepEnable => 'Etkinleştir\'i açın, sonra Tamam';

  @override
  String get setupFlowComesBack => 'Açıldığında Hearth kendiliğinden geri gelir. Google TV kimin izlediğini sorarsa kendinizi seçin.';

  @override
  String get setupFlowOpenAccessibility => 'Erişilebilirlik\'i aç';

  @override
  String get setupFlowHomeButtonDone => 'Ana Sayfa düğmesi artık Hearth\'ü açıyor';

  @override
  String get setupFlowNotOnYetTitle => 'Henüz açık değil';

  @override
  String get setupFlowNotOnYetBody => 'Yeniden deneyin ya da atlayıp daha sonra Ayarlar\'dan yapın.';

  @override
  String get setupFlowStuckTitle => 'Açık ama çalışmıyor';

  @override
  String get setupFlowStuckBody => 'Android onu açık gösteriyor ama çalışmıyor. Kapatıp yeniden açın.';

  @override
  String get setupFlowSkipHomeButtonTitle => 'Ana Sayfa düğmesi atlansın mı?';

  @override
  String get setupFlowSkipHomeButtonBody => 'Bu olmadan Ana Sayfa düğmesi Google TV\'yi açar ve Hearth bir çocuk profilinin ne zaman kullanıldığını anlayamaz.';

  @override
  String get setupFlowSkipAnyway => 'Yine de atla';

  @override
  String get setupFlowSkip => 'Atla';

  @override
  String get setupFlowNext => 'İleri';

  @override
  String get setupFlowLostTitle => 'Güncelleme Ana Sayfa düğmesini kapattı';

  @override
  String get setupFlowLostBody => 'Android bazı güncellemelerden sonra onu kapatır. Tek adımda yeniden açın.';

  @override
  String get setupFlowBlockedTitle => 'Android bu anahtarı engelledi';

  @override
  String get setupFlowBlockedBody => 'Anahtar griyse bunun nedeni Hearth\'ün indirilmiş bir dosyadan yüklenmiş olmasıdır. TV\'de buna izin veren bir ayar yok.';

  @override
  String get setupFlowBlockedComputer => 'Bir bilgisayarla:';

  @override
  String get setupFlowBlockedComputerThen => 'Ardından anahtarı açın. Hearth bunu kendisi fark eder.';

  @override
  String get setupFlowBlockedSelfFixBody => 'Hata ayıklama açık, bu yüzden Hearth bunu kendisi düzeltebilir. TV \"Hata ayıklamaya izin verilsin mi?\" diye soracak: Her zaman izin ver\'i seçin; Hearth anahtarının engelini kaldırıp açacak.';

  @override
  String get setupFlowSkipForNow => 'Şimdilik atla';

  @override
  String get setupFlowBlockedSkipLine => 'Uygulamalar, arama ve İzlemeye Devam Et çalışmaya devam eder. Ana Sayfa düğmesi, profiller, açılır bildirimler ve uyku zamanlayıcısı çalışmaz.';

  @override
  String get setupFlowLetHearthFix => 'Hearth düzeltsin';

  @override
  String get setupFlowFixConfirmBody => 'Hearth kendi hata ayıklama bağlantısıyla TV\'de şunu çalıştıracak:';

  @override
  String get setupFlowFixConfirmApproval => 'İlk seferde TV \"Hata ayıklamaya izin verilsin mi?\" diye sorar. Her zaman izin ver\'i seçin. Yalnızca Hearth\'ün kendi izinleri değişir.';

  @override
  String get setupFlowFixRun => 'Çalıştır';

  @override
  String get setupFlowFixWaiting => 'Çalışılıyor. TV \"Hata ayıklamaya izin verilsin mi?\" diye sorarsa Her zaman izin ver\'i seçin.';

  @override
  String get setupFlowFixFailedTitle => 'Hearth bunu yapamadı';

  @override
  String get setupFlowFixFailedBody => 'Hearth TV\'nin hata ayıklamasına ulaşamadı. TV \"Hata ayıklamaya izin verilsin mi?\" diye sorduysa Her zaman izin ver\'i seçip yeniden deneyin. Hata ayıklama Geliştirici seçenekleri\'nde açık kalmalıdır.';

  @override
  String get setupFlowHomeAppTitle => 'Hearth\'ü ana ekran uygulamanız yapın';

  @override
  String get setupFlowHomeAppBody => 'Android ana ekran uygulamalarının listesini gösterecek. Hearth\'ü seçin. Böylece çocuk profilleri Hearth\'ü engellemez.';

  @override
  String get setupFlowChooseHearth => 'Hearth\'ü seç';

  @override
  String get setupFlowHomeAppDone => 'Hearth ana ekran uygulamanız';

  @override
  String get setupFlowNotChosenTitle => 'Henüz seçilmedi';

  @override
  String get setupFlowFinishTitle => 'Hearth hazır';

  @override
  String setupFlowFinishBody(String where) {
    return 'Atladığınız her şey Ayarlar\'da; bunu $where bölümünden yeniden çalıştırabilirsiniz.';
  }

  @override
  String get setupFlowFinishOn => 'Açık';

  @override
  String get setupFlowFinishLaterHeading => 'Sonra, Ayarlar\'da';

  @override
  String get setupFlowFinishMore => 'Ayarlar\'da daha fazlası: kumanda düğmeleri, bölümler, bildirimler ve yedekleme.';

  @override
  String get setupFlowGoHome => 'Ana ekranıma git';

  @override
  String get setupHearthTitle => 'Hearth\'ü kur';

  @override
  String get setupRunAgain => 'Kurulumu yeniden çalıştır';

  @override
  String get setupCardFamily => 'Aileniz';

  @override
  String get setupCardWatching => 'İzleme';

  @override
  String setupChipLeft(int count) {
    return 'Kurulumu bitir · kalan: $count';
  }

  @override
  String get setupChipFix => 'Ana Sayfa düğmesinin düzeltilmesi gerekiyor';

  @override
  String get setupChipHideTitle => 'Bu hatırlatıcı gizlensin mi?';

  @override
  String setupChipHideBody(String where) {
    return 'Kurulumu yine de $where bölümünden çalıştırabilirsiniz.';
  }

  @override
  String get setupChipHide => 'Gizle';

  @override
  String get setupFlowCardIncluded => 'Neler var';

  @override
  String get setupFlowCardNeeds => 'Gerekenler';

  @override
  String get setupFlowCardSkipped => 'Atlandı';

  @override
  String get setupFlowChange => 'Değiştir';

  @override
  String get setupFlowKeep => 'Koru';

  @override
  String get setupFlowTurnOn => 'Aç';

  @override
  String get setupFlowNeedsQuestion => 'Android\'den bir soru';

  @override
  String get setupFlowNeedsOneSwitch => 'Android ayarlarında bir anahtar';

  @override
  String get setupFlowNeedsAboutAMinute => 'Yaklaşık bir dakika';

  @override
  String get setupFlowWatchingBenefit => 'Kaldığınız yerden devam edin ve neyin oynatıldığını görün.';

  @override
  String get setupFlowWatchingIncluded1 => 'Ana ekranda İzlemeye devam et';

  @override
  String get setupFlowWatchingIncluded2 => 'Bildirimler ve oynatılanlar';

  @override
  String get setupFlowSearchWorks => 'Arama zaten çalışıyor: ana ekranda Ara\'ya basın.';

  @override
  String get setupFlowContinueBody => 'Uygulamalarınızda izlediklerinizi ana ekranda gösterin. Android bir kez soracak; İzin ver\'i seçin.';

  @override
  String get setupFlowContinueDone => 'İzlemeye devam et açık';

  @override
  String get setupFlowContinueDeniedTitle => 'Android izin vermedi';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'Daha sonra $where bölümünden açabilirsiniz.';
  }

  @override
  String get setupFlowNotificationsTitle => 'Oynatılanlar ve bildirimler';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'Bildirimlerinizi ve oynatılanları görün. Sonraki ekranda \"$name\" öğesini seçip izin verin.';
  }

  @override
  String get setupFlowNotificationsDone => 'Bildirimler açık';

  @override
  String get setupFlowTvTitle => 'Kimse izlemediğinde TV kapatılsın mı?';

  @override
  String get setupFlowTvBody => 'Bu süre boyunca kumandaya basılmazsa. Video veya müzik çalması izleme sayılır.';

  @override
  String get setupFlowTvNeedsHomeButton => 'Bunun için ilk adımlardaki Ana Ekran düğmesi anahtarı gerekir: o olmadan Hearth kumandanın ne zaman kullanıldığını bilemez.';

  @override
  String get setupFlowStartOnBoot => 'TV açıldığında Hearth\'ü başlat';

  @override
  String get setupFlowScreensaver => 'Ekran koruyucu fotoğraflarını seç';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth kendini ve yardımcı uygulamalarını güncel tutar.';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth kendini günceller';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, Hearth için yapılmış bir YouTube uygulaması';

  @override
  String get setupFlowInstallTitle => 'Hearth\'ün güncelleme yüklemesine izin ver';

  @override
  String get setupFlowInstallBody => 'Sonraki ekranda Hearth\'ü bulup açın, ardından Geri\'ye basın.';

  @override
  String get setupFlowInstallDone => 'Hearth güncelleme yükleyebilir';

  @override
  String get setupFlowTubeTitle => 'HearthTube yüklensin mi?';

  @override
  String get setupFlowTubeBody => 'Hearth için yapılmış bir YouTube uygulaması: profillerinizi, saat stilini ve çocukların yatma saatini izler.';

  @override
  String get setupFlowTubeInstalled => 'HearthTube yüklü';

  @override
  String get setupCardHome => 'Ana ekranınız';

  @override
  String get setupFlowLookTitle => 'Bir görünüm seçin';

  @override
  String setupFlowLookBody(String where) {
    return 'Her biri, üzerine geldiğinizde bu kartın arkasında görünür. Herhangi bir parçasını daha sonra $where bölümünden değiştirebilirsiniz.';
  }

  @override
  String get setupFlowLookOtherTitle => 'Ana ekranınız için bir görünüm seçin';

  @override
  String get setupFlowLookOtherBody => 'Her profilin kendi ana ekranı vardır. Sizinkinin nasıl görüneceğini seçin.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'Günün fotoğrafı';

  @override
  String get setupLookCalmDark => 'Sakin koyu';

  @override
  String get setupLookBold => 'Canlı';

  @override
  String get setupFlowLookNow => 'Şu anki';

  @override
  String get setupFlowLookUse => 'Bu görünümü kullan';

  @override
  String get setupFlowLookKeep => 'Mevcut kalsın';

  @override
  String get setupFlowLookCustomize => 'Özelleştir';

  @override
  String get setupFlowWeatherTitle => 'Hava durumu gösterilsin mi?';

  @override
  String get setupFlowWeatherBody => 'Şehrinizi seçin. Yalnızca konumu Open-Meteo\'ya gönderilir; hesap gerekmez.';

  @override
  String get setupFlowWeatherChoose => 'Şehir seç';

  @override
  String get setupFlowWeatherDone => 'Hava durumu üst çubukta görünür';

  @override
  String get setupFlowFamilyBenefit => 'Yayın uygulamaları doğru kişiyle açılır ve çocuklar Hearth\'ü değiştiremez.';

  @override
  String get setupFlowFamilyIncluded1 => 'Çocuklar Hearth\'ü değiştiremesin diye ebeveyn PIN\'i';

  @override
  String get setupFlowFamilyIncluded2 => 'Netflix, Disney+, Apple TV, Max ve Paramount+\'ta doğru profil';

  @override
  String get setupFlowFamilyIncluded3 => 'Hearth çocuklarınızın profillerinde kalır';

  @override
  String get setupFlowNeedsPin => 'Seçeceğiniz dört rakam';

  @override
  String get setupFlowNeedsTwoMinutes => 'Yaklaşık 2 dakika';

  @override
  String get setupFlowPinTitle => 'Ebeveyn PIN\'i seçin';

  @override
  String get setupFlowPinBody => 'Çocukların Hearth\'ü değiştirmesi için gerekir. Bir çocuğun tahmin edemeyeceği dört rakam seçin.';

  @override
  String get setupFlowPinChoose => 'PIN seç';

  @override
  String get setupFlowPinDone => 'Ebeveyn PIN\'i ayarlandı';

  @override
  String get setupFlowPairingTitle => 'Yayın uygulamalarında doğru profil';

  @override
  String setupFlowPairingBody(String name) {
    return 'Hearth; Netflix, Disney+, Apple TV, Max ve Paramount+\'ta her kişinin profilini seçer. Aynı Android ekranında bir anahtar daha gerekir: \"$name\".';
  }

  @override
  String get setupFlowPairingDone => 'Profil eşleştirme açık';

  @override
  String get setupFlowPairingDoneBody => 'Hearth adları kendisi eşleştirir: \"Alex\", \"Alex Morgan\" ile eşleşir. Her uygulamanın profilleri, \"Kim izliyor?\" ekranı bir kez göründükten sonra çıkar.';

  @override
  String get setupFlowCheckPairings => 'Eşleştirmeleri kontrol et';

  @override
  String get setupFlowVoiceTitle => 'Netflix için bir adım daha';

  @override
  String setupFlowVoiceBody(String name) {
    return 'Netflix profil ekranını sesli okur; bu yüzden Hearth kendi sesiyle dinler. Sonraki ekranda Tercih edilen motor altında \"$name\" seçin, sonra Tamam. Diğer uygulamalar Google\'ın sesini kullanmaya devam eder.';
  }

  @override
  String get setupFlowVoiceDone => 'Hearth sesi açık';

  @override
  String get setupFlowKidsTitle => 'Hearth\'ü çocuklarınızın profillerinde tutun';

  @override
  String get setupFlowKidsBody => 'Google TV, çocuk profilleri her başladığında kendi yüklemediği uygulamaları kaldırır. Hearth orada kendisini ve HearthTube\'u koruyabilir. Her çocuk bir Family Link \"uygulama eklendi\" bildirimi alır; istediğiniz zaman Ayarlar\'dan geri alın.';

  @override
  String get setupFlowKidsApprove => 'TV \"Hata ayıklamaya izin verilsin mi?\" diye soracak. Her zaman izin ver\'i işaretleyip İzin ver\'i seçin. Bunu yalnızca bir kez yaparsınız.';

  @override
  String get setupFlowKidsAdd => 'Profillerine ekle';

  @override
  String get setupFlowKidsDone => 'Hearth çocuklarınızın profillerinde';

  @override
  String get setupFlowKidsKeepDebugging => 'Hata ayıklamayı açık bırakın: Hearth\'ün yeni bir çocuk profili için ve kendini kaldırmak için buna yine ihtiyacı olacak.';

  @override
  String get setupFlowDebugTitle => 'Önce hata ayıklamayı açın';

  @override
  String get setupFlowDebugBody => 'Hearth\'ün çocuk profillerini kurmak için TV\'nin hata ayıklama anahtarına ihtiyacı var. Sonraki ekranda \"Android TV OS derlemesi\" öğesini yedi kez seçin. Ardından Ayarlar > Sistem > Geliştirici seçenekleri\'nde USB hata ayıklama\'yı açıp geri gelin. Açık bırakın: Hearth\'ün yeni bir çocuk profili için buna yine ihtiyacı olacak.';

  @override
  String get setupFlowDebugOpen => 'Hakkında\'yı aç';

  @override
  String get setupCardSmartHome => 'Akıllı ev';

  @override
  String get setupFlowHaBenefit => 'Kapı zili ve diğer uyarılar TV\'de, Home Assistant panonuz tek tuş uzağınızda.';

  @override
  String get setupFlowHaIncluded1 => 'Her uygulamanın üstünde kapı zili ve diğer uyarılar';

  @override
  String get setupFlowHaIncluded2 => 'Panonuz tek tuş uzağınızda';

  @override
  String get setupFlowHaIncluded3 => 'Açık olan şey Home Assistant\'a gönderilir';

  @override
  String get setupFlowNeedsPhone => 'Aynı Wi-Fi\'de bir telefon';

  @override
  String get setupFlowNeedsFewMinutes => 'Birkaç dakika';

  @override
  String get setupFlowHaUse => 'Home Assistant kullanıyorum';

  @override
  String get setupFlowHaAlertsTitle => 'Home Assistant uyarıları';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'Home Assistant\'ta bu TV\'nin adresiyle \"Notifications for Android TV / Fire TV\" ekleyin: $ip. Ardından bir test gönderin.';
  }

  @override
  String get setupFlowHaAlertsDone => 'Uyarılar açık';

  @override
  String get setupFlowHaDashboardTitle => 'Panonuz TV\'de';

  @override
  String get setupFlowHaDashboardBody => 'Telefonunuzla tarayın, Home Assistant adresini ve bir belirteci yapıştırıp Gönder\'e dokunun. Yönetici değil, TV için oluşturulmuş bir Home Assistant kullanıcısı kullanın.';

  @override
  String get setupFlowHaDashboardDone => 'Panonuz kuruldu';

  @override
  String get setupFlowHaStatusTitle => 'Home Assistant\'a neyin açık olduğunu bildir';

  @override
  String get setupFlowHaStatusBody => 'TV, oynatılanı ve etkin profili Home Assistant\'a gönderebilir. Aynı telefon sayfasında Home Assistant\'taki bir webhook otomasyonunun kimliğini ekleyin.';

  @override
  String get setupFlowHaStatusNoWebhook => 'Telefon bir webhook kimliği göndermedi. Sayfadaki son kutuyu doldurun.';

  @override
  String get setupFlowHaStatusDone => 'TV, Home Assistant\'a neyin açık olduğunu bildiriyor';

  @override
  String setupChipNewOne(String feature) {
    return 'Hearth\'te yeni: $feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'Hearth\'te yeni · $count';
  }
}
