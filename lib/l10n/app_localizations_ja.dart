import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get aboutFlauncher => 'Hearthについて';

  @override
  String get addSection => 'セクションを追加';

  @override
  String get alphabetical => 'アルファベット順';

  @override
  String get appCardHighlightAnimation => 'アプリカードのハイライトアニメーション';

  @override
  String get appInfo => 'アプリ情報';

  @override
  String get appKeyClick => 'キー押下時のクリック音';

  @override
  String get applications => 'アプリケーション';

  @override
  String get autoHideAppBar => 'ステータスバーを自動非表示';

  @override
  String get backButtonAction => '戻るボタンの動作';

  @override
  String get category => 'カテゴリ';

  @override
  String get columnCount => '列数';

  @override
  String get date => '日付';

  @override
  String get dateAndTimeFormat => '日付と時刻の形式';

  @override
  String get delete => '削除';

  @override
  String get dialogOptionBackButtonActionDoNothing => '何もしない';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'スクリーンセーバーを表示';

  @override
  String get dialogOptionBackButtonActionShowClock => '時計を表示';

  @override
  String get dialogTextNoFileExplorer => '画像を選択するにはファイルエクスプローラーをインストールしてください。';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (カテゴリ)';
  }

  @override
  String get gradient => 'グラデーション';

  @override
  String get favoriteApps => 'お気に入りアプリ';

  @override
  String get grid => 'グリッド';

  @override
  String get height => '高さ';

  @override
  String get hide => '非表示';

  @override
  String get hiddenApplications => '非表示のアプリ';

  @override
  String get launcherSections => 'セクション';

  @override
  String get layout => 'レイアウト';

  @override
  String get loading => '読み込み中';

  @override
  String get manual => '手動';

  @override
  String get modifySection => 'セクションを変更';

  @override
  String get name => '名前';

  @override
  String get newSection => '新しいセクション';

  @override
  String get nonTvApplications => '非TVアプリ';

  @override
  String get open => '開く';

  @override
  String get picture => '画像';

  @override
  String removeFrom(String name) {
    return '$nameから削除';
  }

  @override
  String get reorder => '並べ替え';

  @override
  String get row => '行';

  @override
  String get rowHeight => '行の高さ';

  @override
  String get save => '保存';

  @override
  String get spacer => 'スペーサー';

  @override
  String get statusBar => 'ステータスバー';

  @override
  String get show => '表示';

  @override
  String get showCategoryTitles => 'カテゴリタイトルを表示';

  @override
  String get showCategoryAppCount => 'カテゴリ内のアプリ数を表示';

  @override
  String get hideHighlightOutlineOnHomescreen => 'ホーム画面でハイライトのアウトラインを非表示';

  @override
  String get appSelectorTransitionAnimation => 'アプリセレクターの遷移アニメーション';

  @override
  String get sort => '並べ替え';

  @override
  String get systemSettings => 'Google TV の設定';

  @override
  String get textEmptyCategory => 'このカテゴリは空です。';

  @override
  String get time => '時刻';

  @override
  String get tvApplications => 'TVアプリ';

  @override
  String get type => '種類';

  @override
  String get uninstall => 'アンインストール';

  @override
  String get wallpaper => '壁紙';

  @override
  String get withEllipsisAddTo => '追加...';

  @override
  String get timeBasedWallpaper => '時間ベースの壁紙';

  @override
  String get pickDayWallpaper => '昼の壁紙を選択';

  @override
  String get pickNightWallpaper => '夜の壁紙を選択';

  @override
  String get inputs => '入力';

  @override
  String get inputSources => '入力ソース';

  @override
  String get backupAndRestore => 'バックアップと復元';

  @override
  String get exportBackup => 'バックアップをエクスポート';

  @override
  String get importBackup => 'バックアップをインポート';

  @override
  String exportSuccess(String path) {
    return 'バックアップが$pathに正常にエクスポートされました';
  }

  @override
  String get importSuccess => 'バックアップが正常にインポートされました';

  @override
  String get importConfirm => 'バックアップをインポートしますか？現在の設定とレイアウトが上書きされます。';

  @override
  String importError(String error) {
    return 'バックアップのインポートに失敗しました: $error';
  }

  @override
  String exportError(String error) {
    return 'バックアップのエクスポートに失敗しました: $error';
  }

  @override
  String get shareBackup => 'バックアップを共有';

  @override
  String get notificationBell => '通知ベル';

  @override
  String get autoHideNotificationBell => '通知ベルを自動非表示';

  @override
  String get continueWatching => '続きを見る';

  @override
  String get showContinueWatchingOnHome => 'ホームに「続きを見る」を表示';

  @override
  String get permissionDeniedContinueWatching => '「続きを見る」を表示するには権限が必要です';

  @override
  String get system => 'システム';

  @override
  String get accentColor => 'アクセントカラー';

  @override
  String get dataUsagePeriod => 'データ使用期間';

  @override
  String get notificationAccess => '通知アクセス';

  @override
  String get watchNextAccess => 'Watch Next へのアクセス';

  @override
  String get granted => '許可済み';

  @override
  String get permissionRequired => '権限が必要です';

  @override
  String get systemWidePopupAlert => 'システム全体のポップアップアラート';

  @override
  String get overlayPermissionRequired => 'オーバーレイ権限が必要です';

  @override
  String get enabled => '有効';

  @override
  String get disabled => '無効';

  @override
  String get showAppNamesBelowIcons => 'アイコンの下にアプリ名を表示';

  @override
  String get dataUsage => 'データ使用量';

  @override
  String get networkIndicator => 'ネットワークインジケーター';

  @override
  String get startOnBoot => '起動時に開始 (Google TV / Fire TV)';

  @override
  String get appLanguage => '言語';

  @override
  String get systemDefault => 'システムのデフォルト';

  @override
  String get english => '英語';

  @override
  String get spanish => 'スペイン語';

  @override
  String get ukrainian => 'ウクライナ語';

  @override
  String get chinese => '中国語';

  @override
  String get french => 'フランス語';

  @override
  String get german => 'ドイツ語';

  @override
  String get japanese => '日本語';

  @override
  String get portuguese => 'ポルトガル語';

  @override
  String get russian => 'ロシア語';

  @override
  String get italian => 'イタリア語';

  @override
  String get hindi => 'ヒンディー語';

  @override
  String get korean => '韓国語';

  @override
  String get arabic => 'アラビア語';

  @override
  String get turkish => 'トルコ語';

  @override
  String get hidePersistentNotifications => '常駐通知を非表示';

  @override
  String get blockedNotificationApps => 'ブロックされたアプリ';

  @override
  String get unblockAppNotifications => '通知のブロックを解除';

  @override
  String get noBlockedApps => 'ブロックされたアプリはありません';

  @override
  String get persistentNotification => '常駐';

  @override
  String get unblockAll => 'すべてブロック解除';

  @override
  String get weather => '天気';

  @override
  String get showWeatherWarnings => '天気と雨の警告を表示';

  @override
  String get celsius => '摂氏 (°C)';

  @override
  String get fahrenheit => '華氏 (°F)';

  @override
  String get notifications => '通知';

  @override
  String get continueWatchingDescription => 'ホーム画面に最近再生した映画や番組を表示します';

  @override
  String get dismiss => '非表示';

  @override
  String get noBlockedAppsDesc => '現在、すべてのアプリで通知の表示が許可されています';

  @override
  String get notificationsAllowed => '通知を許可';

  @override
  String get notificationsBlocked => '通知をブロック';

  @override
  String get dpadDismissHint => '左: 非表示 • OK: オプション';

  @override
  String get settingsTitle => '設定';

  @override
  String get profilesTitle => 'プロフィール';

  @override
  String get homeScreenTitle => 'ホーム画面';

  @override
  String get remoteAndSearchTitle => 'リモコン';

  @override
  String get parentSettingsTitle => '保護者の設定';

  @override
  String get tvPowerTitle => 'テレビと電源';

  @override
  String get updatesTitle => 'アップデート';

  @override
  String get kidsProfilesTitle => '子どものプロフィール';

  @override
  String get kidsProfilesUnnamed => 'キッズプロフィール';

  @override
  String get kidsProfilesReady => '準備完了';

  @override
  String get kidsProfilesNeedsFix => '修正が必要';

  @override
  String kidsProfilesNeedFixCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の修正が必要',
    );
    return '$_temp0';
  }

  @override
  String get kidsProfilesHearthOn => 'Hearth が入っています';

  @override
  String get kidsProfilesBothOn => 'Hearth と HearthTube が入っています';

  @override
  String get kidsProfilesHearthMissing => 'Hearth が入っていません';

  @override
  String get kidsProfilesHearthTubeMissing => 'HearthTube が入っていません';

  @override
  String get kidsProfilesNotKept => '保護されていません：このプロフィールを次に開いたとき、Hearth のアプリは Google TV に削除されます';

  @override
  String get kidsProfilesFix => '修正';

  @override
  String get kidsProfilesFixBody => '足りないところに Hearth と HearthTube を戻します。追加されたお子さまごとに Family Link の通知が 1 回届きます。';

  @override
  String get kidsProfilesNone => 'このテレビには子どものプロフィールがありません。';

  @override
  String get kidsProfilesAutoOn => '新しい子どものプロフィールにも、Hearth が自動で入ります。';

  @override
  String get kidsProfilesApproval => '初回はテレビに「デバッグを許可しますか？」と表示されます。「常に許可」を選んでください。これで Hearth が設定を行えます。';

  @override
  String get kidsProfilesRemoveTitle => '子どものプロフィールから Hearth を削除';

  @override
  String get kidsProfilesRemoveBody => '子どものプロフィールから Hearth と HearthTube を削除し、新しいプロフィールにも追加しなくなります。Hearth をアンインストールする前に行ってください。';

  @override
  String get kidsProfilesUninstallTitle => 'Hearth をアンインストール';

  @override
  String get kidsProfilesUninstallBody => 'まず子どものプロフィールから Hearth と HearthTube を削除し、そのあと Hearth をアンインストールします。';

  @override
  String get kidsProfilesUninstallWhyHere => 'Android の設定ではなくここからアンインストールすると、キッズプロフィールに何も残りません。';

  @override
  String get kidsProfilesApprovalFirstTitle => '先に 1 回限りの許可を済ませてください';

  @override
  String get kidsProfilesApprovalFirstBody => 'Hearth はまだ子どものプロフィールから自分を削除できませんでした。テレビで「デバッグを許可しますか？」を 1 回許可する必要があります。';

  @override
  String get kidsProfilesApprovalFirstRetry => '許可してから、もう一度アンインストールをお試しください。キッズプロフィールに何も残りません。';

  @override
  String get kidsProfilesFailedTitle => '子どものプロフィールを変更できませんでした';

  @override
  String get kidsProfilesFailedBody => '子どものプロフィールを変更するには、テレビで Hearth を 1 回だけ許可する必要があります。';

  @override
  String get kidsProfilesFailedRetry => 'テレビに「デバッグを許可しますか？」と表示されたら「常に許可」を選んで、もう一度お試しください。';

  @override
  String get kidProfileHint => 'ここにある設定はすべてこのお子さま専用です。お子さまのプロフィールに切り替えなくても、ここから変更できます。';

  @override
  String get kidProfileGetHearthTube => 'HearthTube を入手';

  @override
  String get kidProfileGetHearthTubeBody => 'このテレビにインストールしてから、このプロフィールに追加します。';

  @override
  String get kidProfileHearthTubeSettings => 'HearthTube の設定';

  @override
  String get cardStyleTitle => 'カードのスタイル';

  @override
  String get dockLabelsTitle => 'ドックとラベル';

  @override
  String get animationsSoundTitle => 'アニメーションとサウンド';

  @override
  String get haPanelTitle => 'ダッシュボードパネル';

  @override
  String get lookTitle => '外観';

  @override
  String get remoteButtonsTitle => 'リモコンのボタン';

  @override
  String get profilePairingTitle => 'プロフィールの連携';

  @override
  String get haTvStatusTitle => 'テレビの状態';

  @override
  String get continueWatchingAppsTitle => '「続きを見る」のアプリ';

  @override
  String get cardSizeTitle => 'カードのサイズ';

  @override
  String get maxItemsTitle => '最大アイテム数';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get tryAgain => '再試行';

  @override
  String get notNow => '後で';

  @override
  String get done => '完了';

  @override
  String get remove => '削除';

  @override
  String get homeNothingToWatch => '今見られるものはありません';

  @override
  String get errorScreenTitle => '問題が発生しました';

  @override
  String get appInfoAddToCategory => 'カテゴリに追加';

  @override
  String get appInfoAddToFavorites => 'お気に入りに追加';

  @override
  String get appInfoRemoveFromFavorites => 'お気に入りから削除';

  @override
  String get appInfoSetCustomBanner => 'カスタムバナーを設定';

  @override
  String get appInfoClearCustomBanner => 'カスタムバナーを解除';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'バナーを設定できませんでした: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'バナーを解除できませんでした: $error';
  }

  @override
  String get cwGridAll => 'すべて';

  @override
  String get cwRowSeeAll => 'すべて表示';

  @override
  String cwRowInProgress(int count) {
    return '視聴中 $count 件';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return '残り $hours 時間 $minutes 分';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return '残り $minutes 分';
  }

  @override
  String get watchNextInfoRemove => '「続きを見る」から削除';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return '$appName のすべてを非表示';
  }

  @override
  String get watchNextInfoPlayResume => '再生 / 再開';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '$appName を開く';
  }

  @override
  String get watchNextInfoAppInfo => 'アプリ情報';

  @override
  String get dataWidgetGrantPermission => '使用状況へのアクセスを許可';

  @override
  String dataWidgetDaily(String usage) {
    return '1日: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return '1週間: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return '1か月: $usage';
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
        'today': '今日は雨',
        'tomorrow': '明日は雨',
        'other': '$day曜日は雨',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '今日は雪',
        'tomorrow': '明日は雪',
        'other': '$day曜日は雪',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': '今日は雷雨',
        'tomorrow': '明日は雷雨',
        'other': '$day曜日は雷雨',
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
    return '$apps で見る';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return '$app でレンタル・購入';
  }

  @override
  String get searchMoreWaysToWatch => 'その他の視聴方法 (Google TV)';

  @override
  String get searchListening => '聞き取り中…';

  @override
  String get searchHint => '映画や番組を検索';

  @override
  String get searchEntryHelp => '入力するか、マイクを使うか、Google TV アプリでスマートフォンから入力してください。';

  @override
  String get searchTabWatchNow => '今すぐ見る';

  @override
  String get searchTabRentOrBuy => 'レンタル・購入';

  @override
  String get searchTabOtherApps => 'その他のアプリ';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'レンタル・購入 · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => '視聴方法: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return '$services で配信中 (このテレビにはありません)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の結果',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'ここには「$query」に該当するものはありません。';
  }

  @override
  String get searchGridTmdbNotice => '視聴情報は TMDB (JustWatch 経由) によるものです。この製品は TMDB API を使用していますが、TMDB による承認や認定は受けていません。';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps または $last';
  }

  @override
  String get searchListSeparator => '、';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Google に聞く:「$query」';
  }

  @override
  String get searchAskGoogleDetail => '質問や天気など、番組以外のことはこちら';

  @override
  String searchSearchingFor(String query) {
    return '「$query」を検索中…';
  }

  @override
  String get searchFailed => '現在検索できません。インターネット接続を確認してください。';

  @override
  String searchNothingFound(String query) {
    return '「$query」は見つかりませんでした';
  }

  @override
  String searchNothingInYourApps(String query) {
    return '今のところ、お使いのアプリに「$query」はありません';
  }

  @override
  String get searchSeeMoreResults => 'ほかの視聴先は「その他の結果」で確認できます。';

  @override
  String get searchMoreResults => 'その他の結果';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のタイトル',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Google に聞く';

  @override
  String searchQuoted(String query) {
    return '「$query」';
  }

  @override
  String get searchKindFilm => '映画';

  @override
  String get searchKindSeries => 'シリーズ';

  @override
  String get gradientNamePitchBlack => '漆黒';

  @override
  String get gradientNameGreatWhale => '大きなクジラ';

  @override
  String get gradientNameViciousStance => '凶暴な構え';

  @override
  String get gradientNameTeenNotebook => 'ティーンのノート';

  @override
  String get gradientNameOldHat => '古い帽子';

  @override
  String get gradientNameBurningSpring => '燃える春';

  @override
  String get gradientNameDesertHump => '砂漠の丘';

  @override
  String get gradientNameFarawayRiver => '遠い川';

  @override
  String get gradientNameSaintPetersburg => 'サンクトペテルブルク';

  @override
  String get gradientNameAfricanField => 'アフリカの草原';

  @override
  String get gradientNameGrassShampoo => '草のシャンプー';

  @override
  String get updateErrorNoApk => 'このデバイス用の APK があるリリースはありません';

  @override
  String get updateErrorCheckFailed => 'アップデートを確認できませんでした';

  @override
  String get updateErrorDownloadFailed => 'アップデートをダウンロードできませんでした';

  @override
  String get serviceHearthTubeDescription => 'Hearth 用の YouTube。Hearth のプロフィールに連動します';

  @override
  String get haSummaryOn => 'オン';

  @override
  String get haSummaryOff => 'オフ';

  @override
  String get haSummaryReporting => '送信中';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'ホームボタン修正をオンにしてください（$path）。ポップアップはこの機能で表示されます。';
  }

  @override
  String get haNotificationsShow => 'Home Assistant の通知を表示';

  @override
  String get haNotificationsSendTest => 'テスト通知を送信';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Home Assistant で、ホスト $host を指定して「Notifications for Android TV / Fire TV」統合を追加します。あとはオートメーションから通知を送ります（例：玄関のチャイムや洗濯の完了時）。\n\n送信できるのはホームネットワーク内のデバイスだけです（ポート 7676）。ポップアップはどのアプリの上にも表示され、ホームボタン修正（$path）をオンにする必要があります。';
  }

  @override
  String get haNotificationsThisTvIp => '（このテレビの IP アドレス）';

  @override
  String get haPanelSaved => '保存しました';

  @override
  String get haPanelSavedNoToken => '保存しました。サインインするにはアクセストークンを追加してください。';

  @override
  String get haPanelReceived => 'スマートフォンからアドレスとトークンを受信しました';

  @override
  String get haPanelRightEdge => '右端で右を押すとパネルを開く';

  @override
  String get haSetUpFromPhone => 'スマートフォンで設定';

  @override
  String get haPanelTokenLabel => '長期アクセストークン';

  @override
  String get haPanelTokenSavedHint => '保存済み（置き換えるには新しいトークンを入力）';

  @override
  String get haPanelDashboardLabel => 'ダッシュボード';

  @override
  String haPanelHelp(String tvStatus) {
    return 'このプロフィールでのみオンになります。パネルには $tvStatus のアドレスのダッシュボードが、トークンでサインインした状態で表示されます。トークンは、このテレビ用に作成した管理者ではないユーザーで Home Assistant にログインして作成してください（プロフィールページの「セキュリティ」タブ）。';
  }

  @override
  String get haStatusReportingOff => '状態の送信はオフです';

  @override
  String get haStatusSaved => '保存しました：Home Assistant に送信中';

  @override
  String get haStatusAddressLabel => 'Home Assistant のアドレス';

  @override
  String get haStatusWebhookLabel => 'Webhook ID';

  @override
  String get haStatusNowPlayingOn => '再生中の情報：オン';

  @override
  String get haStatusNowPlayingOff => '再生中の情報：通知へのアクセスをオンにする';

  @override
  String get haStatusHelp => 'テレビは表示中の内容（アプリ、再生中のもの、Google TV のプロフィール、子どものスクリーンタイム）を Home Assistant に送ります。送信先は上のアドレスのみで、変化があったときに送信します。';

  @override
  String get haPhoneSetupNoNetwork => 'このテレビはホームネットワークに接続されていないため、スマートフォンから接続できません。';

  @override
  String get haPhoneSetupScan => '同じ Wi-Fi に接続したスマートフォンでスキャンし、Home Assistant のアドレスとアクセストークンを貼り付けて「Send」をタップします。このページはこの画面を開いている間だけ使えます。';

  @override
  String get profilesSwitchProfile => 'プロフィールを切り替え';

  @override
  String get parentPinTitle => '保護者用 PIN';

  @override
  String get parentPinOn => 'オン';

  @override
  String get parentPinOff => 'オフ';

  @override
  String get parentPinCurrent => '現在の保護者用 PIN';

  @override
  String get parentPinRemove => 'PIN を削除';

  @override
  String get parentPinChange => 'PIN を変更';

  @override
  String get parentPinNew => '新しい保護者用 PIN';

  @override
  String get parentPinNewSubtitle => 'Google TV のキッズプロフィールでランチャーを変更するときに必要です';

  @override
  String get parentPinConfirm => 'PIN をもう一度入力';

  @override
  String get parentPinAskTitle => '保護者に頼んでください';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'キッズプロフィールではランチャーの設定がロックされています。保護者が自分のプロフィールから $settings → $profiles → $parentPin で PIN を設定できます。';
  }

  @override
  String get parentPinKidsSubtitle => 'キッズプロフィール：ランチャーを変更するには保護者用 PIN を入力してください';

  @override
  String get parentPinWrong => 'PIN が違います';

  @override
  String get parentPinEnter => 'PIN を入力';

  @override
  String profileSwitchGreeting(String name) {
    return 'こんにちは、$name さん';
  }

  @override
  String get profileSwitchSettingUp => 'このプロフィールを準備しています…';

  @override
  String profilesKidsName(String name) {
    return '$name（キッズ）';
  }

  @override
  String get pairingShowPicker => '選択画面を表示';

  @override
  String get pairingAlwaysShowPicker => '常に選択画面を表示';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile（名前で一致）';
  }

  @override
  String get pairingNoMatchYet => '一致なし：選択画面を表示';

  @override
  String get pairingOffSetUp => 'プロフィールの連携はオフです。設定する';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Hearth がこれらのアプリを開くと、Google TV のプロフィールと連携したアプリのプロフィールを選びます。名前は Hearth が自動で照合し（「$shortName」と「$fullName」など）、連携はここで変更できます。一致しない場合はアプリ自体の選択画面が表示されます。';
  }

  @override
  String get pairingAppNotInstalled => '未インストール';

  @override
  String get pairingAppOff => 'オフ：アプリ自体の選択画面を表示';

  @override
  String get pairingAppNotSeen => 'Hearth から一度開くと、Hearth がプロフィールを読み取ります';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'プロフィールが $count 件見つかりました',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return '名前で照合（$profile）';
  }

  @override
  String get pairingMatchByNameNone => '名前で照合（一致なし）';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$app での $profile';
  }

  @override
  String pairingPairIn(String app) {
    return '$app のプロフィールを連携';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth はまだこのアプリのプロフィールを読み取っていません。Hearth から一度開いてから戻ってください。';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'このアプリのプロフィール：$profiles。Google TV のプロフィールは、Hearth が読み取るとここに表示されます。';
  }

  @override
  String setupAccessibilityInstructions(String service) {
    return '次の画面で「サービス」までスクロールし、「$service」を選んで「有効にする」をオンにし、確認します。ホームに戻るまで「戻る」を押してください。';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Android で設定が制限されていると表示された場合は、パソコンから次を 1 回実行してください：\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth をホームアプリに';

  @override
  String get setupDefaultLauncherWhy => 'キッズプロフィールで Hearth がブロックされないようにします。';

  @override
  String get setupDefaultLauncherInstructions => '次の画面で Hearth を選んでください。';

  @override
  String get setupHomeFixTitle => 'ホームボタン修正';

  @override
  String get setupHomeFixWhy => 'ホームボタンで Google TV ではなく Hearth が開きます。';

  @override
  String get setupNotificationsTitle => '通知へのアクセス';

  @override
  String get setupNotificationsWhy => '通知と再生中の内容を表示します。';

  @override
  String setupNotificationsInstructions(String service) {
    return '次の画面で「$service」を選んで許可してください。';
  }

  @override
  String get setupInstallTitle => 'アップデートのインストール';

  @override
  String get setupInstallWhy => 'Hearth が自身を更新し、関連アプリをインストールできるようにします。';

  @override
  String get setupInstallInstructions => '次の画面で Hearth をオンにしてください。';

  @override
  String get setupPairingWhy => 'Netflix、Disney+、Apple TV、HBO Max、Paramount+ であなたのプロフィールを選びます。';

  @override
  String get setupVoiceTitle => 'Hearth の音声';

  @override
  String get setupVoiceWhy => 'プロフィールの連携が Netflix のプロフィール画面を聞き取れるようにします。他のアプリでは Google の音声のままです。';

  @override
  String setupVoiceInstructions(String engine) {
    return '次の画面の「優先するエンジン」で「$engine」を選び、警告で「OK」を押します（Hearth が聞き取るのはストリーミングアプリだけです）。「戻る」を押して戻ってください。';
  }

  @override
  String get setupOpenSettings => '設定を開く';

  @override
  String get setupAdbFallback => 'このテレビではその設定画面を開けませんでした。代わりにパソコンから次を 1 回実行してください：';

  @override
  String setupProgress(int done, int total) {
    return '$total 件中 $done 件完了';
  }

  @override
  String get remoteButtonsRemapButton => 'ボタンの割り当てを変更';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'ボタン $keyCode';
  }

  @override
  String get remoteButtonsNormal => '通常';

  @override
  String get remoteButtonsCaptureTitle => 'リモコンのボタンを押してください';

  @override
  String get remoteButtonsCaptureBody => '割り当てを変更するボタンを押してください。キャンセルするには「戻る」を押します。';

  @override
  String get remoteButtonsNeedsFixTitle => '先にホームボタン修正をオンにしてください';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return '割り当ての変更にはホームボタン修正が必要です（$path）。';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'このボタンは割り当てを変更できません';

  @override
  String get remoteButtonsCantRemapBody => '方向キー、決定、戻る、ホーム、電源は通常の動作のままです。';

  @override
  String remoteButtonsPressOption(String action) {
    return '押す：$action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return '長押し：$action';
  }

  @override
  String get remoteButtonsSearchPreset => '押すと Hearth 検索、長押しで Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Hearth のホーム画面でのみ：オン';

  @override
  String get remoteButtonsHomeOnlyOff => 'Hearth のホーム画面でのみ：オフ';

  @override
  String get remoteButtonsRestore => '通常のボタンに戻す';

  @override
  String get remoteButtonsActionTitle => '動作';

  @override
  String get remoteButtonsActionApp => 'アプリを開く…';

  @override
  String get remoteButtonsActionInput => 'テレビの入力を切り替え…';

  @override
  String get remoteButtonsActionSwitchProfile => 'プロフィールを切り替え（Google TV）';

  @override
  String get remoteButtonsActionSearchVoice => 'Hearth 検索（音声）';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Hearth 検索（キーボード）';

  @override
  String get remoteButtonsActionHome => 'Hearth のホーム';

  @override
  String get remoteButtonsActionSleep => 'スリープ';

  @override
  String get remoteButtonsActionAndroidSettings => 'Android の設定';

  @override
  String get remoteButtonsPickAppTitle => 'アプリを開く';

  @override
  String get remoteButtonsPickInputTitle => 'テレビの入力を切り替え';

  @override
  String get remoteButtonsHaConnectTitle => '先に Home Assistant に接続してください';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Home Assistant のパネルを設定してから（$panel > $row）、もう一度お試しください。';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'シーン：$name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return '実行：$name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return '押す：$name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return '切り替え：$name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\n押す：$press  ·  長押し：$hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\n押す：$press  ·  長押し：$hold  ·  ホーム画面のみ';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'ホームボタン修正が必要です（$path）。長押しの動作だけを設定したボタンは、普通に押したときもその動作をします。HearthTube の表示中は、Hearth 検索で HearthTube 自体の検索が開きます。子どものスクリーンタイムの画面が表示されている間は、割り当ての変更は一時停止します。';
  }

  @override
  String get tvPowerScreensaver => 'スクリーンセーバー（Google Photos）';

  @override
  String get tvPowerScreensaverNote => 'Hearth は Google TV のスクリーンセーバーを使います。そこで Google Photos（とアルバム）や他のソースを選んでください。';

  @override
  String get tvPowerSleepWhenIdle => '操作がないときにスリープ';

  @override
  String get tvPowerSleepOff => 'オフ';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes 分';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours 時間',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return '動画や音楽の再生も操作とみなされます。ホームボタン修正が必要です（$path）。';
  }

  @override
  String get accentPurple => 'パープル';

  @override
  String get accentTeal => 'ティール';

  @override
  String get accentBlue => 'ブルー';

  @override
  String get accentOrange => 'オレンジ';

  @override
  String get accentPink => 'ピンク';

  @override
  String get accentGreen => 'グリーン';

  @override
  String get accentWhite => 'ホワイト';

  @override
  String get accentYellow => 'イエロー';

  @override
  String get accentRed => 'レッド';

  @override
  String get accentCyan => 'シアン';

  @override
  String get accentIndigo => 'インディゴ';

  @override
  String get accentLime => 'ライム';

  @override
  String get accentAmber => 'アンバー';

  @override
  String get accentRose => 'ローズ';

  @override
  String get accentIceBlue => 'アイスブルー';

  @override
  String get accentSelected => '選択中のアクセント';

  @override
  String get cardStyleDefault => 'デフォルト';

  @override
  String get cardStylePremium => 'プレミアム';

  @override
  String get cardStyleGlow => 'グロー';

  @override
  String get cardStyleSquircle => 'スクワークル';

  @override
  String get cardStyleClassic => 'クラシック';

  @override
  String get cardStyleMinimal => 'ミニマル';

  @override
  String get cardStyleCapsule => 'カプセル';

  @override
  String get dockFavoritesDock => 'お気に入りドック';

  @override
  String get dockFavoritesDockDescription => 'お気に入りをホーム画面下部のバーとして表示し、その上に「続きを見る」、下にほかのセクションを並べます。角の形はカードのスタイルに合わせます。';

  @override
  String get dockFrosted => 'すりガラスのドック';

  @override
  String get dockDark => 'ダークドック';

  @override
  String get dockShadow => 'ドックの影';

  @override
  String get dockBlurWallpaperBelow => 'ドックの下の壁紙をぼかす';

  @override
  String get wallpaperMatchSelectedApp => '選択中のアプリに合わせる';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Bing の今日の写真';

  @override
  String get wallpaperRefreshNow => '今すぐ更新';

  @override
  String get wallpaperBingError => 'Bing に接続できませんでした。ネットワーク接続を確認してください。';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return '温度単位: $unit';
  }

  @override
  String get weatherLocationNotSet => '天気の地域: 未設定';

  @override
  String weatherLocationValue(String place) {
    return '天気の地域: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => '天気を読み込めませんでした。自動的に再試行します。';

  @override
  String get statusBarWeatherSourceHint => '上で天気の地域を選んでください（天気は Open-Meteo から、無料・アカウント不要）。選ばない場合は、Gadgetbridge 共有をオンにした Breezy Weather アプリがインストールされていれば、そこから天気を取得します。';

  @override
  String get weatherLocationTitle => '天気の地域';

  @override
  String get weatherLocationHint => '市区町村';

  @override
  String get weatherLocationNoResults => '場所が見つかりません';

  @override
  String get weatherLocationSearchError => '天気サービスに接続できませんでした。ネットワーク接続を確認してください。';

  @override
  String get weatherLocationPrivacyNote => '天気は Open-Meteo.com 提供（無料・アカウント不要）。送信されるのは選んだ場所の座標だけです。';

  @override
  String get weatherLocationSearch => '検索';

  @override
  String get dateTimeInvalidFormat => '無効な形式';

  @override
  String get dateTimeSelectFormats => '下で形式を選んでください';

  @override
  String get dataUsageDaily => '1日';

  @override
  String get dataUsageWeekly => '1週間';

  @override
  String get dataUsageMonthly => '1か月';

  @override
  String cwAppsBlockedHeading(int count) {
    return '「続きを見る」でブロック中（$count）';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => '「続きを見る」でブロック中';

  @override
  String get cwAppsUnblock => 'ブロック解除';

  @override
  String get cwAppsUnblockAllApps => 'すべてのアプリのブロックを解除';

  @override
  String get cwAppsNoBlockedApps => 'ブロック中のアプリはありません';

  @override
  String get cwAppsNoBlockedAppsMessage => '対応しているすべてのアプリが「続きを見る」に項目を表示できます。';

  @override
  String get cwAppsWithContinueWatching => '「続きを見る」に対応したアプリ';

  @override
  String get cwAppsWithContinueWatchingHint => '現在ホーム画面に Watch Next の項目を提供しているアプリ';

  @override
  String get cwAppsNoActiveApps => '現在「続きを見る」の項目を提供しているアプリはありません。\n対応アプリ（SmartTube や動画配信サービスなど）が項目を追加すると、ここに表示されます。';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'アクティブな項目 $count 件',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'インストール済みのすべてのアプリ';

  @override
  String get cwAppsAllInstalledAppsHint => 'オフにすると、そのアプリは「続きを見る」に項目を追加できなくなります';

  @override
  String get cwAppsBlocked => 'ブロック中';

  @override
  String get cwAppsAllowed => '許可';

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
  String get cwCardSizeExtraSmall => '極小';

  @override
  String get cwCardSizeVerySmall => 'とても小';

  @override
  String get cwCardSizeSmall => '小';

  @override
  String get cwCardSizeCompact => 'コンパクト';

  @override
  String get cwCardSizeMediumSmall => 'やや小';

  @override
  String get cwCardSizeMedium => '中';

  @override
  String get cwCardSizeStandardDefault => '標準（デフォルト）';

  @override
  String get cwCardSizeStandard => '標準';

  @override
  String get cwCardSizeMediumLarge => 'やや大';

  @override
  String get cwCardSizeLarge => '大';

  @override
  String get cwCardSizeVeryLarge => 'とても大';

  @override
  String get cwCardSizeExtraLarge => '特大';

  @override
  String get cwCardSizeHuge => '超特大';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '最近の項目を最大 $count 件表示',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • デフォルト';
  }

  @override
  String get cwUnlimited => '無制限';

  @override
  String get cwMaxItemsAll => '利用可能なすべての項目を表示';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => '再生の進行状況バー';

  @override
  String get cwPlaybackPercentage => '再生の割合';

  @override
  String get cwEpisodeDetails => 'エピソードと動画の詳細';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件ブロック中',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => '管理';

  @override
  String get cwRestoreHiddenPrograms => '非表示の番組を元に戻す';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件非表示',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => '非表示の番組をすべて元に戻しました';

  @override
  String get cwWatchNextAdbTitle => 'Watch Next へのアクセス（ADB が必要）';

  @override
  String get cwWatchNextAdbMessage => 'ランチャーがインストール済みアプリの「続きを見る」の行を読み取って表示するには、Android TV で READ_WRITE_WATCH_NEXT_PROGRAMS 権限が必要です。\n\nこの権限を付与するには、ADB でテレビに接続して次を実行します:';

  @override
  String get appsNoApplicationsFound => 'アプリが見つかりません';

  @override
  String get appDetailsAddToFavorites => 'お気に入りに追加';

  @override
  String get appDetailsRemoveFromFavorites => 'お気に入りから削除';

  @override
  String get appDetailsAddToCategory => 'カテゴリに追加';

  @override
  String get sectionsCustomOption => 'カスタム...';

  @override
  String get sectionsSelectName => '名前を選択';

  @override
  String get sectionsCustomName => 'カスタム名';

  @override
  String get sectionsSortLastUsed => '最近使用した順';

  @override
  String get sectionsReorderHint => '◄ / ► で選択し、▲ / ▼ で並べ替え';

  @override
  String get inputsNoneDetected => '入力が見つかりません';

  @override
  String get notifClearAll => 'すべて消去';

  @override
  String get notifAllCaughtUp => 'すべて確認済みです';

  @override
  String notifBlockAppNotifications(String app) {
    return '通知をブロック（$app）';
  }

  @override
  String notifOpenApp(String app) {
    return '$app を開く';
  }

  @override
  String get notifAccessAdbTitle => '通知アクセス（ADB が必要）';

  @override
  String get notifAccessAdbMessage => 'Android TV には「通知へのアクセス」（ほかのアプリの通知の受信）のシステム設定画面がありません。\n\n注: テレビのアプリ設定で「通知を表示」をオンにしても、このアプリが送る通知を制御するだけで、通知へのアクセスは許可されません。\n\n通知へのアクセスを許可するには、ADB でテレビに接続して次を実行します:';

  @override
  String get notifOpenAppInfo => 'アプリ情報を開く';

  @override
  String get notifOverlayPermissionTitle => 'オーバーレイ権限';

  @override
  String get notifOverlayAdbMessage => 'このデバイスでは、オーバーレイ権限の設定画面を自動で開けませんでした。\n\nオーバーレイのポップアップを有効にするには、テレビに接続したパソコンから ADB で手動で権限を付与してください:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'ブロックされたアプリ（$count）';
  }

  @override
  String get backupShareText => 'Hearth のバックアップ';

  @override
  String get backupShareFailedTitle => '共有に失敗しました';

  @override
  String backupShareFailed(String error) {
    return 'バックアップを共有できませんでした: $error';
  }

  @override
  String get backupExportSuccessTitle => 'エクスポート完了';

  @override
  String get backupExportFailedTitle => 'エクスポートに失敗しました';

  @override
  String get backupImportSuccessTitle => 'インポート完了';

  @override
  String get backupImportFailedTitle => 'インポートに失敗しました';

  @override
  String get backupImport => 'インポート';

  @override
  String backupLoadError(String error) {
    return 'バックアップの読み込みエラー: $error';
  }

  @override
  String get backupNoFiles => 'バックアップファイルが見つかりません。';

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
  String get updateCheckForUpdatesTitle => 'アップデートを確認';

  @override
  String updateCurrentVersion(String version) {
    return '現在のバージョン: $version';
  }

  @override
  String get updateChecking => 'GitHub で新しいリリースを確認しています…';

  @override
  String get updateUpToDate => '最新バージョンです。';

  @override
  String updateVersionAvailable(String version) {
    return 'バージョン $version が利用可能です';
  }

  @override
  String updateDownloading(String percent) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get updateDownloadedHint => 'ダウンロードしました。インストーラが開かない場合は、デバイスで Hearth に\n「不明なアプリのインストール」を許可する必要があるかもしれません。';

  @override
  String get updateSomethingWentWrong => '問題が発生しました';

  @override
  String get updateDownloadAndInstall => 'ダウンロードしてインストール';

  @override
  String get updateRetryInstall => 'インストールを再試行';

  @override
  String get updateCheckAgain => '再確認';

  @override
  String get updatesInstallPermissionTitle => 'Hearth にアプリのインストールを許可';

  @override
  String get updatesInstallPermissionMessage => '次の画面で Hearth を探してオンにし、戻るボタンを押してください。ここに戻るとインストールが続行されます。';

  @override
  String get updatesOpenSettings => '設定を開く';

  @override
  String get updatesCheckFailed => 'アップデートを確認できませんでした';

  @override
  String get updatesInstallerNotStarted => 'インストーラが起動しませんでした';

  @override
  String get updatesCheckForUpdates => 'アップデートを確認';

  @override
  String get updatesAutoUpdate => '自動的にアップデート';

  @override
  String get updatesAutoUpdateDescription => 'Hearth は毎日確認し、自身がインストールしたアプリのアップデートを、使われていないときにインストールします';

  @override
  String get updatesIncludePrereleases => 'プレリリースを含める';

  @override
  String get updatesIncludePrereleasesDescription => 'Hearth と HearthTube の初期のテスト版です。未完成の場合があります。';

  @override
  String get updatesFooter => '各アプリの GitHub リリースからインストールします。Hearth が一度アプリをインストールまたはアップデートすると、以降のアップデートは確認なしでインストールされ、アップデートは Hearth に任されます。';

  @override
  String get updatesChecking => '確認中…';

  @override
  String get updatesInstall => 'インストール';

  @override
  String updatesUpdateTo(String version) {
    return '$version にアップデート';
  }

  @override
  String get updatesUpToDate => '最新';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'ダウンロード中 $percent%';
  }

  @override
  String get updatesInstalling => 'インストール中…';

  @override
  String get updatesError => 'エラー';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return '$author による $launcher と $original をベースに、$parts の一部を含みます';
  }

  @override
  String get aboutDescription => 'Google TV 向けの、プライバシー重視で家族にやさしいランチャー。Google TV のプロフィールと Home Assistant を内蔵。広告なし、トラッカーなし。';

  @override
  String get aboutHearthOnGitHub => 'GitHub の Hearth';

  @override
  String get aboutCredits => 'クレジット';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'FLauncher のフォーク · $author';
  }

  @override
  String get aboutLicense => '元になったプロジェクトと同じく、GNU GPL v3 のフリーソフトウェアです。';

  @override
  String get profilePinRow => 'プロフィールのPIN';

  @override
  String get profilePinNone => 'なし';

  @override
  String get profilePinSaved => '保存済み';

  @override
  String get profilePinRejected => '保存済み — 前回受け付けられませんでした';

  @override
  String get profilePinPaused => '保存済み — 一時停止中（アプリが変わりました）';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearthはまだ$appでPINを入力できません';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return '$appでの$profileのPIN';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return '$appが求めると、Hearthが「ログイン中」カードの裏で入力します。このテレビに暗号化して保存され、表示されることはありません。';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return '先に保護者のPINを設定してください（$settings → $profiles → $parentPin）。プロフィールのPINを保存するのに必要です。';
  }

  @override
  String get profilePinSaveFailed => 'PINを保存できませんでした。';

  @override
  String get streamingPinsTitle => 'ストリーミングアプリの PIN';

  @override
  String get streamingPinsFooter => 'ここにはこのプロフィールの PIN だけが表示されます。これらのアプリがこのプロフィールの PIN を求めると、Hearth が代わりに入力します。PIN を設定すると、このプロフィールとアプリのプロフィールが固定で連携されます。';

  @override
  String get streamingPinsNone => 'Hearth が PIN を入力できるアプリはインストールされていません。';

  @override
  String get profileLockNow => 'プロフィールをロック';

  @override
  String get profileLockOnSleep => 'テレビがスリープしたらロック';

  @override
  String get profileLockEveryTime => '毎回';

  @override
  String profileLockAfterMinutes(int minutes) {
    return '$minutes分以上スリープした後';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Google TV自体のプロフィールロックを使います。Google TVの設定 → アカウントとログイン → ご自分のアカウント → プロフィールロック でオンにしてください。';

  @override
  String get aboutWallpaperPhoto => '壁紙の写真';

  @override
  String get updateErrorWrongApp => 'このダウンロードはこの Hearth の更新ではありません';

  @override
  String get notifOpen => '開く';

  @override
  String get notifOpenHint => 'OK: 開く · 左: 閉じる · 右: その他';

  @override
  String get tvPowerGoogleTvHome => 'Google TV のホームを使う';

  @override
  String get tvPowerGoogleTvHomeNote => 'これをオフにするまで Hearth は表示されません。ホームボタンでは引き続き Hearth が開きます。';

  @override
  String get setupFlowFinishLater => '後で続ける';

  @override
  String get setupFlowStripEssentials => '基本';

  @override
  String get setupFlowWelcomeTitle => 'Hearth へようこそ';

  @override
  String get setupFlowWelcomeBody => '家族みんなのホーム画面。アプリ、見ていた番組、そして各ストリーミングアプリの正しいプロフィール。';

  @override
  String get setupFlowWelcomeTime => '約5分です。どれもスキップできます。';

  @override
  String get setupFlowGetStarted => '始める';

  @override
  String get setupFlowSetUpLater => '後で設定';

  @override
  String setupFlowLanguageLink(String language) {
    return '言語: $language';
  }

  @override
  String get setupFlowRestoreLink => 'バックアップから復元';

  @override
  String get setupFlowHomeButtonTitle => 'ホームボタンで Hearth を開く';

  @override
  String get setupFlowHomeButtonBody => 'Google TV はホームボタンに自分のホーム画面を割り当てています。Android の設定のスイッチを1つ入れると解決し、Hearth は次のこともできるようになります:';

  @override
  String get setupFlowHomeButtonPoint1 => 'プロフィールの切り替えや子どもの就寝時間に合わせる';

  @override
  String get setupFlowHomeButtonPoint2 => 'ポップアップを表示し、使われていないときにテレビを切る';

  @override
  String get setupFlowOnNextScreen => '次の画面で:';

  @override
  String get setupFlowStepServices => '「サービス」までスクロール';

  @override
  String setupFlowStepSelect(String name) {
    return '「$name」を選択';
  }

  @override
  String get setupFlowStepEnable => '「有効にする」をオンにして「OK」';

  @override
  String get setupFlowComesBack => 'オンになると Hearth は自動で戻ります。Google TV に「誰が見ていますか」と聞かれたら、ご自身を選んでください。';

  @override
  String get setupFlowOpenAccessibility => 'ユーザー補助を開く';

  @override
  String get setupFlowHomeButtonDone => 'ホームボタンで Hearth が開くようになりました';

  @override
  String get setupFlowNotOnYetTitle => 'まだオンになっていません';

  @override
  String get setupFlowNotOnYetBody => 'もう一度試すか、スキップして後で設定から行ってください。';

  @override
  String get setupFlowStuckTitle => 'オンですが動作していません';

  @override
  String get setupFlowStuckBody => 'Android ではオンと表示されていますが、動作していません。いったんオフにしてから再度オンにしてください。';

  @override
  String get setupFlowSkipHomeButtonTitle => 'ホームボタンの設定をスキップしますか?';

  @override
  String get setupFlowSkipHomeButtonBody => 'これがないと、ホームボタンで Google TV が開き、Hearth はキッズ プロフィールの使用中を判別できません。';

  @override
  String get setupFlowSkipAnyway => 'それでもスキップ';

  @override
  String get setupFlowSkip => 'スキップ';

  @override
  String get setupFlowNext => '次へ';

  @override
  String get setupFlowLostTitle => 'アップデートでホームボタンの設定がオフになりました';

  @override
  String get setupFlowLostBody => '一部のアップデート後に Android がオフにします。1ステップで再びオンにできます。';

  @override
  String get setupFlowBlockedTitle => 'Android がこのスイッチをブロックしました';

  @override
  String get setupFlowBlockedBody => 'スイッチがグレー表示だったのは、Hearth がダウンロードしたファイルからインストールされたためです。テレビにはこれを許可する設定がありません。';

  @override
  String get setupFlowBlockedComputer => 'パソコンを使う場合:';

  @override
  String get setupFlowBlockedComputerThen => 'その後スイッチをオンにしてください。Hearth が自動で検出します。';

  @override
  String get setupFlowBlockedSelfFixBody => 'デバッグがオンなので、Hearth が自分で解決できます。テレビに「デバッグを許可しますか?」と表示されたら「常に許可」を選ぶと、Hearth がスイッチのブロックを解除してオンにします。';

  @override
  String get setupFlowSkipForNow => '今はスキップ';

  @override
  String get setupFlowBlockedSkipLine => 'アプリ、検索、続きを見るは使えます。ホームボタン、プロフィール、ポップアップ、スリープタイマーは使えません。';

  @override
  String get setupFlowLetHearthFix => 'Hearth に修正させる';

  @override
  String get setupFlowFixConfirmBody => 'Hearth は自身のデバッグ接続を使って、テレビで次を実行します:';

  @override
  String get setupFlowFixConfirmApproval => '初回はテレビに「デバッグを許可しますか?」と表示されます。「常に許可」を選んでください。変更されるのは Hearth 自身の権限だけです。';

  @override
  String get setupFlowFixRun => '実行';

  @override
  String get setupFlowFixWaiting => '処理中です。テレビに「デバッグを許可しますか?」と表示されたら「常に許可」を選んでください。';

  @override
  String get setupFlowFixFailedTitle => 'Hearth は実行できませんでした';

  @override
  String get setupFlowFixFailedBody => 'Hearth はテレビのデバッグに接続できませんでした。「デバッグを許可しますか?」と表示された場合は「常に許可」を選んで、もう一度お試しください。開発者向けオプションでデバッグをオンのままにしておく必要があります。';

  @override
  String get setupFlowHomeAppTitle => 'Hearth をホームアプリにする';

  @override
  String get setupFlowHomeAppBody => 'Android にホームアプリの一覧が表示されます。Hearth を選んでください。キッズ プロフィールで Hearth がブロックされるのを防ぎます。';

  @override
  String get setupFlowChooseHearth => 'Hearth を選ぶ';

  @override
  String get setupFlowHomeAppDone => 'Hearth がホームアプリになりました';

  @override
  String get setupFlowNotChosenTitle => 'まだ選ばれていません';

  @override
  String get setupFlowFinishTitle => 'Hearth の準備ができました';

  @override
  String setupFlowFinishBody(String where) {
    return 'スキップした項目は設定にあります。$where からもう一度実行できます。';
  }

  @override
  String get setupFlowFinishOn => 'オン';

  @override
  String get setupFlowFinishLaterHeading => '後で設定から';

  @override
  String get setupFlowFinishMore => '設定にはほかにも、リモコンのボタン、セクション、通知、バックアップがあります。';

  @override
  String get setupFlowGoHome => 'ホームへ';

  @override
  String get setupHearthTitle => 'Hearth の設定';

  @override
  String get setupRunAgain => '設定をもう一度行う';

  @override
  String get setupCardFamily => '家族';

  @override
  String get setupCardWatching => '視聴';

  @override
  String setupChipLeft(int count) {
    return '設定を完了 · 残り $count';
  }

  @override
  String get setupChipFix => 'ホームボタンの修正が必要です';

  @override
  String get setupChipHideTitle => 'このリマインダーを非表示にしますか?';

  @override
  String setupChipHideBody(String where) {
    return '$where からいつでも設定できます。';
  }

  @override
  String get setupChipHide => '非表示';

  @override
  String get setupFlowCardIncluded => '含まれるもの';

  @override
  String get setupFlowCardNeeds => '必要なもの';

  @override
  String get setupFlowTurnOn => 'オンにする';

  @override
  String get setupFlowNeedsQuestion => 'Android からの確認が1回';

  @override
  String get setupFlowNeedsOneSwitch => 'Android の設定でスイッチを1つ';

  @override
  String get setupFlowNeedsAboutAMinute => '約1分';

  @override
  String get setupFlowWatchingBenefit => '続きから見られて、再生中のものもわかります。';

  @override
  String get setupFlowWatchingIncluded1 => 'ホーム画面に「続きを見る」';

  @override
  String get setupFlowWatchingIncluded2 => '通知と再生中の内容';

  @override
  String get setupFlowSearchWorks => '検索はすでに使えます。ホーム画面で検索を押してください。';

  @override
  String get setupFlowContinueBody => 'アプリで見ていたものをホーム画面に表示します。Android から一度確認されるので、「許可」を選んでください。';

  @override
  String get setupFlowContinueDone => '「続きを見る」がオンになりました';

  @override
  String get setupFlowContinueDeniedTitle => 'Android で許可されませんでした';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'あとで $where からオンにできます。';
  }

  @override
  String get setupFlowNotificationsTitle => '再生中の内容と通知';

  @override
  String setupFlowNotificationsBody(String name) {
    return '通知と再生中の内容が見られます。次の画面で「$name」を選んで許可してください。';
  }

  @override
  String get setupFlowNotificationsDone => '通知がオンになりました';

  @override
  String get setupFlowTvTitle => '誰も見ていないときにテレビを消しますか？';

  @override
  String get setupFlowTvBody => 'リモコン操作がこの時間ないとき。動画や音楽の再生中は視聴中とみなします。';

  @override
  String get setupFlowTvNeedsHomeButton => '最初の手順のホームボタンのスイッチが必要です。それがないと、Hearth はリモコンが使われたかわかりません。';

  @override
  String get setupFlowStartOnBoot => 'テレビの起動時に Hearth を開始';

  @override
  String get setupFlowScreensaver => 'スクリーンセーバーの写真を選ぶ';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth が自分自身と関連アプリを最新に保ちます。';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth が自動で更新';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube（Hearth 用の YouTube アプリ）';

  @override
  String get setupFlowInstallTitle => 'Hearth にアップデートのインストールを許可';

  @override
  String get setupFlowInstallBody => '次の画面で Hearth を探してオンにし、戻るを押してください。';

  @override
  String get setupFlowInstallDone => 'Hearth がアップデートをインストールできます';

  @override
  String get setupFlowTubeTitle => 'HearthTube をインストールしますか？';

  @override
  String get setupFlowTubeBody => 'Hearth 用に作られた YouTube アプリ。プロフィール、時計のスタイル、子どもの就寝時間に従います。';

  @override
  String get setupFlowTubeInstalled => 'HearthTube がインストールされました';

  @override
  String get setupCardHome => 'ホーム画面';

  @override
  String get setupFlowLookTitle => '見た目を選ぶ';

  @override
  String setupFlowLookBody(String where) {
    return '選ぶと、このカードの後ろに表示されます。あとで $where からどこでも変更できます。';
  }

  @override
  String get setupFlowLookOtherTitle => 'ホーム画面の見た目を選ぶ';

  @override
  String get setupFlowLookOtherBody => 'プロフィールごとに自分のホーム画面があります。見た目を選んでください。';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => '今日の写真';

  @override
  String get setupLookCalmDark => '落ち着いたダーク';

  @override
  String get setupLookBold => '大胆';

  @override
  String get setupFlowLookNow => '現在';

  @override
  String get setupFlowLookUse => 'この見た目にする';

  @override
  String get setupFlowLookKeep => '今のままにする';

  @override
  String get setupFlowLookCustomize => 'カスタマイズ';

  @override
  String get setupFlowWeatherTitle => '天気を表示しますか？';

  @override
  String get setupFlowWeatherBody => 'お住まいの町を選んでください。送られるのはその位置だけで、送り先は Open-Meteo です。アカウントは不要です。';

  @override
  String get setupFlowWeatherChoose => '町を選ぶ';

  @override
  String get setupFlowWeatherDone => '天気は上部のバーに表示されます';

  @override
  String get setupFlowFamilyBenefit => '動画アプリが正しい人のプロフィールで開き、子どもは Hearth を変更できません。';

  @override
  String get setupFlowFamilyIncluded1 => '保護者用 PIN（子どもが Hearth を変更できないように）';

  @override
  String get setupFlowFamilyIncluded2 => 'Netflix、Disney+、Apple TV、Max、Paramount+ で正しいプロフィール';

  @override
  String get setupFlowFamilyIncluded3 => '子どものプロフィールに Hearth を残す';

  @override
  String get setupFlowNeedsPin => '自分で決める4桁の数字';

  @override
  String get setupFlowNeedsTwoMinutes => '約2分';

  @override
  String get setupFlowPinTitle => '保護者用 PIN を決める';

  @override
  String get setupFlowPinBody => '子どもが Hearth を変更するには、この PIN が必要です。子どもに推測されない4桁を選んでください。';

  @override
  String get setupFlowPinChoose => 'PIN を決める';

  @override
  String get setupFlowPinDone => '保護者用 PIN を設定しました';

  @override
  String get setupFlowPairingTitle => '動画アプリで正しいプロフィールを選ぶ';

  @override
  String setupFlowPairingBody(String name) {
    return 'Hearth が Netflix、Disney+、Apple TV、Max、Paramount+ で各自のプロフィールを選びます。同じ Android の画面で、もう1つのスイッチ「$name」が必要です。';
  }

  @override
  String get setupFlowPairingDone => 'プロフィールの連携がオンになりました';

  @override
  String get setupFlowPairingDoneBody => 'Hearth が名前を自動で照合します（「Alex」と「Alex Morgan」など）。各アプリのプロフィールは、そのアプリの「誰が見ていますか？」画面が一度表示されると現れます。';

  @override
  String get setupFlowCheckPairings => '連携を確認';

  @override
  String get setupFlowVoiceTitle => 'Netflix 用にもう1ステップ';

  @override
  String setupFlowVoiceBody(String name) {
    return 'Netflix はプロフィール画面を読み上げるので、Hearth は自分の音声で聞き取ります。次の画面の「優先するエンジン」で「$name」を選び、OK を押してください。ほかのアプリは Google の音声のままです。';
  }

  @override
  String get setupFlowVoiceDone => 'Hearth の音声がオンになりました';

  @override
  String get setupFlowKidsTitle => '子どものプロフィールに Hearth を残す';

  @override
  String get setupFlowKidsBody => 'Google TV は、子どものプロフィールが起動するたびに、自分でインストールしていないアプリを削除します。Hearth はそこで自分自身と HearthTube を守れます。お子さまごとに Family Link の「アプリが追加されました」通知が1回届きます。設定からいつでも元に戻せます。';

  @override
  String get setupFlowKidsApprove => 'テレビに「デバッグを許可しますか？」と表示されます。「常に許可」にチェックを入れて「許可」を選んでください。これは一度だけです。';

  @override
  String get setupFlowKidsAdd => '子どものプロフィールに追加';

  @override
  String get setupFlowKidsDone => '子どものプロフィールに Hearth を追加しました';

  @override
  String get setupFlowKidsKeepDebugging => 'デバッグはオンのままにしてください。新しい子どものプロフィールや、Hearth の削除・アンインストールの際に再び必要です。';

  @override
  String get setupFlowDebugTitle => 'まずデバッグをオンにする';

  @override
  String get setupFlowDebugBody => '子どものプロフィールを設定するには、テレビのデバッグのスイッチが必要です。次の画面で「Android TV OS ビルド」を7回選んでください。次に「設定」>「システム」>「開発者向けオプション」で「USB デバッグ」をオンにして、戻ってきてください。オンのままにしてください。新しい子どものプロフィールで再び必要になります。';

  @override
  String get setupFlowDebugOpen => 'デバイス情報を開く';

  @override
  String get setupCardSmartHome => 'スマートホーム';

  @override
  String get setupFlowHaBenefit => '玄関チャイムなどの通知をテレビに表示し、Home Assistant のダッシュボードをワンタッチで開けます。';

  @override
  String get setupFlowHaIncluded1 => 'どのアプリの上にも玄関チャイムなどの通知';

  @override
  String get setupFlowHaIncluded2 => 'ダッシュボードをワンタッチで';

  @override
  String get setupFlowHaIncluded3 => '表示中の内容を Home Assistant に送信';

  @override
  String get setupFlowNeedsPhone => '同じ Wi-Fi につながったスマートフォン';

  @override
  String get setupFlowNeedsFewMinutes => '数分';

  @override
  String get setupFlowHaUse => 'Home Assistant を使っている';

  @override
  String get setupFlowHaAlertsTitle => 'Home Assistant の通知';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'Home Assistant で「Notifications for Android TV / Fire TV」を、このテレビのアドレス $ip で追加してください。次にテストを送ります。';
  }

  @override
  String get setupFlowHaAlertsDone => '通知がオンになりました';

  @override
  String get setupFlowHaDashboardTitle => 'テレビでダッシュボード';

  @override
  String get setupFlowHaDashboardBody => 'スマートフォンでスキャンし、Home Assistant のアドレスとトークンを貼り付けて送信します。管理者ではなく、テレビ用に作った Home Assistant ユーザーを使ってください。';

  @override
  String get setupFlowHaDashboardDone => 'ダッシュボードを設定しました';

  @override
  String get setupFlowHaStatusTitle => '表示中の内容を Home Assistant に伝える';

  @override
  String get setupFlowHaStatusBody => 'テレビは再生中の内容と使用中のプロフィールを Home Assistant に送れます。同じスマートフォンのページで、Home Assistant の Webhook オートメーションの ID を入力してください。';

  @override
  String get setupFlowHaStatusNoWebhook => 'スマートフォンから Webhook ID が送られませんでした。ページの最後の欄に入力してください。';

  @override
  String get setupFlowHaStatusDone => 'テレビが表示中の内容を Home Assistant に伝えます';

  @override
  String setupChipNewOne(String feature) {
    return 'Hearth の新機能：$feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'Hearth の新機能 · $count';
  }

  @override
  String get setupFlowKidsNotAll => 'まだすべての子どものプロフィールに Hearth がありません';

  @override
  String get setupFlowLeaveAsIs => 'このままにする';

  @override
  String get setupFlowSetUpMissing => '足りないものを設定';

  @override
  String get setupFlowChooseAgain => 'もう一度選ぶ';

  @override
  String get weatherForecastHourly => '時間別';

  @override
  String get weatherForecastDaily => '日別';

  @override
  String get weatherForecastShowDaily => 'OK: 日別';

  @override
  String get weatherForecastShowHourly => 'OK: 時間別';

  @override
  String get weatherForecastNow => '現在';

  @override
  String get weatherForecastToday => '今日';

  @override
  String get weatherForecastNone => '予報はまだ届いていません';

  @override
  String get youTubeLimitTitle => '1日のYouTube時間';

  @override
  String get youTubeLimitNone => '制限なし';

  @override
  String youTubeLimitMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes分',
    );
    return '$_temp0';
  }

  @override
  String get youTubeLimitHint => 'このプロフィールのHearthTubeでの時間です。Home Assistantを設定している場合、ほかのデバイスと共有する制限も適用されます。';
}
