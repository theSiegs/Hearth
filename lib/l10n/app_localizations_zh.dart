import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get aboutFlauncher => '关于 Hearth';

  @override
  String get addSection => '添加分区';

  @override
  String get alphabetical => '按字母顺序';

  @override
  String get appCardHighlightAnimation => '应用卡片高亮动画';

  @override
  String get appInfo => '应用信息';

  @override
  String get appKeyClick => '按键提示音';

  @override
  String get applications => '应用';

  @override
  String get autoHideAppBar => '自动隐藏状态栏';

  @override
  String get backButtonAction => '返回键行为';

  @override
  String get category => '类别';

  @override
  String get columnCount => '列数';

  @override
  String get date => '日期';

  @override
  String get dateAndTimeFormat => '日期和时间格式';

  @override
  String get delete => '删除';

  @override
  String get dialogOptionBackButtonActionDoNothing => '无操作';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => '显示屏保';

  @override
  String get dialogOptionBackButtonActionShowClock => '显示时钟';

  @override
  String get dialogTextNoFileExplorer => '请安装文件管理器以选择图片。';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title（类别）';
  }

  @override
  String get gradient => '渐变';

  @override
  String get favoriteApps => '收藏应用';

  @override
  String get grid => '网格';

  @override
  String get height => '高度';

  @override
  String get hide => '隐藏';

  @override
  String get hiddenApplications => '已隐藏应用';

  @override
  String get launcherSections => '分区';

  @override
  String get layout => '布局';

  @override
  String get loading => '加载中';

  @override
  String get manual => '手动';

  @override
  String get modifySection => '修改分区';

  @override
  String get name => '名称';

  @override
  String get newSection => '新建分区';

  @override
  String get nonTvApplications => '非电视应用';

  @override
  String get open => '打开';

  @override
  String get picture => '图片';

  @override
  String removeFrom(String name) {
    return '从$name中移除';
  }

  @override
  String get reorder => '重新排序';

  @override
  String get row => '行';

  @override
  String get rowHeight => '行高';

  @override
  String get save => '保存';

  @override
  String get spacer => '间隔';

  @override
  String get statusBar => '状态栏';

  @override
  String get show => '显示';

  @override
  String get showCategoryTitles => '显示类别标题';

  @override
  String get showCategoryAppCount => '在类别中显示应用数量';

  @override
  String get hideHighlightOutlineOnHomescreen => '在主屏幕隐藏高亮边框';

  @override
  String get appSelectorTransitionAnimation => '应用选择器转场动画';

  @override
  String get sort => '排序';

  @override
  String get systemSettings => 'Google TV 设置';

  @override
  String get textEmptyCategory => '此类别为空。';

  @override
  String get time => '时间';

  @override
  String get tvApplications => '电视应用';

  @override
  String get type => '类型';

  @override
  String get uninstall => '卸载';

  @override
  String get wallpaper => '壁纸';

  @override
  String get withEllipsisAddTo => '添加到…';

  @override
  String get timeBasedWallpaper => '按时间切换壁纸';

  @override
  String get pickDayWallpaper => '选择日间壁纸';

  @override
  String get pickNightWallpaper => '选择夜间壁纸';

  @override
  String get inputs => '输入源';

  @override
  String get inputSources => '输入源';

  @override
  String get backupAndRestore => '备份与恢复';

  @override
  String get exportBackup => '导出备份';

  @override
  String get importBackup => '导入备份';

  @override
  String exportSuccess(String path) {
    return '备份已成功导出到 $path';
  }

  @override
  String get importSuccess => '备份导入成功';

  @override
  String get importConfirm => '确定要导入备份吗？这将会覆盖你当前的设置和布局。';

  @override
  String importError(String error) {
    return '导入备份失败：$error';
  }

  @override
  String exportError(String error) {
    return '导出备份失败：$error';
  }

  @override
  String get shareBackup => '共享备份';

  @override
  String get notificationBell => '通知铃铛';

  @override
  String get autoHideNotificationBell => '自动隐藏通知铃铛';

  @override
  String get continueWatching => '继续观看';

  @override
  String get showContinueWatchingOnHome => '在主页显示「继续观看」';

  @override
  String get permissionDeniedContinueWatching => '显示「继续观看」需要权限';

  @override
  String get system => '系统';

  @override
  String get accentColor => '强调色';

  @override
  String get dataUsagePeriod => '数据使用周期';

  @override
  String get notificationAccess => '通知访问权限';

  @override
  String get watchNextAccess => 'Watch Next 访问权限';

  @override
  String get granted => '已授予';

  @override
  String get permissionRequired => '需要权限';

  @override
  String get systemWidePopupAlert => '全局弹窗提醒';

  @override
  String get overlayPermissionRequired => '需要悬浮窗权限';

  @override
  String get enabled => '已启用';

  @override
  String get disabled => '已禁用';

  @override
  String get showAppNamesBelowIcons => '在图标下方显示应用名称';

  @override
  String get dataUsage => '数据使用';

  @override
  String get networkIndicator => '网络指示器';

  @override
  String get startOnBoot => '开机时启动 (Google TV / Fire TV)';

  @override
  String get appLanguage => '语言';

  @override
  String get systemDefault => '跟随系统';

  @override
  String get english => '英语';

  @override
  String get spanish => '西班牙语';

  @override
  String get ukrainian => '乌克兰语';

  @override
  String get chinese => '中文';

  @override
  String get french => '法语';

  @override
  String get german => '德语';

  @override
  String get japanese => '日语';

  @override
  String get portuguese => '葡萄牙语';

  @override
  String get russian => '俄语';

  @override
  String get italian => '意大利语';

  @override
  String get hindi => '印地语';

  @override
  String get korean => '韩语';

  @override
  String get arabic => '阿拉伯语';

  @override
  String get turkish => '土耳其语';

  @override
  String get hidePersistentNotifications => '隐藏常驻通知';

  @override
  String get blockedNotificationApps => '已屏蔽的应用';

  @override
  String get unblockAppNotifications => '取消屏蔽通知';

  @override
  String get noBlockedApps => '暂无已屏蔽的应用';

  @override
  String get persistentNotification => '常驻';

  @override
  String get unblockAll => '全部取消屏蔽';

  @override
  String get weather => '天气';

  @override
  String get showWeatherWarnings => '显示降雨及天气预警';

  @override
  String get celsius => '摄氏度 (°C)';

  @override
  String get fahrenheit => '华氏度 (°F)';

  @override
  String get notifications => '通知';

  @override
  String get continueWatchingDescription => '在主屏幕上显示支持的应用最近观看的电影和电视剧';

  @override
  String get dismiss => '关闭';

  @override
  String get noBlockedAppsDesc => '当前所有应用均允许显示通知';

  @override
  String get notificationsAllowed => '允许通知';

  @override
  String get notificationsBlocked => '已屏蔽通知';

  @override
  String get dpadDismissHint => '左键: 关闭 • 确定: 选项';

  @override
  String get settingsTitle => '设置';

  @override
  String get profilesTitle => '个人资料';

  @override
  String get homeScreenTitle => '主屏幕';

  @override
  String get remoteAndSearchTitle => '遥控器';

  @override
  String get parentSettingsTitle => '家长设置';

  @override
  String get tvPowerTitle => '电视和电源';

  @override
  String get setupPermissionsTitle => '设置和权限';

  @override
  String get updatesTitle => '更新';

  @override
  String get familyAppsTitle => '其他个人资料中的 Hearth';

  @override
  String get cardStyleTitle => '卡片样式';

  @override
  String get dockLabelsTitle => '程序坞和标签';

  @override
  String get animationsSoundTitle => '动画和声音';

  @override
  String get haPanelTitle => '仪表板面板';

  @override
  String get lookTitle => '外观';

  @override
  String get remoteButtonsTitle => '遥控器按钮';

  @override
  String get profilePairingTitle => '个人资料配对';

  @override
  String get haTvStatusTitle => '电视状态';

  @override
  String get continueWatchingAppsTitle => '继续观看应用';

  @override
  String get cardSizeTitle => '卡片大小';

  @override
  String get maxItemsTitle => '最多项目数';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get tryAgain => '重试';

  @override
  String get notNow => '以后再说';

  @override
  String get done => '完成';

  @override
  String get remove => '移除';

  @override
  String get homeNothingToWatch => '现在没有可看的内容';

  @override
  String get errorScreenTitle => '出了点问题';

  @override
  String get appInfoAddToCategory => '添加到类别';

  @override
  String get appInfoAddToFavorites => '添加到收藏';

  @override
  String get appInfoRemoveFromFavorites => '从收藏中移除';

  @override
  String get appInfoSetCustomBanner => '设置自定义横幅';

  @override
  String get appInfoClearCustomBanner => '清除自定义横幅';

  @override
  String appInfoSetBannerFailed(String error) {
    return '无法设置横幅：$error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return '无法清除横幅：$error';
  }

  @override
  String get cwGridAll => '全部';

  @override
  String get cwRowSeeAll => '查看全部';

  @override
  String cwRowInProgress(int count) {
    return '$count 个观看中';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '剩余 $hours 小时 $minutes 分钟';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '剩余 $minutes 分钟';
  }

  @override
  String get watchNextInfoRemove => '从“继续观看”中移除';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return '隐藏来自 $appName 的全部内容';
  }

  @override
  String get watchNextInfoPlayResume => '播放 / 继续';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '打开 $appName';
  }

  @override
  String get watchNextInfoAppInfo => '应用信息';

  @override
  String get dataWidgetGrantPermission => '授予使用情况权限';

  @override
  String dataWidgetDaily(String usage) {
    return '每日：$usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return '每周：$usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return '每月：$usage';
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
        'today': '今天有雨',
        'tomorrow': '明天有雨',
        'other': '$day有雨',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '今天有雪',
        'tomorrow': '明天有雪',
        'other': '$day有雪',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '今天有雷暴',
        'tomorrow': '明天有雷暴',
        'other': '$day有雷暴',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$forecast（$percent%）';
  }

  @override
  String searchWatchOn(String apps) {
    return '在 $apps 上观看';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return '在 $app 上租借或购买';
  }

  @override
  String get searchMoreWaysToWatch => '更多观看方式 (Google TV)';

  @override
  String get searchListening => '正在聆听…';

  @override
  String get searchHint => '搜索电影和剧集';

  @override
  String get searchEntryHelp => '输入文字、使用麦克风，或通过 Google TV 应用在手机上输入。';

  @override
  String get searchTabWatchNow => '立即观看';

  @override
  String get searchTabRentOrBuy => '租借或购买';

  @override
  String get searchTabOtherApps => '其他应用';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return '租借或购买 · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => '观看途径：Google TV';

  @override
  String searchGridElsewhere(String services) {
    return '在 $services 上（不在这台电视上）';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个结果',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return '这里没有与“$query”相关的内容。';
  }

  @override
  String get searchGridTmdbNotice => '观看途径信息来自 TMDB（通过 JustWatch）。本产品使用 TMDB API，但未获得 TMDB 的认可或认证。';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps或$last';
  }

  @override
  String get searchListSeparator => '、';

  @override
  String searchAskGoogleQuery(String query) {
    return '问 Google：“$query”';
  }

  @override
  String get searchAskGoogleDetail => '用于提问、查天气以及节目以外的任何内容';

  @override
  String searchSearchingFor(String query) {
    return '正在搜索“$query”…';
  }

  @override
  String get searchFailed => '暂时无法搜索。请检查网络连接。';

  @override
  String searchNothingFound(String query) {
    return '未找到与“$query”相关的内容';
  }

  @override
  String searchNothingInYourApps(String query) {
    return '目前你的应用中没有“$query”';
  }

  @override
  String get searchSeeMoreResults => '在“更多结果”中查看其他可观看途径。';

  @override
  String get searchMoreResults => '更多结果';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 部作品',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => '问 Google';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => '电影';

  @override
  String get searchKindSeries => '剧集';

  @override
  String get gradientNamePitchBlack => '漆黑';

  @override
  String get gradientNameGreatWhale => '巨鲸';

  @override
  String get gradientNameViciousStance => '凶猛姿态';

  @override
  String get gradientNameTeenNotebook => '少女笔记本';

  @override
  String get gradientNameOldHat => '旧帽子';

  @override
  String get gradientNameBurningSpring => '燃烧之春';

  @override
  String get gradientNameDesertHump => '沙漠驼峰';

  @override
  String get gradientNameFarawayRiver => '远方河流';

  @override
  String get gradientNameSaintPetersburg => '圣彼得堡';

  @override
  String get gradientNameAfricanField => '非洲原野';

  @override
  String get gradientNameGrassShampoo => '青草洗发水';

  @override
  String get updateErrorNoApk => '没有适用于此设备的 APK 版本';

  @override
  String get updateErrorCheckFailed => '无法检查更新';

  @override
  String get updateErrorDownloadFailed => '无法下载更新';

  @override
  String get serviceHearthTubeDescription => '适用于 Hearth 的 YouTube；跟随你的 Hearth 个人资料';

  @override
  String get haSummaryOn => '开';

  @override
  String get haSummaryOff => '关';

  @override
  String get haSummaryReporting => '正在上报';

  @override
  String haNotificationsNeedsFix(String path) {
    return '请打开主页按钮修复（$path），弹窗由它显示。';
  }

  @override
  String get haNotificationsShow => '显示 Home Assistant 通知';

  @override
  String get haNotificationsSendTest => '发送测试通知';

  @override
  String haNotificationsHelp(String host, String path) {
    return '在 Home Assistant 中添加“Notifications for Android TV / Fire TV”集成，主机填 $host。然后在自动化中向它发送通知，例如门铃响起或洗衣完成时。\n\n只有家庭网络中的设备可以发送（端口 7676）。弹窗会显示在任何应用之上，并且需要打开主页按钮修复（$path）。';
  }

  @override
  String get haNotificationsThisTvIp => '（这台电视的 IP 地址）';

  @override
  String get haPanelSaved => '已保存';

  @override
  String get haPanelSavedNoToken => '已保存。请添加访问令牌以登录。';

  @override
  String get haPanelReceived => '已从手机收到地址和令牌';

  @override
  String get haPanelRightEdge => '在右边缘按右键打开面板';

  @override
  String get haSetUpFromPhone => '用手机设置';

  @override
  String get haPanelTokenLabel => '长期访问令牌';

  @override
  String get haPanelTokenSavedHint => '已保存（输入新的令牌即可替换）';

  @override
  String get haPanelDashboardLabel => '仪表板';

  @override
  String haPanelHelp(String tvStatus) {
    return '仅对此个人资料开启。面板会显示$tvStatus中所填地址的仪表板，并使用令牌登录。请在 Home Assistant 中以为这台电视创建的非管理员用户登录后创建令牌（个人资料页面的“安全”标签页）。';
  }

  @override
  String get haStatusReportingOff => '状态上报已关闭';

  @override
  String get haStatusSaved => '已保存：正在上报到 Home Assistant';

  @override
  String get haStatusAddressLabel => 'Home Assistant 地址';

  @override
  String get haStatusWebhookLabel => 'Webhook ID';

  @override
  String get haStatusNowPlayingOn => '正在播放：开';

  @override
  String get haStatusNowPlayingOff => '正在播放：请开启通知访问权限';

  @override
  String get haStatusHelp => '电视会把当前内容发送给 Home Assistant：应用、正在播放的内容、Google TV 个人资料和儿童屏幕使用时间。只会在有变化时发送到上面的地址。';

  @override
  String get haPhoneSetupNoNetwork => '这台电视不在家庭网络中，手机无法连接到它。';

  @override
  String get haPhoneSetupScan => '用连接同一 Wi-Fi 的手机扫描，粘贴 Home Assistant 地址和访问令牌，然后点按 Send。此窗口打开时页面才可用。';

  @override
  String get profilesSwitchProfile => '切换个人资料';

  @override
  String get parentPinTitle => '家长 PIN 码';

  @override
  String get parentPinOn => '开';

  @override
  String get parentPinOff => '关';

  @override
  String get parentPinCurrent => '当前家长 PIN 码';

  @override
  String get parentPinRemove => '移除 PIN 码';

  @override
  String get parentPinChange => '更改 PIN 码';

  @override
  String get parentPinNew => '新家长 PIN 码';

  @override
  String get parentPinNewSubtitle => '在 Google TV 儿童个人资料中更改启动器时需要';

  @override
  String get parentPinConfirm => '再次输入 PIN 码';

  @override
  String get parentPinAskTitle => '请家长帮忙';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return '儿童个人资料中的启动器设置已锁定。家长可以在自己的个人资料中前往 $settings → $profiles → $parentPin 设置 PIN 码。';
  }

  @override
  String get parentPinKidsSubtitle => '儿童个人资料：输入家长 PIN 码以更改启动器';

  @override
  String get parentPinWrong => 'PIN 码错误';

  @override
  String get parentPinEnter => '输入 PIN 码';

  @override
  String profileSwitchGreeting(String name) {
    return '你好，$name';
  }

  @override
  String get profileSwitchSettingUp => '正在设置此个人资料…';

  @override
  String profilesKidsName(String name) {
    return '$name（儿童）';
  }

  @override
  String profilesAdultName(String name) {
    return '$name（成人）';
  }

  @override
  String get pairingShowPicker => '显示选择界面';

  @override
  String get pairingAlwaysShowPicker => '始终显示选择界面';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile（按名称匹配）';
  }

  @override
  String get pairingNoMatchYet => '暂无匹配：显示选择界面';

  @override
  String get pairingOffSetUp => '个人资料配对已关闭。去设置';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Hearth 打开其中某个应用时，会选择与 Google TV 个人资料配对的应用个人资料。Hearth 会自动匹配名称（“$shortName”对应“$fullName”）；可在此更改任何配对。没有匹配时，会显示应用自己的选择界面。';
  }

  @override
  String get pairingAppNotInstalled => '未安装';

  @override
  String get pairingAppOff => '关：显示应用自己的选择界面';

  @override
  String get pairingAppNotSeen => '从 Hearth 打开一次，让 Hearth 了解它的个人资料';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 个个人资料',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return '按名称匹配（$profile）';
  }

  @override
  String get pairingMatchByNameNone => '按名称匹配（暂无匹配）';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$app 中的 $profile';
  }

  @override
  String pairingPairIn(String app) {
    return '在 $app 中配对个人资料';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth 还没有看到此应用的个人资料。请从 Hearth 打开一次，然后再回来。';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return '此应用中的个人资料：$profiles。Hearth 看到 Google TV 个人资料后，它们会显示在这里。';
  }

  @override
  String get familyAppsAddTitle => '将 Hearth 添加到其他个人资料';

  @override
  String get familyAppsAddKids => '这会将 Hearth 和 HearthTube 安装到孩子的个人资料中，让 HearthTube 在那里正常运行，并让 Hearth 能在流媒体服务中选择正确的个人资料。';

  @override
  String get familyAppsAddAdults => '它还会安装到电视上的其他成人个人资料中，其他成人无需自己设置。';

  @override
  String get familyAppsAddOnlyOwnApps => '只会添加 Hearth 自己的两个应用，你可以随时用下方的“移除”撤销。';

  @override
  String get familyAppsAddFamilyLink => '每个孩子会收到一条 Family Link“已添加应用”通知。';

  @override
  String get familyAppsAddApproval => '第一次时，电视会询问“允许调试吗？”——请选择“始终允许”，这样 Hearth 才能完成设置。';

  @override
  String get familyAppsAdd => '添加';

  @override
  String get familyAppsRemoveTitle => '从其他个人资料中移除 Hearth';

  @override
  String get familyAppsRemoveBody => '这会从其他个人资料中移除 Hearth 和 HearthTube。';

  @override
  String get familyAppsRemoveFirst => '如果你打算卸载 Hearth 本身，请先执行此操作，否则它在儿童个人资料中的副本可能会残留，需要用电脑才能清除。';

  @override
  String get familyAppsUninstallTitle => '卸载 Hearth';

  @override
  String get familyAppsUninstallBody => '这会先从其他个人资料中移除 Hearth 和 HearthTube，然后从当前个人资料中卸载 Hearth。';

  @override
  String get familyAppsUninstallWhyHere => '在这里卸载（而不是在 Android 设置中卸载）可以确保儿童个人资料中不留下任何东西。';

  @override
  String get familyAppsApprovalFirstTitle => '请先完成一次性授权';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth 还无法清理其他个人资料——需要先在电视上对“允许调试吗？”授权一次。';

  @override
  String get familyAppsApprovalFirstRetry => '授权后再试一次卸载，这样儿童个人资料中就不会有残留。';

  @override
  String get familyAppsAddDone => '添加完成';

  @override
  String get familyAppsRemoveDone => '移除完成';

  @override
  String get familyAppsAdded => '完成。Hearth 和 HearthTube 现已安装到其他个人资料中，请查看下方列表。';

  @override
  String get familyAppsRemoved => '完成。已从其他个人资料中移除 Hearth 和 HearthTube。';

  @override
  String get familyAppsNothingToSetUp => '目前还没有其他需要设置的个人资料。';

  @override
  String get familyAppsFailedTitle => '无法设置个人资料';

  @override
  String get familyAppsFailedBody => 'Hearth 需要先在电视上获得一次性授权，才能设置其他个人资料。';

  @override
  String get familyAppsFailedRetry => '当电视询问“允许调试吗？”时，请选择“始终允许”，然后重试。';

  @override
  String get familyAppsAlsoAdults => '同时设置其他成人个人资料';

  @override
  String get familyAppsOn => '开';

  @override
  String get familyAppsOff => '关';

  @override
  String get familyAppsNoneYet => '尚未设置其他个人资料。';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app：已安装';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app：已安装，已保留';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app：未安装';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app：未安装，已保留';
  }

  @override
  String get familyAppsUnnamedKids => '一个儿童个人资料';

  @override
  String get familyAppsUnnamedAdult => '一个成人个人资料';

  @override
  String setupAccessibilityInstructions(String service) {
    return '在下一个屏幕中向下滚动到“服务”，选择“$service”，然后打开“启用”并确认。按返回键直到回到主屏幕。';
  }

  @override
  String setupRestrictedWarning(String command) {
    return '如果 Android 提示该设置受限，请在电脑上运行一次：\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => '将 Hearth 设为主屏幕应用';

  @override
  String get setupDefaultLauncherWhy => '防止儿童个人资料屏蔽 Hearth。';

  @override
  String get setupDefaultLauncherInstructions => '在下一个屏幕中选择 Hearth。';

  @override
  String get setupHomeFixTitle => '主页按钮修复';

  @override
  String get setupHomeFixWhy => '主页按钮会打开 Hearth，而不是 Google TV。';

  @override
  String get setupNotificationsTitle => '通知访问权限';

  @override
  String get setupNotificationsWhy => '显示通知和正在播放的内容。';

  @override
  String setupNotificationsInstructions(String service) {
    return '在下一个屏幕中选择“$service”并允许。';
  }

  @override
  String get setupInstallTitle => '安装更新';

  @override
  String get setupInstallWhy => '允许 Hearth 自我更新并安装配套应用。';

  @override
  String get setupInstallInstructions => '在下一个屏幕中打开 Hearth。';

  @override
  String get setupPairingWhy => '在 Netflix、Disney+、Apple TV、HBO Max 和 Paramount+ 中选择你的个人资料。';

  @override
  String get setupVoiceTitle => 'Hearth 语音';

  @override
  String get setupVoiceWhy => '让个人资料配对能“听到”Netflix 的个人资料界面。其他应用仍使用 Google 的语音。';

  @override
  String setupVoiceInstructions(String engine) {
    return '在下一个屏幕的“首选引擎”中选择“$engine”，然后在警告中点“确定”（Hearth 只会监听流媒体应用）。按返回键回来。';
  }

  @override
  String get setupOpenSettings => '打开设置';

  @override
  String get setupAdbFallback => '这台电视无法打开该设置界面。请改为在电脑上运行一次：';

  @override
  String setupProgress(int done, int total) {
    return '已完成 $done/$total';
  }

  @override
  String get setupOptional => '可选';

  @override
  String get homeButtonFixOffTitle => '主页按钮修复已关闭';

  @override
  String get homeButtonFixOffBody => 'Hearth 的无障碍服务已停止，通常发生在更新之后。在重新开启之前，主页按钮可能会打开 Google TV 而不是 Hearth，并且不会跟随个人资料切换。';

  @override
  String get homeButtonFixStuck => 'Android 仍显示它已开启，但它并未运行。请在无障碍设置中将 Hearth 关闭后再打开，以重新启动它。';

  @override
  String get homeButtonFixRestricted => '如果那里的 Hearth 开关呈灰色，是因为此更新是从下载的文件安装的，Android 阻止了它。请在连接到电视的电脑上运行以下命令，然后打开 Hearth：';

  @override
  String get homeButtonFixDontRemind => '不再提醒';

  @override
  String get homeButtonFixOpenSettings => '打开无障碍设置';

  @override
  String get remoteButtonsRemapButton => '重新映射按钮';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return '按钮 $keyCode';
  }

  @override
  String get remoteButtonsNormal => '默认';

  @override
  String get remoteButtonsCaptureTitle => '请按遥控器上的按钮';

  @override
  String get remoteButtonsCaptureBody => '按下要重新映射的按钮。按返回键取消。';

  @override
  String get remoteButtonsNeedsFixTitle => '请先打开主页按钮修复';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return '重新映射需要主页按钮修复（$path）。';
  }

  @override
  String get remoteButtonsCantRemapTitle => '无法重新映射该按钮';

  @override
  String get remoteButtonsCantRemapBody => '方向键、确定、返回、主页和电源键保持原有功能。';

  @override
  String remoteButtonsPressOption(String action) {
    return '按下：$action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return '长按：$action';
  }

  @override
  String get remoteButtonsSearchPreset => '按下使用 Hearth 搜索，长按使用 Google';

  @override
  String get remoteButtonsHomeOnlyOn => '仅在 Hearth 主屏幕：开';

  @override
  String get remoteButtonsHomeOnlyOff => '仅在 Hearth 主屏幕：关';

  @override
  String get remoteButtonsRestore => '恢复按钮原有功能';

  @override
  String get remoteButtonsActionTitle => '操作';

  @override
  String get remoteButtonsActionApp => '打开应用…';

  @override
  String get remoteButtonsActionInput => '切换到电视输入源…';

  @override
  String get remoteButtonsActionSwitchProfile => '切换个人资料（Google TV）';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth 搜索（语音）';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth 搜索（键盘）';

  @override
  String get remoteButtonsActionHome => 'Hearth 主屏幕';

  @override
  String get remoteButtonsActionSleep => '休眠';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android 设置';

  @override
  String get remoteButtonsPickAppTitle => '打开应用';

  @override
  String get remoteButtonsPickInputTitle => '切换到电视输入源';

  @override
  String get remoteButtonsHaConnectTitle => '请先连接 Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return '请先设置 Home Assistant 面板（$panel > $row），然后重试。';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return '场景：$name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return '运行：$name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return '按下：$name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return '切换：$name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\n按下：$press  ·  长按：$hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\n按下：$press  ·  长按：$hold  ·  仅主屏幕';
  }

  @override
  String remoteButtonsFooter(String path) {
    return '需要主页按钮修复（$path）。只设置了长按操作的按钮，按下时也会执行该操作。HearthTube 在前台时，Hearth 搜索会打开 HearthTube 自己的搜索。显示儿童屏幕使用时间界面时，重新映射会暂停。';
  }

  @override
  String get tvPowerScreensaver => '屏幕保护程序（Google Photos）';

  @override
  String get tvPowerScreensaverNote => 'Hearth 使用 Google TV 的屏幕保护程序。请在那里选择 Google Photos（以及哪些相册）或其他来源。';

  @override
  String get tvPowerSleepWhenIdle => '闲置时休眠';

  @override
  String get tvPowerSleepOff => '关';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours 小时',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return '播放视频或音乐也算作活动。需要主页按钮修复（$path）。';
  }

  @override
  String get accentPurple => '紫色';

  @override
  String get accentTeal => '青绿色';

  @override
  String get accentBlue => '蓝色';

  @override
  String get accentOrange => '橙色';

  @override
  String get accentPink => '粉色';

  @override
  String get accentGreen => '绿色';

  @override
  String get accentWhite => '白色';

  @override
  String get accentYellow => '黄色';

  @override
  String get accentRed => '红色';

  @override
  String get accentCyan => '青色';

  @override
  String get accentIndigo => '靛蓝';

  @override
  String get accentLime => '青柠色';

  @override
  String get accentAmber => '琥珀色';

  @override
  String get accentRose => '玫瑰色';

  @override
  String get accentIceBlue => '冰蓝色';

  @override
  String get accentSelected => '当前强调色';

  @override
  String get cardStyleDefault => '默认';

  @override
  String get cardStylePremium => '高级';

  @override
  String get cardStyleGlow => '发光';

  @override
  String get cardStyleSquircle => '超椭圆';

  @override
  String get cardStyleClassic => '经典';

  @override
  String get cardStyleMinimal => '极简';

  @override
  String get cardStyleCapsule => '胶囊';

  @override
  String get dockFavoritesDock => '收藏程序坞';

  @override
  String get dockFavoritesDockDescription => '将收藏以横栏形式显示在主屏幕底部，上方为「继续观看」，下方为其他分区。圆角随卡片样式变化。';

  @override
  String get dockFrosted => '磨砂程序坞';

  @override
  String get dockDark => '深色程序坞';

  @override
  String get dockShadow => '程序坞阴影';

  @override
  String get dockBlurWallpaperBelow => '模糊程序坞下方的壁纸';

  @override
  String get wallpaperMatchSelectedApp => '匹配所选应用';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing 每日图片';

  @override
  String get wallpaperRefreshNow => '立即刷新';

  @override
  String get wallpaperBingError => '无法连接 Bing。请检查网络连接。';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return '温度单位：$unit';
  }

  @override
  String get weatherLocationNotSet => '天气位置：未设置';

  @override
  String weatherLocationValue(String place) {
    return '天气位置：$place';
  }

  @override
  String get statusBarWeatherLoadFailed => '无法加载天气，将自动重试。';

  @override
  String get statusBarWeatherSourceHint => '请在上方选择天气位置（天气来自 Open-Meteo，免费，无需账号）。如未选择，且已安装 Breezy Weather 应用并开启 Gadgetbridge 共享，则从该应用获取天气。';

  @override
  String get weatherLocationTitle => '天气位置';

  @override
  String get weatherLocationHint => '城市或城镇';

  @override
  String get weatherLocationNoResults => '未找到地点';

  @override
  String get weatherLocationSearchError => '无法连接天气服务。请检查网络连接。';

  @override
  String get weatherLocationPrivacyNote => '天气由 Open-Meteo.com 提供：免费，无需账号。仅发送所选地点的坐标。';

  @override
  String get weatherLocationSearch => '搜索';

  @override
  String get dateTimeInvalidFormat => '格式无效';

  @override
  String get dateTimeSelectFormats => '请在下方选择格式';

  @override
  String get dataUsageDaily => '每日';

  @override
  String get dataUsageWeekly => '每周';

  @override
  String get dataUsageMonthly => '每月';

  @override
  String cwAppsBlockedHeading(int count) {
    return '已从「继续观看」屏蔽（$count）';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => '已从「继续观看」屏蔽';

  @override
  String get cwAppsUnblock => '取消屏蔽';

  @override
  String get cwAppsUnblockAllApps => '取消屏蔽所有应用';

  @override
  String get cwAppsNoBlockedApps => '没有屏蔽的应用';

  @override
  String get cwAppsNoBlockedAppsMessage => '所有支持的应用都可以在「继续观看」中显示内容。';

  @override
  String get cwAppsWithContinueWatching => '支持「继续观看」的应用';

  @override
  String get cwAppsWithContinueWatchingHint => '目前在主屏幕上提供 Watch Next 内容的应用';

  @override
  String get cwAppsNoActiveApps => '目前没有应用提供「继续观看」内容。\n支持的应用（如 SmartTube 或流媒体服务）添加内容后，会显示在这里。';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个活跃项目',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => '所有已安装的应用';

  @override
  String get cwAppsAllInstalledAppsHint => '关闭即可阻止应用向「继续观看」添加内容';

  @override
  String get cwAppsBlocked => '已屏蔽';

  @override
  String get cwAppsAllowed => '已允许';

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
    return '$height dp（$size）';
  }

  @override
  String get cwCardSizeExtraSmall => '特小';

  @override
  String get cwCardSizeVerySmall => '很小';

  @override
  String get cwCardSizeSmall => '小';

  @override
  String get cwCardSizeCompact => '紧凑';

  @override
  String get cwCardSizeMediumSmall => '中小';

  @override
  String get cwCardSizeMedium => '中';

  @override
  String get cwCardSizeStandardDefault => '标准（默认）';

  @override
  String get cwCardSizeStandard => '标准';

  @override
  String get cwCardSizeMediumLarge => '中大';

  @override
  String get cwCardSizeLarge => '大';

  @override
  String get cwCardSizeVeryLarge => '很大';

  @override
  String get cwCardSizeExtraLarge => '特大';

  @override
  String get cwCardSizeHuge => '超大';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最多显示 $count 个最近项目',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • 默认';
  }

  @override
  String get cwUnlimited => '无限制';

  @override
  String get cwMaxItemsAll => '显示所有可用项目';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => '播放进度条';

  @override
  String get cwPlaybackPercentage => '播放百分比';

  @override
  String get cwEpisodeDetails => '剧集和视频详情';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已屏蔽 $count 个',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => '管理';

  @override
  String get cwRestoreHiddenPrograms => '恢复已隐藏的节目';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已隐藏 $count 个',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => '已恢复所有隐藏的节目';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next 访问权限（需要 ADB）';

  @override
  String get cwWatchNextAdbMessage => 'Android TV 要求启动器拥有 READ_WRITE_WATCH_NEXT_PROGRAMS 权限，才能读取并显示已安装应用的「继续观看」行。\n\n要授予此权限，请通过 ADB 连接电视并运行：';

  @override
  String get appsNoApplicationsFound => '未找到应用';

  @override
  String get appDetailsAddToFavorites => '添加到收藏';

  @override
  String get appDetailsRemoveFromFavorites => '从收藏中移除';

  @override
  String get appDetailsAddToCategory => '添加到类别';

  @override
  String get sectionsCustomOption => '自定义...';

  @override
  String get sectionsSelectName => '选择名称';

  @override
  String get sectionsCustomName => '自定义名称';

  @override
  String get sectionsSortLastUsed => '最近使用';

  @override
  String get sectionsReorderHint => '用 ◄ / ► 选择，再用 ▲ / ▼ 调整顺序';

  @override
  String get inputsNoneDetected => '未检测到输入源';

  @override
  String get notifClearAll => '全部清除';

  @override
  String get notifAllCaughtUp => '全部看完了！';

  @override
  String notifBlockAppNotifications(String app) {
    return '屏蔽通知（$app）';
  }

  @override
  String notifOpenApp(String app) {
    return '打开 $app';
  }

  @override
  String get notifAccessAdbTitle => '通知访问权限（需要 ADB）';

  @override
  String get notifAccessAdbMessage => 'Android TV 没有提供「通知访问权限」（读取其他应用的通知）的系统设置页面。\n\n注意：在电视的应用设置中开启「显示通知」只控制本应用发出的通知，并不会授予通知访问权限。\n\n要授予通知访问权限，请通过 ADB 连接电视并运行：';

  @override
  String get notifOpenAppInfo => '打开应用信息';

  @override
  String get notifOverlayPermissionTitle => '悬浮窗权限';

  @override
  String get notifOverlayAdbMessage => '此设备无法自动打开悬浮窗权限设置页面。\n\n要启用悬浮弹窗，请在连接到电视的电脑上通过 ADB 手动授予权限：';

  @override
  String blockedNotificationsHeading(int count) {
    return '已屏蔽的应用（$count）';
  }

  @override
  String get systemPageUseGoogleTv => '暂时使用 Google TV';

  @override
  String get backupShareText => 'Hearth 备份';

  @override
  String get backupShareFailedTitle => '共享失败';

  @override
  String backupShareFailed(String error) {
    return '共享备份失败：$error';
  }

  @override
  String get backupExportSuccessTitle => '导出成功';

  @override
  String get backupExportFailedTitle => '导出失败';

  @override
  String get backupImportSuccessTitle => '导入成功';

  @override
  String get backupImportFailedTitle => '导入失败';

  @override
  String get backupImport => '导入';

  @override
  String backupLoadError(String error) {
    return '加载备份出错：$error';
  }

  @override
  String get backupNoFiles => '未找到备份文件。';

  @override
  String backupFileDetails(String date, String size) {
    return '$date（$size）';
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
  String get updateCheckForUpdatesTitle => '检查更新';

  @override
  String updateCurrentVersion(String version) {
    return '当前版本：$version';
  }

  @override
  String get updateChecking => '正在 GitHub 上检查新版本…';

  @override
  String get updateUpToDate => '已是最新版本。';

  @override
  String updateVersionAvailable(String version) {
    return '有新版本 $version 可用';
  }

  @override
  String updateDownloading(String percent) {
    return '正在下载… $percent%';
  }

  @override
  String get updateDownloadedHint => '已下载。如果安装程序没有打开，可能需要在设备上\n为 Hearth 授予「安装未知应用」权限。';

  @override
  String get updateSomethingWentWrong => '出了点问题';

  @override
  String get updateDownloadAndInstall => '下载并安装';

  @override
  String get updateRetryInstall => '重试安装';

  @override
  String get updateCheckAgain => '再次检查';

  @override
  String get updatesInstallPermissionTitle => '允许 Hearth 安装应用';

  @override
  String get updatesInstallPermissionMessage => '在下一个页面中找到 Hearth 并开启，然后按返回键。回到这里后安装会继续。';

  @override
  String get updatesOpenSettings => '打开设置';

  @override
  String get updatesCheckFailed => '无法检查更新';

  @override
  String get updatesInstallerNotStarted => '安装程序未启动';

  @override
  String get updatesCheckForUpdates => '检查更新';

  @override
  String get updatesAutoUpdate => '自动更新';

  @override
  String get updatesAutoUpdateDescription => 'Hearth 每天检查，并在其安装的应用未使用时安装更新';

  @override
  String get updatesFooter => '从各应用的 GitHub 发布版本安装。Hearth 安装或更新某个应用一次后，其更新会直接安装，无需询问，应用也会将更新交给 Hearth。';

  @override
  String get updatesChecking => '正在检查…';

  @override
  String get updatesInstall => '安装';

  @override
  String updatesUpdateTo(String version) {
    return '更新到 $version';
  }

  @override
  String get updatesUpToDate => '已是最新';

  @override
  String updatesDownloadingPercent(int percent) {
    return '正在下载 $percent%';
  }

  @override
  String get updatesInstalling => '正在安装…';

  @override
  String get updatesError => '错误';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutForkOf(String launcher, String author, String parts) {
    return '$author 的 $launcher 的分支，包含 $parts 的部分代码';
  }

  @override
  String get aboutDescription => '一款注重隐私、适合家庭的 Google TV 启动器，内置 Google TV 个人资料和 Home Assistant。无广告、无跟踪器。';

  @override
  String get aboutHearthOnGitHub => 'GitHub 上的 Hearth';

  @override
  String get aboutCredits => '致谢';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher 分支 · $author';
  }

  @override
  String get aboutLicense => '与其所基于的项目一样，是遵循 GNU GPL v3 的自由软件。';

  @override
  String get familyAppsStatusInstalled => '已安装';

  @override
  String get familyAppsStatusPartial => '部分安装';

  @override
  String get familyAppsStatusNotInstalled => '未安装';

  @override
  String get familyAppsStatusAtRisk => '有风险';

  @override
  String get familyAppsAtRiskDetail => '此个人资料下次启动时，Google TV 会移除这里未受保护的应用。请再次使用“添加”来保护它们。';

  @override
  String get profilePinRow => '个人资料 PIN';

  @override
  String get profilePinNone => '无';

  @override
  String get profilePinSaved => '已保存';

  @override
  String get profilePinRejected => '已保存 — 上次未被接受';

  @override
  String get profilePinPaused => '已保存 — 已暂停（应用已变化）';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth 暂时还无法在 $app 中输入 PIN';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$profile 在 $app 中的 PIN';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return '当 $app 要求时，Hearth 会在“正在登录”卡片后面输入。它加密保存在这台电视上，从不显示。';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return '请先设置家长 PIN（$settings → $profiles → $parentPin）：保存个人资料 PIN 需要它。';
  }

  @override
  String get profilePinSaveFailed => '无法保存 PIN。';

  @override
  String get profileLockNow => '锁定我的个人资料';

  @override
  String get profileLockNowSubtitle => '要回来，Google TV 会要求输入个人资料 PIN。按住个人资料按钮也可以。';

  @override
  String get profileLockOnSleep => '电视休眠时锁定';

  @override
  String get profileLockEveryTime => '每次';

  @override
  String profileLockAfterMinutes(int minutes) {
    return '休眠 $minutes 分钟后';
  }

  @override
  String get profileLockNeedsGoogleLock => '使用 Google TV 自带的个人资料锁：在 Google TV 设置 → 账号与登录 → 你的账号 → 个人资料锁 中为你的账号开启。';

  @override
  String get aboutWallpaperPhoto => '壁纸照片';
}
