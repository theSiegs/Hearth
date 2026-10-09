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
  String get systemSettings => 'システム設定';

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
  String get blockAppNotifications => '通知をブロック';

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
  String get temperatureUnit => '温度単位';

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
  String get openApp => '開く';

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
  String get remoteAndSearchTitle => 'リモコンと検索';

  @override
  String get parentSettingsTitle => '保護者の設定';

  @override
  String get tvPowerTitle => 'テレビと電源';

  @override
  String get setupPermissionsTitle => 'セットアップと権限';

  @override
  String get updatesTitle => 'アップデート';

  @override
  String get familyAppsTitle => '他のプロフィールの Hearth';

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
  String profilesAdultName(String name) {
    return '$name（大人）';
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
  String get familyAppsIntro => 'Hearth と HearthTube を Google TV の他のプロフィールにも入れます。キッズプロフィールでは、HearthTube を使うためと、Netflix や Disney+ などのアプリで Hearth が正しいプロフィールを選ぶために必要です。大人のプロフィールでは、手動でインストールする手間を省くためのものです。';

  @override
  String get familyAppsAddTitle => '他のプロフィールに Hearth を追加';

  @override
  String get familyAppsAddKids => 'お子さんのプロフィールに Hearth と HearthTube を入れます。これで HearthTube が使えるようになり、Netflix や Disney+ などのアプリで Hearth が正しいプロフィールを選べます。';

  @override
  String get familyAppsAddAdults => 'テレビの他の大人のプロフィールにもインストールするので、他の大人が自分で設定する必要はありません。';

  @override
  String get familyAppsAddOnlyOwnApps => '追加するのは Hearth 自身の 2 つのアプリだけです。下の「削除」でいつでも元に戻せます。';

  @override
  String get familyAppsAddFamilyLink => 'お子さんごとに Family Link の「アプリが追加されました」という通知が 1 件届きます。';

  @override
  String get familyAppsAddApproval => '初回はテレビに「デバッグを許可しますか？」と表示されます。「常に許可」を選んでください。これで Hearth が設定を行えます。';

  @override
  String get familyAppsAdd => '追加';

  @override
  String get familyAppsRemoveTitle => '他のプロフィールから Hearth を削除';

  @override
  String get familyAppsRemoveBody => '他のプロフィールから Hearth と HearthTube を削除します。';

  @override
  String get familyAppsRemoveFirst => 'Hearth 自体をアンインストールする予定なら、先にこれを実行してください。そうしないと、キッズプロフィールに残ったコピーを消すのにパソコンが必要になることがあります。';

  @override
  String get familyAppsUninstallTitle => 'Hearth をアンインストール';

  @override
  String get familyAppsUninstallBody => 'まず他のプロフィールから Hearth と HearthTube を削除し、そのあとこのプロフィールから Hearth をアンインストールします。';

  @override
  String get familyAppsUninstallWhyHere => 'Android の設定ではなくここからアンインストールすると、キッズプロフィールに何も残りません。';

  @override
  String get familyAppsApprovalFirstTitle => '先に 1 回限りの許可を済ませてください';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth はまだ他のプロフィールを整理できませんでした。テレビで「デバッグを許可しますか？」を 1 回許可する必要があります。';

  @override
  String get familyAppsApprovalFirstRetry => '許可してから、もう一度アンインストールをお試しください。キッズプロフィールに何も残りません。';

  @override
  String get familyAppsAddDone => '追加が完了しました';

  @override
  String get familyAppsRemoveDone => '削除が完了しました';

  @override
  String get familyAppsAdded => '完了しました。Hearth と HearthTube が他のプロフィールに追加されました。下の一覧をご覧ください。';

  @override
  String get familyAppsRemoved => '完了しました。他のプロフィールから Hearth と HearthTube を削除しました。';

  @override
  String get familyAppsNothingToSetUp => '設定できる他のプロフィールはまだありません。';

  @override
  String get familyAppsFailedTitle => 'プロフィールを設定できませんでした';

  @override
  String get familyAppsFailedBody => '他のプロフィールを設定するには、テレビで Hearth を 1 回だけ許可する必要があります。';

  @override
  String get familyAppsFailedRetry => 'テレビに「デバッグを許可しますか？」と表示されたら「常に許可」を選んで、もう一度お試しください。';

  @override
  String get familyAppsAlsoAdults => '他の大人のプロフィールも設定';

  @override
  String get familyAppsOn => 'オン';

  @override
  String get familyAppsOff => 'オフ';

  @override
  String get familyAppsNoneYet => 'まだ他のプロフィールは設定されていません。';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app：インストール済み';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app：インストール済み、保持';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app：未インストール';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app：未インストール、保持';
  }

  @override
  String get familyAppsUnnamedKids => 'キッズプロフィール';

  @override
  String get familyAppsUnnamedAdult => '大人のプロフィール';

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
  String get setupOptional => 'オプション';

  @override
  String get homeButtonFixOffTitle => 'ホームボタン修正がオフです';

  @override
  String get homeButtonFixOffBody => 'Hearth のユーザー補助サービスが停止しました（通常はアップデート後に起こります）。再びオンにするまで、ホームボタンで Hearth ではなく Google TV が開くことがあり、プロフィールの切り替えにも追従しません。';

  @override
  String get homeButtonFixStuck => 'Android ではまだオンと表示されていますが、動作していません。ユーザー補助の設定で Hearth をオフにしてから再度オンにし、再起動してください。';

  @override
  String get homeButtonFixRestricted => 'そこで Hearth のスイッチがグレー表示になっている場合、このアップデートがダウンロードからインストールされたため Android がブロックしています。テレビに接続したパソコンから次を実行してから、Hearth をオンにしてください：';

  @override
  String get homeButtonFixDontRemind => '今後表示しない';

  @override
  String get homeButtonFixOpenSettings => 'ユーザー補助の設定を開く';

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
}
