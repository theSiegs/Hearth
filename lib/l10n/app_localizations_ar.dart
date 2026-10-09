import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get aboutFlauncher => 'حول Hearth';

  @override
  String get addSection => 'إضافة قسم';

  @override
  String get alphabetical => 'أبجدي';

  @override
  String get appCardHighlightAnimation => 'رسوم متحركة لإبراز بطاقة التطبيق';

  @override
  String get appInfo => 'معلومات التطبيق';

  @override
  String get appKeyClick => 'صوت نقر عند الضغط على المفتاح';

  @override
  String get applications => 'التطبيقات';

  @override
  String get autoHideAppBar => 'إخفاء شريط الحالة تلقائياً';

  @override
  String get backButtonAction => 'إجراء زر الرجوع';

  @override
  String get category => 'فئة';

  @override
  String get columnCount => 'عدد الأعمدة';

  @override
  String get date => 'التاريخ';

  @override
  String get dateAndTimeFormat => 'تنسيق التاريخ والوقت';

  @override
  String get delete => 'حذف';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'عدم القيام بشيء';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'إظهار شاشة التوقف';

  @override
  String get dialogOptionBackButtonActionShowClock => 'إظهار الساعة';

  @override
  String get dialogTextNoFileExplorer => 'يرجى تثبيت مستكشف الملفات لاختيار صورة.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (فئة)';
  }

  @override
  String get gradient => 'تدرج لوني';

  @override
  String get favoriteApps => 'التطبيقات المفضلة';

  @override
  String get grid => 'شبكة';

  @override
  String get height => 'الارتفاع';

  @override
  String get hide => 'إخفاء';

  @override
  String get hiddenApplications => 'التطبيقات المخفية';

  @override
  String get launcherSections => 'الأقسام';

  @override
  String get layout => 'التخطيط';

  @override
  String get loading => 'جارٍ التحميل';

  @override
  String get manual => 'يدوي';

  @override
  String get modifySection => 'تعديل القسم';

  @override
  String get name => 'الاسم';

  @override
  String get newSection => 'قسم جديد';

  @override
  String get nonTvApplications => 'تطبيقات غير تلفزيونية';

  @override
  String get open => 'فتح';

  @override
  String get picture => 'صورة';

  @override
  String removeFrom(String name) {
    return 'إزالة من $name';
  }

  @override
  String get reorder => 'إعادة ترتيب';

  @override
  String get row => 'صف';

  @override
  String get rowHeight => 'ارتفاع الصف';

  @override
  String get save => 'حفظ';

  @override
  String get spacer => 'فاصل';

  @override
  String get statusBar => 'شريط الحالة';

  @override
  String get show => 'إظهار';

  @override
  String get showCategoryTitles => 'إظهار عناوين الفئات';

  @override
  String get showCategoryAppCount => 'إظهار عدد التطبيقات في الفئات';

  @override
  String get hideHighlightOutlineOnHomescreen => 'إخفاء مخطط التمييز على الشاشة الرئيسية';

  @override
  String get appSelectorTransitionAnimation => 'رسوم متحركة لانتقال محدد التطبيقات';

  @override
  String get sort => 'فرز';

  @override
  String get systemSettings => 'إعدادات النظام';

  @override
  String get textEmptyCategory => 'هذه الفئة فارغة.';

  @override
  String get time => 'الوقت';

  @override
  String get tvApplications => 'تطبيقات التلفزيون';

  @override
  String get type => 'النوع';

  @override
  String get uninstall => 'إلغاء التثبيت';

  @override
  String get wallpaper => 'خلفية';

  @override
  String get withEllipsisAddTo => 'إضافة إلى...';

  @override
  String get timeBasedWallpaper => 'خلفية تعتمد على الوقت';

  @override
  String get pickDayWallpaper => 'اختيار خلفية النهار';

  @override
  String get pickNightWallpaper => 'اختيار خلفية الليل';

  @override
  String get inputs => 'المدخلات';

  @override
  String get inputSources => 'مصادر الإدخال';

  @override
  String get backupAndRestore => 'النسخ الاحتياطي والاستعادة';

  @override
  String get exportBackup => 'تصدير النسخ الاحتياطي';

  @override
  String get importBackup => 'استيراد النسخ الاحتياطي';

  @override
  String exportSuccess(String path) {
    return 'تم تصدير النسخ الاحتياطي بنجاح إلى $path';
  }

  @override
  String get importSuccess => 'تم استيراد النسخ الاحتياطي بنجاح';

  @override
  String get importConfirm => 'هل أنت متأكد أنك تريد استيراد النسخ الاحتياطي؟ سيؤدي هذا إلى الكتابة فوق إعداداتك وتخطيطك الحاليين.';

  @override
  String importError(String error) {
    return 'فشل استيراد النسخ الاحتياطي: $error';
  }

  @override
  String exportError(String error) {
    return 'فشل تصدير النسخ الاحتياطي: $error';
  }

  @override
  String get shareBackup => 'مشاركة النسخ الاحتياطي';

  @override
  String get notificationBell => 'جرس الإشعارات';

  @override
  String get autoHideNotificationBell => 'إخفاء جرس الإشعارات تلقائياً';

  @override
  String get continueWatching => 'متابعة المشاهدة';

  @override
  String get showContinueWatchingOnHome => 'إظهار متابعة المشاهدة على الصفحة الرئيسية';

  @override
  String get permissionDeniedContinueWatching => 'الإذن مطلوب لإظهار متابعة المشاهدة';

  @override
  String get system => 'النظام';

  @override
  String get accentColor => 'لون التمييز';

  @override
  String get dataUsagePeriod => 'فترة استخدام البيانات';

  @override
  String get notificationAccess => 'الوصول إلى الإشعارات';

  @override
  String get watchNextAccess => 'الوصول إلى Watch Next';

  @override
  String get granted => 'مُمنوح';

  @override
  String get permissionRequired => 'الإذن مطلوب';

  @override
  String get systemWidePopupAlert => 'تنبيه منبثق على مستوى النظام';

  @override
  String get overlayPermissionRequired => 'إذن التراكب مطلوب';

  @override
  String get enabled => 'مفعّل';

  @override
  String get disabled => 'معطّل';

  @override
  String get showAppNamesBelowIcons => 'إظهار أسماء التطبيقات أسفل الأيقونات';

  @override
  String get dataUsage => 'استخدام البيانات';

  @override
  String get networkIndicator => 'مؤشر الشبكة';

  @override
  String get startOnBoot => 'التشغيل عند بدء الجهاز (Google TV / Fire TV)';

  @override
  String get appLanguage => 'اللغة';

  @override
  String get systemDefault => 'افتراضي النظام';

  @override
  String get english => 'الإنجليزية';

  @override
  String get spanish => 'الإسبانية';

  @override
  String get ukrainian => 'الأوكرانية';

  @override
  String get chinese => 'الصينية';

  @override
  String get french => 'الفرنسية';

  @override
  String get german => 'الألمانية';

  @override
  String get japanese => 'اليابانية';

  @override
  String get portuguese => 'البرتغالية';

  @override
  String get russian => 'الروسية';

  @override
  String get italian => 'الإيطالية';

  @override
  String get hindi => 'الهندية';

  @override
  String get korean => 'الكورية';

  @override
  String get arabic => 'العربية';

  @override
  String get turkish => 'التركية';

  @override
  String get hidePersistentNotifications => 'إخفاء الإشعارات الدائمة';

  @override
  String get blockedNotificationApps => 'التطبيقات المحظورة';

  @override
  String get blockAppNotifications => 'حظر الإشعارات';

  @override
  String get unblockAppNotifications => 'إلغاء حظر الإشعارات';

  @override
  String get noBlockedApps => 'لا توجد تطبيقات محظورة';

  @override
  String get persistentNotification => 'دائم';

  @override
  String get unblockAll => 'إلغاء حظر الكل';

  @override
  String get weather => 'الطقس';

  @override
  String get showWeatherWarnings => 'إظهار تحذيرات الطقس والأمطار';

  @override
  String get temperatureUnit => 'وحدة درجة الحرارة';

  @override
  String get celsius => 'مئوية (°C)';

  @override
  String get fahrenheit => 'فهرنهايت (°F)';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get continueWatchingDescription => 'عرض الأفلام والبرامج التلفزيونية التي تمت مشاهدتها مؤخرًا على الشاشة الرئيسية';

  @override
  String get dismiss => 'تجاهل';

  @override
  String get openApp => 'فتح';

  @override
  String get noBlockedAppsDesc => 'يُسمح لجميع التطبيقات حاليًا بإظهار الإشعارات';

  @override
  String get notificationsAllowed => 'الإشعارات مسموحة';

  @override
  String get notificationsBlocked => 'الإشعارات محظورة';

  @override
  String get dpadDismissHint => 'يسار: تجاهل • موافق: خيارات';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get profilesTitle => 'الملفات الشخصية';

  @override
  String get homeScreenTitle => 'الشاشة الرئيسية';

  @override
  String get remoteAndSearchTitle => 'جهاز التحكم والبحث';

  @override
  String get parentSettingsTitle => 'إعدادات الوالدين';

  @override
  String get tvPowerTitle => 'التلفزيون والطاقة';

  @override
  String get setupPermissionsTitle => 'الإعداد والأذونات';

  @override
  String get updatesTitle => 'التحديثات';

  @override
  String get familyAppsTitle => 'Hearth على الملفات الشخصية الأخرى';

  @override
  String get cardStyleTitle => 'نمط البطاقات';

  @override
  String get dockLabelsTitle => 'الشريط والتسميات';

  @override
  String get animationsSoundTitle => 'الحركات والصوت';

  @override
  String get haPanelTitle => 'لوحة المعلومات الجانبية';

  @override
  String get lookTitle => 'المظهر';

  @override
  String get remoteButtonsTitle => 'أزرار جهاز التحكم';

  @override
  String get profilePairingTitle => 'ربط الملفات الشخصية';

  @override
  String get haTvStatusTitle => 'حالة التلفزيون';

  @override
  String get continueWatchingAppsTitle => 'تطبيقات متابعة المشاهدة';

  @override
  String get cardSizeTitle => 'حجم البطاقة';

  @override
  String get maxItemsTitle => 'الحد الأقصى للعناصر';

  @override
  String get ok => 'حسنًا';

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get tryAgain => 'حاول مرة أخرى';

  @override
  String get notNow => 'ليس الآن';

  @override
  String get done => 'تم';

  @override
  String get remove => 'إزالة';

  @override
  String get homeNothingToWatch => 'لا يوجد ما يمكن مشاهدته الآن';

  @override
  String get errorScreenTitle => 'حدث خطأ ما';

  @override
  String get appInfoAddToCategory => 'إضافة إلى فئة';

  @override
  String get appInfoAddToFavorites => 'إضافة إلى المفضلة';

  @override
  String get appInfoRemoveFromFavorites => 'إزالة من المفضلة';

  @override
  String get appInfoSetCustomBanner => 'تعيين لافتة مخصصة';

  @override
  String get appInfoClearCustomBanner => 'إزالة اللافتة المخصصة';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'تعذّر تعيين اللافتة: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'تعذّرت إزالة اللافتة: $error';
  }

  @override
  String get cwGridAll => 'الكل';

  @override
  String get cwRowSeeAll => 'عرض الكل';

  @override
  String cwRowInProgress(int count) {
    return '$count قيد المشاهدة';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'متبقٍ $hours س $minutes د';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'متبقٍ $minutes د';
  }

  @override
  String get watchNextInfoRemove => 'إزالة من متابعة المشاهدة';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'إخفاء الكل من $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'تشغيل / استئناف';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'فتح $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'معلومات التطبيق';

  @override
  String get dataWidgetGrantPermission => 'منح إذن الاستخدام';

  @override
  String dataWidgetDaily(String usage) {
    return 'يوميًا: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'أسبوعيًا: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'شهريًا: $usage';
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
        'today': 'أمطار اليوم',
        'tomorrow': 'أمطار غدًا',
        'other': 'أمطار يوم $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'ثلوج اليوم',
        'tomorrow': 'ثلوج غدًا',
        'other': 'ثلوج يوم $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'عاصفة رعدية اليوم',
        'tomorrow': 'عاصفة رعدية غدًا',
        'other': 'عاصفة رعدية يوم $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$forecast بنسبة $percent%';
  }

  @override
  String searchWatchOn(String apps) {
    return 'شاهد على $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'استئجار أو شراء على $app';
  }

  @override
  String get searchMoreWaysToWatch => 'طرق أخرى للمشاهدة (Google TV)';

  @override
  String get searchListening => 'جارٍ الاستماع…';

  @override
  String get searchHint => 'ابحث عن أفلام ومسلسلات';

  @override
  String get searchEntryHelp => 'اكتب أو استخدم الميكروفون أو اكتب على هاتفك باستخدام تطبيق Google TV.';

  @override
  String get searchTabWatchNow => 'شاهد الآن';

  @override
  String get searchTabRentOrBuy => 'استئجار أو شراء';

  @override
  String get searchTabOtherApps => 'تطبيقات أخرى';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'استئجار أو شراء · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'أين تشاهد: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'على $services (غير متوفر على هذا التلفزيون)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نتيجة',
      many: '$count نتيجة',
      few: '$count نتائج',
      two: 'نتيجتان',
      one: 'نتيجة واحدة',
      zero: 'لا توجد نتائج',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'لا يوجد شيء هنا عن «$query».';
  }

  @override
  String get searchGridTmdbNotice => 'معلومات المشاهدة من TMDB (عبر JustWatch). يستخدم هذا المنتج واجهة TMDB البرمجية لكنه غير معتمد أو مصدّق من TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps أو $last';
  }

  @override
  String get searchListSeparator => '، ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'اسأل Google: «$query»';
  }

  @override
  String get searchAskGoogleDetail => 'للأسئلة والطقس وأي شيء آخر ليس برنامجًا';

  @override
  String searchSearchingFor(String query) {
    return 'جارٍ البحث عن «$query»…';
  }

  @override
  String get searchFailed => 'تعذّر البحث الآن. تحقق من الاتصال بالإنترنت.';

  @override
  String searchNothingFound(String query) {
    return 'لم يُعثر على شيء لـ «$query»';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'لا يوجد شيء لـ «$query» في تطبيقاتك الآن';
  }

  @override
  String get searchSeeMoreResults => 'اعرف أين يتوفر أيضًا في نتائج أخرى.';

  @override
  String get searchMoreResults => 'نتائج أخرى';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنوان',
      many: '$count عنوانًا',
      few: '$count عناوين',
      two: 'عنوانان',
      one: 'عنوان واحد',
      zero: 'لا توجد عناوين',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'اسأل Google';

  @override
  String searchQuoted(String query) {
    return '«$query»';
  }

  @override
  String get searchKindFilm => 'فيلم';

  @override
  String get searchKindSeries => 'مسلسل';

  @override
  String get gradientNamePitchBlack => 'أسود حالك';

  @override
  String get gradientNameGreatWhale => 'الحوت الكبير';

  @override
  String get gradientNameViciousStance => 'وقفة شرسة';

  @override
  String get gradientNameTeenNotebook => 'دفتر المراهقين';

  @override
  String get gradientNameOldHat => 'قبعة قديمة';

  @override
  String get gradientNameBurningSpring => 'ربيع متقد';

  @override
  String get gradientNameDesertHump => 'كثبان الصحراء';

  @override
  String get gradientNameFarawayRiver => 'نهر بعيد';

  @override
  String get gradientNameSaintPetersburg => 'سانت بطرسبرغ';

  @override
  String get gradientNameAfricanField => 'حقل أفريقي';

  @override
  String get gradientNameGrassShampoo => 'شامبو العشب';

  @override
  String get updateErrorNoApk => 'لا يوجد إصدار يحتوي على APK لهذا الجهاز';

  @override
  String get updateErrorCheckFailed => 'تعذّر التحقق من وجود تحديثات';

  @override
  String get updateErrorDownloadFailed => 'تعذّر تنزيل التحديث';

  @override
  String get serviceHearthTubeDescription => 'YouTube لـ Hearth؛ يتبع ملفك الشخصي في Hearth';

  @override
  String get haSummaryOn => 'مفعّل';

  @override
  String get haSummaryOff => 'متوقف';

  @override
  String get haSummaryReporting => 'يُرسل التقارير';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'فعّل إصلاح زر الرئيسية ($path)؛ فهو الذي يعرض النوافذ المنبثقة.';
  }

  @override
  String get haNotificationsShow => 'عرض إشعارات Home Assistant';

  @override
  String get haNotificationsSendTest => 'إرسال إشعار تجريبي';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'في Home Assistant، أضف تكامل \"Notifications for Android TV / Fire TV\" مع المضيف $host. ثم أرسل إليه الإشعارات من الأتمتة، مثلًا لجرس الباب أو عند انتهاء الغسيل.\n\nيمكن فقط للأجهزة الموجودة على شبكتك المنزلية إرسالها (المنفذ 7676). تظهر النوافذ المنبثقة فوق أي تطبيق وتتطلب تفعيل إصلاح زر الرئيسية ($path).';
  }

  @override
  String get haNotificationsThisTvIp => '(عنوان IP لهذا التلفزيون)';

  @override
  String get haPanelSaved => 'تم الحفظ';

  @override
  String get haPanelSavedNoToken => 'تم الحفظ. أضف رمز وصول لتسجيل الدخول.';

  @override
  String get haPanelReceived => 'تم استلام العنوان والرمز من هاتفك';

  @override
  String get haPanelRightEdge => 'الضغط على اليمين عند الحافة اليمنى يفتح اللوحة';

  @override
  String get haSetUpFromPhone => 'الإعداد من هاتفك';

  @override
  String get haPanelTokenLabel => 'رمز وصول طويل الأمد';

  @override
  String get haPanelTokenSavedHint => 'محفوظ (اكتب رمزًا جديدًا لاستبداله)';

  @override
  String get haPanelDashboardLabel => 'لوحة المعلومات';

  @override
  String haPanelHelp(String tvStatus) {
    return 'مفعّل لهذا الملف الشخصي فقط. تعرض اللوحة لوحة معلومات من العنوان المحدد في $tvStatus، مع تسجيل الدخول بالرمز. أنشئ الرمز في Home Assistant أثناء تسجيل الدخول بمستخدم غير مسؤول مخصص لهذا التلفزيون (صفحة الملف الشخصي، علامة تبويب الأمان).';
  }

  @override
  String get haStatusReportingOff => 'إرسال الحالة متوقف';

  @override
  String get haStatusSaved => 'تم الحفظ: يتم الإرسال إلى Home Assistant';

  @override
  String get haStatusAddressLabel => 'عنوان Home Assistant';

  @override
  String get haStatusWebhookLabel => 'معرّف Webhook';

  @override
  String get haStatusNowPlayingOn => 'قيد التشغيل الآن: مفعّل';

  @override
  String get haStatusNowPlayingOff => 'قيد التشغيل الآن: فعّل الوصول إلى الإشعارات';

  @override
  String get haStatusHelp => 'يرسل التلفزيون إلى Home Assistant ما يُعرض: التطبيق، وما يُشغَّل، وملف Google TV الشخصي، ووقت شاشة الأطفال. ولا يرسل إلا إلى العنوان أعلاه، عند حدوث التغييرات.';

  @override
  String get haPhoneSetupNoNetwork => 'هذا التلفزيون غير متصل بالشبكة المنزلية، لذا لا يمكن للهاتف الوصول إليه.';

  @override
  String get haPhoneSetupScan => 'امسح الرمز بهاتف متصل بشبكة Wi-Fi نفسها، والصق عنوان Home Assistant ورمز الوصول، ثم اضغط Send. تعمل الصفحة فقط ما دامت هذه النافذة مفتوحة.';

  @override
  String get profilesSwitchProfile => 'تبديل الملف الشخصي';

  @override
  String get parentPinTitle => 'رمز PIN للوالدين';

  @override
  String get parentPinOn => 'مفعّل';

  @override
  String get parentPinOff => 'متوقف';

  @override
  String get parentPinCurrent => 'رمز PIN الحالي للوالدين';

  @override
  String get parentPinRemove => 'إزالة رمز PIN';

  @override
  String get parentPinChange => 'تغيير رمز PIN';

  @override
  String get parentPinNew => 'رمز PIN جديد للوالدين';

  @override
  String get parentPinNewSubtitle => 'مطلوب لتغيير المشغّل في الملفات الشخصية للأطفال على Google TV';

  @override
  String get parentPinConfirm => 'أدخل رمز PIN مرة أخرى';

  @override
  String get parentPinAskTitle => 'اطلب من أحد الوالدين';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'إعدادات المشغّل مقفلة في الملفات الشخصية للأطفال. يمكن لأحد الوالدين تعيين رمز PIN من $settings ← $profiles ← $parentPin من ملفه الشخصي.';
  }

  @override
  String get parentPinKidsSubtitle => 'ملف شخصي للأطفال: أدخل رمز PIN للوالدين لتغيير المشغّل';

  @override
  String get parentPinWrong => 'رمز PIN خاطئ';

  @override
  String get parentPinEnter => 'أدخل رمز PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'مرحبًا، $name';
  }

  @override
  String get profileSwitchSettingUp => 'جارٍ إعداد هذا الملف الشخصي…';

  @override
  String profilesKidsName(String name) {
    return '$name (أطفال)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (بالغ)';
  }

  @override
  String get pairingShowPicker => 'عرض أداة الاختيار';

  @override
  String get pairingAlwaysShowPicker => 'عرض أداة الاختيار دائمًا';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (مطابقة بالاسم)';
  }

  @override
  String get pairingNoMatchYet => 'لا توجد مطابقة بعد: تظهر أداة الاختيار';

  @override
  String get pairingOffSetUp => 'ربط الملفات الشخصية متوقف. اضبطه الآن';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'عندما يفتح Hearth أحد هذه التطبيقات، يختار ملف التطبيق الشخصي المرتبط بملف Google TV الشخصي. يطابق Hearth الأسماء تلقائيًا (\"$shortName\" يتوافق مع \"$fullName\")؛ ويمكنك تغيير أي ربط هنا. إذا لم توجد مطابقة، تظهر أداة الاختيار الخاصة بالتطبيق.';
  }

  @override
  String get pairingAppNotInstalled => 'غير مثبّت';

  @override
  String get pairingAppOff => 'متوقف: تظهر أداة الاختيار الخاصة بالتطبيق';

  @override
  String get pairingAppNotSeen => 'افتحه مرة واحدة من Hearth حتى يتعرّف Hearth على ملفاته الشخصية';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم العثور على $count ملف شخصي',
      many: 'تم العثور على $count ملفًا شخصيًا',
      few: 'تم العثور على $count ملفات شخصية',
      two: 'تم العثور على ملفين شخصيين',
      one: 'تم العثور على ملف شخصي واحد',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'المطابقة بالاسم ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'المطابقة بالاسم (لا توجد مطابقة بعد)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile في $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'ربط الملفات الشخصية في $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'لم يتعرّف Hearth على الملفات الشخصية لهذا التطبيق بعد. افتحه مرة واحدة من Hearth، ثم عُد إلى هنا.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'الملفات الشخصية في هذا التطبيق: $profiles. تظهر ملفات Google TV الشخصية هنا بعد أن يتعرّف عليها Hearth.';
  }

  @override
  String get familyAppsIntro => 'ثبّت Hearth وHearthTube على ملفات Google TV الشخصية الأخرى. على ملفات الأطفال، هذا ضروري ليعمل HearthTube وليختار Hearth الملف الشخصي الصحيح في Netflix وDisney+ وتطبيقات أخرى. أما على ملفات البالغين فهو للراحة فقط، كي لا يضطروا إلى تثبيتهما يدويًا.';

  @override
  String get familyAppsAddTitle => 'إضافة Hearth إلى الملفات الشخصية الأخرى';

  @override
  String get familyAppsAddKids => 'يثبّت هذا Hearth وHearthTube على ملفات أطفالك الشخصية، ليعمل HearthTube هناك ويتمكن Hearth من اختيار الملف الشخصي الصحيح في تطبيقات مثل Netflix وDisney+.';

  @override
  String get familyAppsAddAdults => 'ويثبّتهما أيضًا على ملفات البالغين الأخرى على التلفزيون، كي لا يضطر أي بالغ آخر إلى إعداده بنفسه.';

  @override
  String get familyAppsAddOnlyOwnApps => 'يضيف فقط تطبيقَي Hearth، ويمكنك التراجع عن ذلك في أي وقت عبر \"إزالة\" أدناه.';

  @override
  String get familyAppsAddFamilyLink => 'سيتلقى كل طفل إشعارًا واحدًا من Family Link بأنه \"تمت إضافة تطبيق\".';

  @override
  String get familyAppsAddApproval => 'في المرة الأولى، يسأل التلفزيون \"هل تريد السماح بتصحيح الأخطاء؟\" — اختر \"السماح دائمًا\"؛ فهذا ما يتيح لـ Hearth إجراء الإعداد.';

  @override
  String get familyAppsAdd => 'إضافة';

  @override
  String get familyAppsRemoveTitle => 'إزالة Hearth من الملفات الشخصية الأخرى';

  @override
  String get familyAppsRemoveBody => 'يزيل هذا Hearth وHearthTube من ملفاتك الشخصية الأخرى.';

  @override
  String get familyAppsRemoveFirst => 'إذا كنت تنوي إلغاء تثبيت Hearth نفسه، فنفّذ هذا أولًا — وإلا فقد تبقى نسخه على ملفات الأطفال عالقة وتحتاج إلى كمبيوتر لإزالتها.';

  @override
  String get familyAppsUninstallTitle => 'إلغاء تثبيت Hearth';

  @override
  String get familyAppsUninstallBody => 'يزيل هذا أولًا Hearth وHearthTube من ملفاتك الشخصية الأخرى، ثم يلغي تثبيت Hearth من هذا الملف.';

  @override
  String get familyAppsUninstallWhyHere => 'إلغاء التثبيت من هنا — بدلًا من إعدادات Android — يضمن عدم بقاء أي شيء على ملفات الأطفال.';

  @override
  String get familyAppsApprovalFirstTitle => 'أكمل الموافقة لمرة واحدة أولًا';

  @override
  String get familyAppsApprovalFirstBody => 'تعذّر على Hearth تنظيف الملفات الشخصية الأخرى بعد — فهو يحتاج إلى الموافقة لمرة واحدة على \"هل تريد السماح بتصحيح الأخطاء؟\" على التلفزيون.';

  @override
  String get familyAppsApprovalFirstRetry => 'وافق عليها، ثم جرّب إلغاء التثبيت مرة أخرى، حتى لا يبقى شيء على ملفات الأطفال.';

  @override
  String get familyAppsAddDone => 'اكتملت الإضافة';

  @override
  String get familyAppsRemoveDone => 'اكتملت الإزالة';

  @override
  String get familyAppsAdded => 'تم. أصبح Hearth وHearthTube الآن على ملفاتك الشخصية الأخرى — راجع القائمة أدناه.';

  @override
  String get familyAppsRemoved => 'تم. أُزيل Hearth وHearthTube من ملفاتك الشخصية الأخرى.';

  @override
  String get familyAppsNothingToSetUp => 'لا توجد ملفات شخصية أخرى لإعدادها بعد.';

  @override
  String get familyAppsFailedTitle => 'تعذّر إعداد الملفات الشخصية';

  @override
  String get familyAppsFailedBody => 'يحتاج Hearth إلى موافقة لمرة واحدة على التلفزيون قبل أن يتمكن من إعداد الملفات الشخصية الأخرى.';

  @override
  String get familyAppsFailedRetry => 'على التلفزيون، اختر \"السماح دائمًا\" عندما يسأل \"هل تريد السماح بتصحيح الأخطاء؟\"، ثم حاول مرة أخرى.';

  @override
  String get familyAppsAlsoAdults => 'إعداد ملفات البالغين الأخرى أيضًا';

  @override
  String get familyAppsOn => 'مفعّل';

  @override
  String get familyAppsOff => 'متوقف';

  @override
  String get familyAppsNoneYet => 'لم يتم إعداد ملفات شخصية أخرى بعد.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: مثبّت';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: مثبّت، محمي';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: غير مثبّت';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: غير مثبّت، محمي';
  }

  @override
  String get familyAppsUnnamedKids => 'ملف شخصي للأطفال';

  @override
  String get familyAppsUnnamedAdult => 'ملف شخصي لبالغ';
}
