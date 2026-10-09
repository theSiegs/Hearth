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
  String get familyAppsIntro => 'Установите Hearth и HearthTube в другие профили Google TV. В детских профилях это нужно, чтобы работал HearthTube и чтобы Hearth выбирал нужный профиль в Netflix, Disney+ и других приложениях. Во взрослых профилях это просто удобство: не придётся устанавливать их вручную.';

  @override
  String get familyAppsAddTitle => 'Добавить Hearth в другие профили';

  @override
  String get familyAppsAddKids => 'Hearth и HearthTube будут установлены в профили ваших детей: там заработает HearthTube, а Hearth сможет выбирать нужный профиль в таких приложениях, как Netflix и Disney+.';

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
}
