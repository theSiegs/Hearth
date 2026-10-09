import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutFlauncher => 'Hearth 정보';

  @override
  String get addSection => '섹션 추가';

  @override
  String get alphabetical => '알파벳순';

  @override
  String get appCardHighlightAnimation => '앱 카드 하이라이트 애니메이션';

  @override
  String get appInfo => '앱 정보';

  @override
  String get appKeyClick => '키 누름 시 클릭 소리';

  @override
  String get applications => '애플리케이션';

  @override
  String get autoHideAppBar => '상태 표시줄 자동 숨기기';

  @override
  String get backButtonAction => '뒤로 버튼 동작';

  @override
  String get category => '카테고리';

  @override
  String get columnCount => '열 수';

  @override
  String get date => '날짜';

  @override
  String get dateAndTimeFormat => '날짜 및 시간 형식';

  @override
  String get delete => '삭제';

  @override
  String get dialogOptionBackButtonActionDoNothing => '아무 작업 안 함';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => '화면 보호기 표시';

  @override
  String get dialogOptionBackButtonActionShowClock => '시계 표시';

  @override
  String get dialogTextNoFileExplorer => '사진을 선택하려면 파일 탐색기를 설치하세요.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (카테고리)';
  }

  @override
  String get gradient => '그라데이션';

  @override
  String get favoriteApps => '즐겨찾는 앱';

  @override
  String get grid => '그리드';

  @override
  String get height => '높이';

  @override
  String get hide => '숨기기';

  @override
  String get hiddenApplications => '숨겨진 앱';

  @override
  String get launcherSections => '섹션';

  @override
  String get layout => '레이아웃';

  @override
  String get loading => '로딩 중';

  @override
  String get manual => '수동';

  @override
  String get modifySection => '섹션 수정';

  @override
  String get name => '이름';

  @override
  String get newSection => '새 섹션';

  @override
  String get nonTvApplications => '비 TV 앱';

  @override
  String get open => '열기';

  @override
  String get picture => '사진';

  @override
  String removeFrom(String name) {
    return '$name에서 제거';
  }

  @override
  String get reorder => '재정렬';

  @override
  String get row => '행';

  @override
  String get rowHeight => '행 높이';

  @override
  String get save => '저장';

  @override
  String get spacer => '간격';

  @override
  String get statusBar => '상태 표시줄';

  @override
  String get show => '표시';

  @override
  String get showCategoryTitles => '카테고리 제목 표시';

  @override
  String get showCategoryAppCount => '카테고리의 앱 수 표시';

  @override
  String get hideHighlightOutlineOnHomescreen => '홈 화면에서 하이라이트 윤곽선 숨기기';

  @override
  String get appSelectorTransitionAnimation => '앱 선택기 전환 애니메이션';

  @override
  String get sort => '정렬';

  @override
  String get systemSettings => '시스템 설정';

  @override
  String get textEmptyCategory => '이 카테고리는 비어 있습니다.';

  @override
  String get time => '시간';

  @override
  String get tvApplications => 'TV 앱';

  @override
  String get type => '유형';

  @override
  String get uninstall => '제거';

  @override
  String get wallpaper => '배경화면';

  @override
  String get withEllipsisAddTo => '추가...';

  @override
  String get timeBasedWallpaper => '시간 기반 배경화면';

  @override
  String get pickDayWallpaper => '주간 배경화면 선택';

  @override
  String get pickNightWallpaper => '야간 배경화면 선택';

  @override
  String get inputs => '입력';

  @override
  String get inputSources => '입력 소스';

  @override
  String get backupAndRestore => '백업 및 복원';

  @override
  String get exportBackup => '백업 내보내기';

  @override
  String get importBackup => '백업 가져오기';

  @override
  String exportSuccess(String path) {
    return '백업이 $path로 성공적으로 내보내졌습니다';
  }

  @override
  String get importSuccess => '백업을 성공적으로 가져왔습니다';

  @override
  String get importConfirm => '백업을 가져오시겠습니까? 현재 설정 및 레이아웃을 덮어씁니다.';

  @override
  String importError(String error) {
    return '백업 가져오기 실패: $error';
  }

  @override
  String exportError(String error) {
    return '백업 내보내기 실패: $error';
  }

  @override
  String get shareBackup => '백업 공유';

  @override
  String get notificationBell => '알림 벨';

  @override
  String get autoHideNotificationBell => '알림 벨 자동 숨기기';

  @override
  String get continueWatching => '계속 시청';

  @override
  String get showContinueWatchingOnHome => '홈에서 계속 시청 표시';

  @override
  String get permissionDeniedContinueWatching => '계속 시청을 표시하려면 권한이 필요합니다';

  @override
  String get system => '시스템';

  @override
  String get accentColor => '강조 색상';

  @override
  String get dataUsagePeriod => '데이터 사용 기간';

  @override
  String get notificationAccess => '알림 액세스';

  @override
  String get watchNextAccess => 'Watch Next 액세스';

  @override
  String get granted => '부여됨';

  @override
  String get permissionRequired => '권한 필요';

  @override
  String get systemWidePopupAlert => '시스템 전체 팝업 알림';

  @override
  String get overlayPermissionRequired => '오버레이 권한 필요';

  @override
  String get enabled => '사용 설정됨';

  @override
  String get disabled => '사용 중지됨';

  @override
  String get showAppNamesBelowIcons => '아이콘 아래에 앱 이름 표시';

  @override
  String get dataUsage => '데이터 사용량';

  @override
  String get networkIndicator => '네트워크 표시기';

  @override
  String get startOnBoot => '부팅 시 시작 (Google TV / Fire TV)';

  @override
  String get appLanguage => '언어';

  @override
  String get systemDefault => '시스템 기본값';

  @override
  String get english => '영어';

  @override
  String get spanish => '스페인어';

  @override
  String get ukrainian => '우크라이나어';

  @override
  String get chinese => '중국어';

  @override
  String get french => '프랑스어';

  @override
  String get german => '독일어';

  @override
  String get japanese => '일본어';

  @override
  String get portuguese => '포르투갈어';

  @override
  String get russian => '러시아어';

  @override
  String get italian => '이탈리아어';

  @override
  String get hindi => '힌디어';

  @override
  String get korean => '한국어';

  @override
  String get arabic => '아랍어';

  @override
  String get turkish => '터키어';

  @override
  String get hidePersistentNotifications => '고정 알림 숨기기';

  @override
  String get blockedNotificationApps => '차단된 앱';

  @override
  String get blockAppNotifications => '알림 차단';

  @override
  String get unblockAppNotifications => '알림 차단 해제';

  @override
  String get noBlockedApps => '차단된 앱이 없습니다';

  @override
  String get persistentNotification => '고정';

  @override
  String get unblockAll => '모두 차단 해제';

  @override
  String get weather => '날씨';

  @override
  String get showWeatherWarnings => '날씨 및 강우 경보 표시';

  @override
  String get temperatureUnit => '온도 단위';

  @override
  String get celsius => '섭씨 (°C)';

  @override
  String get fahrenheit => '화씨 (°F)';

  @override
  String get notifications => '알림';

  @override
  String get continueWatchingDescription => '홈 화면에 최근 시청한 영화 및 TV 프로그램 표시';

  @override
  String get dismiss => '닫기';

  @override
  String get openApp => '열기';

  @override
  String get noBlockedAppsDesc => '현재 모든 애플리케이션의 알림 표시가 허용되어 있습니다';

  @override
  String get notificationsAllowed => '알림 허용됨';

  @override
  String get notificationsBlocked => '알림 차단됨';

  @override
  String get dpadDismissHint => '왼쪽: 닫기 • 확인: 옵션';

  @override
  String get settingsTitle => '설정';

  @override
  String get profilesTitle => '프로필';

  @override
  String get homeScreenTitle => '홈 화면';

  @override
  String get remoteAndSearchTitle => '리모컨 및 검색';

  @override
  String get parentSettingsTitle => '보호자 설정';

  @override
  String get tvPowerTitle => 'TV 및 전원';

  @override
  String get setupPermissionsTitle => '설정 및 권한';

  @override
  String get updatesTitle => '업데이트';

  @override
  String get familyAppsTitle => '다른 프로필의 Hearth';

  @override
  String get cardStyleTitle => '카드 스타일';

  @override
  String get dockLabelsTitle => '독 및 레이블';

  @override
  String get animationsSoundTitle => '애니메이션 및 소리';

  @override
  String get haPanelTitle => '대시보드 패널';

  @override
  String get lookTitle => '모양';

  @override
  String get remoteButtonsTitle => '리모컨 버튼';

  @override
  String get profilePairingTitle => '프로필 연결';

  @override
  String get haTvStatusTitle => 'TV 상태';

  @override
  String get continueWatchingAppsTitle => '계속 시청 앱';

  @override
  String get cardSizeTitle => '카드 크기';

  @override
  String get maxItemsTitle => '최대 항목 수';

  @override
  String get ok => '확인';

  @override
  String get cancel => '취소';

  @override
  String get close => '닫기';

  @override
  String get tryAgain => '다시 시도';

  @override
  String get notNow => '나중에';

  @override
  String get done => '완료';

  @override
  String get remove => '제거';

  @override
  String get homeNothingToWatch => '지금 볼 수 있는 항목이 없습니다';

  @override
  String get errorScreenTitle => '문제가 발생했습니다';

  @override
  String get appInfoAddToCategory => '카테고리에 추가';

  @override
  String get appInfoAddToFavorites => '즐겨찾기에 추가';

  @override
  String get appInfoRemoveFromFavorites => '즐겨찾기에서 제거';

  @override
  String get appInfoSetCustomBanner => '사용자 지정 배너 설정';

  @override
  String get appInfoClearCustomBanner => '사용자 지정 배너 지우기';

  @override
  String appInfoSetBannerFailed(String error) {
    return '배너를 설정하지 못했습니다: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return '배너를 지우지 못했습니다: $error';
  }

  @override
  String get cwGridAll => '전체';

  @override
  String get cwRowSeeAll => '모두 보기';

  @override
  String cwRowInProgress(int count) {
    return '시청 중 $count개';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '$hours시간 $minutes분 남음';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '$minutes분 남음';
  }

  @override
  String get watchNextInfoRemove => '계속 시청에서 제거';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return '$appName의 항목 모두 숨기기';
  }

  @override
  String get watchNextInfoPlayResume => '재생 / 이어보기';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '$appName 열기';
  }

  @override
  String get watchNextInfoAppInfo => '앱 정보';

  @override
  String get dataWidgetGrantPermission => '사용 권한 허용';

  @override
  String dataWidgetDaily(String usage) {
    return '일간: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return '주간: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return '월간: $usage';
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
        'today': '오늘 비',
        'tomorrow': '내일 비',
        'other': '$day요일 비',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '오늘 눈',
        'tomorrow': '내일 눈',
        'other': '$day요일 눈',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '오늘 뇌우',
        'tomorrow': '내일 뇌우',
        'other': '$day요일 뇌우',
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
    return '$apps에서 보기';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return '$app에서 대여 또는 구매';
  }

  @override
  String get searchMoreWaysToWatch => '다른 시청 방법 (Google TV)';

  @override
  String get searchListening => '듣는 중…';

  @override
  String get searchHint => '영화 및 프로그램 검색';

  @override
  String get searchEntryHelp => '입력하거나 마이크를 사용하거나 Google TV 앱으로 휴대전화에서 입력하세요.';

  @override
  String get searchTabWatchNow => '지금 보기';

  @override
  String get searchTabRentOrBuy => '대여 또는 구매';

  @override
  String get searchTabOtherApps => '다른 앱';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return '대여 또는 구매 · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => '시청 위치: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return '$services에서 시청 가능 (이 TV에 없음)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '결과 $count개',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return '여기에는 “$query”에 대한 결과가 없습니다.';
  }

  @override
  String get searchGridTmdbNotice => '시청 정보 제공: TMDB (JustWatch 경유). 이 제품은 TMDB API를 사용하지만 TMDB의 보증이나 인증을 받지 않았습니다.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps 또는 $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Google에 묻기: “$query”';
  }

  @override
  String get searchAskGoogleDetail => '질문, 날씨 등 프로그램이 아닌 모든 것';

  @override
  String searchSearchingFor(String query) {
    return '“$query” 검색 중…';
  }

  @override
  String get searchFailed => '지금은 검색할 수 없습니다. 인터넷 연결을 확인하세요.';

  @override
  String searchNothingFound(String query) {
    return '“$query”에 대한 결과가 없습니다';
  }

  @override
  String searchNothingInYourApps(String query) {
    return '지금은 내 앱에 “$query” 항목이 없습니다';
  }

  @override
  String get searchSeeMoreResults => '다른 시청처는 결과 더보기에서 확인하세요.';

  @override
  String get searchMoreResults => '결과 더보기';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '타이틀 $count개',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Google에 묻기';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => '영화';

  @override
  String get searchKindSeries => '시리즈';

  @override
  String get gradientNamePitchBlack => '칠흑';

  @override
  String get gradientNameGreatWhale => '큰 고래';

  @override
  String get gradientNameViciousStance => '사나운 자세';

  @override
  String get gradientNameTeenNotebook => '십대의 노트';

  @override
  String get gradientNameOldHat => '낡은 모자';

  @override
  String get gradientNameBurningSpring => '불타는 봄';

  @override
  String get gradientNameDesertHump => '사막 언덕';

  @override
  String get gradientNameFarawayRiver => '먼 강';

  @override
  String get gradientNameSaintPetersburg => '상트페테르부르크';

  @override
  String get gradientNameAfricanField => '아프리카 들판';

  @override
  String get gradientNameGrassShampoo => '풀 샴푸';

  @override
  String get updateErrorNoApk => '이 기기용 APK가 있는 릴리스가 없습니다';

  @override
  String get updateErrorCheckFailed => '업데이트를 확인할 수 없습니다';

  @override
  String get updateErrorDownloadFailed => '업데이트를 다운로드할 수 없습니다';

  @override
  String get serviceHearthTubeDescription => 'Hearth용 YouTube, Hearth 프로필을 따릅니다';

  @override
  String get haSummaryOn => '켜짐';

  @override
  String get haSummaryOff => '꺼짐';

  @override
  String get haSummaryReporting => '보고 중';

  @override
  String haNotificationsNeedsFix(String path) {
    return '홈 버튼 수정을 켜세요($path). 이 기능이 팝업을 표시합니다.';
  }

  @override
  String get haNotificationsShow => 'Home Assistant 알림 표시';

  @override
  String get haNotificationsSendTest => '테스트 알림 보내기';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Home Assistant에서 호스트 $host로 \"Notifications for Android TV / Fire TV\" 통합을 추가하세요. 그런 다음 자동화에서 알림을 보내세요. 예를 들어 초인종이 울리거나 빨래가 끝났을 때요.\n\n홈 네트워크에 있는 기기만 보낼 수 있습니다(포트 7676). 팝업은 모든 앱 위에 표시되며 홈 버튼 수정($path)이 켜져 있어야 합니다.';
  }

  @override
  String get haNotificationsThisTvIp => '(이 TV의 IP 주소)';

  @override
  String get haPanelSaved => '저장됨';

  @override
  String get haPanelSavedNoToken => '저장됨. 로그인하려면 액세스 토큰을 추가하세요.';

  @override
  String get haPanelReceived => '휴대전화에서 주소와 토큰을 받았습니다';

  @override
  String get haPanelRightEdge => '오른쪽 끝에서 오른쪽을 누르면 패널 열기';

  @override
  String get haSetUpFromPhone => '휴대전화로 설정';

  @override
  String get haPanelTokenLabel => '장기 액세스 토큰';

  @override
  String get haPanelTokenSavedHint => '저장됨(바꾸려면 새 토큰 입력)';

  @override
  String get haPanelDashboardLabel => '대시보드';

  @override
  String haPanelHelp(String tvStatus) {
    return '이 프로필에서만 켜집니다. 패널은 $tvStatus에 입력한 주소의 대시보드를 토큰으로 로그인해 표시합니다. 이 TV용으로 만든 관리자가 아닌 사용자로 Home Assistant에 로그인한 상태에서 토큰을 만드세요(프로필 페이지, 보안 탭).';
  }

  @override
  String get haStatusReportingOff => '상태 보고가 꺼져 있습니다';

  @override
  String get haStatusSaved => '저장됨: Home Assistant에 보고 중';

  @override
  String get haStatusAddressLabel => 'Home Assistant 주소';

  @override
  String get haStatusWebhookLabel => '웹훅 ID';

  @override
  String get haStatusNowPlayingOn => '재생 중인 항목: 켜짐';

  @override
  String get haStatusNowPlayingOff => '재생 중인 항목: 알림 액세스 켜기';

  @override
  String get haStatusHelp => 'TV는 지금 표시 중인 앱, 재생 중인 항목, Google TV 프로필, 어린이 스크린 타임을 Home Assistant에 보냅니다. 변경될 때마다 위 주소로만 보냅니다.';

  @override
  String get haPhoneSetupNoNetwork => '이 TV가 홈 네트워크에 연결되어 있지 않아 휴대전화에서 연결할 수 없습니다.';

  @override
  String get haPhoneSetupScan => '같은 Wi-Fi에 연결된 휴대전화로 스캔하고 Home Assistant 주소와 액세스 토큰을 붙여넣은 다음 Send를 탭하세요. 이 창이 열려 있는 동안에만 페이지가 작동합니다.';

  @override
  String get profilesSwitchProfile => '프로필 전환';

  @override
  String get parentPinTitle => '보호자 PIN';

  @override
  String get parentPinOn => '켜짐';

  @override
  String get parentPinOff => '꺼짐';

  @override
  String get parentPinCurrent => '현재 보호자 PIN';

  @override
  String get parentPinRemove => 'PIN 삭제';

  @override
  String get parentPinChange => 'PIN 변경';

  @override
  String get parentPinNew => '새 보호자 PIN';

  @override
  String get parentPinNewSubtitle => 'Google TV 어린이 프로필에서 런처를 변경하려면 필요합니다';

  @override
  String get parentPinConfirm => 'PIN을 다시 입력하세요';

  @override
  String get parentPinAskTitle => '보호자에게 물어보세요';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return '어린이 프로필에서는 런처 설정이 잠겨 있습니다. 보호자가 자신의 프로필에서 $settings → $profiles → $parentPin에서 PIN을 설정할 수 있습니다.';
  }

  @override
  String get parentPinKidsSubtitle => '어린이 프로필: 런처를 변경하려면 보호자 PIN을 입력하세요';

  @override
  String get parentPinWrong => 'PIN이 틀렸습니다';

  @override
  String get parentPinEnter => 'PIN 입력';

  @override
  String profileSwitchGreeting(String name) {
    return '$name님, 안녕하세요';
  }

  @override
  String get profileSwitchSettingUp => '이 프로필을 설정하는 중…';

  @override
  String profilesKidsName(String name) {
    return '$name(어린이)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name(성인)';
  }

  @override
  String get pairingShowPicker => '선택 화면 표시';

  @override
  String get pairingAlwaysShowPicker => '항상 선택 화면 표시';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile(이름으로 일치)';
  }

  @override
  String get pairingNoMatchYet => '아직 일치 항목 없음: 선택 화면 표시';

  @override
  String get pairingOffSetUp => '프로필 연결이 꺼져 있습니다. 설정하기';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Hearth가 이 앱 중 하나를 열면 Google TV 프로필과 연결된 앱 프로필을 선택합니다. Hearth가 이름을 알아서 맞추며(\"$shortName\"은 \"$fullName\"과 연결), 여기에서 연결을 바꿀 수 있습니다. 일치하는 항목이 없으면 앱의 자체 선택 화면이 표시됩니다.';
  }

  @override
  String get pairingAppNotInstalled => '설치되지 않음';

  @override
  String get pairingAppOff => '꺼짐: 앱의 자체 선택 화면 표시';

  @override
  String get pairingAppNotSeen => 'Hearth에서 한 번 열면 Hearth가 프로필을 알 수 있습니다';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '프로필 $count개 찾음',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return '이름으로 맞추기($profile)';
  }

  @override
  String get pairingMatchByNameNone => '이름으로 맞추기(아직 일치 항목 없음)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$app의 $profile';
  }

  @override
  String pairingPairIn(String app) {
    return '$app에서 프로필 연결';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth가 아직 이 앱의 프로필을 확인하지 못했습니다. Hearth에서 한 번 연 다음 돌아오세요.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return '이 앱의 프로필: $profiles. Google TV 프로필은 Hearth가 확인하면 여기에 표시됩니다.';
  }

  @override
  String get familyAppsIntro => 'Hearth와 HearthTube를 다른 Google TV 프로필에도 설치합니다. 어린이 프로필에서는 HearthTube가 작동하고 Hearth가 Netflix, Disney+ 등의 앱에서 올바른 프로필을 고르려면 필요합니다. 성인 프로필에서는 직접 설치하지 않아도 되도록 하는 편의 기능입니다.';

  @override
  String get familyAppsAddTitle => '다른 프로필에 Hearth 추가';

  @override
  String get familyAppsAddKids => '자녀 프로필에 Hearth와 HearthTube를 설치합니다. 그러면 그곳에서 HearthTube가 작동하고 Hearth가 Netflix, Disney+ 같은 앱에서 올바른 프로필을 고를 수 있습니다.';

  @override
  String get familyAppsAddAdults => 'TV의 다른 성인 프로필에도 설치하므로 다른 성인이 직접 설정할 필요가 없습니다.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Hearth의 앱 2개만 추가되며, 아래의 제거로 언제든지 되돌릴 수 있습니다.';

  @override
  String get familyAppsAddFamilyLink => '자녀마다 Family Link의 \'앱 추가됨\' 알림이 한 번 표시됩니다.';

  @override
  String get familyAppsAddApproval => '처음에는 TV에 \'디버깅을 허용하시겠습니까?\'가 표시됩니다. \'항상 허용\'을 선택하세요. 그래야 Hearth가 설정할 수 있습니다.';

  @override
  String get familyAppsAdd => '추가';

  @override
  String get familyAppsRemoveTitle => '다른 프로필에서 Hearth 제거';

  @override
  String get familyAppsRemoveBody => '다른 프로필에서 Hearth와 HearthTube를 제거합니다.';

  @override
  String get familyAppsRemoveFirst => 'Hearth 자체를 제거하려면 먼저 이것을 실행하세요. 그렇지 않으면 어린이 프로필의 사본이 남아 컴퓨터로 지워야 할 수 있습니다.';

  @override
  String get familyAppsUninstallTitle => 'Hearth 제거';

  @override
  String get familyAppsUninstallBody => '먼저 다른 프로필에서 Hearth와 HearthTube를 제거한 다음 이 프로필에서 Hearth를 제거합니다.';

  @override
  String get familyAppsUninstallWhyHere => 'Android 설정이 아니라 여기에서 제거해야 어린이 프로필에 아무것도 남지 않습니다.';

  @override
  String get familyAppsApprovalFirstTitle => '먼저 1회 승인을 완료하세요';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth가 아직 다른 프로필을 정리하지 못했습니다. TV에서 \'디버깅을 허용하시겠습니까?\'를 한 번 승인해야 합니다.';

  @override
  String get familyAppsApprovalFirstRetry => '승인한 다음 다시 제거를 시도하세요. 그래야 어린이 프로필에 아무것도 남지 않습니다.';

  @override
  String get familyAppsAddDone => '추가 완료';

  @override
  String get familyAppsRemoveDone => '제거 완료';

  @override
  String get familyAppsAdded => '완료되었습니다. 이제 다른 프로필에 Hearth와 HearthTube가 있습니다. 아래 목록을 확인하세요.';

  @override
  String get familyAppsRemoved => '완료되었습니다. 다른 프로필에서 Hearth와 HearthTube를 제거했습니다.';

  @override
  String get familyAppsNothingToSetUp => '아직 설정할 다른 프로필이 없습니다.';

  @override
  String get familyAppsFailedTitle => '프로필을 설정할 수 없습니다';

  @override
  String get familyAppsFailedBody => '다른 프로필을 설정하려면 TV에서 한 번 승인해야 합니다.';

  @override
  String get familyAppsFailedRetry => 'TV에 \'디버깅을 허용하시겠습니까?\'가 표시되면 \'항상 허용\'을 선택한 다음 다시 시도하세요.';

  @override
  String get familyAppsAlsoAdults => '다른 성인 프로필도 설정';

  @override
  String get familyAppsOn => '켜짐';

  @override
  String get familyAppsOff => '꺼짐';

  @override
  String get familyAppsNoneYet => '아직 설정된 다른 프로필이 없습니다.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: 설치됨';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: 설치됨, 유지됨';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: 설치되지 않음';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: 설치되지 않음, 유지됨';
  }

  @override
  String get familyAppsUnnamedKids => '어린이 프로필';

  @override
  String get familyAppsUnnamedAdult => '성인 프로필';
}
