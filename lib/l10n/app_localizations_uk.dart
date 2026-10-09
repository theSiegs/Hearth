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
}
