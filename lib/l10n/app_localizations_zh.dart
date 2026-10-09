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
  String get systemSettings => '系统设置';

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
  String get blockAppNotifications => '屏蔽通知';

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
  String get temperatureUnit => '温度单位';

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
  String get openApp => '打开';

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
  String get remoteAndSearchTitle => '遥控器和搜索';

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
}
