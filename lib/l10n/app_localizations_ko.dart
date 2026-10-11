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
  String get systemSettings => 'Google TV 설정';

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
  String get remoteAndSearchTitle => '리모컨';

  @override
  String get parentSettingsTitle => '보호자 설정';

  @override
  String get tvPowerTitle => 'TV 및 전원';

  @override
  String get updatesTitle => '업데이트';

  @override
  String get kidsProfilesTitle => '아이 프로필';

  @override
  String get kidsProfilesUnnamed => '어린이 프로필';

  @override
  String get kidsProfilesReady => '준비됨';

  @override
  String get kidsProfilesNeedsFix => '수정 필요';

  @override
  String kidsProfilesNeedFixCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 수정 필요',
    );
    return '$_temp0';
  }

  @override
  String get kidsProfilesHearthOn => 'Hearth가 있습니다';

  @override
  String get kidsProfilesBothOn => 'Hearth와 HearthTube가 있습니다';

  @override
  String get kidsProfilesHearthMissing => 'Hearth가 없습니다';

  @override
  String get kidsProfilesHearthTubeMissing => 'HearthTube가 없습니다';

  @override
  String get kidsProfilesNotKept => '보호되지 않음: 이 프로필이 다음에 시작될 때 Google TV가 Hearth 앱을 삭제합니다';

  @override
  String get kidsProfilesFix => '수정';

  @override
  String get kidsProfilesFixBody => '빠진 곳에 Hearth와 HearthTube를 다시 넣습니다. 앱이 추가되는 아이마다 Family Link 알림이 한 번 갑니다.';

  @override
  String get kidsProfilesNone => '이 TV에는 아이 프로필이 없습니다.';

  @override
  String get kidsProfilesAutoOn => 'Hearth는 새 아이 프로필에도 스스로 추가됩니다.';

  @override
  String get kidsProfilesApproval => '처음에는 TV에 \'디버깅을 허용하시겠습니까?\'가 표시됩니다. \'항상 허용\'을 선택하세요. 그래야 Hearth가 설정할 수 있습니다.';

  @override
  String get kidsProfilesRemoveTitle => '아이 프로필에서 Hearth 제거';

  @override
  String get kidsProfilesRemoveBody => '아이 프로필에서 Hearth와 HearthTube를 제거하고, 새 프로필에도 더 이상 추가하지 않습니다. Hearth를 제거하기 전에 하세요.';

  @override
  String get kidsProfilesUninstallTitle => 'Hearth 제거';

  @override
  String get kidsProfilesUninstallBody => '먼저 아이 프로필에서 Hearth와 HearthTube를 제거한 다음 Hearth를 제거합니다.';

  @override
  String get kidsProfilesUninstallWhyHere => 'Android 설정이 아니라 여기에서 제거해야 어린이 프로필에 아무것도 남지 않습니다.';

  @override
  String get kidsProfilesApprovalFirstTitle => '먼저 1회 승인을 완료하세요';

  @override
  String get kidsProfilesApprovalFirstBody => 'Hearth가 아직 아이 프로필에서 자신을 제거하지 못했습니다. TV에서 \'디버깅을 허용하시겠습니까?\'를 한 번 승인해야 합니다.';

  @override
  String get kidsProfilesApprovalFirstRetry => '승인한 다음 다시 제거를 시도하세요. 그래야 어린이 프로필에 아무것도 남지 않습니다.';

  @override
  String get kidsProfilesFailedTitle => '아이 프로필을 변경할 수 없습니다';

  @override
  String get kidsProfilesFailedBody => 'Hearth가 아이 프로필을 변경하려면 TV에서 한 번 승인해야 합니다.';

  @override
  String get kidsProfilesFailedRetry => 'TV에 \'디버깅을 허용하시겠습니까?\'가 표시되면 \'항상 허용\'을 선택한 다음 다시 시도하세요.';

  @override
  String get kidProfileHint => '여기 있는 설정은 모두 이 아이만의 것입니다. 아이 프로필로 전환하지 않고도 여기서 바꿀 수 있습니다.';

  @override
  String get kidProfileGetHearthTube => 'HearthTube 받기';

  @override
  String get kidProfileGetHearthTubeBody => '이 TV에 설치한 다음 이 프로필에 추가합니다.';

  @override
  String get kidProfileHearthTubeSettings => 'HearthTube 설정';

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
  String setupAccessibilityInstructions(String service) {
    return '다음 화면에서 \'서비스\'까지 스크롤하여 \'$service\'을(를) 선택한 다음 \'사용\'을 켜고 확인하세요. 홈으로 돌아갈 때까지 뒤로를 누르세요.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Android에서 설정이 제한되었다고 표시되면 컴퓨터에서 다음을 한 번 실행하세요.\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth를 홈 앱으로';

  @override
  String get setupDefaultLauncherWhy => '어린이 프로필에서 Hearth가 차단되지 않게 합니다.';

  @override
  String get setupDefaultLauncherInstructions => '다음 화면에서 Hearth를 선택하세요.';

  @override
  String get setupHomeFixTitle => '홈 버튼 수정';

  @override
  String get setupHomeFixWhy => '홈 버튼을 누르면 Google TV 대신 Hearth가 열립니다.';

  @override
  String get setupNotificationsTitle => '알림 액세스';

  @override
  String get setupNotificationsWhy => '알림과 재생 중인 항목을 표시합니다.';

  @override
  String setupNotificationsInstructions(String service) {
    return '다음 화면에서 \'$service\'을(를) 선택하고 허용하세요.';
  }

  @override
  String get setupInstallTitle => '업데이트 설치';

  @override
  String get setupInstallWhy => 'Hearth가 스스로 업데이트하고 함께 쓰는 앱을 설치할 수 있게 합니다.';

  @override
  String get setupInstallInstructions => '다음 화면에서 Hearth를 켜세요.';

  @override
  String get setupPairingWhy => 'Netflix, Disney+, Apple TV, HBO Max, Paramount+에서 내 프로필을 선택합니다.';

  @override
  String get setupVoiceTitle => 'Hearth 음성';

  @override
  String get setupVoiceWhy => '프로필 연결이 Netflix의 프로필 화면을 들을 수 있게 합니다. 다른 앱은 Google 음성을 그대로 사용합니다.';

  @override
  String setupVoiceInstructions(String engine) {
    return '다음 화면의 \'기본 엔진\'에서 \'$engine\'을(를) 선택하고 경고에서 확인을 누르세요(Hearth는 스트리밍 앱만 듣습니다). 뒤로를 눌러 돌아오세요.';
  }

  @override
  String get setupOpenSettings => '설정 열기';

  @override
  String get setupAdbFallback => '이 TV에서 해당 설정 화면을 열 수 없습니다. 대신 컴퓨터에서 다음을 한 번 실행하세요.';

  @override
  String setupProgress(int done, int total) {
    return '$total개 중 $done개 완료';
  }

  @override
  String get remoteButtonsRemapButton => '버튼 다시 지정';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return '버튼 $keyCode';
  }

  @override
  String get remoteButtonsNormal => '기본';

  @override
  String get remoteButtonsCaptureTitle => '리모컨 버튼을 누르세요';

  @override
  String get remoteButtonsCaptureBody => '다시 지정할 버튼을 누르세요. 취소하려면 뒤로를 누르세요.';

  @override
  String get remoteButtonsNeedsFixTitle => '먼저 홈 버튼 수정을 켜세요';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return '버튼을 다시 지정하려면 홈 버튼 수정이 필요합니다($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => '이 버튼은 다시 지정할 수 없습니다';

  @override
  String get remoteButtonsCantRemapBody => '방향키, 확인, 뒤로, 홈, 전원 버튼은 원래 기능을 유지합니다.';

  @override
  String remoteButtonsPressOption(String action) {
    return '누르기: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return '길게 누르기: $action';
  }

  @override
  String get remoteButtonsSearchPreset => '누르면 Hearth 검색, 길게 누르면 Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Hearth 홈 화면에서만: 켜짐';

  @override
  String get remoteButtonsHomeOnlyOff => 'Hearth 홈 화면에서만: 꺼짐';

  @override
  String get remoteButtonsRestore => '기본 버튼으로 복원';

  @override
  String get remoteButtonsActionTitle => '동작';

  @override
  String get remoteButtonsActionApp => '앱 열기…';

  @override
  String get remoteButtonsActionInput => 'TV 입력으로 전환…';

  @override
  String get remoteButtonsActionSwitchProfile => '프로필 전환(Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth 검색(음성)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth 검색(키보드)';

  @override
  String get remoteButtonsActionHome => 'Hearth 홈';

  @override
  String get remoteButtonsActionSleep => '절전';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android 설정';

  @override
  String get remoteButtonsPickAppTitle => '앱 열기';

  @override
  String get remoteButtonsPickInputTitle => 'TV 입력으로 전환';

  @override
  String get remoteButtonsHaConnectTitle => '먼저 Home Assistant를 연결하세요';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Home Assistant 패널을 설정한 다음($panel > $row) 다시 시도하세요.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return '장면: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return '실행: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return '누르기: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return '전환: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\n누르기: $press  ·  길게 누르기: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\n누르기: $press  ·  길게 누르기: $hold  ·  홈 화면에서만';
  }

  @override
  String remoteButtonsFooter(String path) {
    return '홈 버튼 수정이 필요합니다($path). 길게 누르기 동작만 있는 버튼은 그냥 눌러도 그 동작을 합니다. HearthTube가 앞에 있을 때 Hearth 검색은 HearthTube 자체 검색을 엽니다. 어린이 스크린 타임 화면이 표시되는 동안에는 다시 지정한 버튼이 일시 중지됩니다.';
  }

  @override
  String get tvPowerScreensaver => '화면 보호기(Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth는 Google TV의 화면 보호기를 사용합니다. 그곳에서 Google Photos(와 앨범) 또는 다른 소스를 선택하세요.';

  @override
  String get tvPowerSleepWhenIdle => '사용하지 않을 때 절전';

  @override
  String get tvPowerSleepOff => '꺼짐';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours시간',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return '동영상이나 음악 재생도 사용 중으로 간주됩니다. 홈 버튼 수정이 필요합니다($path).';
  }

  @override
  String get accentPurple => '보라';

  @override
  String get accentTeal => '청록';

  @override
  String get accentBlue => '파랑';

  @override
  String get accentOrange => '주황';

  @override
  String get accentPink => '분홍';

  @override
  String get accentGreen => '초록';

  @override
  String get accentWhite => '흰색';

  @override
  String get accentYellow => '노랑';

  @override
  String get accentRed => '빨강';

  @override
  String get accentCyan => '시안';

  @override
  String get accentIndigo => '남색';

  @override
  String get accentLime => '라임';

  @override
  String get accentAmber => '호박색';

  @override
  String get accentRose => '로즈';

  @override
  String get accentIceBlue => '아이스 블루';

  @override
  String get accentSelected => '선택한 강조 색상';

  @override
  String get cardStyleDefault => '기본';

  @override
  String get cardStylePremium => '프리미엄';

  @override
  String get cardStyleGlow => '글로우';

  @override
  String get cardStyleSquircle => '스퀴클';

  @override
  String get cardStyleClassic => '클래식';

  @override
  String get cardStyleMinimal => '미니멀';

  @override
  String get cardStyleCapsule => '캡슐';

  @override
  String get dockFavoritesDock => '즐겨찾기 독';

  @override
  String get dockFavoritesDockDescription => '즐겨찾기를 홈 화면 하단의 바로 표시하고, 위에는 계속 시청, 아래에는 다른 섹션을 둡니다. 모서리는 카드 스타일을 따릅니다.';

  @override
  String get dockFrosted => '반투명 독';

  @override
  String get dockDark => '어두운 독';

  @override
  String get dockShadow => '독 그림자';

  @override
  String get dockBlurWallpaperBelow => '독 아래 배경화면 흐리게';

  @override
  String get wallpaperMatchSelectedApp => '선택한 앱에 맞추기';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing 오늘의 사진';

  @override
  String get wallpaperRefreshNow => '지금 새로고침';

  @override
  String get wallpaperBingError => 'Bing에 연결할 수 없습니다. 네트워크 연결을 확인하세요.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return '온도 단위: $unit';
  }

  @override
  String get weatherLocationNotSet => '날씨 위치: 설정 안 됨';

  @override
  String weatherLocationValue(String place) {
    return '날씨 위치: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => '날씨를 불러오지 못했습니다. 자동으로 다시 시도합니다.';

  @override
  String get statusBarWeatherSourceHint => '위에서 날씨 위치를 선택하세요(날씨는 Open-Meteo 제공, 무료, 계정 불필요). 선택하지 않으면 Gadgetbridge 공유가 켜진 Breezy Weather 앱이 설치된 경우 해당 앱에서 날씨를 가져옵니다.';

  @override
  String get weatherLocationTitle => '날씨 위치';

  @override
  String get weatherLocationHint => '도시 또는 마을';

  @override
  String get weatherLocationNoResults => '장소를 찾을 수 없습니다';

  @override
  String get weatherLocationSearchError => '날씨 서비스에 연결할 수 없습니다. 네트워크 연결을 확인하세요.';

  @override
  String get weatherLocationPrivacyNote => '날씨 제공: Open-Meteo.com(무료, 계정 불필요). 선택한 장소의 좌표만 전송됩니다.';

  @override
  String get weatherLocationSearch => '검색';

  @override
  String get dateTimeInvalidFormat => '잘못된 형식';

  @override
  String get dateTimeSelectFormats => '아래에서 형식을 선택하세요';

  @override
  String get dataUsageDaily => '일간';

  @override
  String get dataUsageWeekly => '주간';

  @override
  String get dataUsageMonthly => '월간';

  @override
  String cwAppsBlockedHeading(int count) {
    return '계속 시청에서 차단됨($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => '계속 시청에서 차단됨';

  @override
  String get cwAppsUnblock => '차단 해제';

  @override
  String get cwAppsUnblockAllApps => '모든 앱 차단 해제';

  @override
  String get cwAppsNoBlockedApps => '차단된 앱 없음';

  @override
  String get cwAppsNoBlockedAppsMessage => '지원되는 모든 앱이 계속 시청에 항목을 표시할 수 있습니다.';

  @override
  String get cwAppsWithContinueWatching => '계속 시청 지원 앱';

  @override
  String get cwAppsWithContinueWatchingHint => '현재 홈 화면에 Watch Next 항목을 제공하는 앱';

  @override
  String get cwAppsNoActiveApps => '현재 계속 시청 항목을 제공하는 앱이 없습니다.\n지원되는 앱(SmartTube 또는 스트리밍 서비스 등)이 항목을 추가하면 여기에 표시됩니다.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '활성 항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => '설치된 모든 앱';

  @override
  String get cwAppsAllInstalledAppsHint => '끄면 해당 앱이 계속 시청에 항목을 추가하지 못합니다';

  @override
  String get cwAppsBlocked => '차단됨';

  @override
  String get cwAppsAllowed => '허용됨';

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
    return '$height dp($size)';
  }

  @override
  String get cwCardSizeExtraSmall => '초소형';

  @override
  String get cwCardSizeVerySmall => '매우 작음';

  @override
  String get cwCardSizeSmall => '작음';

  @override
  String get cwCardSizeCompact => '컴팩트';

  @override
  String get cwCardSizeMediumSmall => '약간 작음';

  @override
  String get cwCardSizeMedium => '보통';

  @override
  String get cwCardSizeStandardDefault => '표준(기본값)';

  @override
  String get cwCardSizeStandard => '표준';

  @override
  String get cwCardSizeMediumLarge => '약간 큼';

  @override
  String get cwCardSizeLarge => '큼';

  @override
  String get cwCardSizeVeryLarge => '매우 큼';

  @override
  String get cwCardSizeExtraLarge => '특대';

  @override
  String get cwCardSizeHuge => '초대형';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '최근 항목을 최대 $count개 표시',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • 기본값';
  }

  @override
  String get cwUnlimited => '무제한';

  @override
  String get cwMaxItemsAll => '사용 가능한 모든 항목 표시';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => '재생 진행률 표시줄';

  @override
  String get cwPlaybackPercentage => '재생 비율';

  @override
  String get cwEpisodeDetails => '에피소드 및 동영상 세부정보';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 차단됨',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => '관리';

  @override
  String get cwRestoreHiddenPrograms => '숨긴 프로그램 복원';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 숨김',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => '숨긴 프로그램을 모두 복원했습니다';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next 액세스(ADB 필요)';

  @override
  String get cwWatchNextAdbMessage => '런처가 설치된 앱의 계속 시청 행을 읽고 표시하려면 Android TV에서 READ_WRITE_WATCH_NEXT_PROGRAMS 권한이 필요합니다.\n\n이 권한을 부여하려면 ADB로 TV에 연결하고 다음을 실행하세요:';

  @override
  String get appsNoApplicationsFound => '앱을 찾을 수 없습니다';

  @override
  String get appDetailsAddToFavorites => '즐겨찾기에 추가';

  @override
  String get appDetailsRemoveFromFavorites => '즐겨찾기에서 삭제';

  @override
  String get appDetailsAddToCategory => '카테고리에 추가';

  @override
  String get sectionsCustomOption => '사용자 지정...';

  @override
  String get sectionsSelectName => '이름 선택';

  @override
  String get sectionsCustomName => '사용자 지정 이름';

  @override
  String get sectionsSortLastUsed => '최근 사용';

  @override
  String get sectionsReorderHint => '◄ / ►로 선택한 다음 ▲ / ▼로 순서 변경';

  @override
  String get inputsNoneDetected => '감지된 입력이 없습니다';

  @override
  String get notifClearAll => '모두 지우기';

  @override
  String get notifAllCaughtUp => '모두 확인했습니다!';

  @override
  String notifBlockAppNotifications(String app) {
    return '알림 차단($app)';
  }

  @override
  String notifOpenApp(String app) {
    return '$app 열기';
  }

  @override
  String get notifAccessAdbTitle => '알림 액세스(ADB 필요)';

  @override
  String get notifAccessAdbMessage => 'Android TV에는 \'알림 액세스\'(다른 앱의 알림 수신)를 위한 시스템 설정 화면이 없습니다.\n\n참고: TV 앱 설정에서 \'알림 표시\'를 켜면 이 앱이 보내는 알림만 제어되며 알림 액세스는 허용되지 않습니다.\n\n알림 액세스를 허용하려면 ADB로 TV에 연결하고 다음을 실행하세요:';

  @override
  String get notifOpenAppInfo => '앱 정보 열기';

  @override
  String get notifOverlayPermissionTitle => '오버레이 권한';

  @override
  String get notifOverlayAdbMessage => '이 기기에서는 오버레이 권한 설정 화면을 자동으로 열 수 없습니다.\n\n오버레이 팝업을 사용하려면 TV에 연결된 컴퓨터에서 ADB로 직접 권한을 부여하세요:';

  @override
  String blockedNotificationsHeading(int count) {
    return '차단된 앱($count)';
  }

  @override
  String get backupShareText => 'Hearth 백업';

  @override
  String get backupShareFailedTitle => '공유 실패';

  @override
  String backupShareFailed(String error) {
    return '백업 공유 실패: $error';
  }

  @override
  String get backupExportSuccessTitle => '내보내기 성공';

  @override
  String get backupExportFailedTitle => '내보내기 실패';

  @override
  String get backupImportSuccessTitle => '가져오기 성공';

  @override
  String get backupImportFailedTitle => '가져오기 실패';

  @override
  String get backupImport => '가져오기';

  @override
  String backupLoadError(String error) {
    return '백업을 불러오는 중 오류: $error';
  }

  @override
  String get backupNoFiles => '백업 파일을 찾을 수 없습니다.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date($size)';
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
  String get updateCheckForUpdatesTitle => '업데이트 확인';

  @override
  String updateCurrentVersion(String version) {
    return '현재 버전: $version';
  }

  @override
  String get updateChecking => 'GitHub에서 새 릴리스를 확인하는 중…';

  @override
  String get updateUpToDate => '최신 버전을 사용 중입니다.';

  @override
  String updateVersionAvailable(String version) {
    return '버전 $version을(를) 사용할 수 있습니다';
  }

  @override
  String updateDownloading(String percent) {
    return '다운로드 중… $percent%';
  }

  @override
  String get updateDownloadedHint => '다운로드했습니다. 설치 프로그램이 열리지 않으면 기기에서 Hearth에\n\'알 수 없는 앱 설치\' 권한을 허용해야 할 수 있습니다.';

  @override
  String get updateSomethingWentWrong => '문제가 발생했습니다';

  @override
  String get updateDownloadAndInstall => '다운로드 및 설치';

  @override
  String get updateRetryInstall => '설치 다시 시도';

  @override
  String get updateCheckAgain => '다시 확인';

  @override
  String get updatesInstallPermissionTitle => 'Hearth가 앱을 설치하도록 허용';

  @override
  String get updatesInstallPermissionMessage => '다음 화면에서 Hearth를 찾아 켠 다음 뒤로를 누르세요. 여기로 돌아오면 설치가 계속됩니다.';

  @override
  String get updatesOpenSettings => '설정 열기';

  @override
  String get updatesCheckFailed => '업데이트를 확인할 수 없습니다';

  @override
  String get updatesInstallerNotStarted => '설치 프로그램이 시작되지 않았습니다';

  @override
  String get updatesCheckForUpdates => '업데이트 확인';

  @override
  String get updatesAutoUpdate => '자동으로 업데이트';

  @override
  String get updatesAutoUpdateDescription => 'Hearth가 매일 확인하고, 직접 설치한 앱이 사용 중이 아닐 때 업데이트를 설치합니다';

  @override
  String get updatesIncludePrereleases => '사전 출시 버전 포함';

  @override
  String get updatesIncludePrereleasesDescription => 'Hearth 및 HearthTube의 초기 테스트 빌드입니다. 완성되지 않았을 수 있습니다.';

  @override
  String get updatesFooter => '각 앱의 GitHub 릴리스에서 설치합니다. Hearth가 앱을 한 번 설치하거나 업데이트하면 이후 업데이트는 묻지 않고 설치되며, 앱은 업데이트를 Hearth에 맡깁니다.';

  @override
  String get updatesChecking => '확인 중…';

  @override
  String get updatesInstall => '설치';

  @override
  String updatesUpdateTo(String version) {
    return '$version(으)로 업데이트';
  }

  @override
  String get updatesUpToDate => '최신 상태';

  @override
  String updatesDownloadingPercent(int percent) {
    return '다운로드 중 $percent%';
  }

  @override
  String get updatesInstalling => '설치 중…';

  @override
  String get updatesError => '오류';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return '$author의 $launcher 및 $original 기반이며, $parts의 일부를 포함합니다';
  }

  @override
  String get aboutDescription => 'Google TV용 비공개 가족 친화형 런처로, Google TV 프로필과 Home Assistant가 내장되어 있습니다. 광고 및 추적기가 없습니다.';

  @override
  String get aboutHearthOnGitHub => 'GitHub의 Hearth';

  @override
  String get aboutCredits => '크레딧';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher 포크 · $author';
  }

  @override
  String get aboutLicense => '기반이 된 프로젝트와 마찬가지로 GNU GPL v3에 따른 자유 소프트웨어입니다.';

  @override
  String get profilePinRow => '프로필 PIN';

  @override
  String get profilePinNone => '없음';

  @override
  String get profilePinSaved => '저장됨';

  @override
  String get profilePinRejected => '저장됨 — 지난번에 받아들여지지 않음';

  @override
  String get profilePinPaused => '저장됨 — 일시 중지됨(앱이 바뀜)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth는 아직 $app에서 PIN을 입력할 수 없습니다';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$app의 $profile PIN';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return '$app이(가) 요청하면 Hearth가 ‘로그인 중’ 카드 뒤에서 입력합니다. 이 TV에 암호화되어 저장되며 표시되지 않습니다.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return '먼저 보호자 PIN을 설정하세요($settings → $profiles → $parentPin). 프로필 PIN을 저장하려면 필요합니다.';
  }

  @override
  String get profilePinSaveFailed => 'PIN을 저장하지 못했습니다.';

  @override
  String get streamingPinsTitle => '스트리밍 앱 PIN';

  @override
  String get streamingPinsFooter => '여기에는 이 프로필의 PIN만 있습니다. 이 앱들이 이 프로필의 PIN을 요청하면 Hearth가 대신 입력합니다. PIN을 설정하면 이 프로필이 해당 앱 프로필과 계속 연결됩니다.';

  @override
  String get streamingPinsNone => 'Hearth가 PIN을 입력할 수 있는 앱이 설치되어 있지 않습니다.';

  @override
  String get profileLockNow => '프로필 잠금';

  @override
  String get profileLockOnSleep => 'TV가 절전 모드가 되면 잠그기';

  @override
  String get profileLockEveryTime => '매번';

  @override
  String profileLockAfterMinutes(int minutes) {
    return '$minutes분 절전 후';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Google TV 자체의 프로필 잠금을 사용합니다. Google TV 설정 → 계정 및 로그인 → 내 계정 → 프로필 잠금에서 켜세요.';

  @override
  String get aboutWallpaperPhoto => '배경화면 사진';

  @override
  String get updateErrorWrongApp => '이 다운로드는 이 Hearth의 업데이트가 아닙니다';

  @override
  String get notifOpen => '열기';

  @override
  String get notifOpenHint => '확인: 열기 · 왼쪽: 닫기 · 오른쪽: 더 보기';

  @override
  String get tvPowerGoogleTvHome => 'Google TV 홈 사용';

  @override
  String get tvPowerGoogleTvHomeNote => '이 설정을 끌 때까지 Hearth가 나서지 않습니다. 홈 버튼은 계속 Hearth를 엽니다.';

  @override
  String get setupFlowFinishLater => '나중에 마치기';

  @override
  String get setupFlowStripEssentials => '필수';

  @override
  String get setupFlowWelcomeTitle => 'Hearth에 오신 것을 환영합니다';

  @override
  String get setupFlowWelcomeBody => '온 가족을 위한 홈 화면: 내 앱, 보던 콘텐츠, 그리고 모든 스트리밍 앱의 올바른 프로필.';

  @override
  String get setupFlowWelcomeTime => '약 5분 걸립니다. 무엇이든 건너뛸 수 있습니다.';

  @override
  String get setupFlowGetStarted => '시작하기';

  @override
  String get setupFlowSetUpLater => '나중에 설정';

  @override
  String setupFlowLanguageLink(String language) {
    return '언어: $language';
  }

  @override
  String get setupFlowRestoreLink => '백업에서 복원';

  @override
  String get setupFlowHomeButtonTitle => '홈 버튼으로 Hearth 열기';

  @override
  String get setupFlowHomeButtonBody => 'Google TV는 홈 버튼에 자체 홈을 연결해 둡니다. Android 설정의 스위치 하나로 이를 바꿀 수 있고, Hearth가 다음도 할 수 있게 됩니다:';

  @override
  String get setupFlowHomeButtonPoint1 => '프로필 전환과 아이들의 취침 시간 따르기';

  @override
  String get setupFlowHomeButtonPoint2 => '팝업 표시 및 사용하지 않을 때 TV 끄기';

  @override
  String get setupFlowOnNextScreen => '다음 화면에서:';

  @override
  String get setupFlowStepServices => '\'서비스\'까지 스크롤';

  @override
  String setupFlowStepSelect(String name) {
    return '\'$name\' 선택';
  }

  @override
  String get setupFlowStepEnable => '\'사용\'을 켠 다음 \'확인\'';

  @override
  String get setupFlowComesBack => '켜지면 Hearth가 알아서 돌아옵니다. Google TV가 누가 시청 중인지 물으면 본인을 선택하세요.';

  @override
  String get setupFlowOpenAccessibility => '접근성 열기';

  @override
  String get setupFlowHomeButtonDone => '이제 홈 버튼으로 Hearth가 열립니다';

  @override
  String get setupFlowNotOnYetTitle => '아직 켜지지 않았습니다';

  @override
  String get setupFlowNotOnYetBody => '다시 시도하거나, 건너뛰고 나중에 설정에서 하세요.';

  @override
  String get setupFlowStuckTitle => '켜져 있지만 실행되지 않습니다';

  @override
  String get setupFlowStuckBody => 'Android에는 켜짐으로 표시되지만 실행되지 않습니다. 껐다가 다시 켜세요.';

  @override
  String get setupFlowSkipHomeButtonTitle => '홈 버튼 설정을 건너뛸까요?';

  @override
  String get setupFlowSkipHomeButtonBody => '이 설정이 없으면 홈 버튼이 Google TV를 열고, Hearth는 어린이 프로필이 사용 중인지 알 수 없습니다.';

  @override
  String get setupFlowSkipAnyway => '그래도 건너뛰기';

  @override
  String get setupFlowSkip => '건너뛰기';

  @override
  String get setupFlowNext => '다음';

  @override
  String get setupFlowLostTitle => '업데이트로 홈 버튼 설정이 꺼졌습니다';

  @override
  String get setupFlowLostBody => '일부 업데이트 후 Android가 이를 끕니다. 한 단계로 다시 켜세요.';

  @override
  String get setupFlowBlockedTitle => 'Android가 이 스위치를 차단했습니다';

  @override
  String get setupFlowBlockedBody => '스위치가 회색이었다면 Hearth가 다운로드한 파일로 설치되었기 때문입니다. TV에는 이를 허용하는 설정이 없습니다.';

  @override
  String get setupFlowBlockedComputer => '컴퓨터로:';

  @override
  String get setupFlowBlockedComputerThen => '그런 다음 스위치를 켜세요. Hearth가 알아서 감지합니다.';

  @override
  String get setupFlowBlockedSelfFixBody => '디버깅이 켜져 있으므로 Hearth가 직접 해결할 수 있습니다. TV에서 \'디버깅을 허용하시겠습니까?\'라고 물으면 \'항상 허용\'을 선택하세요. Hearth가 스위치 차단을 풀고 켭니다.';

  @override
  String get setupFlowSkipForNow => '지금은 건너뛰기';

  @override
  String get setupFlowBlockedSkipLine => '앱, 검색, 이어 보기는 계속 작동합니다. 홈 버튼, 프로필, 팝업, 취침 타이머는 작동하지 않습니다.';

  @override
  String get setupFlowLetHearthFix => 'Hearth가 해결하기';

  @override
  String get setupFlowFixConfirmBody => 'Hearth가 자체 디버깅 연결로 TV에서 다음을 실행합니다:';

  @override
  String get setupFlowFixConfirmApproval => '처음에는 TV에서 \'디버깅을 허용하시겠습니까?\'라고 묻습니다. \'항상 허용\'을 선택하세요. Hearth 자체의 권한만 바뀝니다.';

  @override
  String get setupFlowFixRun => '실행';

  @override
  String get setupFlowFixWaiting => '처리 중입니다. TV에서 \'디버깅을 허용하시겠습니까?\'라고 물으면 \'항상 허용\'을 선택하세요.';

  @override
  String get setupFlowFixFailedTitle => 'Hearth가 실행하지 못했습니다';

  @override
  String get setupFlowFixFailedBody => 'Hearth가 TV의 디버깅에 연결하지 못했습니다. TV에서 \'디버깅을 허용하시겠습니까?\'라고 물었다면 \'항상 허용\'을 선택하고 다시 시도하세요. 개발자 옵션에서 디버깅이 켜져 있어야 합니다.';

  @override
  String get setupFlowHomeAppTitle => 'Hearth를 홈 앱으로 설정';

  @override
  String get setupFlowHomeAppBody => 'Android에 홈 앱 목록이 표시됩니다. Hearth를 선택하세요. 어린이 프로필이 Hearth를 차단하지 않게 됩니다.';

  @override
  String get setupFlowChooseHearth => 'Hearth 선택';

  @override
  String get setupFlowHomeAppDone => 'Hearth가 홈 앱입니다';

  @override
  String get setupFlowNotChosenTitle => '아직 선택되지 않았습니다';

  @override
  String get setupFlowFinishTitle => 'Hearth 준비 완료';

  @override
  String setupFlowFinishBody(String where) {
    return '건너뛴 항목은 설정에 있으며, $where에서 다시 실행할 수 있습니다.';
  }

  @override
  String get setupFlowFinishOn => '켜짐';

  @override
  String get setupFlowFinishLaterHeading => '나중에 설정에서';

  @override
  String get setupFlowFinishMore => '설정에서 더 보기: 리모컨 버튼, 섹션, 알림, 백업.';

  @override
  String get setupFlowGoHome => '내 홈으로';

  @override
  String get setupHearthTitle => 'Hearth 설정';

  @override
  String get setupRunAgain => '설정 다시 실행';

  @override
  String get setupCardFamily => '가족';

  @override
  String get setupCardWatching => '시청';

  @override
  String setupChipLeft(int count) {
    return '설정 마치기 · $count개 남음';
  }

  @override
  String get setupChipFix => '홈 버튼 설정 필요';

  @override
  String get setupChipHideTitle => '이 알림을 숨길까요?';

  @override
  String setupChipHideBody(String where) {
    return '$where에서 언제든지 설정을 실행할 수 있습니다.';
  }

  @override
  String get setupChipHide => '숨기기';

  @override
  String get setupFlowCardIncluded => '포함된 기능';

  @override
  String get setupFlowCardNeeds => '필요한 것';

  @override
  String get setupFlowTurnOn => '켜기';

  @override
  String get setupFlowNeedsQuestion => 'Android의 질문 한 번';

  @override
  String get setupFlowNeedsOneSwitch => 'Android 설정의 스위치 하나';

  @override
  String get setupFlowNeedsAboutAMinute => '약 1분';

  @override
  String get setupFlowWatchingBenefit => '보던 곳에서 이어 보고, 무엇이 재생 중인지 확인하세요.';

  @override
  String get setupFlowWatchingIncluded1 => '홈 화면의 이어 보기';

  @override
  String get setupFlowWatchingIncluded2 => '알림과 재생 중인 콘텐츠';

  @override
  String get setupFlowSearchWorks => '검색은 이미 작동합니다. 홈 화면에서 검색을 누르세요.';

  @override
  String get setupFlowContinueBody => '앱에서 보던 콘텐츠를 홈 화면에 표시합니다. Android가 한 번 물으면 허용을 선택하세요.';

  @override
  String get setupFlowContinueDone => '이어 보기가 켜졌습니다';

  @override
  String get setupFlowContinueDeniedTitle => 'Android에서 허용하지 않았습니다';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return '나중에 $where에서 켤 수 있습니다.';
  }

  @override
  String get setupFlowNotificationsTitle => '재생 중인 콘텐츠와 알림';

  @override
  String setupFlowNotificationsBody(String name) {
    return '알림과 재생 중인 콘텐츠를 볼 수 있습니다. 다음 화면에서 \"$name\"을(를) 선택하고 허용하세요.';
  }

  @override
  String get setupFlowNotificationsDone => '알림이 켜졌습니다';

  @override
  String get setupFlowTvTitle => '아무도 보지 않을 때 TV를 끌까요?';

  @override
  String get setupFlowTvBody => '리모컨을 이 시간 동안 누르지 않으면 꺼집니다. 동영상이나 음악 재생은 시청으로 봅니다.';

  @override
  String get setupFlowTvNeedsHomeButton => '처음 단계의 홈 버튼 스위치가 필요합니다. 없으면 Hearth가 리모컨 사용 여부를 알 수 없습니다.';

  @override
  String get setupFlowStartOnBoot => 'TV가 시작될 때 Hearth 시작';

  @override
  String get setupFlowScreensaver => '화면 보호기 사진 선택';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth가 자신과 함께 쓰는 앱을 최신 상태로 유지합니다.';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth 자동 업데이트';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, Hearth용 YouTube 앱';

  @override
  String get setupFlowInstallTitle => 'Hearth가 업데이트를 설치하도록 허용';

  @override
  String get setupFlowInstallBody => '다음 화면에서 Hearth를 찾아 켠 다음 뒤로를 누르세요.';

  @override
  String get setupFlowInstallDone => 'Hearth가 업데이트를 설치할 수 있습니다';

  @override
  String get setupFlowTubeTitle => 'HearthTube를 설치할까요?';

  @override
  String get setupFlowTubeBody => 'Hearth용으로 만든 YouTube 앱: 프로필, 시계 스타일, 아이들의 취침 시간을 따릅니다.';

  @override
  String get setupFlowTubeInstalled => 'HearthTube가 설치되었습니다';

  @override
  String get setupCardHome => '내 홈';

  @override
  String get setupFlowLookTitle => '스타일 선택';

  @override
  String setupFlowLookBody(String where) {
    return '선택하면 이 카드 뒤에 바로 보입니다. 나중에 $where에서 무엇이든 바꿀 수 있습니다.';
  }

  @override
  String get setupFlowLookOtherTitle => '내 홈의 스타일을 선택하세요';

  @override
  String get setupFlowLookOtherBody => '프로필마다 홈이 따로 있습니다. 내 홈의 모습을 고르세요.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => '오늘의 사진';

  @override
  String get setupLookCalmDark => '차분한 어둠';

  @override
  String get setupLookBold => '선명하게';

  @override
  String get setupFlowLookNow => '현재';

  @override
  String get setupFlowLookUse => '이 스타일 사용';

  @override
  String get setupFlowLookKeep => '현재 유지';

  @override
  String get setupFlowLookCustomize => '맞춤 설정';

  @override
  String get setupFlowWeatherTitle => '날씨를 표시할까요?';

  @override
  String get setupFlowWeatherBody => '사는 곳을 선택하세요. 위치만 Open-Meteo로 보내며 계정은 필요 없습니다.';

  @override
  String get setupFlowWeatherChoose => '지역 선택';

  @override
  String get setupFlowWeatherDone => '날씨가 상단 바에 표시됩니다';

  @override
  String get setupFlowFamilyBenefit => '스트리밍 앱이 맞는 사람으로 열리고, 아이들은 Hearth를 바꿀 수 없습니다.';

  @override
  String get setupFlowFamilyIncluded1 => '아이들이 Hearth를 바꾸지 못하게 하는 부모 PIN';

  @override
  String get setupFlowFamilyIncluded2 => 'Netflix, Disney+, Apple TV, Max, Paramount+에서 맞는 프로필';

  @override
  String get setupFlowFamilyIncluded3 => '아이 프로필에 Hearth 유지';

  @override
  String get setupFlowNeedsPin => '직접 고르는 숫자 네 자리';

  @override
  String get setupFlowNeedsTwoMinutes => '약 2분';

  @override
  String get setupFlowPinTitle => '부모 PIN 정하기';

  @override
  String get setupFlowPinBody => '아이가 Hearth를 바꾸려면 이 PIN이 필요합니다. 아이가 짐작하지 못할 숫자 네 자리를 고르세요.';

  @override
  String get setupFlowPinChoose => 'PIN 정하기';

  @override
  String get setupFlowPinDone => '부모 PIN이 설정되었습니다';

  @override
  String get setupFlowPairingTitle => '스트리밍 앱에서 맞는 프로필 선택';

  @override
  String setupFlowPairingBody(String name) {
    return 'Hearth가 Netflix, Disney+, Apple TV, Max, Paramount+에서 각 사람의 프로필을 고릅니다. 같은 Android 화면의 스위치가 하나 더 필요합니다: \"$name\".';
  }

  @override
  String get setupFlowPairingDone => '프로필 연결이 켜졌습니다';

  @override
  String get setupFlowPairingDoneBody => 'Hearth가 이름을 알아서 맞춥니다: \"Alex\"는 \"Alex Morgan\"과 연결됩니다. 각 앱의 프로필은 그 앱의 \"누가 보고 있나요?\" 화면이 한 번 나온 뒤에 나타납니다.';

  @override
  String get setupFlowCheckPairings => '연결 확인';

  @override
  String get setupFlowVoiceTitle => 'Netflix를 위한 한 단계 더';

  @override
  String setupFlowVoiceBody(String name) {
    return 'Netflix는 프로필 화면을 소리 내어 읽으므로 Hearth가 자체 음성으로 듣습니다. 다음 화면의 기본 엔진에서 \"$name\"을(를) 선택한 다음 확인을 누르세요. 다른 앱은 Google 음성을 그대로 씁니다.';
  }

  @override
  String get setupFlowVoiceDone => 'Hearth 음성이 켜졌습니다';

  @override
  String get setupFlowKidsTitle => '아이 프로필에 Hearth 유지하기';

  @override
  String get setupFlowKidsBody => 'Google TV는 아이 프로필이 시작될 때마다 직접 설치하지 않은 앱을 지웁니다. Hearth가 그곳에서 자신과 HearthTube를 보호할 수 있습니다. 아이마다 Family Link의 \"앱 추가됨\" 알림이 한 번 갑니다. 설정에서 언제든 되돌릴 수 있습니다.';

  @override
  String get setupFlowKidsApprove => 'TV에서 \"디버깅을 허용하시겠습니까?\"라고 묻습니다. 항상 허용에 체크한 다음 허용을 누르세요. 한 번만 하면 됩니다.';

  @override
  String get setupFlowKidsAdd => '아이 프로필에 추가';

  @override
  String get setupFlowKidsDone => '아이 프로필에 Hearth가 있습니다';

  @override
  String get setupFlowKidsKeepDebugging => '디버깅을 켜 두세요. 새 아이 프로필을 추가하거나 Hearth를 제거하거나 삭제할 때 다시 필요합니다.';

  @override
  String get setupFlowDebugTitle => '먼저 디버깅 켜기';

  @override
  String get setupFlowDebugBody => '아이 프로필을 설정하려면 TV의 디버깅 스위치가 필요합니다. 다음 화면에서 \"Android TV OS 빌드\"를 일곱 번 선택하세요. 그런 다음 설정 > 시스템 > 개발자 옵션에서 USB 디버깅을 켜고 돌아오세요. 켜 두세요. 새 아이 프로필에 다시 필요합니다.';

  @override
  String get setupFlowDebugOpen => '정보 열기';

  @override
  String get setupCardSmartHome => '스마트 홈';

  @override
  String get setupFlowHaBenefit => '초인종 등 알림을 TV에서 보고, Home Assistant 대시보드를 버튼 하나로 엽니다.';

  @override
  String get setupFlowHaIncluded1 => '어떤 앱 위에서도 초인종 등 알림';

  @override
  String get setupFlowHaIncluded2 => '버튼 하나로 여는 대시보드';

  @override
  String get setupFlowHaIncluded3 => '지금 보는 것을 Home Assistant로 전송';

  @override
  String get setupFlowNeedsPhone => '같은 Wi-Fi에 연결된 휴대전화';

  @override
  String get setupFlowNeedsFewMinutes => '몇 분';

  @override
  String get setupFlowHaUse => 'Home Assistant를 사용합니다';

  @override
  String get setupFlowHaAlertsTitle => 'Home Assistant 알림';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'Home Assistant에서 이 TV의 주소 $ip로 \"Notifications for Android TV / Fire TV\"를 추가하세요. 그런 다음 테스트를 보내세요.';
  }

  @override
  String get setupFlowHaAlertsDone => '알림이 켜졌습니다';

  @override
  String get setupFlowHaDashboardTitle => 'TV에서 보는 대시보드';

  @override
  String get setupFlowHaDashboardBody => '휴대전화로 스캔하고 Home Assistant 주소와 토큰을 붙여 넣은 다음 보내기를 누르세요. 관리자가 아닌 TV용으로 만든 Home Assistant 사용자를 쓰세요.';

  @override
  String get setupFlowHaDashboardDone => '대시보드가 설정되었습니다';

  @override
  String get setupFlowHaStatusTitle => 'Home Assistant에 지금 보는 것 알리기';

  @override
  String get setupFlowHaStatusBody => 'TV가 재생 중인 콘텐츠와 현재 프로필을 Home Assistant로 보낼 수 있습니다. 같은 휴대전화 페이지에 Home Assistant 웹훅 자동화의 ID를 넣으세요.';

  @override
  String get setupFlowHaStatusNoWebhook => '휴대전화에서 웹훅 ID를 보내지 않았습니다. 페이지의 마지막 칸을 채우세요.';

  @override
  String get setupFlowHaStatusDone => 'TV가 Home Assistant에 지금 보는 것을 알립니다';

  @override
  String setupChipNewOne(String feature) {
    return 'Hearth 새 기능: $feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'Hearth 새 기능 · $count';
  }

  @override
  String get setupFlowKidsNotAll => '아직 모든 아이 프로필에 Hearth가 있지는 않습니다';

  @override
  String get setupFlowLeaveAsIs => '그대로 두기';

  @override
  String get setupFlowSetUpMissing => '빠진 항목 설정';

  @override
  String get setupFlowChooseAgain => '다시 선택';

  @override
  String get weatherForecastHourly => '시간별';

  @override
  String get weatherForecastDaily => '일별';

  @override
  String get weatherForecastShowDaily => '확인: 일별';

  @override
  String get weatherForecastShowHourly => '확인: 시간별';

  @override
  String get weatherForecastNow => '지금';

  @override
  String get weatherForecastToday => '오늘';

  @override
  String get weatherForecastNone => '아직 예보가 없습니다';

  @override
  String get youTubeLimitTitle => '하루 YouTube 시간';

  @override
  String get youTubeLimitNone => '제한 없음';

  @override
  String youTubeLimitMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes분',
    );
    return '$_temp0';
  }

  @override
  String get youTubeLimitHint => '이 프로필의 HearthTube 시간입니다. Home Assistant를 설정하면 다른 기기와 공유하는 제한도 적용됩니다.';

  @override
  String get haPanelProfileDashboard => '이 프로필의 대시보드';

  @override
  String get haPanelProfileDashboardTv => 'TV와 동일';

  @override
  String get haPanelChooseDashboard => '대시보드 선택';

  @override
  String haPanelChooseView(String dashboard) {
    return '$dashboard의 어떤 보기?';
  }

  @override
  String get haPanelFirstView => '첫 번째 보기';

  @override
  String get haPanelDashboardsError => 'Home Assistant에서 대시보드를 가져오지 못했습니다. 아래 주소와 토큰을 확인하세요.';

  @override
  String get calendar => '캘린더';

  @override
  String get calendarRestOfToday => '오늘 남은 일정';

  @override
  String get calendarShowWeek => '확인: 앞으로 7일';

  @override
  String get calendarNothingToday => '오늘은 더 이상 일정이 없습니다';

  @override
  String get calendarNoTitle => '(제목 없음)';

  @override
  String get calendarAllDay => '종일';

  @override
  String get calendarNow => '지금';

  @override
  String calendarUntil(String time) {
    return '$time까지';
  }

  @override
  String get calendarTomorrow => '내일';

  @override
  String calendarMore(int count) {
    return '+$count개 더';
  }

  @override
  String calendarNextDays(int days) {
    return '앞으로 $days일';
  }

  @override
  String calendarNothingWeek(int days) {
    return '앞으로 $days일 동안 일정이 없습니다';
  }

  @override
  String get haCalendarsTitle => '캘린더';

  @override
  String get haCalendarsLoading => 'Home Assistant에 캘린더를 요청하는 중…';

  @override
  String haCalendarsNotSetUp(String place) {
    return '이 TV에는 아직 Home Assistant가 설정되지 않았습니다. $place에서 주소와 토큰을 추가하세요.';
  }

  @override
  String get haCalendarsError => 'Home Assistant에서 캘린더를 가져오지 못했습니다. 주소와 토큰을 확인하세요.';

  @override
  String get haCalendarsNone => 'Home Assistant에 캘린더가 없습니다.';

  @override
  String get haCalendarsHelp => '여기서 켠 캘린더는 오른쪽 위의 날짜와 시간에 포커스가 있을 때 표시됩니다: 오늘 남은 일정, 확인을 누르면 앞으로 7일. 프로필마다 따로 고릅니다.';
}
