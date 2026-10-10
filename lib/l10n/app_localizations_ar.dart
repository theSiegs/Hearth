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
  String get systemSettings => 'إعدادات Google TV';

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
  String get remoteAndSearchTitle => 'جهاز التحكم';

  @override
  String get parentSettingsTitle => 'إعدادات الوالدين';

  @override
  String get tvPowerTitle => 'التلفزيون والطاقة';

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
  String get familyAppsAddTitle => 'إضافة Hearth إلى الملفات الشخصية الأخرى';

  @override
  String get familyAppsAddKids => 'يثبّت هذا Hearth وHearthTube على ملفات أطفالك الشخصية، ليعمل HearthTube هناك ويتمكن Hearth من اختيار الملف الشخصي الصحيح في خدمات البث.';

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

  @override
  String setupAccessibilityInstructions(String service) {
    return 'في الشاشة التالية، مرّر لأسفل إلى \"الخدمات\"، واختر \"$service\"، ثم فعّل \"تفعيل\" وأكّد. اضغط \"رجوع\" حتى تعود إلى الشاشة الرئيسية.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'إذا قال Android إن الإعداد مقيّد، فشغّل هذا مرة واحدة من كمبيوتر:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth كتطبيق رئيسي';

  @override
  String get setupDefaultLauncherWhy => 'يمنع ملفات الأطفال الشخصية من حظر Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'في الشاشة التالية، اختر Hearth.';

  @override
  String get setupHomeFixTitle => 'إصلاح زر الرئيسية';

  @override
  String get setupHomeFixWhy => 'يفتح زر الرئيسية Hearth بدلًا من Google TV.';

  @override
  String get setupNotificationsTitle => 'الوصول إلى الإشعارات';

  @override
  String get setupNotificationsWhy => 'يعرض الإشعارات وما يُشغَّل الآن.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'في الشاشة التالية، اختر \"$service\" واسمح به.';
  }

  @override
  String get setupInstallTitle => 'تثبيت التحديثات';

  @override
  String get setupInstallWhy => 'يتيح لـ Hearth تحديث نفسه وتثبيت التطبيقات المرافقة.';

  @override
  String get setupInstallInstructions => 'في الشاشة التالية، فعّل Hearth.';

  @override
  String get setupPairingWhy => 'يختار ملفك الشخصي في Netflix وDisney+ وApple TV وHBO Max وParamount+.';

  @override
  String get setupVoiceTitle => 'صوت Hearth';

  @override
  String get setupVoiceWhy => 'يتيح لربط الملفات الشخصية سماع شاشة الملفات الشخصية في Netflix. تحتفظ التطبيقات الأخرى بصوت Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'في الشاشة التالية، ضمن \"المحرك المفضل\"، اختر \"$engine\"، ثم \"حسنًا\" في التحذير (لا يستمع Hearth إلا إلى تطبيقات البث). اضغط \"رجوع\" للعودة.';
  }

  @override
  String get setupOpenSettings => 'فتح الإعدادات';

  @override
  String get setupAdbFallback => 'لم يفتح هذا التلفزيون شاشة الإعدادات تلك. شغّل هذا مرة واحدة من كمبيوتر بدلًا من ذلك:';

  @override
  String setupProgress(int done, int total) {
    return 'تم $done من $total';
  }

  @override
  String get remoteButtonsRemapButton => 'إعادة تعيين زر';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'الزر $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'عادي';

  @override
  String get remoteButtonsCaptureTitle => 'اضغط زرًا في جهاز التحكم';

  @override
  String get remoteButtonsCaptureBody => 'اضغط الزر الذي تريد إعادة تعيينه. اضغط \"رجوع\" للإلغاء.';

  @override
  String get remoteButtonsNeedsFixTitle => 'فعّل إصلاح زر الرئيسية أولًا';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'تتطلب إعادة التعيين إصلاح زر الرئيسية ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'لا يمكن إعادة تعيين هذا الزر';

  @override
  String get remoteButtonsCantRemapBody => 'تحتفظ الأسهم و\"حسنًا\" و\"رجوع\" و\"الرئيسية\" وزر التشغيل بوظائفها المعتادة.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'ضغط: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'ضغط مطوّل: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'ضغطة لبحث Hearth، وضغط مطوّل لـ Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'على شاشة Hearth الرئيسية فقط: مفعّل';

  @override
  String get remoteButtonsHomeOnlyOff => 'على شاشة Hearth الرئيسية فقط: متوقف';

  @override
  String get remoteButtonsRestore => 'استعادة الزر العادي';

  @override
  String get remoteButtonsActionTitle => 'الإجراء';

  @override
  String get remoteButtonsActionApp => 'فتح تطبيق…';

  @override
  String get remoteButtonsActionInput => 'التبديل إلى مدخل تلفزيون…';

  @override
  String get remoteButtonsActionSwitchProfile => 'تبديل الملف الشخصي (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'بحث Hearth (صوتي)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'بحث Hearth (لوحة المفاتيح)';

  @override
  String get remoteButtonsActionHome => 'شاشة Hearth الرئيسية';

  @override
  String get remoteButtonsActionSleep => 'سكون';

  @override
  String get remoteButtonsActionAndroidSettings => 'إعدادات Android';

  @override
  String get remoteButtonsPickAppTitle => 'فتح تطبيق';

  @override
  String get remoteButtonsPickInputTitle => 'التبديل إلى مدخل تلفزيون';

  @override
  String get remoteButtonsHaConnectTitle => 'اربط Home Assistant أولًا';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'اضبط لوحة Home Assistant ($panel > $row)، ثم حاول مرة أخرى.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'مشهد: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'تشغيل: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'ضغط: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'تبديل: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nضغط: $press  ·  ضغط مطوّل: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nضغط: $press  ·  ضغط مطوّل: $hold  ·  الشاشة الرئيسية فقط';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'يتطلب إصلاح زر الرئيسية ($path). الزر الذي له إجراء ضغط مطوّل فقط ينفّذ هذا الإجراء عند الضغط العادي أيضًا. يفتح بحث Hearth بحث HearthTube نفسه عندما يكون HearthTube في المقدمة. تتوقف إعادة التعيين مؤقتًا أثناء ظهور شاشة وقت الشاشة للأطفال.';
  }

  @override
  String get tvPowerScreensaver => 'شاشة التوقف (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'يستخدم Hearth شاشة توقف Google TV. اختر هناك Google Photos (والألبومات التي تريدها) أو مصدرًا آخر.';

  @override
  String get tvPowerSleepWhenIdle => 'السكون عند عدم النشاط';

  @override
  String get tvPowerSleepOff => 'متوقف';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes دقيقة';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ساعة',
      many: '$hours ساعة',
      few: '$hours ساعات',
      two: 'ساعتان',
      one: 'ساعة واحدة',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'يُحتسب تشغيل الفيديو أو الموسيقى نشاطًا. يتطلب إصلاح زر الرئيسية ($path).';
  }

  @override
  String get accentPurple => 'أرجواني';

  @override
  String get accentTeal => 'أزرق مخضر';

  @override
  String get accentBlue => 'أزرق';

  @override
  String get accentOrange => 'برتقالي';

  @override
  String get accentPink => 'وردي';

  @override
  String get accentGreen => 'أخضر';

  @override
  String get accentWhite => 'أبيض';

  @override
  String get accentYellow => 'أصفر';

  @override
  String get accentRed => 'أحمر';

  @override
  String get accentCyan => 'سماوي';

  @override
  String get accentIndigo => 'نيلي';

  @override
  String get accentLime => 'ليموني';

  @override
  String get accentAmber => 'كهرماني';

  @override
  String get accentRose => 'وردي فاتح';

  @override
  String get accentIceBlue => 'أزرق جليدي';

  @override
  String get accentSelected => 'اللون المميز المحدد';

  @override
  String get cardStyleDefault => 'افتراضي';

  @override
  String get cardStylePremium => 'مميز';

  @override
  String get cardStyleGlow => 'توهج';

  @override
  String get cardStyleSquircle => 'مربع منحني';

  @override
  String get cardStyleClassic => 'كلاسيكي';

  @override
  String get cardStyleMinimal => 'بسيط';

  @override
  String get cardStyleCapsule => 'كبسولة';

  @override
  String get dockFavoritesDock => 'شريط المفضلة';

  @override
  String get dockFavoritesDockDescription => 'يعرض المفضلة كشريط أسفل الشاشة الرئيسية، مع متابعة المشاهدة فوقه وأقسامك الأخرى أسفله. تتبع زواياه نمط البطاقات.';

  @override
  String get dockFrosted => 'شريط بتأثير زجاجي';

  @override
  String get dockDark => 'شريط داكن';

  @override
  String get dockShadow => 'ظل الشريط';

  @override
  String get dockBlurWallpaperBelow => 'تمويه الخلفية أسفل الشريط';

  @override
  String get wallpaperMatchSelectedApp => 'مطابقة التطبيق المحدد';

  @override
  String get wallpaperBingPhotoOfTheDay => 'صورة اليوم من Bing';

  @override
  String get wallpaperRefreshNow => 'تحديث الآن';

  @override
  String get wallpaperBingError => 'تعذّر الوصول إلى Bing. تحقق من اتصال الشبكة.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'وحدة درجة الحرارة: $unit';
  }

  @override
  String get weatherLocationNotSet => 'موقع الطقس: غير محدد';

  @override
  String weatherLocationValue(String place) {
    return 'موقع الطقس: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'تعذّر تحميل الطقس. ستتم إعادة المحاولة تلقائيًا.';

  @override
  String get statusBarWeatherSourceHint => 'اختر موقعًا للطقس أعلاه (الطقس من Open-Meteo، مجاني وبدون حساب). بدونه، يأتي الطقس من تطبيق Breezy Weather إذا كان مثبتًا مع تفعيل المشاركة عبر Gadgetbridge.';

  @override
  String get weatherLocationTitle => 'موقع الطقس';

  @override
  String get weatherLocationHint => 'مدينة أو بلدة';

  @override
  String get weatherLocationNoResults => 'لم يتم العثور على أماكن';

  @override
  String get weatherLocationSearchError => 'تعذّر الوصول إلى خدمة الطقس. تحقق من اتصال الشبكة.';

  @override
  String get weatherLocationPrivacyNote => 'الطقس من Open-Meteo.com: مجاني وبدون حساب. تُرسل إحداثيات المكان المختار فقط.';

  @override
  String get weatherLocationSearch => 'بحث';

  @override
  String get dateTimeInvalidFormat => 'تنسيق غير صالح';

  @override
  String get dateTimeSelectFormats => 'اختر التنسيقات أدناه';

  @override
  String get dataUsageDaily => 'يومي';

  @override
  String get dataUsageWeekly => 'أسبوعي';

  @override
  String get dataUsageMonthly => 'شهري';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'محظورة من متابعة المشاهدة ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'محظور من متابعة المشاهدة';

  @override
  String get cwAppsUnblock => 'إلغاء الحظر';

  @override
  String get cwAppsUnblockAllApps => 'إلغاء حظر كل التطبيقات';

  @override
  String get cwAppsNoBlockedApps => 'لا توجد تطبيقات محظورة';

  @override
  String get cwAppsNoBlockedAppsMessage => 'يمكن لكل التطبيقات المدعومة عرض عناصر في متابعة المشاهدة.';

  @override
  String get cwAppsWithContinueWatching => 'التطبيقات التي تدعم متابعة المشاهدة';

  @override
  String get cwAppsWithContinueWatchingHint => 'التطبيقات التي توفر حاليًا عناصر Watch Next على شاشتك الرئيسية';

  @override
  String get cwAppsNoActiveApps => 'لا توجد تطبيقات توفر حاليًا عناصر متابعة المشاهدة.\nعندما تضيف التطبيقات المدعومة (مثل SmartTube أو خدمات البث) عناصر، ستظهر هنا.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر نشط',
      many: '$count عنصرًا نشطًا',
      few: '$count عناصر نشطة',
      two: 'عنصران نشطان',
      one: 'عنصر نشط واحد',
      zero: 'لا توجد عناصر نشطة',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'كل التطبيقات المثبتة';

  @override
  String get cwAppsAllInstalledAppsHint => 'أوقف التبديل لمنع أي تطبيق من إضافة عناصر إلى متابعة المشاهدة';

  @override
  String get cwAppsBlocked => 'محظور';

  @override
  String get cwAppsAllowed => 'مسموح';

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
  String get cwCardSizeExtraSmall => 'صغير للغاية';

  @override
  String get cwCardSizeVerySmall => 'صغير جدًا';

  @override
  String get cwCardSizeSmall => 'صغير';

  @override
  String get cwCardSizeCompact => 'مدمج';

  @override
  String get cwCardSizeMediumSmall => 'متوسط صغير';

  @override
  String get cwCardSizeMedium => 'متوسط';

  @override
  String get cwCardSizeStandardDefault => 'قياسي (افتراضي)';

  @override
  String get cwCardSizeStandard => 'قياسي';

  @override
  String get cwCardSizeMediumLarge => 'متوسط كبير';

  @override
  String get cwCardSizeLarge => 'كبير';

  @override
  String get cwCardSizeVeryLarge => 'كبير جدًا';

  @override
  String get cwCardSizeExtraLarge => 'كبير للغاية';

  @override
  String get cwCardSizeHuge => 'ضخم';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'عرض حتى $count عنصر حديث',
      many: 'عرض حتى $count عنصرًا حديثًا',
      few: 'عرض حتى $count عناصر حديثة',
      two: 'عرض عنصرين حديثين كحد أقصى',
      one: 'عرض عنصر حديث واحد كحد أقصى',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • افتراضي';
  }

  @override
  String get cwUnlimited => 'غير محدود';

  @override
  String get cwMaxItemsAll => 'عرض كل العناصر المتاحة';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'شريط تقدم التشغيل';

  @override
  String get cwPlaybackPercentage => 'نسبة التشغيل';

  @override
  String get cwEpisodeDetails => 'تفاصيل الحلقة والفيديو';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تطبيق محظور',
      many: '$count تطبيقًا محظورًا',
      few: '$count تطبيقات محظورة',
      two: 'تطبيقان محظوران',
      one: 'تطبيق محظور واحد',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'إدارة';

  @override
  String get cwRestoreHiddenPrograms => 'استعادة البرامج المخفية';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count برنامج مخفي',
      many: '$count برنامجًا مخفيًا',
      few: '$count برامج مخفية',
      two: 'برنامجان مخفيان',
      one: 'برنامج مخفي واحد',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'تمت استعادة كل البرامج المخفية';

  @override
  String get cwWatchNextAdbTitle => 'الوصول إلى Watch Next (يتطلب ADB)';

  @override
  String get cwWatchNextAdbMessage => 'يتطلب Android TV إذن READ_WRITE_WATCH_NEXT_PROGRAMS لكي تقرأ المشغّلات صفوف متابعة المشاهدة من التطبيقات المثبتة وتعرضها.\n\nلمنح هذا الإذن، وصّل التلفزيون عبر ADB وشغّل:';

  @override
  String get appsNoApplicationsFound => 'لم يتم العثور على تطبيقات';

  @override
  String get appDetailsAddToFavorites => 'إضافة إلى المفضلة';

  @override
  String get appDetailsRemoveFromFavorites => 'إزالة من المفضلة';

  @override
  String get appDetailsAddToCategory => 'إضافة إلى فئة';

  @override
  String get sectionsCustomOption => 'مخصص...';

  @override
  String get sectionsSelectName => 'اختر اسمًا';

  @override
  String get sectionsCustomName => 'اسم مخصص';

  @override
  String get sectionsSortLastUsed => 'آخر استخدام';

  @override
  String get sectionsReorderHint => 'حدّد باستخدام ◄ / ► ثم استخدم ▲ / ▼ لإعادة الترتيب';

  @override
  String get inputsNoneDetected => 'لم يتم اكتشاف مصادر إدخال';

  @override
  String get notifClearAll => 'مسح الكل';

  @override
  String get notifAllCaughtUp => 'لا توجد إشعارات جديدة';

  @override
  String notifBlockAppNotifications(String app) {
    return 'حظر الإشعارات ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'فتح $app';
  }

  @override
  String get notifAccessAdbTitle => 'الوصول إلى الإشعارات (يتطلب ADB)';

  @override
  String get notifAccessAdbMessage => 'لا يوفر Android TV شاشة إعدادات نظام لـ\"الوصول إلى الإشعارات\" (الاستماع إلى إشعارات التطبيقات الأخرى).\n\nملاحظة: تفعيل \"إظهار الإشعارات\" في إعدادات تطبيقات التلفزيون يتحكم فقط في الإشعارات الصادرة من هذا التطبيق، وليس في الوصول إلى الإشعارات.\n\nلمنح الوصول إلى الإشعارات، وصّل التلفزيون عبر ADB وشغّل:';

  @override
  String get notifOpenAppInfo => 'فتح معلومات التطبيق';

  @override
  String get notifOverlayPermissionTitle => 'إذن التراكب';

  @override
  String get notifOverlayAdbMessage => 'تعذّر فتح شاشة إعدادات إذن التراكب تلقائيًا على هذا الجهاز.\n\nلتفعيل النوافذ المنبثقة، امنح الإذن يدويًا عبر ADB من كمبيوتر متصل بالتلفزيون:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'التطبيقات المحظورة ($count)';
  }

  @override
  String get backupShareText => 'نسخة Hearth الاحتياطية';

  @override
  String get backupShareFailedTitle => 'فشلت المشاركة';

  @override
  String backupShareFailed(String error) {
    return 'فشلت مشاركة النسخ الاحتياطي: $error';
  }

  @override
  String get backupExportSuccessTitle => 'نجح التصدير';

  @override
  String get backupExportFailedTitle => 'فشل التصدير';

  @override
  String get backupImportSuccessTitle => 'نجح الاستيراد';

  @override
  String get backupImportFailedTitle => 'فشل الاستيراد';

  @override
  String get backupImport => 'استيراد';

  @override
  String backupLoadError(String error) {
    return 'خطأ في تحميل النسخ الاحتياطية: $error';
  }

  @override
  String get backupNoFiles => 'لم يتم العثور على ملفات نسخ احتياطي.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date ($size)';
  }

  @override
  String backupSizeBytes(String size) {
    return '$size بايت';
  }

  @override
  String backupSizeKilobytes(String size) {
    return '$size كيلوبايت';
  }

  @override
  String backupSizeMegabytes(String size) {
    return '$size ميغابايت';
  }

  @override
  String get updateCheckForUpdatesTitle => 'التحقق من التحديثات';

  @override
  String updateCurrentVersion(String version) {
    return 'الإصدار الحالي: $version';
  }

  @override
  String get updateChecking => 'جارٍ البحث عن إصدار جديد على GitHub…';

  @override
  String get updateUpToDate => 'أنت تستخدم أحدث إصدار.';

  @override
  String updateVersionAvailable(String version) {
    return 'الإصدار $version متاح';
  }

  @override
  String updateDownloading(String percent) {
    return 'جارٍ التنزيل… $percent%';
  }

  @override
  String get updateDownloadedHint => 'تم التنزيل. إذا لم يُفتح المثبّت، فقد يحتاج جهازك إلى\nمنح Hearth إذن \"تثبيت التطبيقات غير المعروفة\".';

  @override
  String get updateSomethingWentWrong => 'حدث خطأ ما';

  @override
  String get updateDownloadAndInstall => 'تنزيل وتثبيت';

  @override
  String get updateRetryInstall => 'إعادة محاولة التثبيت';

  @override
  String get updateCheckAgain => 'التحقق مجددًا';

  @override
  String get updatesInstallPermissionTitle => 'السماح لـ Hearth بتثبيت التطبيقات';

  @override
  String get updatesInstallPermissionMessage => 'في الشاشة التالية، ابحث عن Hearth وفعّله، ثم اضغط رجوع. سيستمر التثبيت عند عودتك إلى هنا.';

  @override
  String get updatesOpenSettings => 'فتح الإعدادات';

  @override
  String get updatesCheckFailed => 'تعذّر التحقق من التحديثات';

  @override
  String get updatesInstallerNotStarted => 'لم يبدأ المثبّت';

  @override
  String get updatesCheckForUpdates => 'التحقق من التحديثات';

  @override
  String get updatesAutoUpdate => 'التحديث تلقائيًا';

  @override
  String get updatesAutoUpdateDescription => 'يتحقق Hearth يوميًا ويثبّت تحديثات التطبيقات التي ثبّتها، عندما لا تكون قيد الاستخدام';

  @override
  String get updatesIncludePrereleases => 'تضمين الإصدارات التجريبية';

  @override
  String get updatesIncludePrereleasesDescription => 'إصدارات اختبار مبكرة من Hearth وHearthTube. قد تكون غير مكتملة.';

  @override
  String get updatesFooter => 'تُثبَّت من إصدارات GitHub لكل تطبيق. بعد أن يثبّت Hearth تطبيقًا أو يحدّثه مرة واحدة، تُثبَّت تحديثاته دون سؤال، ويترك التطبيق التحديث لـ Hearth.';

  @override
  String get updatesChecking => 'جارٍ التحقق…';

  @override
  String get updatesInstall => 'تثبيت';

  @override
  String updatesUpdateTo(String version) {
    return 'التحديث إلى $version';
  }

  @override
  String get updatesUpToDate => 'محدّث';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'جارٍ التنزيل $percent%';
  }

  @override
  String get updatesInstalling => 'جارٍ التثبيت…';

  @override
  String get updatesError => 'خطأ';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'مبني على $launcher من $author و$original، مع أجزاء من $parts';
  }

  @override
  String get aboutDescription => 'مشغّل خاص ومناسب للعائلة لـ Google TV، مع ملفات Google TV الشخصية وHome Assistant مدمجة. بلا إعلانات وبلا تتبع.';

  @override
  String get aboutHearthOnGitHub => 'Hearth على GitHub';

  @override
  String get aboutCredits => 'شكر وتقدير';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'نسخة متفرعة من FLauncher · $author';
  }

  @override
  String get aboutLicense => 'برنامج حر بموجب رخصة GNU GPL v3، مثل المشاريع التي يعتمد عليها.';

  @override
  String get familyAppsStatusInstalled => 'مثبّت';

  @override
  String get familyAppsStatusPartial => 'جزئي';

  @override
  String get familyAppsStatusNotInstalled => 'غير مثبّت';

  @override
  String get familyAppsStatusAtRisk => 'معرّض للخطر';

  @override
  String get familyAppsAtRiskDetail => 'سيزيل Google TV التطبيقات غير المحمية هنا عند بدء هذا الملف الشخصي في المرة القادمة. استخدم \"إضافة\" مرة أخرى لحمايتها.';

  @override
  String get profilePinRow => 'رمز PIN للملف الشخصي';

  @override
  String get profilePinNone => 'لا يوجد';

  @override
  String get profilePinSaved => 'محفوظ';

  @override
  String get profilePinRejected => 'محفوظ — لم يُقبل في المرة الأخيرة';

  @override
  String get profilePinPaused => 'محفوظ — متوقف مؤقتًا (تغيّر التطبيق)';

  @override
  String profilePinUnsupported(String app) {
    return 'لا يستطيع Hearth بعد كتابة رموز PIN في $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'رمز PIN لـ $profile في $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'يكتبه Hearth خلف بطاقة \"تسجيل الدخول باسم\" عندما يطلبه $app. يبقى مشفّرًا على هذا التلفزيون ولا يُعرض أبدًا.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'عيّن أولًا رمز PIN للوالدين ($settings ← $profiles ← $parentPin): هو مطلوب لحفظ رمز ملف شخصي.';
  }

  @override
  String get profilePinSaveFailed => 'تعذّر حفظ الرمز.';

  @override
  String get profileLockNow => 'قفل الملف الشخصي';

  @override
  String get profileLockOnSleep => 'القفل عند سكون التلفزيون';

  @override
  String get profileLockEveryTime => 'في كل مرة';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'بعد $minutes دقيقة من السكون';
  }

  @override
  String get profileLockNeedsGoogleLock => 'يستخدم قفل الملف الشخصي في Google TV: فعّله لحسابك من إعدادات Google TV ← الحسابات وتسجيل الدخول ← حسابك ← قفل الملف الشخصي.';

  @override
  String get aboutWallpaperPhoto => 'صورة الخلفية';

  @override
  String get updateErrorWrongApp => 'هذا التنزيل ليس تحديثًا لـ Hearth هذا';

  @override
  String get notifOpen => 'فتح';

  @override
  String get notifOpenHint => 'موافق: فتح · يسار: تجاهل · يمين: المزيد';

  @override
  String get tvPowerGoogleTvHome => 'استخدام الشاشة الرئيسية لـ Google TV';

  @override
  String get tvPowerGoogleTvHomeNote => 'يبقى Hearth بعيدًا حتى توقف هذا الخيار. لا يزال زر الصفحة الرئيسية يفتح Hearth.';

  @override
  String get setupFlowFinishLater => 'إكمال لاحقًا';

  @override
  String get setupFlowStripEssentials => 'الأساسيات';

  @override
  String get setupFlowWelcomeTitle => 'مرحبًا بك في Hearth';

  @override
  String get setupFlowWelcomeBody => 'شاشة رئيسية للعائلة كلها: تطبيقاتك، وما كنت تشاهده، والملف الشخصي الصحيح في كل تطبيق بث.';

  @override
  String get setupFlowWelcomeTime => 'يستغرق نحو 5 دقائق. يمكنك تخطي أي شيء.';

  @override
  String get setupFlowGetStarted => 'ابدأ';

  @override
  String get setupFlowSetUpLater => 'الإعداد لاحقًا';

  @override
  String setupFlowLanguageLink(String language) {
    return 'اللغة: $language';
  }

  @override
  String get setupFlowRestoreLink => 'الاستعادة من نسخة احتياطية';

  @override
  String get setupFlowHomeButtonTitle => 'اجعل زر الصفحة الرئيسية يفتح Hearth';

  @override
  String get setupFlowHomeButtonBody => 'يحتفظ Google TV بشاشته الرئيسية على زر الصفحة الرئيسية. مفتاح واحد في إعدادات Android يصلح ذلك، ويتيح لـ Hearth أيضًا:';

  @override
  String get setupFlowHomeButtonPoint1 => 'متابعة تبديل الملفات الشخصية ووقت نوم الأطفال';

  @override
  String get setupFlowHomeButtonPoint2 => 'عرض النوافذ المنبثقة وإطفاء التلفزيون عند عدم الاستخدام';

  @override
  String get setupFlowOnNextScreen => 'في الشاشة التالية:';

  @override
  String get setupFlowStepServices => 'مرّر لأسفل إلى \"الخدمات\"';

  @override
  String setupFlowStepSelect(String name) {
    return 'اختر \"$name\"';
  }

  @override
  String get setupFlowStepEnable => 'فعّل \"تفعيل\" ثم \"حسنًا\"';

  @override
  String get setupFlowComesBack => 'يعود Hearth من تلقاء نفسه عند تفعيله. إذا سأل Google TV عمّن يشاهد، فاختر نفسك.';

  @override
  String get setupFlowOpenAccessibility => 'فتح إمكانية الوصول';

  @override
  String get setupFlowHomeButtonDone => 'زر الصفحة الرئيسية يفتح Hearth الآن';

  @override
  String get setupFlowNotOnYetTitle => 'لم يتم التفعيل بعد';

  @override
  String get setupFlowNotOnYetBody => 'حاول مرة أخرى، أو تخطَّ الخطوة وأكملها لاحقًا في الإعدادات.';

  @override
  String get setupFlowStuckTitle => 'مفعّل لكنه لا يعمل';

  @override
  String get setupFlowStuckBody => 'يعرضه Android على أنه مفعّل، لكنه لا يعمل. أوقفه ثم شغّله مرة أخرى.';

  @override
  String get setupFlowSkipHomeButtonTitle => 'هل تريد تخطي زر الصفحة الرئيسية؟';

  @override
  String get setupFlowSkipHomeButtonBody => 'من دونه، يفتح زر الصفحة الرئيسية Google TV، ولا يستطيع Hearth معرفة متى يكون ملف الأطفال قيد الاستخدام.';

  @override
  String get setupFlowSkipAnyway => 'تخطٍّ على أي حال';

  @override
  String get setupFlowSkip => 'تخطٍّ';

  @override
  String get setupFlowNext => 'التالي';

  @override
  String get setupFlowLostTitle => 'أوقف التحديث زر الصفحة الرئيسية';

  @override
  String get setupFlowLostBody => 'يوقفه Android بعد بعض التحديثات. أعد تفعيله بخطوة واحدة.';

  @override
  String get setupFlowBlockedTitle => 'حظر Android هذا المفتاح';

  @override
  String get setupFlowBlockedBody => 'إذا كان المفتاح رماديًا، فذلك لأن Hearth ثُبّت من ملف تم تنزيله. لا يوجد في التلفزيون إعداد للسماح به.';

  @override
  String get setupFlowBlockedComputer => 'باستخدام كمبيوتر:';

  @override
  String get setupFlowBlockedComputerThen => 'ثم فعّل المفتاح. سيلاحظ Hearth ذلك تلقائيًا.';

  @override
  String get setupFlowBlockedSelfFixBody => 'التصحيح مفعّل، لذا يمكن لـ Hearth إصلاح ذلك بنفسه. سيسأل التلفزيون \"هل تريد السماح بتصحيح الأخطاء؟\": اختر \"السماح دائمًا\"، وسيرفع Hearth الحظر عن مفتاحه ويفعّله.';

  @override
  String get setupFlowSkipForNow => 'تخطٍّ الآن';

  @override
  String get setupFlowBlockedSkipLine => 'تظل التطبيقات والبحث و\"متابعة المشاهدة\" تعمل. أما زر الصفحة الرئيسية والملفات الشخصية والنوافذ المنبثقة ومؤقت النوم فلا.';

  @override
  String get setupFlowLetHearthFix => 'دع Hearth يصلحه';

  @override
  String get setupFlowFixConfirmBody => 'سيشغّل Hearth ما يلي على التلفزيون عبر اتصال التصحيح الخاص به:';

  @override
  String get setupFlowFixConfirmApproval => 'في المرة الأولى، يسأل التلفزيون \"هل تريد السماح بتصحيح الأخطاء؟\". اختر \"السماح دائمًا\". لا يغيّر ذلك سوى أذونات Hearth نفسه.';

  @override
  String get setupFlowFixRun => 'تشغيل';

  @override
  String get setupFlowFixWaiting => 'جارٍ التنفيذ. إذا سأل التلفزيون \"هل تريد السماح بتصحيح الأخطاء؟\"، فاختر \"السماح دائمًا\".';

  @override
  String get setupFlowFixFailedTitle => 'تعذّر على Hearth تنفيذ ذلك';

  @override
  String get setupFlowFixFailedBody => 'تعذّر على Hearth الوصول إلى تصحيح الأخطاء في التلفزيون. إذا سأل التلفزيون \"هل تريد السماح بتصحيح الأخطاء؟\"، فاختر \"السماح دائمًا\" وحاول مرة أخرى. يجب أن يبقى التصحيح مفعّلًا في \"خيارات المطوّرين\".';

  @override
  String get setupFlowHomeAppTitle => 'اجعل Hearth تطبيق الشاشة الرئيسية';

  @override
  String get setupFlowHomeAppBody => 'سيعرض Android قائمة بتطبيقات الشاشة الرئيسية. اختر Hearth. فهذا يمنع ملفات الأطفال من حظر Hearth.';

  @override
  String get setupFlowChooseHearth => 'اختيار Hearth';

  @override
  String get setupFlowHomeAppDone => 'Hearth هو تطبيق الشاشة الرئيسية لديك';

  @override
  String get setupFlowNotChosenTitle => 'لم يتم الاختيار بعد';

  @override
  String get setupFlowFinishTitle => 'Hearth جاهز';

  @override
  String setupFlowFinishBody(String where) {
    return 'كل ما تخطيته موجود في الإعدادات، ويمكنك تشغيل هذا مرة أخرى من $where.';
  }

  @override
  String get setupFlowFinishOn => 'مفعّل';

  @override
  String get setupFlowFinishLaterHeading => 'للإعداد لاحقًا في الإعدادات';

  @override
  String get setupFlowFinishMore => 'المزيد في الإعدادات: أزرار جهاز التحكم، والأقسام، والإشعارات، والنسخ الاحتياطي.';

  @override
  String get setupFlowGoHome => 'الانتقال إلى شاشتي الرئيسية';

  @override
  String get setupHearthTitle => 'إعداد Hearth';

  @override
  String get setupRunAgain => 'تشغيل الإعداد مرة أخرى';

  @override
  String get setupCardFamily => 'عائلتك';

  @override
  String get setupCardWatching => 'المشاهدة';

  @override
  String setupChipLeft(int count) {
    return 'إكمال الإعداد · المتبقي: $count';
  }

  @override
  String get setupChipFix => 'زر الصفحة الرئيسية يحتاج إلى إصلاح';

  @override
  String get setupChipHideTitle => 'هل تريد إخفاء هذا التذكير؟';

  @override
  String setupChipHideBody(String where) {
    return 'لا يزال بإمكانك تشغيل الإعداد من $where.';
  }

  @override
  String get setupChipHide => 'إخفاء';

  @override
  String get setupFlowCardIncluded => 'ما الذي يتضمنه';

  @override
  String get setupFlowCardNeeds => 'ما يحتاجه';

  @override
  String get setupFlowTurnOn => 'تشغيل';

  @override
  String get setupFlowNeedsQuestion => 'سؤال واحد من Android';

  @override
  String get setupFlowNeedsOneSwitch => 'مفتاح واحد في إعدادات Android';

  @override
  String get setupFlowNeedsAboutAMinute => 'دقيقة تقريبًا';

  @override
  String get setupFlowWatchingBenefit => 'تابع من حيث توقفت، وشاهد ما يتم تشغيله.';

  @override
  String get setupFlowWatchingIncluded1 => 'متابعة المشاهدة على الشاشة الرئيسية';

  @override
  String get setupFlowWatchingIncluded2 => 'الإشعارات وما يتم تشغيله';

  @override
  String get setupFlowSearchWorks => 'البحث يعمل بالفعل: اضغط على البحث في الشاشة الرئيسية.';

  @override
  String get setupFlowContinueBody => 'اعرض ما كنت تشاهده في تطبيقاتك على الشاشة الرئيسية. سيسألك Android مرة واحدة؛ اختر السماح.';

  @override
  String get setupFlowContinueDone => 'تم تشغيل متابعة المشاهدة';

  @override
  String get setupFlowContinueDeniedTitle => 'لم يسمح Android بذلك';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'يمكنك تشغيله لاحقًا من $where.';
  }

  @override
  String get setupFlowNotificationsTitle => 'ما يتم تشغيله والإشعارات';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'شاهد إشعاراتك وما يتم تشغيله. في الشاشة التالية، اختر \"$name\" واسمح به.';
  }

  @override
  String get setupFlowNotificationsDone => 'تم تشغيل الإشعارات';

  @override
  String get setupFlowTvTitle => 'إيقاف التلفزيون عندما لا يشاهده أحد؟';

  @override
  String get setupFlowTvBody => 'بعد هذه المدة دون أي ضغطة على جهاز التحكم. تشغيل فيديو أو موسيقى يُحسب مشاهدة.';

  @override
  String get setupFlowTvNeedsHomeButton => 'يحتاج هذا إلى مفتاح زر الصفحة الرئيسية من الخطوات الأولى: بدونه لا يعرف Hearth متى يُستخدم جهاز التحكم.';

  @override
  String get setupFlowStartOnBoot => 'تشغيل Hearth عند تشغيل التلفزيون';

  @override
  String get setupFlowScreensaver => 'اختيار صور شاشة التوقف';

  @override
  String get setupFlowUpdatesBenefit => 'يحافظ Hearth على تحديث نفسه وتطبيقاته المرافقة.';

  @override
  String get setupFlowUpdatesIncluded1 => 'يحدّث Hearth نفسه';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube، تطبيق YouTube مصمم لـ Hearth';

  @override
  String get setupFlowInstallTitle => 'السماح لـ Hearth بتثبيت التحديثات';

  @override
  String get setupFlowInstallBody => 'في الشاشة التالية، ابحث عن Hearth وشغّله، ثم اضغط رجوع.';

  @override
  String get setupFlowInstallDone => 'يمكن لـ Hearth تثبيت التحديثات';

  @override
  String get setupFlowTubeTitle => 'تثبيت HearthTube؟';

  @override
  String get setupFlowTubeBody => 'تطبيق YouTube مصمم لـ Hearth: يتبع ملفاتك الشخصية ونمط الساعة ووقت نوم الأطفال.';

  @override
  String get setupFlowTubeInstalled => 'تم تثبيت HearthTube';

  @override
  String get setupCardHome => 'شاشتك الرئيسية';

  @override
  String get setupFlowLookTitle => 'اختر مظهرًا';

  @override
  String setupFlowLookBody(String where) {
    return 'يظهر كل مظهر خلف هذه البطاقة عند الانتقال إليه. يمكنك تغيير أي جزء لاحقًا من $where.';
  }

  @override
  String get setupFlowLookOtherTitle => 'اختر مظهرًا لشاشتك الرئيسية';

  @override
  String get setupFlowLookOtherBody => 'لكل ملف شخصي شاشته الرئيسية. اختر مظهر شاشتك.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'صورة اليوم';

  @override
  String get setupLookCalmDark => 'داكن هادئ';

  @override
  String get setupLookBold => 'جريء';

  @override
  String get setupFlowLookNow => 'الحالي';

  @override
  String get setupFlowLookUse => 'استخدام هذا المظهر';

  @override
  String get setupFlowLookKeep => 'إبقاء الحالي';

  @override
  String get setupFlowLookCustomize => 'تخصيص';

  @override
  String get setupFlowWeatherTitle => 'عرض الطقس؟';

  @override
  String get setupFlowWeatherBody => 'اختر مدينتك. يُرسل موقعها فقط إلى Open-Meteo، دون حساب.';

  @override
  String get setupFlowWeatherChoose => 'اختيار المدينة';

  @override
  String get setupFlowWeatherDone => 'يظهر الطقس في الشريط العلوي';

  @override
  String get setupFlowFamilyBenefit => 'تفتح تطبيقات البث على الشخص الصحيح، ولا يمكن للأطفال تغيير Hearth.';

  @override
  String get setupFlowFamilyIncluded1 => 'رمز PIN للوالدين، حتى لا يغيّر الأطفال Hearth';

  @override
  String get setupFlowFamilyIncluded2 => 'الملف الشخصي الصحيح في Netflix وDisney+ وApple TV وMax وParamount+';

  @override
  String get setupFlowFamilyIncluded3 => 'إبقاء Hearth على ملفات أطفالك';

  @override
  String get setupFlowNeedsPin => 'أربعة أرقام تختارها';

  @override
  String get setupFlowNeedsTwoMinutes => 'دقيقتان تقريبًا';

  @override
  String get setupFlowPinTitle => 'اختر رمز PIN للوالدين';

  @override
  String get setupFlowPinBody => 'يحتاجه الأطفال لتغيير Hearth. اختر أربعة أرقام لن يخمنها طفل.';

  @override
  String get setupFlowPinChoose => 'اختيار رمز PIN';

  @override
  String get setupFlowPinDone => 'تم تعيين رمز PIN للوالدين';

  @override
  String get setupFlowPairingTitle => 'اختيار الملف الشخصي الصحيح في تطبيقات البث';

  @override
  String setupFlowPairingBody(String name) {
    return 'يختار Hearth الملف الشخصي لكل شخص في Netflix وDisney+ وApple TV وMax وParamount+. يحتاج إلى مفتاح آخر في شاشة Android نفسها: \"$name\".';
  }

  @override
  String get setupFlowPairingDone => 'تم تشغيل ربط الملفات الشخصية';

  @override
  String get setupFlowPairingDoneBody => 'يطابق Hearth الأسماء تلقائيًا: \"Alex\" يتوافق مع \"Alex Morgan\". تظهر الملفات الشخصية لكل تطبيق بعد ظهور شاشة \"من يشاهد؟\" فيه مرة واحدة.';

  @override
  String get setupFlowCheckPairings => 'التحقق من الربط';

  @override
  String get setupFlowVoiceTitle => 'خطوة إضافية لـ Netflix';

  @override
  String setupFlowVoiceBody(String name) {
    return 'يقرأ Netflix شاشة الملفات الشخصية بصوت عالٍ، لذا يستمع Hearth عبر صوته الخاص. في الشاشة التالية، ضمن المحرك المفضل، اختر \"$name\" ثم موافق. تحتفظ التطبيقات الأخرى بصوت Google.';
  }

  @override
  String get setupFlowVoiceDone => 'تم تشغيل صوت Hearth';

  @override
  String get setupFlowKidsTitle => 'إبقاء Hearth على ملفات أطفالك';

  @override
  String get setupFlowKidsBody => 'يزيل Google TV التطبيقات التي لم يثبتها من ملفات الأطفال في كل مرة تبدأ فيها. يمكن لـ Hearth حماية نفسه وHearthTube هناك. يتلقى كل طفل إشعار Family Link واحدًا \"تمت إضافة تطبيق\"؛ يمكنك التراجع في أي وقت من الإعدادات.';

  @override
  String get setupFlowKidsApprove => 'سيسأل التلفزيون \"السماح بتصحيح الأخطاء؟\". حدّد السماح دائمًا، ثم السماح. تفعل ذلك مرة واحدة فقط.';

  @override
  String get setupFlowKidsAdd => 'إضافة إلى ملفاتهم';

  @override
  String get setupFlowKidsDone => 'أصبح Hearth على ملفات أطفالك';

  @override
  String get setupFlowKidsKeepDebugging => 'اترك تصحيح الأخطاء مفعّلًا: يحتاجه Hearth مجددًا لملف طفل جديد، ولإزالة نفسه أو إلغاء تثبيته.';

  @override
  String get setupFlowDebugTitle => 'شغّل تصحيح الأخطاء أولًا';

  @override
  String get setupFlowDebugBody => 'يحتاج Hearth إلى مفتاح تصحيح الأخطاء في التلفزيون لإعداد ملفات الأطفال. في الشاشة التالية، اختر \"Android TV OS build\" سبع مرات. ثم من الإعدادات > النظام > خيارات المطوّرين، شغّل تصحيح أخطاء USB وارجع. اتركه مفعّلًا: يحتاجه Hearth مجددًا لملف طفل جديد.';

  @override
  String get setupFlowDebugOpen => 'فتح \"حول\"';

  @override
  String get setupCardSmartHome => 'المنزل الذكي';

  @override
  String get setupFlowHaBenefit => 'تنبيهات جرس الباب وغيرها على التلفزيون، ولوحة Home Assistant بضغطة واحدة.';

  @override
  String get setupFlowHaIncluded1 => 'تنبيهات جرس الباب وغيرها فوق أي تطبيق';

  @override
  String get setupFlowHaIncluded2 => 'لوحتك بضغطة واحدة';

  @override
  String get setupFlowHaIncluded3 => 'إرسال ما يُعرض إلى Home Assistant';

  @override
  String get setupFlowNeedsPhone => 'هاتف على شبكة Wi-Fi نفسها';

  @override
  String get setupFlowNeedsFewMinutes => 'بضع دقائق';

  @override
  String get setupFlowHaUse => 'أستخدم Home Assistant';

  @override
  String get setupFlowHaAlertsTitle => 'تنبيهات Home Assistant';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'في Home Assistant، أضف \"Notifications for Android TV / Fire TV\" بعنوان هذا التلفزيون: $ip. ثم أرسل اختبارًا.';
  }

  @override
  String get setupFlowHaAlertsDone => 'تم تشغيل التنبيهات';

  @override
  String get setupFlowHaDashboardTitle => 'لوحتك على التلفزيون';

  @override
  String get setupFlowHaDashboardBody => 'امسح الرمز بهاتفك، والصق عنوان Home Assistant ورمزًا مميزًا، ثم أرسل. استخدم مستخدم Home Assistant مخصصًا للتلفزيون، وليس مسؤولًا.';

  @override
  String get setupFlowHaDashboardDone => 'تم إعداد لوحتك';

  @override
  String get setupFlowHaStatusTitle => 'أخبر Home Assistant بما يُعرض';

  @override
  String get setupFlowHaStatusBody => 'يمكن للتلفزيون إرسال ما يتم تشغيله والملف الشخصي النشط إلى Home Assistant. في صفحة الهاتف نفسها، أضف معرّف أتمتة Webhook من Home Assistant.';

  @override
  String get setupFlowHaStatusNoWebhook => 'لم يرسل الهاتف معرّف Webhook. املأ المربع الأخير في الصفحة.';

  @override
  String get setupFlowHaStatusDone => 'يُخبر التلفزيون Home Assistant بما يُعرض';

  @override
  String setupChipNewOne(String feature) {
    return 'جديد في Hearth: $feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'جديد في Hearth · $count';
  }

  @override
  String get setupFlowKidsNotAll => 'لم يُثبَّت Hearth بعد على كل ملفات الأطفال';

  @override
  String get setupFlowLeaveAsIs => 'اتركه كما هو';

  @override
  String get setupFlowSetUpMissing => 'إعداد ما ينقص';

  @override
  String get setupFlowChooseAgain => 'اختر مرة أخرى';

  @override
  String get weatherForecastHourly => 'كل ساعة';

  @override
  String get weatherForecastDaily => 'يوميًا';

  @override
  String get weatherForecastShowDaily => 'موافق: يوميًا';

  @override
  String get weatherForecastShowHourly => 'موافق: كل ساعة';

  @override
  String get weatherForecastNow => 'الآن';

  @override
  String get weatherForecastToday => 'اليوم';

  @override
  String get weatherForecastNone => 'لم تصل التوقعات بعد';
}
