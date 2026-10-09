import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get aboutFlauncher => 'Про Hearth';

  @override
  String get addSection => 'Додати розділ';

  @override
  String get alphabetical => 'За алфавітом';

  @override
  String get appCardHighlightAnimation => 'Анімація виділення картки застосунку';

  @override
  String get appInfo => 'Інформація про застосунок';

  @override
  String get appKeyClick => 'Звук клацання при натисканні клавіші';

  @override
  String get applications => 'Застосунки';

  @override
  String get autoHideAppBar => 'Автоматично приховувати рядок стану';

  @override
  String get backButtonAction => 'Дія кнопки «Назад»';

  @override
  String get category => 'Категорія';

  @override
  String get columnCount => 'Кількість стовпців';

  @override
  String get date => 'Дата';

  @override
  String get dateAndTimeFormat => 'Формат дати й часу';

  @override
  String get delete => 'Видалити';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Нічого не робити';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Показати заставку';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Показати годинник';

  @override
  String get dialogTextNoFileExplorer => 'Будь ласка, встановіть файловий менеджер, щоб вибрати зображення.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Категорія)';
  }

  @override
  String get gradient => 'Градієнт';

  @override
  String get favoriteApps => 'Улюблені застосунки';

  @override
  String get grid => 'Сітка';

  @override
  String get height => 'Висота';

  @override
  String get hide => 'Приховати';

  @override
  String get hiddenApplications => 'Приховані застосунки';

  @override
  String get launcherSections => 'Розділи';

  @override
  String get layout => 'Розташування';

  @override
  String get loading => 'Завантаження';

  @override
  String get manual => 'Вручну';

  @override
  String get modifySection => 'Змінити розділ';

  @override
  String get name => 'Назва';

  @override
  String get newSection => 'Новий розділ';

  @override
  String get nonTvApplications => 'Застосунки не для ТБ';

  @override
  String get open => 'Відкрити';

  @override
  String get picture => 'Зображення';

  @override
  String removeFrom(String name) {
    return 'Видалити з $name';
  }

  @override
  String get reorder => 'Змінити порядок';

  @override
  String get row => 'Рядок';

  @override
  String get rowHeight => 'Висота рядка';

  @override
  String get save => 'Зберегти';

  @override
  String get spacer => 'Роздільник';

  @override
  String get statusBar => 'Рядок стану';

  @override
  String get show => 'Показати';

  @override
  String get showCategoryTitles => 'Показувати назви категорій';

  @override
  String get showCategoryAppCount => 'Показувати кількість додатків у категоріях';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Приховати контур виділення на головному екрані';

  @override
  String get appSelectorTransitionAnimation => 'Анімація переходу вибору застосунку';

  @override
  String get sort => 'Сортування';

  @override
  String get systemSettings => 'Системні налаштування';

  @override
  String get textEmptyCategory => 'Ця категорія порожня.';

  @override
  String get time => 'Час';

  @override
  String get tvApplications => 'Застосунки для ТБ';

  @override
  String get type => 'Тип';

  @override
  String get uninstall => 'Видалити';

  @override
  String get wallpaper => 'Шпалери';

  @override
  String get withEllipsisAddTo => 'Додати до...';

  @override
  String get timeBasedWallpaper => 'Шпалери залежно від часу';

  @override
  String get pickDayWallpaper => 'Вибрати денні шпалери';

  @override
  String get pickNightWallpaper => 'Вибрати нічні шпалери';

  @override
  String get inputs => 'Джерела сигналу';

  @override
  String get inputSources => 'Джерела сигналу';

  @override
  String get backupAndRestore => 'Резервне копіювання та відновлення';

  @override
  String get exportBackup => 'Експортувати резервну копію';

  @override
  String get importBackup => 'Імпортувати резервну копію';

  @override
  String exportSuccess(String path) {
    return 'Резервну копію успішно експортовано до $path';
  }

  @override
  String get importSuccess => 'Резервну копію успішно імпортовано';

  @override
  String get importConfirm => 'Ви впевнені, що хочете імпортувати резервну копію? Це замінить поточні налаштування та розташування.';

  @override
  String importError(String error) {
    return 'Не вдалося імпортувати резервну копію: $error';
  }

  @override
  String exportError(String error) {
    return 'Не вдалося експортувати резервну копію: $error';
  }

  @override
  String get shareBackup => 'Поділитися резервною копією';

  @override
  String get notificationBell => 'Дзвіночок сповіщень';

  @override
  String get autoHideNotificationBell => 'Автоматично приховувати дзвіночок сповіщень';

  @override
  String get continueWatching => 'Продовжити перегляд';

  @override
  String get showContinueWatchingOnHome => 'Показувати «Продовжити перегляд» на головному екрані';

  @override
  String get permissionDeniedContinueWatching => 'Потрібен дозвіл для показу «Продовжити перегляд»';

  @override
  String get system => 'Система';

  @override
  String get accentColor => 'Акцентний колір';

  @override
  String get dataUsagePeriod => 'Період використання даних';

  @override
  String get notificationAccess => 'Доступ до сповіщень';

  @override
  String get watchNextAccess => 'Доступ до Watch Next';

  @override
  String get granted => 'Надано';

  @override
  String get permissionRequired => 'Потрібен дозвіл';

  @override
  String get systemWidePopupAlert => 'Спливне сповіщення в системі';

  @override
  String get overlayPermissionRequired => 'Потрібен дозвіл на накладання';

  @override
  String get enabled => 'Увімкнено';

  @override
  String get disabled => 'Вимкнено';

  @override
  String get showAppNamesBelowIcons => 'Показувати назви застосунків під іконками';

  @override
  String get dataUsage => 'Використання даних';

  @override
  String get networkIndicator => 'Індикатор мережі';

  @override
  String get startOnBoot => 'Запускати після завантаження (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Мова';

  @override
  String get systemDefault => 'Системна мова за замовчуванням';

  @override
  String get english => 'Англійська';

  @override
  String get spanish => 'Іспанська';

  @override
  String get ukrainian => 'Українська';

  @override
  String get chinese => 'Китайська';

  @override
  String get french => 'Французька';

  @override
  String get german => 'Німецька';

  @override
  String get japanese => 'Японська';

  @override
  String get portuguese => 'Португальська';

  @override
  String get russian => 'Російська';

  @override
  String get italian => 'Італійська';

  @override
  String get hindi => 'Гінді';

  @override
  String get korean => 'Корейська';

  @override
  String get arabic => 'Арабська';

  @override
  String get turkish => 'Турецька';

  @override
  String get hidePersistentNotifications => 'Приховати постійні сповіщення';

  @override
  String get blockedNotificationApps => 'Заблоковані додатки';

  @override
  String get blockAppNotifications => 'Блокувати сповіщення';

  @override
  String get unblockAppNotifications => 'Розблокувати сповіщення';

  @override
  String get noBlockedApps => 'Немає заблокованих додатків';

  @override
  String get persistentNotification => 'Постійне';

  @override
  String get unblockAll => 'Розблокувати все';

  @override
  String get weather => 'Погода';

  @override
  String get showWeatherWarnings => 'Показувати сповіщення про погоду та дощ';

  @override
  String get temperatureUnit => 'Одиниця температури';

  @override
  String get celsius => 'Цельсій (°C)';

  @override
  String get fahrenheit => 'Фаренгейт (°F)';

  @override
  String get notifications => 'Сповіщення';

  @override
  String get continueWatchingDescription => 'Показувати нещодавно переглянуті фільми та серіали на головному екрані';

  @override
  String get dismiss => 'Закрити';

  @override
  String get openApp => 'Відкрити';

  @override
  String get noBlockedAppsDesc => 'Усім програмам наразі дозволено показувати сповіщення';

  @override
  String get notificationsAllowed => 'Сповіщення дозволено';

  @override
  String get notificationsBlocked => 'Сповіщення заблоковано';

  @override
  String get dpadDismissHint => 'Вліво: Закрити • OK: Параметри';

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String get profilesTitle => 'Профілі';

  @override
  String get homeScreenTitle => 'Головний екран';

  @override
  String get remoteAndSearchTitle => 'Пульт і пошук';

  @override
  String get parentSettingsTitle => 'Налаштування для батьків';

  @override
  String get tvPowerTitle => 'Телевізор і живлення';

  @override
  String get setupPermissionsTitle => 'Налаштування та дозволи';

  @override
  String get updatesTitle => 'Оновлення';

  @override
  String get familyAppsTitle => 'Hearth в інших профілях';

  @override
  String get cardStyleTitle => 'Стиль карток';

  @override
  String get dockLabelsTitle => 'Док і підписи';

  @override
  String get animationsSoundTitle => 'Анімація і звук';

  @override
  String get haPanelTitle => 'Панель дашборда';

  @override
  String get lookTitle => 'Вигляд';

  @override
  String get remoteButtonsTitle => 'Кнопки пульта';

  @override
  String get profilePairingTitle => 'Зв\'язування профілів';

  @override
  String get haTvStatusTitle => 'Стан телевізора';

  @override
  String get continueWatchingAppsTitle => 'Застосунки «Продовжити перегляд»';

  @override
  String get cardSizeTitle => 'Розмір карток';

  @override
  String get maxItemsTitle => 'Максимум елементів';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Скасувати';

  @override
  String get close => 'Закрити';

  @override
  String get tryAgain => 'Повторити';

  @override
  String get notNow => 'Не зараз';

  @override
  String get done => 'Готово';

  @override
  String get remove => 'Видалити';

  @override
  String get homeNothingToWatch => 'Зараз нічого дивитися';

  @override
  String get errorScreenTitle => 'Щось пішло не так';

  @override
  String get appInfoAddToCategory => 'Додати до категорії';

  @override
  String get appInfoAddToFavorites => 'До улюблених';

  @override
  String get appInfoRemoveFromFavorites => 'Прибрати з улюблених';

  @override
  String get appInfoSetCustomBanner => 'Встановити власний банер';

  @override
  String get appInfoClearCustomBanner => 'Прибрати власний банер';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Не вдалося встановити банер: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Не вдалося прибрати банер: $error';
  }

  @override
  String get cwGridAll => 'Усі';

  @override
  String get cwRowSeeAll => 'Показати всі';

  @override
  String cwRowInProgress(int count) {
    return 'Розпочато: $count';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Залишилося $hours год $minutes хв';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Залишилося $minutes хв';
  }

  @override
  String get watchNextInfoRemove => 'Прибрати з «Продовжити перегляд»';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Приховати все з $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Дивитися / Продовжити';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Відкрити $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Інформація про застосунок';

  @override
  String get dataWidgetGrantPermission => 'Надати доступ до статистики';

  @override
  String dataWidgetDaily(String usage) {
    return 'За день: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'За тиждень: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'За місяць: $usage';
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
        'today': 'Дощ сьогодні',
        'tomorrow': 'Дощ завтра',
        'other': 'Дощ, $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Сніг сьогодні',
        'tomorrow': 'Сніг завтра',
        'other': 'Сніг, $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Гроза сьогодні',
        'tomorrow': 'Гроза завтра',
        'other': 'Гроза, $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$forecast ($percent%)';
  }

  @override
  String searchWatchOn(String apps) {
    return 'Дивитися в $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Орендувати або купити в $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Інші способи переглянути (Google TV)';

  @override
  String get searchListening => 'Слухаю…';

  @override
  String get searchHint => 'Пошук фільмів і серіалів';

  @override
  String get searchEntryHelp => 'Введіть текст, скористайтеся мікрофоном або наберіть його на телефоні в застосунку Google TV.';

  @override
  String get searchTabWatchNow => 'Дивитися зараз';

  @override
  String get searchTabRentOrBuy => 'Оренда або купівля';

  @override
  String get searchTabOtherApps => 'Інші застосунки';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Оренда або купівля · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Де переглянути: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'У $services (немає на цьому телевізорі)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результату',
      many: '$count результатів',
      few: '$count результати',
      one: '$count результат',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Тут нічого немає за запитом «$query».';
  }

  @override
  String get searchGridTmdbNotice => 'Де переглянути — за даними TMDB (через JustWatch). Цей продукт використовує API TMDB, але не схвалений і не сертифікований TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps або $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Запитати Google: «$query»';
  }

  @override
  String get searchAskGoogleDetail => 'Для запитань, погоди та всього, що не є передачею';

  @override
  String searchSearchingFor(String query) {
    return 'Пошук «$query»…';
  }

  @override
  String get searchFailed => 'Зараз не вдається виконати пошук. Перевірте підключення до інтернету.';

  @override
  String searchNothingFound(String query) {
    return 'За запитом «$query» нічого не знайдено';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Зараз у ваших застосунках немає нічого за запитом «$query»';
  }

  @override
  String get searchSeeMoreResults => 'Де ще це доступно — у розділі «Інші результати».';

  @override
  String get searchMoreResults => 'Інші результати';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count назви',
      many: '$count назв',
      few: '$count назви',
      one: '$count назва',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Запитати Google';

  @override
  String searchQuoted(String query) {
    return '«$query»';
  }

  @override
  String get searchKindFilm => 'Фільм';

  @override
  String get searchKindSeries => 'Серіал';

  @override
  String get gradientNamePitchBlack => 'Вугільно-чорний';

  @override
  String get gradientNameGreatWhale => 'Великий кит';

  @override
  String get gradientNameViciousStance => 'Грізна стійка';

  @override
  String get gradientNameTeenNotebook => 'Підлітковий блокнот';

  @override
  String get gradientNameOldHat => 'Старий капелюх';

  @override
  String get gradientNameBurningSpring => 'Палаюча весна';

  @override
  String get gradientNameDesertHump => 'Пустельний пагорб';

  @override
  String get gradientNameFarawayRiver => 'Далека річка';

  @override
  String get gradientNameSaintPetersburg => 'Санкт-Петербург';

  @override
  String get gradientNameAfricanField => 'Африканське поле';

  @override
  String get gradientNameGrassShampoo => 'Трав\'яний шампунь';

  @override
  String get updateErrorNoApk => 'У жодному випуску немає APK для цього пристрою';

  @override
  String get updateErrorCheckFailed => 'Не вдалося перевірити оновлення';

  @override
  String get updateErrorDownloadFailed => 'Не вдалося завантажити оновлення';

  @override
  String get serviceHearthTubeDescription => 'YouTube для Hearth; відповідає вашому профілю Hearth';

  @override
  String get haSummaryOn => 'Увімк.';

  @override
  String get haSummaryOff => 'Вимк.';

  @override
  String get haSummaryReporting => 'Надсилається';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Увімкніть «Виправлення кнопки Додому» ($path): воно показує спливні вікна.';
  }

  @override
  String get haNotificationsShow => 'Показувати сповіщення Home Assistant';

  @override
  String get haNotificationsSendTest => 'Надіслати тестове сповіщення';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'У Home Assistant додайте інтеграцію \"Notifications for Android TV / Fire TV\" з хостом $host. Потім надсилайте на неї сповіщення з автоматизацій, наприклад для дверного дзвінка або коли закінчилося прання.\n\nНадсилати їх можуть лише пристрої у вашій домашній мережі (порт 7676). Спливні вікна з\'являються поверх будь-якого застосунку, і для них має бути увімкнено «Виправлення кнопки Додому» ($path).';
  }

  @override
  String get haNotificationsThisTvIp => '(IP-адреса цього телевізора)';

  @override
  String get haPanelSaved => 'Збережено';

  @override
  String get haPanelSavedNoToken => 'Збережено. Додайте токен доступу, щоб увійти.';

  @override
  String get haPanelReceived => 'Адресу й токен отримано з телефона';

  @override
  String get haPanelRightEdge => 'Вправо біля правого краю відкриває панель';

  @override
  String get haSetUpFromPhone => 'Налаштувати з телефона';

  @override
  String get haPanelTokenLabel => 'Довготривалий токен доступу';

  @override
  String get haPanelTokenSavedHint => 'Збережено (введіть новий, щоб замінити)';

  @override
  String get haPanelDashboardLabel => 'Дашборд';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Увімкнено лише для цього профілю. Панель показує дашборд за адресою з розділу «$tvStatus», вхід виконується за допомогою токена. Створіть токен у Home Assistant, увійшовши як користувач без прав адміністратора, створений для цього телевізора (сторінка профілю, вкладка «Безпека»).';
  }

  @override
  String get haStatusReportingOff => 'Надсилання стану вимкнено';

  @override
  String get haStatusSaved => 'Збережено: надсилання в Home Assistant';

  @override
  String get haStatusAddressLabel => 'Адреса Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID вебхука';

  @override
  String get haStatusNowPlayingOn => 'Зараз грає: увімк.';

  @override
  String get haStatusNowPlayingOff => 'Зараз грає: увімкніть доступ до сповіщень';

  @override
  String get haStatusHelp => 'Телевізор повідомляє Home Assistant, що на екрані: застосунок, що відтворюється, профіль Google TV і екранний час дітей. Дані надсилаються лише на адресу вище й лише під час змін.';

  @override
  String get haPhoneSetupNoNetwork => 'Цей телевізор не підключено до домашньої мережі, тому телефон не може з ним зв\'язатися.';

  @override
  String get haPhoneSetupScan => 'Відскануйте телефоном у тій самій мережі Wi-Fi, вставте адресу Home Assistant і токен доступу та натисніть Send. Сторінка працює, лише поки це вікно відкрите.';

  @override
  String get profilesSwitchProfile => 'Змінити профіль';

  @override
  String get parentPinTitle => 'Батьківський PIN-код';

  @override
  String get parentPinOn => 'Увімк.';

  @override
  String get parentPinOff => 'Вимк.';

  @override
  String get parentPinCurrent => 'Поточний батьківський PIN-код';

  @override
  String get parentPinRemove => 'Видалити PIN-код';

  @override
  String get parentPinChange => 'Змінити PIN-код';

  @override
  String get parentPinNew => 'Новий батьківський PIN-код';

  @override
  String get parentPinNewSubtitle => 'Потрібен, щоб змінювати лаунчер у дитячих профілях Google TV';

  @override
  String get parentPinConfirm => 'Введіть PIN-код ще раз';

  @override
  String get parentPinAskTitle => 'Попроси батьків';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'У дитячих профілях налаштування лаунчера заблоковано. Батьки можуть задати PIN-код у своєму профілі: $settings → $profiles → $parentPin.';
  }

  @override
  String get parentPinKidsSubtitle => 'Дитячий профіль: введіть батьківський PIN-код, щоб змінити лаунчер';

  @override
  String get parentPinWrong => 'НЕПРАВИЛЬНИЙ PIN-КОД';

  @override
  String get parentPinEnter => 'ВВЕДІТЬ PIN-КОД';

  @override
  String profileSwitchGreeting(String name) {
    return 'Привіт, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Налаштовуємо цей профіль…';

  @override
  String profilesKidsName(String name) {
    return '$name (дитячий)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (дорослий)';
  }

  @override
  String get pairingShowPicker => 'Показати вибір профілю';

  @override
  String get pairingAlwaysShowPicker => 'Завжди показувати вибір профілю';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (збіг за іменем)';
  }

  @override
  String get pairingNoMatchYet => 'Збігів поки немає: показується вибір профілю';

  @override
  String get pairingOffSetUp => 'Зв\'язування профілів вимкнено. Налаштувати';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Коли Hearth відкриває один із цих застосунків, він вибирає профіль застосунку, пов\'язаний із профілем Google TV. Hearth сам зіставляє імена (\"$shortName\" відповідає \"$fullName\"); будь-який зв\'язок можна змінити тут. Якщо збігу немає, показується вибір профілю самого застосунку.';
  }

  @override
  String get pairingAppNotInstalled => 'Не встановлено';

  @override
  String get pairingAppOff => 'Вимк.: показується вибір профілю застосунку';

  @override
  String get pairingAppNotSeen => 'Відкрийте його один раз із Hearth, щоб Hearth дізнався його профілі';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Знайдено $count профілю',
      many: 'Знайдено $count профілів',
      few: 'Знайдено $count профілі',
      one: 'Знайдено $count профіль',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'За іменем ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'За іменем (збігів поки немає)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile у $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Зв\'язувати профілі в $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth ще не бачив профілів цього застосунку. Відкрийте його один раз із Hearth і поверніться.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Профілі в цьому застосунку: $profiles. Профілі Google TV з\'являться тут, коли Hearth їх побачить.';
  }

  @override
  String get familyAppsIntro => 'Установіть Hearth і HearthTube в інші профілі Google TV. У дитячих профілях це потрібно, щоб працював HearthTube і щоб Hearth вибирав правильний профіль у Netflix, Disney+ та інших застосунках. У дорослих профілях це просто зручність: не доведеться встановлювати їх вручну.';

  @override
  String get familyAppsAddTitle => 'Додати Hearth в інші профілі';

  @override
  String get familyAppsAddKids => 'Hearth і HearthTube буде встановлено в профілі ваших дітей: там запрацює HearthTube, а Hearth зможе вибирати правильний профіль у таких застосунках, як Netflix і Disney+.';

  @override
  String get familyAppsAddAdults => 'Їх також буде встановлено в інші дорослі профілі телевізора, щоб іншим дорослим не довелося налаштовувати все самим.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Додаються лише два застосунки Hearth, і це можна будь-коли скасувати кнопкою «Видалити» нижче.';

  @override
  String get familyAppsAddFamilyLink => 'Кожна дитина отримає одне сповіщення Family Link «Застосунок додано».';

  @override
  String get familyAppsAddApproval => 'Першого разу телевізор запитає «Дозволити налагодження?» — виберіть «Завжди дозволяти»: так Hearth зможе виконати налаштування.';

  @override
  String get familyAppsAdd => 'Додати';

  @override
  String get familyAppsRemoveTitle => 'Видалити Hearth з інших профілів';

  @override
  String get familyAppsRemoveBody => 'Hearth і HearthTube буде видалено з інших профілів.';

  @override
  String get familyAppsRemoveFirst => 'Якщо ви збираєтеся видалити сам Hearth, спершу виконайте це — інакше його копії в дитячих профілях можуть залишитися, і видалити їх можна буде лише з комп\'ютера.';

  @override
  String get familyAppsUninstallTitle => 'Видалити Hearth';

  @override
  String get familyAppsUninstallBody => 'Спершу Hearth і HearthTube буде видалено з інших профілів, а потім Hearth буде видалено з цього.';

  @override
  String get familyAppsUninstallWhyHere => 'Видалення тут, а не в налаштуваннях Android, гарантує, що в дитячих профілях нічого не залишиться.';

  @override
  String get familyAppsApprovalFirstTitle => 'Спершу надайте одноразовий дозвіл';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth поки не зміг очистити інші профілі: потрібно один раз підтвердити на телевізорі запит «Дозволити налагодження?».';

  @override
  String get familyAppsApprovalFirstRetry => 'Підтвердьте його й знову спробуйте видалити, щоб у дитячих профілях нічого не залишилося.';

  @override
  String get familyAppsAddDone => 'Додавання завершено';

  @override
  String get familyAppsRemoveDone => 'Видалення завершено';

  @override
  String get familyAppsAdded => 'Готово. Hearth і HearthTube тепер є в інших профілях — дивіться список нижче.';

  @override
  String get familyAppsRemoved => 'Готово. Hearth і HearthTube видалено з інших профілів.';

  @override
  String get familyAppsNothingToSetUp => 'Інших профілів для налаштування поки немає.';

  @override
  String get familyAppsFailedTitle => 'Не вдалося налаштувати профілі';

  @override
  String get familyAppsFailedBody => 'Щоб налаштувати інші профілі, Hearth потрібно один раз отримати дозвіл на телевізорі.';

  @override
  String get familyAppsFailedRetry => 'Коли телевізор запитає «Дозволити налагодження?», виберіть «Завжди дозволяти» й спробуйте ще раз.';

  @override
  String get familyAppsAlsoAdults => 'Також налаштувати інші дорослі профілі';

  @override
  String get familyAppsOn => 'Увімк.';

  @override
  String get familyAppsOff => 'Вимк.';

  @override
  String get familyAppsNoneYet => 'Інші профілі поки не налаштовано.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: встановлено';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: встановлено, захищено';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: не встановлено';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: не встановлено, захищено';
  }

  @override
  String get familyAppsUnnamedKids => 'Дитячий профіль';

  @override
  String get familyAppsUnnamedAdult => 'Дорослий профіль';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'На наступному екрані прокрутіть униз до розділу «Служби», виберіть \"$service\", потім увімкніть «Увімкнути» й підтвердьте. Натискайте «Назад», доки не повернетеся на головний екран.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Якщо Android повідомляє, що налаштування обмежене, виконайте це один раз із комп\'ютера:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth як головний екран';

  @override
  String get setupDefaultLauncherWhy => 'Не дає дитячим профілям блокувати Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'На наступному екрані виберіть Hearth.';

  @override
  String get setupHomeFixTitle => 'Виправлення кнопки Додому';

  @override
  String get setupHomeFixWhy => 'Кнопка «Додому» відкриває Hearth замість Google TV.';

  @override
  String get setupNotificationsTitle => 'Доступ до сповіщень';

  @override
  String get setupNotificationsWhy => 'Показує сповіщення й те, що зараз грає.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'На наступному екрані виберіть \"$service\" і дозвольте доступ.';
  }

  @override
  String get setupInstallTitle => 'Встановлення оновлень';

  @override
  String get setupInstallWhy => 'Дає змогу Hearth оновлюватися й установлювати супутні застосунки.';

  @override
  String get setupInstallInstructions => 'На наступному екрані увімкніть Hearth.';

  @override
  String get setupPairingWhy => 'Вибирає ваш профіль у Netflix, Disney+, Apple TV, HBO Max і Paramount+.';

  @override
  String get setupVoiceTitle => 'Голос Hearth';

  @override
  String get setupVoiceWhy => 'Дає змогу зв\'язуванню профілів «чути» екран профілів Netflix. Інші застосунки зберігають голос Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'На наступному екрані в розділі «Пріоритетний синтезатор» виберіть \"$engine\", потім натисніть «OK» у попередженні (Hearth слухає лише стримінгові застосунки). Натисніть «Назад», щоб повернутися.';
  }

  @override
  String get setupOpenSettings => 'Відкрити налаштування';

  @override
  String get setupAdbFallback => 'Телевізор не відкрив цей екран налаштувань. Натомість виконайте один раз із комп\'ютера:';

  @override
  String setupProgress(int done, int total) {
    return 'Виконано: $done з $total';
  }

  @override
  String get setupOptional => 'Необов\'язково';

  @override
  String get homeButtonFixOffTitle => '«Виправлення кнопки Додому» вимкнено';

  @override
  String get homeButtonFixOffBody => 'Службу спеціальних можливостей Hearth зупинено — зазвичай це стається після оновлення. Доки її знову не ввімкнено, кнопка «Додому» може відкривати Google TV замість Hearth, а зміна профілю не відстежується.';

  @override
  String get homeButtonFixStuck => 'Android досі показує її як увімкнену, але вона не працює. Вимкніть і знову ввімкніть Hearth у налаштуваннях спеціальних можливостей, щоб перезапустити її.';

  @override
  String get homeButtonFixRestricted => 'Якщо перемикач Hearth там неактивний (сірий), Android блокує його, бо це оновлення встановлено із завантаженого файлу. Виконайте це на комп\'ютері, підключеному до телевізора, а потім увімкніть Hearth:';

  @override
  String get homeButtonFixDontRemind => 'Не нагадувати';

  @override
  String get homeButtonFixOpenSettings => 'Відкрити спеціальні можливості';
}
