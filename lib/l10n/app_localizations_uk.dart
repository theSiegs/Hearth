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
}
