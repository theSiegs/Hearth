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
}
