import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get aboutFlauncher => 'О программе Hearth';

  @override
  String get addSection => 'Добавить раздел';

  @override
  String get alphabetical => 'По алфавиту';

  @override
  String get appCardHighlightAnimation => 'Анимация выделения карточки приложения';

  @override
  String get appInfo => 'Информация о приложении';

  @override
  String get appKeyClick => 'Звук нажатия клавиши';

  @override
  String get applications => 'Приложения';

  @override
  String get autoHideAppBar => 'Автоскрытие строки состояния';

  @override
  String get backButtonAction => 'Действие кнопки назад';

  @override
  String get category => 'Категория';

  @override
  String get columnCount => 'Количество столбцов';

  @override
  String get date => 'Дата';

  @override
  String get dateAndTimeFormat => 'Формат даты и времени';

  @override
  String get delete => 'Удалить';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Ничего не делать';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Показать заставку';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Показать часы';

  @override
  String get dialogTextNoFileExplorer => 'Пожалуйста, установите файловый менеджер, чтобы выбрать изображение.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Категория)';
  }

  @override
  String get gradient => 'Градиент';

  @override
  String get favoriteApps => 'Избранные приложения';

  @override
  String get grid => 'Сетка';

  @override
  String get height => 'Высота';

  @override
  String get hide => 'Скрыть';

  @override
  String get hiddenApplications => 'Скрытые приложения';

  @override
  String get launcherSections => 'Разделы';

  @override
  String get layout => 'Макет';

  @override
  String get loading => 'Загрузка';

  @override
  String get manual => 'Вручную';

  @override
  String get modifySection => 'Изменить раздел';

  @override
  String get name => 'Имя';

  @override
  String get newSection => 'Новый раздел';

  @override
  String get nonTvApplications => 'Приложения не для ТВ';

  @override
  String get open => 'Открыть';

  @override
  String get picture => 'Изображение';

  @override
  String removeFrom(String name) {
    return 'Удалить из $name';
  }

  @override
  String get reorder => 'Изменить порядок';

  @override
  String get row => 'Строка';

  @override
  String get rowHeight => 'Высота строки';

  @override
  String get save => 'Сохранить';

  @override
  String get spacer => 'Разделитель';

  @override
  String get statusBar => 'Строка состояния';

  @override
  String get show => 'Показать';

  @override
  String get showCategoryTitles => 'Показывать заголовки категорий';

  @override
  String get showCategoryAppCount => 'Показывать количество приложений в категориях';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Скрыть контур выделения на главном экране';

  @override
  String get appSelectorTransitionAnimation => 'Анимация перехода селектора приложений';

  @override
  String get sort => 'Сортировать';

  @override
  String get systemSettings => 'Системные настройки';

  @override
  String get textEmptyCategory => 'Эта категория пуста.';

  @override
  String get time => 'Время';

  @override
  String get tvApplications => 'ТВ-приложения';

  @override
  String get type => 'Тип';

  @override
  String get uninstall => 'Удалить';

  @override
  String get wallpaper => 'Обои';

  @override
  String get withEllipsisAddTo => 'Добавить в...';

  @override
  String get timeBasedWallpaper => 'Обои в зависимости от времени';

  @override
  String get pickDayWallpaper => 'Выбрать дневные обои';

  @override
  String get pickNightWallpaper => 'Выбрать ночные обои';

  @override
  String get inputs => 'Входы';

  @override
  String get inputSources => 'Источники ввода';

  @override
  String get backupAndRestore => 'Резервное копирование и восстановление';

  @override
  String get exportBackup => 'Экспорт резервной копии';

  @override
  String get importBackup => 'Импорт резервной копии';

  @override
  String exportSuccess(String path) {
    return 'Резервная копия успешно экспортирована в $path';
  }

  @override
  String get importSuccess => 'Резервная копия успешно импортирована';

  @override
  String get importConfirm => 'Вы уверены, что хотите импортировать резервную копию? Это перезапишет ваши текущие настройки и макет.';

  @override
  String importError(String error) {
    return 'Не удалось импортировать резервную копию: $error';
  }

  @override
  String exportError(String error) {
    return 'Не удалось экспортировать резервную копию: $error';
  }

  @override
  String get shareBackup => 'Поделиться резервной копией';

  @override
  String get notificationBell => 'Колокольчик уведомлений';

  @override
  String get autoHideNotificationBell => 'Автоскрытие колокольчика уведомлений';

  @override
  String get continueWatching => 'Продолжить просмотр';

  @override
  String get showContinueWatchingOnHome => 'Показывать «Продолжить просмотр» на главном экране';

  @override
  String get permissionDeniedContinueWatching => 'Требуется разрешение для показа «Продолжить просмотр»';

  @override
  String get system => 'Система';

  @override
  String get accentColor => 'Акцентный цвет';

  @override
  String get dataUsagePeriod => 'Период использования данных';

  @override
  String get notificationAccess => 'Доступ к уведомлениям';

  @override
  String get watchNextAccess => 'Доступ к Watch Next';

  @override
  String get granted => 'Предоставлено';

  @override
  String get permissionRequired => 'Требуется разрешение';

  @override
  String get systemWidePopupAlert => 'Системное всплывающее предупреждение';

  @override
  String get overlayPermissionRequired => 'Требуется разрешение на наложение';

  @override
  String get enabled => 'Включено';

  @override
  String get disabled => 'Отключено';

  @override
  String get showAppNamesBelowIcons => 'Показывать названия приложений под значками';

  @override
  String get dataUsage => 'Использование данных';

  @override
  String get networkIndicator => 'Индикатор сети';

  @override
  String get startOnBoot => 'Запускать при включении (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Язык';

  @override
  String get systemDefault => 'Системный по умолчанию';

  @override
  String get english => 'Английский';

  @override
  String get spanish => 'Испанский';

  @override
  String get ukrainian => 'Украинский';

  @override
  String get chinese => 'Китайский';

  @override
  String get french => 'Французский';

  @override
  String get german => 'Немецкий';

  @override
  String get japanese => 'Японский';

  @override
  String get portuguese => 'Португальский';

  @override
  String get russian => 'Русский';

  @override
  String get italian => 'Итальянский';

  @override
  String get hindi => 'Хинди';

  @override
  String get korean => 'Корейский';

  @override
  String get arabic => 'Арабский';

  @override
  String get turkish => 'Турецкий';

  @override
  String get hidePersistentNotifications => 'Скрыть постоянные уведомления';

  @override
  String get blockedNotificationApps => 'Заблокированные приложения';

  @override
  String get blockAppNotifications => 'Блокировать уведомления';

  @override
  String get unblockAppNotifications => 'Разблокировать уведомления';

  @override
  String get noBlockedApps => 'Нет заблокированных приложений';

  @override
  String get persistentNotification => 'Постоянное';

  @override
  String get unblockAll => 'Разблокировать все';

  @override
  String get weather => 'Погода';

  @override
  String get showWeatherWarnings => 'Показывать предупреждения о погоде и дожде';

  @override
  String get temperatureUnit => 'Единица температуры';

  @override
  String get celsius => 'Цельсий (°C)';

  @override
  String get fahrenheit => 'Фаренгейт (°F)';

  @override
  String get notifications => 'Уведомления';

  @override
  String get continueWatchingDescription => 'Показывать недавно просмотренные фильмы и передачи на главном экране';

  @override
  String get dismiss => 'Закрыть';

  @override
  String get openApp => 'Открыть';

  @override
  String get noBlockedAppsDesc => 'Всем приложениям в данный момент разрешено показывать уведомления';

  @override
  String get notificationsAllowed => 'Уведомления разрешены';

  @override
  String get notificationsBlocked => 'Уведомления заблокированы';

  @override
  String get dpadDismissHint => 'Влево: Закрыть • OK: Параметры';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get profilesTitle => 'Профили';

  @override
  String get homeScreenTitle => 'Главный экран';

  @override
  String get remoteAndSearchTitle => 'Пульт и поиск';

  @override
  String get parentSettingsTitle => 'Настройки для родителей';

  @override
  String get tvPowerTitle => 'Телевизор и питание';

  @override
  String get setupPermissionsTitle => 'Настройка и разрешения';

  @override
  String get updatesTitle => 'Обновления';

  @override
  String get familyAppsTitle => 'Hearth в других профилях';

  @override
  String get cardStyleTitle => 'Стиль карточек';

  @override
  String get dockLabelsTitle => 'Док и подписи';

  @override
  String get animationsSoundTitle => 'Анимация и звук';

  @override
  String get haPanelTitle => 'Панель дашборда';

  @override
  String get lookTitle => 'Внешний вид';

  @override
  String get remoteButtonsTitle => 'Кнопки пульта';

  @override
  String get profilePairingTitle => 'Связывание профилей';

  @override
  String get haTvStatusTitle => 'Состояние телевизора';

  @override
  String get continueWatchingAppsTitle => 'Приложения «Продолжить просмотр»';

  @override
  String get cardSizeTitle => 'Размер карточек';

  @override
  String get maxItemsTitle => 'Максимум элементов';

  @override
  String get ok => 'ОК';

  @override
  String get cancel => 'Отмена';

  @override
  String get close => 'Закрыть';

  @override
  String get tryAgain => 'Повторить';

  @override
  String get notNow => 'Не сейчас';

  @override
  String get done => 'Готово';

  @override
  String get remove => 'Удалить';

  @override
  String get homeNothingToWatch => 'Сейчас нечего смотреть';

  @override
  String get errorScreenTitle => 'Что-то пошло не так';

  @override
  String get appInfoAddToCategory => 'Добавить в категорию';

  @override
  String get appInfoAddToFavorites => 'В избранное';

  @override
  String get appInfoRemoveFromFavorites => 'Убрать из избранного';

  @override
  String get appInfoSetCustomBanner => 'Задать свой баннер';

  @override
  String get appInfoClearCustomBanner => 'Убрать свой баннер';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Не удалось задать баннер: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Не удалось убрать баннер: $error';
  }

  @override
  String get cwGridAll => 'Все';

  @override
  String get cwRowSeeAll => 'Показать все';

  @override
  String cwRowInProgress(int count) {
    return 'Начато: $count';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Осталось $hours ч $minutes мин';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Осталось $minutes мин';
  }

  @override
  String get watchNextInfoRemove => 'Убрать из «Продолжить просмотр»';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Скрыть всё из $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Смотреть / Продолжить';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Открыть $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Информация о приложении';

  @override
  String get dataWidgetGrantPermission => 'Разрешить доступ к статистике';

  @override
  String dataWidgetDaily(String usage) {
    return 'За день: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'За неделю: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'За месяц: $usage';
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
        'today': 'Дождь сегодня',
        'tomorrow': 'Дождь завтра',
        'other': 'Дождь, $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Снег сегодня',
        'tomorrow': 'Снег завтра',
        'other': 'Снег, $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Гроза сегодня',
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
}
