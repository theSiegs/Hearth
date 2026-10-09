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
  String get systemSettings => 'Настройки Google TV';

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
  String get remoteAndSearchTitle => 'Пульт';

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

  @override
  String searchWatchOn(String apps) {
    return 'Смотреть в $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Взять напрокат или купить в $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Другие способы посмотреть (Google TV)';

  @override
  String get searchListening => 'Слушаю…';

  @override
  String get searchHint => 'Поиск фильмов и сериалов';

  @override
  String get searchEntryHelp => 'Введите текст, скажите в микрофон или наберите его на телефоне в приложении Google TV.';

  @override
  String get searchTabWatchNow => 'Смотреть сейчас';

  @override
  String get searchTabRentOrBuy => 'Прокат или покупка';

  @override
  String get searchTabOtherApps => 'Другие приложения';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Прокат или покупка · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Где посмотреть: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'В $services (нет на этом телевизоре)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результата',
      many: '$count результатов',
      few: '$count результата',
      one: '$count результат',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Здесь ничего нет по запросу «$query».';
  }

  @override
  String get searchGridTmdbNotice => 'Где посмотреть — по данным TMDB (через JustWatch). Этот продукт использует API TMDB, но не одобрен и не сертифицирован TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps или $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Спросить Google: «$query»';
  }

  @override
  String get searchAskGoogleDetail => 'Для вопросов, погоды и всего, что не является передачей';

  @override
  String searchSearchingFor(String query) {
    return 'Поиск «$query»…';
  }

  @override
  String get searchFailed => 'Сейчас не удаётся выполнить поиск. Проверьте подключение к интернету.';

  @override
  String searchNothingFound(String query) {
    return 'По запросу «$query» ничего не найдено';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Сейчас в ваших приложениях нет ничего по запросу «$query»';
  }

  @override
  String get searchSeeMoreResults => 'Где ещё это доступно — в разделе «Другие результаты».';

  @override
  String get searchMoreResults => 'Другие результаты';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count названия',
      many: '$count названий',
      few: '$count названия',
      one: '$count название',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Спросить Google';

  @override
  String searchQuoted(String query) {
    return '«$query»';
  }

  @override
  String get searchKindFilm => 'Фильм';

  @override
  String get searchKindSeries => 'Сериал';

  @override
  String get gradientNamePitchBlack => 'Угольно-чёрный';

  @override
  String get gradientNameGreatWhale => 'Большой кит';

  @override
  String get gradientNameViciousStance => 'Грозная стойка';

  @override
  String get gradientNameTeenNotebook => 'Подростковый блокнот';

  @override
  String get gradientNameOldHat => 'Старая шляпа';

  @override
  String get gradientNameBurningSpring => 'Пылающая весна';

  @override
  String get gradientNameDesertHump => 'Пустынный холм';

  @override
  String get gradientNameFarawayRiver => 'Далёкая река';

  @override
  String get gradientNameSaintPetersburg => 'Санкт-Петербург';

  @override
  String get gradientNameAfricanField => 'Африканское поле';

  @override
  String get gradientNameGrassShampoo => 'Травяной шампунь';

  @override
  String get updateErrorNoApk => 'Ни в одном выпуске нет APK для этого устройства';

  @override
  String get updateErrorCheckFailed => 'Не удалось проверить обновления';

  @override
  String get updateErrorDownloadFailed => 'Не удалось загрузить обновление';

  @override
  String get serviceHearthTubeDescription => 'YouTube для Hearth; следует вашему профилю Hearth';

  @override
  String get haSummaryOn => 'Вкл.';

  @override
  String get haSummaryOff => 'Выкл.';

  @override
  String get haSummaryReporting => 'Отправляется';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Включите «Исправление кнопки Домой» ($path): оно показывает всплывающие окна.';
  }

  @override
  String get haNotificationsShow => 'Показывать уведомления Home Assistant';

  @override
  String get haNotificationsSendTest => 'Отправить тестовое уведомление';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'В Home Assistant добавьте интеграцию \"Notifications for Android TV / Fire TV\" с хостом $host. Затем отправляйте на неё уведомления из автоматизаций, например для дверного звонка или когда закончилась стирка.\n\nОтправлять их могут только устройства в вашей домашней сети (порт 7676). Всплывающие окна появляются поверх любого приложения, и для них должно быть включено «Исправление кнопки Домой» ($path).';
  }

  @override
  String get haNotificationsThisTvIp => '(IP-адрес этого телевизора)';

  @override
  String get haPanelSaved => 'Сохранено';

  @override
  String get haPanelSavedNoToken => 'Сохранено. Добавьте токен доступа, чтобы войти.';

  @override
  String get haPanelReceived => 'Адрес и токен получены с телефона';

  @override
  String get haPanelRightEdge => 'Вправо у правого края открывает панель';

  @override
  String get haSetUpFromPhone => 'Настроить с телефона';

  @override
  String get haPanelTokenLabel => 'Долгосрочный токен доступа';

  @override
  String get haPanelTokenSavedHint => 'Сохранён (введите новый, чтобы заменить)';

  @override
  String get haPanelDashboardLabel => 'Дашборд';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Включено только для этого профиля. Панель показывает дашборд по адресу из раздела «$tvStatus», вход выполняется с помощью токена. Создайте токен в Home Assistant, войдя как пользователь без прав администратора, созданный для этого телевизора (страница профиля, вкладка «Безопасность»).';
  }

  @override
  String get haStatusReportingOff => 'Отправка состояния выключена';

  @override
  String get haStatusSaved => 'Сохранено: отправка в Home Assistant';

  @override
  String get haStatusAddressLabel => 'Адрес Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID вебхука';

  @override
  String get haStatusNowPlayingOn => 'Сейчас играет: вкл.';

  @override
  String get haStatusNowPlayingOff => 'Сейчас играет: включите доступ к уведомлениям';

  @override
  String get haStatusHelp => 'Телевизор сообщает Home Assistant, что на экране: приложение, что воспроизводится, профиль Google TV и экранное время детей. Данные отправляются только на адрес выше и только при изменениях.';

  @override
  String get haPhoneSetupNoNetwork => 'Этот телевизор не подключён к домашней сети, поэтому телефон не может с ним связаться.';

  @override
  String get haPhoneSetupScan => 'Отсканируйте телефоном, подключённым к той же сети Wi-Fi, вставьте адрес Home Assistant и токен доступа и нажмите Send. Страница работает, только пока это окно открыто.';

  @override
  String get profilesSwitchProfile => 'Сменить профиль';

  @override
  String get parentPinTitle => 'Родительский PIN-код';

  @override
  String get parentPinOn => 'Вкл.';

  @override
  String get parentPinOff => 'Выкл.';

  @override
  String get parentPinCurrent => 'Текущий родительский PIN-код';

  @override
  String get parentPinRemove => 'Удалить PIN-код';

  @override
  String get parentPinChange => 'Изменить PIN-код';

  @override
  String get parentPinNew => 'Новый родительский PIN-код';

  @override
  String get parentPinNewSubtitle => 'Нужен, чтобы менять лаунчер в детских профилях Google TV';

  @override
  String get parentPinConfirm => 'Введите PIN-код ещё раз';

  @override
  String get parentPinAskTitle => 'Попроси родителей';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'В детских профилях настройки лаунчера заблокированы. Родитель может задать PIN-код в своём профиле: $settings → $profiles → $parentPin.';
  }

  @override
  String get parentPinKidsSubtitle => 'Детский профиль: введите родительский PIN-код, чтобы изменить лаунчер';

  @override
  String get parentPinWrong => 'НЕВЕРНЫЙ PIN-КОД';

  @override
  String get parentPinEnter => 'ВВЕДИТЕ PIN-КОД';

  @override
  String profileSwitchGreeting(String name) {
    return 'Привет, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Настраиваем этот профиль…';

  @override
  String profilesKidsName(String name) {
    return '$name (детский)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (взрослый)';
  }

  @override
  String get pairingShowPicker => 'Показать выбор профиля';

  @override
  String get pairingAlwaysShowPicker => 'Всегда показывать выбор профиля';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (совпадение по имени)';
  }

  @override
  String get pairingNoMatchYet => 'Совпадений пока нет: показывается выбор профиля';

  @override
  String get pairingOffSetUp => 'Связывание профилей выключено. Настроить';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Когда Hearth открывает одно из этих приложений, он выбирает профиль приложения, связанный с профилем Google TV. Hearth сам сопоставляет имена (\"$shortName\" соответствует \"$fullName\"); любую связь можно изменить здесь. Если совпадения нет, показывается выбор профиля самого приложения.';
  }

  @override
  String get pairingAppNotInstalled => 'Не установлено';

  @override
  String get pairingAppOff => 'Выкл.: показывается выбор профиля приложения';

  @override
  String get pairingAppNotSeen => 'Откройте его один раз из Hearth, чтобы Hearth узнал его профили';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Найдено $count профиля',
      many: 'Найдено $count профилей',
      few: 'Найдено $count профиля',
      one: 'Найден $count профиль',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'По имени ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'По имени (совпадений пока нет)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile в $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Связывать профили в $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth ещё не видел профили этого приложения. Откройте его один раз из Hearth и вернитесь.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Профили в этом приложении: $profiles. Профили Google TV появятся здесь, когда Hearth их увидит.';
  }

  @override
  String get familyAppsAddTitle => 'Добавить Hearth в другие профили';

  @override
  String get familyAppsAddKids => 'Hearth и HearthTube будут установлены в профили ваших детей: там заработает HearthTube, а Hearth сможет выбирать нужный профиль в стриминговых сервисах.';

  @override
  String get familyAppsAddAdults => 'Они также будут установлены в другие взрослые профили телевизора, чтобы другим взрослым не пришлось настраивать всё самим.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Добавляются только два приложения Hearth, и это можно в любой момент отменить кнопкой «Удалить» ниже.';

  @override
  String get familyAppsAddFamilyLink => 'Каждый ребёнок получит одно уведомление Family Link «Приложение добавлено».';

  @override
  String get familyAppsAddApproval => 'В первый раз телевизор спросит «Разрешить отладку?» — выберите «Всегда разрешать»: так Hearth сможет выполнить настройку.';

  @override
  String get familyAppsAdd => 'Добавить';

  @override
  String get familyAppsRemoveTitle => 'Удалить Hearth из других профилей';

  @override
  String get familyAppsRemoveBody => 'Hearth и HearthTube будут удалены из других профилей.';

  @override
  String get familyAppsRemoveFirst => 'Если вы собираетесь удалить сам Hearth, сначала выполните это — иначе его копии в детских профилях могут остаться, и удалить их можно будет только с компьютера.';

  @override
  String get familyAppsUninstallTitle => 'Удалить Hearth';

  @override
  String get familyAppsUninstallBody => 'Сначала Hearth и HearthTube будут удалены из других профилей, затем Hearth будет удалён из этого.';

  @override
  String get familyAppsUninstallWhyHere => 'Удаление здесь, а не в настройках Android, гарантирует, что в детских профилях ничего не останется.';

  @override
  String get familyAppsApprovalFirstTitle => 'Сначала дайте одноразовое разрешение';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth пока не смог очистить другие профили: нужно один раз подтвердить на телевизоре запрос «Разрешить отладку?».';

  @override
  String get familyAppsApprovalFirstRetry => 'Подтвердите его и снова попробуйте удалить, чтобы в детских профилях ничего не осталось.';

  @override
  String get familyAppsAddDone => 'Добавление завершено';

  @override
  String get familyAppsRemoveDone => 'Удаление завершено';

  @override
  String get familyAppsAdded => 'Готово. Hearth и HearthTube теперь есть в других профилях — см. список ниже.';

  @override
  String get familyAppsRemoved => 'Готово. Hearth и HearthTube удалены из других профилей.';

  @override
  String get familyAppsNothingToSetUp => 'Других профилей для настройки пока нет.';

  @override
  String get familyAppsFailedTitle => 'Не удалось настроить профили';

  @override
  String get familyAppsFailedBody => 'Чтобы настроить другие профили, Hearth нужно один раз получить разрешение на телевизоре.';

  @override
  String get familyAppsFailedRetry => 'Когда телевизор спросит «Разрешить отладку?», выберите «Всегда разрешать» и попробуйте ещё раз.';

  @override
  String get familyAppsAlsoAdults => 'Также настроить другие взрослые профили';

  @override
  String get familyAppsOn => 'Вкл.';

  @override
  String get familyAppsOff => 'Выкл.';

  @override
  String get familyAppsNoneYet => 'Другие профили пока не настроены.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: установлено';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: установлено, защищено';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: не установлено';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: не установлено, защищено';
  }

  @override
  String get familyAppsUnnamedKids => 'Детский профиль';

  @override
  String get familyAppsUnnamedAdult => 'Взрослый профиль';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'На следующем экране прокрутите вниз до раздела «Службы», выберите \"$service\", затем включите «Включить» и подтвердите. Нажимайте «Назад», пока не вернётесь на главный экран.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Если Android сообщает, что настройка ограничена, выполните это один раз с компьютера:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth как главный экран';

  @override
  String get setupDefaultLauncherWhy => 'Не даёт детским профилям блокировать Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'На следующем экране выберите Hearth.';

  @override
  String get setupHomeFixTitle => 'Исправление кнопки Домой';

  @override
  String get setupHomeFixWhy => 'Кнопка «Домой» открывает Hearth вместо Google TV.';

  @override
  String get setupNotificationsTitle => 'Доступ к уведомлениям';

  @override
  String get setupNotificationsWhy => 'Показывает уведомления и то, что сейчас играет.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'На следующем экране выберите \"$service\" и разрешите доступ.';
  }

  @override
  String get setupInstallTitle => 'Установка обновлений';

  @override
  String get setupInstallWhy => 'Позволяет Hearth обновляться и устанавливать сопутствующие приложения.';

  @override
  String get setupInstallInstructions => 'На следующем экране включите Hearth.';

  @override
  String get setupPairingWhy => 'Выбирает ваш профиль в Netflix, Disney+, Apple TV, HBO Max и Paramount+.';

  @override
  String get setupVoiceTitle => 'Голос Hearth';

  @override
  String get setupVoiceWhy => 'Позволяет связыванию профилей «слышать» экран профилей Netflix. Остальные приложения сохраняют голос Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'На следующем экране в разделе «Предпочитаемый синтезатор» выберите \"$engine\", затем нажмите «ОК» в предупреждении (Hearth слушает только стриминговые приложения). Нажмите «Назад», чтобы вернуться.';
  }

  @override
  String get setupOpenSettings => 'Открыть настройки';

  @override
  String get setupAdbFallback => 'Телевизор не открыл этот экран настроек. Вместо этого выполните один раз с компьютера:';

  @override
  String setupProgress(int done, int total) {
    return 'Выполнено: $done из $total';
  }

  @override
  String get setupOptional => 'Необязательно';

  @override
  String get homeButtonFixOffTitle => '«Исправление кнопки Домой» выключено';

  @override
  String get homeButtonFixOffBody => 'Служба специальных возможностей Hearth остановилась — обычно это происходит после обновления. Пока она снова не включена, кнопка «Домой» может открывать Google TV вместо Hearth, а смена профиля не отслеживается.';

  @override
  String get homeButtonFixStuck => 'Android всё ещё показывает её как включённую, но она не работает. Выключите и снова включите Hearth в настройках специальных возможностей, чтобы перезапустить её.';

  @override
  String get homeButtonFixRestricted => 'Если переключатель Hearth там неактивен (серый), Android блокирует его, потому что это обновление установлено из загруженного файла. Выполните это на компьютере, подключённом к телевизору, а затем включите Hearth:';

  @override
  String get homeButtonFixDontRemind => 'Не напоминать';

  @override
  String get homeButtonFixOpenSettings => 'Открыть специальные возможности';

  @override
  String get remoteButtonsRemapButton => 'Переназначить кнопку';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Кнопка $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Как обычно';

  @override
  String get remoteButtonsCaptureTitle => 'Нажмите кнопку на пульте';

  @override
  String get remoteButtonsCaptureBody => 'Нажмите кнопку, которую хотите переназначить. Для отмены нажмите «Назад».';

  @override
  String get remoteButtonsNeedsFixTitle => 'Сначала включите «Исправление кнопки Домой»';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Для переназначения нужно «Исправление кнопки Домой» ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Эту кнопку нельзя переназначить';

  @override
  String get remoteButtonsCantRemapBody => 'Стрелки, OK, «Назад», «Домой» и кнопка питания работают как обычно.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Нажатие: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Удержание: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Нажатие — поиск Hearth, удержание — Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Только на главном экране Hearth: вкл.';

  @override
  String get remoteButtonsHomeOnlyOff => 'Только на главном экране Hearth: выкл.';

  @override
  String get remoteButtonsRestore => 'Вернуть обычную кнопку';

  @override
  String get remoteButtonsActionTitle => 'Действие';

  @override
  String get remoteButtonsActionApp => 'Открыть приложение…';

  @override
  String get remoteButtonsActionInput => 'Переключить вход телевизора…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Сменить профиль (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Поиск Hearth (голос)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Поиск Hearth (клавиатура)';

  @override
  String get remoteButtonsActionHome => 'Главный экран Hearth';

  @override
  String get remoteButtonsActionSleep => 'Спящий режим';

  @override
  String get remoteButtonsActionAndroidSettings => 'Настройки Android';

  @override
  String get remoteButtonsPickAppTitle => 'Открыть приложение';

  @override
  String get remoteButtonsPickInputTitle => 'Переключить вход телевизора';

  @override
  String get remoteButtonsHaConnectTitle => 'Сначала подключите Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Настройте панель Home Assistant ($panel > $row) и попробуйте ещё раз.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Сцена: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Запуск: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Нажать: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Переключить: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nНажатие: $press  ·  Удержание: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nНажатие: $press  ·  Удержание: $hold  ·  Только на главном экране';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Требуется «Исправление кнопки Домой» ($path). Кнопка, у которой задано только действие при удержании, выполняет его и при обычном нажатии. Пока HearthTube на экране, поиск Hearth открывает собственный поиск HearthTube. Переназначения приостанавливаются, пока показан экран экранного времени для детей.';
  }

  @override
  String get tvPowerScreensaver => 'Заставка (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth использует заставку Google TV. Выберите там Google Photos (и нужные альбомы) или другой источник.';

  @override
  String get tvPowerSleepWhenIdle => 'Спящий режим при бездействии';

  @override
  String get tvPowerSleepOff => 'Выкл.';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours часа',
      many: '$hours часов',
      few: '$hours часа',
      one: '$hours час',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'Воспроизведение видео или музыки считается активностью. Требуется «Исправление кнопки Домой» ($path).';
  }

  @override
  String get accentPurple => 'Фиолетовый';

  @override
  String get accentTeal => 'Бирюзовый';

  @override
  String get accentBlue => 'Синий';

  @override
  String get accentOrange => 'Оранжевый';

  @override
  String get accentPink => 'Розовый';

  @override
  String get accentGreen => 'Зелёный';

  @override
  String get accentWhite => 'Белый';

  @override
  String get accentYellow => 'Жёлтый';

  @override
  String get accentRed => 'Красный';

  @override
  String get accentCyan => 'Голубой';

  @override
  String get accentIndigo => 'Индиго';

  @override
  String get accentLime => 'Лаймовый';

  @override
  String get accentAmber => 'Янтарный';

  @override
  String get accentRose => 'Светло-розовый';

  @override
  String get accentIceBlue => 'Ледяной голубой';

  @override
  String get accentSelected => 'Выбранный акцентный цвет';

  @override
  String get cardStyleDefault => 'По умолчанию';

  @override
  String get cardStylePremium => 'Премиум';

  @override
  String get cardStyleGlow => 'Свечение';

  @override
  String get cardStyleSquircle => 'Сквиркл';

  @override
  String get cardStyleClassic => 'Классический';

  @override
  String get cardStyleMinimal => 'Минимальный';

  @override
  String get cardStyleCapsule => 'Капсула';

  @override
  String get dockFavoritesDock => 'Док избранного';

  @override
  String get dockFavoritesDockDescription => 'Показывает избранное панелью внизу главного экрана: над ней «Продолжить просмотр», под ней остальные разделы. Углы следуют стилю карточек.';

  @override
  String get dockFrosted => 'Матовый док';

  @override
  String get dockDark => 'Тёмный док';

  @override
  String get dockShadow => 'Тень дока';

  @override
  String get dockBlurWallpaperBelow => 'Размывать обои под доком';

  @override
  String get wallpaperMatchSelectedApp => 'Подстраивать под выбранное приложение';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Фото дня Bing';

  @override
  String get wallpaperRefreshNow => 'Обновить сейчас';

  @override
  String get wallpaperBingError => 'Не удалось подключиться к Bing. Проверьте подключение к сети.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Единица температуры: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Место для погоды: не задано';

  @override
  String weatherLocationValue(String place) {
    return 'Место для погоды: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Не удалось загрузить погоду. Повторная попытка будет выполнена автоматически.';

  @override
  String get statusBarWeatherSourceHint => 'Выберите место для погоды выше (погода от Open-Meteo, бесплатно, без аккаунта). Без него погода берётся из приложения Breezy Weather, если оно установлено и в нём включён обмен через Gadgetbridge.';

  @override
  String get weatherLocationTitle => 'Место для погоды';

  @override
  String get weatherLocationHint => 'Город или посёлок';

  @override
  String get weatherLocationNoResults => 'Места не найдены';

  @override
  String get weatherLocationSearchError => 'Не удалось подключиться к сервису погоды. Проверьте подключение к сети.';

  @override
  String get weatherLocationPrivacyNote => 'Погода от Open-Meteo.com: бесплатно, без аккаунта. Отправляются только координаты выбранного места.';

  @override
  String get weatherLocationSearch => 'Найти';

  @override
  String get dateTimeInvalidFormat => 'Неверный формат';

  @override
  String get dateTimeSelectFormats => 'Выберите форматы ниже';

  @override
  String get dataUsageDaily => 'За день';

  @override
  String get dataUsageWeekly => 'За неделю';

  @override
  String get dataUsageMonthly => 'За месяц';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Заблокированы в «Продолжить просмотр» ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Заблокировано в «Продолжить просмотр»';

  @override
  String get cwAppsUnblock => 'Разблокировать';

  @override
  String get cwAppsUnblockAllApps => 'Разблокировать все приложения';

  @override
  String get cwAppsNoBlockedApps => 'Нет заблокированных приложений';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Все поддерживаемые приложения могут показывать элементы в «Продолжить просмотр».';

  @override
  String get cwAppsWithContinueWatching => 'Приложения с «Продолжить просмотр»';

  @override
  String get cwAppsWithContinueWatchingHint => 'Приложения, которые сейчас передают элементы Watch Next на главный экран';

  @override
  String get cwAppsNoActiveApps => 'Сейчас ни одно приложение не передаёт элементы «Продолжить просмотр».\nКогда поддерживаемые приложения (например, SmartTube или стриминговые сервисы) добавят элементы, они появятся здесь.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count активного элемента',
      many: '$count активных элементов',
      few: '$count активных элемента',
      one: '$count активный элемент',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Все установленные приложения';

  @override
  String get cwAppsAllInstalledAppsHint => 'Выключите, чтобы запретить приложению добавлять элементы в «Продолжить просмотр»';

  @override
  String get cwAppsBlocked => 'Заблокировано';

  @override
  String get cwAppsAllowed => 'Разрешено';

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
  String get cwCardSizeExtraSmall => 'Крошечный';

  @override
  String get cwCardSizeVerySmall => 'Очень маленький';

  @override
  String get cwCardSizeSmall => 'Маленький';

  @override
  String get cwCardSizeCompact => 'Компактный';

  @override
  String get cwCardSizeMediumSmall => 'Ниже среднего';

  @override
  String get cwCardSizeMedium => 'Средний';

  @override
  String get cwCardSizeStandardDefault => 'Стандартный (по умолчанию)';

  @override
  String get cwCardSizeStandard => 'Стандартный';

  @override
  String get cwCardSizeMediumLarge => 'Выше среднего';

  @override
  String get cwCardSizeLarge => 'Большой';

  @override
  String get cwCardSizeVeryLarge => 'Очень большой';

  @override
  String get cwCardSizeExtraLarge => 'Огромный';

  @override
  String get cwCardSizeHuge => 'Гигантский';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count элемента',
      many: '$count элементов',
      few: '$count элемента',
      one: '$count элемент',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Показывать до $count недавнего элемента',
      many: 'Показывать до $count недавних элементов',
      few: 'Показывать до $count недавних элементов',
      one: 'Показывать до $count недавнего элемента',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • По умолчанию';
  }

  @override
  String get cwUnlimited => 'Без ограничений';

  @override
  String get cwMaxItemsAll => 'Показывать все доступные элементы';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count элемента',
      many: '$count элементов',
      few: '$count элемента',
      one: '$count элемент',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Полоса прогресса воспроизведения';

  @override
  String get cwPlaybackPercentage => 'Процент воспроизведения';

  @override
  String get cwEpisodeDetails => 'Сведения о серии и видео';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Заблокировано: $count',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Управлять';

  @override
  String get cwRestoreHiddenPrograms => 'Вернуть скрытые программы';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Скрыто: $count',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'Все скрытые программы возвращены';

  @override
  String get cwWatchNextAdbTitle => 'Доступ к Watch Next (нужен ADB)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV требует разрешение READ_WRITE_WATCH_NEXT_PROGRAMS, чтобы лаунчеры могли читать и показывать ряды «Продолжить просмотр» из установленных приложений.\n\nЧтобы выдать его, подключитесь к телевизору через ADB и выполните:';

  @override
  String get appsNoApplicationsFound => 'Приложения не найдены';

  @override
  String get appDetailsAddToFavorites => 'В избранное';

  @override
  String get appDetailsRemoveFromFavorites => 'Убрать из избранного';

  @override
  String get appDetailsAddToCategory => 'Добавить в категорию';

  @override
  String get sectionsCustomOption => 'Свой...';

  @override
  String get sectionsSelectName => 'Выберите название';

  @override
  String get sectionsCustomName => 'Своё название';

  @override
  String get sectionsSortLastUsed => 'По последнему использованию';

  @override
  String get sectionsReorderHint => 'Выберите с помощью ◄ / ►, затем перемещайте ▲ / ▼';

  @override
  String get inputsNoneDetected => 'Входы не обнаружены';

  @override
  String get notifClearAll => 'Очистить все';

  @override
  String get notifAllCaughtUp => 'Новых уведомлений нет';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Блокировать уведомления ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Открыть $app';
  }

  @override
  String get notifAccessAdbTitle => 'Доступ к уведомлениям (нужен ADB)';

  @override
  String get notifAccessAdbMessage => 'В Android TV нет экрана системных настроек для «Доступа к уведомлениям» (чтения уведомлений других приложений).\n\nПримечание: параметр «Показывать уведомления» в настройках приложений телевизора управляет только уведомлениями этого приложения, а не доступом к уведомлениям.\n\nЧтобы выдать доступ к уведомлениям, подключитесь к телевизору через ADB и выполните:';

  @override
  String get notifOpenAppInfo => 'Открыть сведения о приложении';

  @override
  String get notifOverlayPermissionTitle => 'Разрешение на наложение';

  @override
  String get notifOverlayAdbMessage => 'На этом устройстве не удалось автоматически открыть экран настроек разрешения на наложение.\n\nЧтобы включить всплывающие окна поверх других, выдайте разрешение вручную через ADB с компьютера, подключённого к телевизору:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Заблокированные приложения ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'Пока использовать Google TV';

  @override
  String get backupShareText => 'Резервная копия Hearth';

  @override
  String get backupShareFailedTitle => 'Не удалось поделиться';

  @override
  String backupShareFailed(String error) {
    return 'Не удалось поделиться резервной копией: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Экспорт выполнен';

  @override
  String get backupExportFailedTitle => 'Ошибка экспорта';

  @override
  String get backupImportSuccessTitle => 'Импорт выполнен';

  @override
  String get backupImportFailedTitle => 'Ошибка импорта';

  @override
  String get backupImport => 'Импортировать';

  @override
  String backupLoadError(String error) {
    return 'Ошибка загрузки резервных копий: $error';
  }

  @override
  String get backupNoFiles => 'Файлы резервных копий не найдены.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date ($size)';
  }

  @override
  String backupSizeBytes(String size) {
    return '$size Б';
  }

  @override
  String backupSizeKilobytes(String size) {
    return '$size КБ';
  }

  @override
  String backupSizeMegabytes(String size) {
    return '$size МБ';
  }

  @override
  String get updateCheckForUpdatesTitle => 'Проверка обновлений';

  @override
  String updateCurrentVersion(String version) {
    return 'Текущая версия: $version';
  }

  @override
  String get updateChecking => 'Поиск новой версии на GitHub…';

  @override
  String get updateUpToDate => 'У вас последняя версия.';

  @override
  String updateVersionAvailable(String version) {
    return 'Доступна версия $version';
  }

  @override
  String updateDownloading(String percent) {
    return 'Загрузка… $percent%';
  }

  @override
  String get updateDownloadedHint => 'Загружено. Если установщик не открылся, возможно, на устройстве нужно\nразрешить Hearth «Установку неизвестных приложений».';

  @override
  String get updateSomethingWentWrong => 'Что-то пошло не так';

  @override
  String get updateDownloadAndInstall => 'Скачать и установить';

  @override
  String get updateRetryInstall => 'Повторить установку';

  @override
  String get updateCheckAgain => 'Проверить снова';

  @override
  String get updatesInstallPermissionTitle => 'Разрешите Hearth устанавливать приложения';

  @override
  String get updatesInstallPermissionMessage => 'На следующем экране найдите Hearth, включите его и нажмите «Назад». Установка продолжится, когда вы вернётесь сюда.';

  @override
  String get updatesOpenSettings => 'Открыть настройки';

  @override
  String get updatesCheckFailed => 'Ошибка проверки';

  @override
  String get updatesInstallerNotStarted => 'Установщик не запустился';

  @override
  String get updatesCheckForUpdates => 'Проверить обновления';

  @override
  String get updatesAutoUpdate => 'Обновлять автоматически';

  @override
  String get updatesAutoUpdateDescription => 'Hearth ежедневно проверяет обновления и устанавливает их для установленных им приложений, когда они не используются';

  @override
  String get updatesFooter => 'Устанавливаются из релизов каждого приложения на GitHub. После того как Hearth один раз установит или обновит приложение, его обновления ставятся без вопросов, а само приложение доверяет обновление Hearth.';

  @override
  String get updatesChecking => 'Проверка…';

  @override
  String get updatesInstall => 'Установить';

  @override
  String updatesUpdateTo(String version) {
    return 'Обновить до $version';
  }

  @override
  String get updatesUpToDate => 'Последняя версия';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Загрузка $percent%';
  }

  @override
  String get updatesInstalling => 'Установка…';

  @override
  String get updatesError => 'Ошибка';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutForkOf(String launcher, String author, String parts) {
    return 'Форк $launcher от $author с частями $parts';
  }

  @override
  String get aboutDescription => 'Приватный семейный лаунчер для Google TV со встроенными профилями Google TV и Home Assistant. Без рекламы и трекеров.';

  @override
  String get aboutHearthOnGitHub => 'Hearth на GitHub';

  @override
  String get aboutCredits => 'Благодарности';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'Форк FLauncher · $author';
  }

  @override
  String get aboutLicense => 'Свободное ПО под лицензией GNU GPL v3, как и проекты, на которых оно основано.';

  @override
  String get familyAppsStatusInstalled => 'Установлено';

  @override
  String get familyAppsStatusPartial => 'Частично';

  @override
  String get familyAppsStatusNotInstalled => 'Не установлено';

  @override
  String get familyAppsStatusAtRisk => 'Под угрозой';

  @override
  String get familyAppsAtRiskDetail => 'Google TV удалит незащищённые приложения в этом профиле при его следующем запуске. Нажмите «Добавить» ещё раз, чтобы защитить их.';

  @override
  String get profilePinRow => 'PIN-код профиля';

  @override
  String get profilePinNone => 'Нет';

  @override
  String get profilePinSaved => 'Сохранён';

  @override
  String get profilePinRejected => 'Сохранён — в прошлый раз не принят';

  @override
  String get profilePinPaused => 'Сохранён — приостановлен (приложение изменилось)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth пока не умеет вводить PIN-коды в $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'PIN-код $profile в $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'Hearth вводит его за карточкой «Вход как», когда $app просит. Код хранится на этом телевизоре в зашифрованном виде и никогда не показывается.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Сначала задайте родительский PIN-код ($settings → $profiles → $parentPin): он нужен, чтобы сохранить PIN-код профиля.';
  }

  @override
  String get profilePinSaveFailed => 'Не удалось сохранить PIN-код.';
}
