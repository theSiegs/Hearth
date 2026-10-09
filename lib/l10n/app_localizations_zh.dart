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
}
