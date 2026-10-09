import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get aboutFlauncher => 'Über Hearth';

  @override
  String get addSection => 'Abschnitt hinzufügen';

  @override
  String get alphabetical => 'Alphabetisch';

  @override
  String get appCardHighlightAnimation => 'App-Karten-Hervorhebungsanimation';

  @override
  String get appInfo => 'App-Info';

  @override
  String get appKeyClick => 'Klickgeräusch bei Tastendruck';

  @override
  String get applications => 'Anwendungen';

  @override
  String get autoHideAppBar => 'Statusleiste automatisch ausblenden';

  @override
  String get backButtonAction => 'Aktion der Zurücktaste';

  @override
  String get category => 'Kategorie';

  @override
  String get columnCount => 'Spaltenanzahl';

  @override
  String get date => 'Datum';

  @override
  String get dateAndTimeFormat => 'Datums- und Zeitformat';

  @override
  String get delete => 'Löschen';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Nichts tun';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Bildschirmschoner anzeigen';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Uhr anzeigen';

  @override
  String get dialogTextNoFileExplorer => 'Bitte installieren Sie einen Dateimanager, um ein Bild auszuwählen.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Kategorie)';
  }

  @override
  String get gradient => 'Farbverlauf';

  @override
  String get favoriteApps => 'Lieblings-Apps';

  @override
  String get grid => 'Raster';

  @override
  String get height => 'Höhe';

  @override
  String get hide => 'Ausblenden';

  @override
  String get hiddenApplications => 'Ausgeblendete Apps';

  @override
  String get launcherSections => 'Abschnitte';

  @override
  String get layout => 'Layout';

  @override
  String get loading => 'Wird geladen';

  @override
  String get manual => 'Manuell';

  @override
  String get modifySection => 'Abschnitt ändern';

  @override
  String get name => 'Name';

  @override
  String get newSection => 'Neuer Abschnitt';

  @override
  String get nonTvApplications => 'Nicht-TV-Apps';

  @override
  String get open => 'Öffnen';

  @override
  String get picture => 'Bild';

  @override
  String removeFrom(String name) {
    return 'Entfernen aus $name';
  }

  @override
  String get reorder => 'Neu anordnen';

  @override
  String get row => 'Zeile';

  @override
  String get rowHeight => 'Zeilenhöhe';

  @override
  String get save => 'Speichern';

  @override
  String get spacer => 'Abstandshalter';

  @override
  String get statusBar => 'Statusleiste';

  @override
  String get show => 'Anzeigen';

  @override
  String get showCategoryTitles => 'Kategorietitel anzeigen';

  @override
  String get showCategoryAppCount => 'App-Anzahl in Kategorien anzeigen';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Hervorhebungskontur auf dem Startbildschirm ausblenden';

  @override
  String get appSelectorTransitionAnimation => 'App-Auswahl-Übergangsanimation';

  @override
  String get sort => 'Sortieren';

  @override
  String get systemSettings => 'Systemeinstellungen';

  @override
  String get textEmptyCategory => 'Diese Kategorie ist leer.';

  @override
  String get time => 'Zeit';

  @override
  String get tvApplications => 'TV-Apps';

  @override
  String get type => 'Typ';

  @override
  String get uninstall => 'Deinstallieren';

  @override
  String get wallpaper => 'Hintergrundbild';

  @override
  String get withEllipsisAddTo => 'Hinzufügen zu...';

  @override
  String get timeBasedWallpaper => 'Zeitbasiertes Hintergrundbild';

  @override
  String get pickDayWallpaper => 'Tag-Hintergrundbild auswählen';

  @override
  String get pickNightWallpaper => 'Nacht-Hintergrundbild auswählen';

  @override
  String get inputs => 'Eingänge';

  @override
  String get inputSources => 'Eingabequellen';

  @override
  String get backupAndRestore => 'Sichern & Wiederherstellen';

  @override
  String get exportBackup => 'Sicherung exportieren';

  @override
  String get importBackup => 'Sicherung importieren';

  @override
  String exportSuccess(String path) {
    return 'Sicherung erfolgreich exportiert nach $path';
  }

  @override
  String get importSuccess => 'Sicherung erfolgreich importiert';

  @override
  String get importConfirm => 'Möchten Sie die Sicherung wirklich importieren? Dies wird Ihre aktuellen Einstellungen und Ihr Layout überschreiben.';

  @override
  String importError(String error) {
    return 'Importieren der Sicherung fehlgeschlagen: $error';
  }

  @override
  String exportError(String error) {
    return 'Exportieren der Sicherung fehlgeschlagen: $error';
  }

  @override
  String get shareBackup => 'Sicherung teilen';

  @override
  String get notificationBell => 'Benachrichtigungsglocke';

  @override
  String get autoHideNotificationBell => 'Benachrichtigungsglocke automatisch ausblenden';

  @override
  String get continueWatching => 'Weiterschauen';

  @override
  String get showContinueWatchingOnHome => 'Weiterschauen auf dem Startbildschirm anzeigen';

  @override
  String get permissionDeniedContinueWatching => 'Berechtigung erforderlich, um Weiterschauen anzuzeigen';

  @override
  String get system => 'System';

  @override
  String get accentColor => 'Akzentfarbe';

  @override
  String get dataUsagePeriod => 'Datennutzungszeitraum';

  @override
  String get notificationAccess => 'Benachrichtigungszugriff';

  @override
  String get watchNextAccess => 'Watch-Next-Zugriff';

  @override
  String get granted => 'Gewährt';

  @override
  String get permissionRequired => 'Berechtigung erforderlich';

  @override
  String get systemWidePopupAlert => 'Systemweite Popup-Warnung';

  @override
  String get overlayPermissionRequired => 'Overlay-Berechtigung erforderlich';

  @override
  String get enabled => 'Aktiviert';

  @override
  String get disabled => 'Deaktiviert';

  @override
  String get showAppNamesBelowIcons => 'App-Namen unter Symbolen anzeigen';

  @override
  String get dataUsage => 'Datennutzung';

  @override
  String get networkIndicator => 'Netzwerkindikator';

  @override
  String get startOnBoot => 'Beim Einschalten starten (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Sprache';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get english => 'Englisch';

  @override
  String get spanish => 'Spanisch';

  @override
  String get ukrainian => 'Ukrainisch';

  @override
  String get chinese => 'Chinesisch';

  @override
  String get french => 'Französisch';

  @override
  String get german => 'Deutsch';

  @override
  String get japanese => 'Japanisch';

  @override
  String get portuguese => 'Portugiesisch';

  @override
  String get russian => 'Russisch';

  @override
  String get italian => 'Italienisch';

  @override
  String get hindi => 'Hindi';

  @override
  String get korean => 'Koreanisch';

  @override
  String get arabic => 'Arabisch';

  @override
  String get turkish => 'Türkisch';

  @override
  String get hidePersistentNotifications => 'Dauerhafte Benachrichtigungen ausblenden';

  @override
  String get blockedNotificationApps => 'Blockierte Apps';

  @override
  String get blockAppNotifications => 'Benachrichtigungen blockieren';

  @override
  String get unblockAppNotifications => 'Benachrichtigungen freigeben';

  @override
  String get noBlockedApps => 'Keine blockierten Apps';

  @override
  String get persistentNotification => 'Dauerhaft';

  @override
  String get unblockAll => 'Alle freigeben';

  @override
  String get weather => 'Wetter';

  @override
  String get showWeatherWarnings => 'Wetter- & Regenwarnungen anzeigen';

  @override
  String get temperatureUnit => 'Temperatureinheit';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get continueWatchingDescription => 'Zuletzt angesehene Filme und Serien von unterstützten Apps auf dem Startbildschirm anzeigen';

  @override
  String get dismiss => 'Verwerfen';

  @override
  String get openApp => 'Öffnen';

  @override
  String get noBlockedAppsDesc => 'Alle Apps dürfen derzeit Benachrichtigungen anzeigen';

  @override
  String get notificationsAllowed => 'Benachrichtigungen erlaubt';

  @override
  String get notificationsBlocked => 'Benachrichtigungen blockiert';

  @override
  String get dpadDismissHint => 'Links: Verwerfen • OK: Optionen';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get profilesTitle => 'Profile';

  @override
  String get homeScreenTitle => 'Startbildschirm';

  @override
  String get remoteAndSearchTitle => 'Fernbedienung & Suche';

  @override
  String get parentSettingsTitle => 'Eltern-Einstellungen';

  @override
  String get tvPowerTitle => 'TV & Energie';

  @override
  String get setupPermissionsTitle => 'Einrichtung & Berechtigungen';

  @override
  String get updatesTitle => 'Updates';

  @override
  String get familyAppsTitle => 'Hearth auf anderen Profilen';

  @override
  String get cardStyleTitle => 'Kartenstil';

  @override
  String get dockLabelsTitle => 'Dock & Beschriftungen';

  @override
  String get animationsSoundTitle => 'Animationen & Ton';

  @override
  String get haPanelTitle => 'Dashboard-Bereich';

  @override
  String get lookTitle => 'Aussehen';

  @override
  String get remoteButtonsTitle => 'Fernbedienungstasten';

  @override
  String get profilePairingTitle => 'Profilkopplung';

  @override
  String get haTvStatusTitle => 'TV-Status';

  @override
  String get continueWatchingAppsTitle => 'Weiterschauen-Apps';

  @override
  String get cardSizeTitle => 'Kartengröße';

  @override
  String get maxItemsTitle => 'Maximale Anzahl';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get close => 'Schließen';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get notNow => 'Nicht jetzt';

  @override
  String get done => 'Fertig';

  @override
  String get remove => 'Entfernen';

  @override
  String get homeNothingToWatch => 'Gerade gibt es nichts zu sehen';

  @override
  String get errorScreenTitle => 'Etwas ist schiefgelaufen';

  @override
  String get appInfoAddToCategory => 'Zu Kategorie hinzufügen';

  @override
  String get appInfoAddToFavorites => 'Zu Favoriten';

  @override
  String get appInfoRemoveFromFavorites => 'Aus Favoriten entfernen';

  @override
  String get appInfoSetCustomBanner => 'Eigenes Banner festlegen';

  @override
  String get appInfoClearCustomBanner => 'Eigenes Banner entfernen';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Banner konnte nicht festgelegt werden: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Banner konnte nicht entfernt werden: $error';
  }

  @override
  String get cwGridAll => 'Alle';

  @override
  String get cwRowSeeAll => 'Alle ansehen';

  @override
  String cwRowInProgress(int count) {
    return '$count begonnen';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Noch $hours Std. $minutes Min.';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Noch $minutes Min.';
  }

  @override
  String get watchNextInfoRemove => 'Aus „Weiterschauen“ entfernen';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Alle von $appName ausblenden';
  }

  @override
  String get watchNextInfoPlayResume => 'Abspielen / Fortsetzen';

  @override
  String watchNextInfoOpenApp(String appName) {
    return '$appName öffnen';
  }

  @override
  String get watchNextInfoAppInfo => 'App-Info';

  @override
  String get dataWidgetGrantPermission => 'Nutzungszugriff erlauben';

  @override
  String dataWidgetDaily(String usage) {
    return 'Täglich: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Wöchentlich: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Monatlich: $usage';
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
        'today': 'Regen heute',
        'tomorrow': 'Regen morgen',
        'other': 'Regen am $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Schnee heute',
        'tomorrow': 'Schnee morgen',
        'other': 'Schnee am $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Gewitter heute',
        'tomorrow': 'Gewitter morgen',
        'other': 'Gewitter am $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$percent % $forecast';
  }

  @override
  String searchWatchOn(String apps) {
    return 'Auf $apps ansehen';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Auf $app leihen oder kaufen';
  }

  @override
  String get searchMoreWaysToWatch => 'Weitere Möglichkeiten (Google TV)';

  @override
  String get searchListening => 'Höre zu…';

  @override
  String get searchHint => 'Filme und Serien suchen';

  @override
  String get searchEntryHelp => 'Tippen Sie, nutzen Sie das Mikrofon oder tippen Sie mit der Google TV App auf Ihrem Smartphone.';

  @override
  String get searchTabWatchNow => 'Jetzt ansehen';

  @override
  String get searchTabRentOrBuy => 'Leihen oder kaufen';

  @override
  String get searchTabOtherApps => 'Andere Apps';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Leihen oder kaufen · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Wo ansehen: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'Auf $services (nicht auf diesem Fernseher)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ergebnisse',
      one: '$count Ergebnis',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Hier gibt es nichts zu „$query“.';
  }

  @override
  String get searchGridTmdbNotice => 'Verfügbarkeit von TMDB (über JustWatch). Dieses Produkt verwendet die TMDB-API, wird aber von TMDB weder unterstützt noch zertifiziert.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps oder $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Google fragen: „$query“';
  }

  @override
  String get searchAskGoogleDetail => 'Für Fragen, das Wetter und alles andere, was keine Sendung ist';

  @override
  String searchSearchingFor(String query) {
    return 'Suche nach „$query“…';
  }

  @override
  String get searchFailed => 'Suche gerade nicht möglich. Prüfen Sie die Internetverbindung.';

  @override
  String searchNothingFound(String query) {
    return 'Nichts gefunden für „$query“';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Gerade nichts zu „$query“ in Ihren Apps';
  }

  @override
  String get searchSeeMoreResults => 'Unter „Weitere Ergebnisse“ sehen Sie, wo es sonst verfügbar ist.';

  @override
  String get searchMoreResults => 'Weitere Ergebnisse';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Titel',
      one: '$count Titel',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Google fragen';

  @override
  String searchQuoted(String query) {
    return '„$query“';
  }

  @override
  String get searchKindFilm => 'Film';

  @override
  String get searchKindSeries => 'Serie';

  @override
  String get gradientNamePitchBlack => 'Pechschwarz';

  @override
  String get gradientNameGreatWhale => 'Großer Wal';

  @override
  String get gradientNameViciousStance => 'Finstere Haltung';

  @override
  String get gradientNameTeenNotebook => 'Teenie-Notizbuch';

  @override
  String get gradientNameOldHat => 'Alter Hut';

  @override
  String get gradientNameBurningSpring => 'Brennender Frühling';

  @override
  String get gradientNameDesertHump => 'Wüstenhügel';

  @override
  String get gradientNameFarawayRiver => 'Ferner Fluss';

  @override
  String get gradientNameSaintPetersburg => 'Sankt Petersburg';

  @override
  String get gradientNameAfricanField => 'Afrikanisches Feld';

  @override
  String get gradientNameGrassShampoo => 'Gras-Shampoo';

  @override
  String get updateErrorNoApk => 'Keine Version hat eine APK für dieses Gerät';

  @override
  String get updateErrorCheckFailed => 'Suche nach Updates fehlgeschlagen';

  @override
  String get updateErrorDownloadFailed => 'Update konnte nicht heruntergeladen werden';

  @override
  String get serviceHearthTubeDescription => 'YouTube für Hearth; folgt Ihrem Hearth-Profil';

  @override
  String get haSummaryOn => 'An';

  @override
  String get haSummaryOff => 'Aus';

  @override
  String get haSummaryReporting => 'Meldet';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Schalten Sie die Home-Tasten-Korrektur ein ($path); sie zeigt die Pop-ups an.';
  }

  @override
  String get haNotificationsShow => 'Home Assistant-Benachrichtigungen anzeigen';

  @override
  String get haNotificationsSendTest => 'Testbenachrichtigung senden';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Fügen Sie in Home Assistant die Integration \"Notifications for Android TV / Fire TV\" mit dem Host $host hinzu. Senden Sie ihr dann Benachrichtigungen aus Automationen, zum Beispiel für die Türklingel oder wenn die Wäsche fertig ist.\n\nNur Geräte in Ihrem Heimnetz können sie senden (Port 7676). Pop-ups erscheinen über jeder App und brauchen die eingeschaltete Home-Tasten-Korrektur ($path).';
  }

  @override
  String get haNotificationsThisTvIp => '(IP-Adresse dieses Fernsehers)';

  @override
  String get haPanelSaved => 'Gespeichert';

  @override
  String get haPanelSavedNoToken => 'Gespeichert. Fügen Sie ein Zugriffstoken hinzu, um sich anzumelden.';

  @override
  String get haPanelReceived => 'Adresse und Token vom Telefon empfangen';

  @override
  String get haPanelRightEdge => 'Rechts am rechten Rand öffnet den Bereich';

  @override
  String get haSetUpFromPhone => 'Mit dem Telefon einrichten';

  @override
  String get haPanelTokenLabel => 'Langlebiges Zugriffstoken';

  @override
  String get haPanelTokenSavedHint => 'Gespeichert (zum Ersetzen ein neues eingeben)';

  @override
  String get haPanelDashboardLabel => 'Dashboard';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Nur für dieses Profil aktiv. Der Bereich zeigt ein Dashboard von der Adresse unter $tvStatus, angemeldet mit dem Token. Erstellen Sie das Token in Home Assistant, angemeldet als Nicht-Admin-Benutzer, der für diesen Fernseher angelegt wurde (Profilseite, Reiter Sicherheit).';
  }

  @override
  String get haStatusReportingOff => 'Statusmeldung ist aus';

  @override
  String get haStatusSaved => 'Gespeichert: meldet an Home Assistant';

  @override
  String get haStatusAddressLabel => 'Home Assistant-Adresse';

  @override
  String get haStatusWebhookLabel => 'Webhook-ID';

  @override
  String get haStatusNowPlayingOn => 'Wird gerade abgespielt: an';

  @override
  String get haStatusNowPlayingOff => 'Wird gerade abgespielt: Benachrichtigungszugriff einschalten';

  @override
  String get haStatusHelp => 'Der Fernseher meldet Home Assistant, was läuft: die App, die Wiedergabe, das Google TV-Profil und die Bildschirmzeit der Kinder. Er sendet nur an die Adresse oben, sobald sich etwas ändert.';

  @override
  String get haPhoneSetupNoNetwork => 'Dieser Fernseher ist nicht im Heimnetz, daher kann das Telefon ihn nicht erreichen.';

  @override
  String get haPhoneSetupScan => 'Mit einem Telefon im selben Wi-Fi scannen, die Home Assistant-Adresse und das Zugriffstoken einfügen und auf Send tippen. Die Seite funktioniert nur, solange dieses Fenster offen ist.';

  @override
  String get profilesSwitchProfile => 'Profil wechseln';

  @override
  String get parentPinTitle => 'Eltern-PIN';

  @override
  String get parentPinOn => 'An';

  @override
  String get parentPinOff => 'Aus';

  @override
  String get parentPinCurrent => 'Aktuelle Eltern-PIN';

  @override
  String get parentPinRemove => 'PIN entfernen';

  @override
  String get parentPinChange => 'PIN ändern';

  @override
  String get parentPinNew => 'Neue Eltern-PIN';

  @override
  String get parentPinNewSubtitle => 'Wird benötigt, um den Launcher in Google TV-Kinderprofilen zu ändern';

  @override
  String get parentPinConfirm => 'PIN erneut eingeben';

  @override
  String get parentPinAskTitle => 'Frag deine Eltern';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Die Launcher-Einstellungen sind in Kinderprofilen gesperrt. Ein Elternteil kann in seinem eigenen Profil unter $settings → $profiles → $parentPin eine PIN festlegen.';
  }

  @override
  String get parentPinKidsSubtitle => 'Kinderprofil: Eltern-PIN eingeben, um den Launcher zu ändern';

  @override
  String get parentPinWrong => 'FALSCHE PIN';

  @override
  String get parentPinEnter => 'PIN EINGEBEN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Hallo, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Dieses Profil wird eingerichtet…';

  @override
  String profilesKidsName(String name) {
    return '$name (Kinder)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (Erwachsene)';
  }

  @override
  String get pairingShowPicker => 'Auswahl anzeigen';

  @override
  String get pairingAlwaysShowPicker => 'Immer die Auswahl anzeigen';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (nach Name zugeordnet)';
  }

  @override
  String get pairingNoMatchYet => 'Noch keine Zuordnung: Auswahl wird angezeigt';

  @override
  String get pairingOffSetUp => 'Profilkopplung ist aus. Jetzt einrichten';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Wenn Hearth eine dieser Apps öffnet, wählt es das App-Profil, das mit dem Google TV-Profil gekoppelt ist. Hearth ordnet Namen selbst zu (\"$shortName\" passt zu \"$fullName\"); jede Kopplung lässt sich hier ändern. Ohne Zuordnung erscheint die Profilauswahl der App.';
  }

  @override
  String get pairingAppNotInstalled => 'Nicht installiert';

  @override
  String get pairingAppOff => 'Aus: Die Profilauswahl der App erscheint';

  @override
  String get pairingAppNotSeen => 'Einmal aus Hearth öffnen, damit Hearth die Profile kennenlernt';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Profile gefunden',
      one: '1 Profil gefunden',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Nach Name zuordnen ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Nach Name zuordnen (noch keine Zuordnung)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile in $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Profile in $app koppeln';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth kennt die Profile dieser App noch nicht. Einmal aus Hearth öffnen und dann zurückkommen.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Profile in dieser App: $profiles. Google TV-Profile erscheinen hier, sobald Hearth sie gesehen hat.';
  }

  @override
  String get familyAppsIntro => 'Bringen Sie Hearth und HearthTube auf Ihre anderen Google TV-Profile. In Kinderprofilen ist das nötig, damit HearthTube funktioniert und Hearth in Netflix, Disney+ und anderen Apps das richtige Profil wählt. In Erwachsenenprofilen ist es nur eine Erleichterung, damit niemand sie von Hand installieren muss.';

  @override
  String get familyAppsAddTitle => 'Hearth zu anderen Profilen hinzufügen';

  @override
  String get familyAppsAddKids => 'Damit kommen Hearth und HearthTube auf die Profile Ihrer Kinder, sodass HearthTube dort funktioniert und Hearth in Apps wie Netflix und Disney+ das richtige Profil wählen kann.';

  @override
  String get familyAppsAddAdults => 'Außerdem werden sie auf den anderen Erwachsenenprofilen des Fernsehers installiert, damit andere Erwachsene nichts selbst einrichten müssen.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Es werden nur die zwei eigenen Apps von Hearth hinzugefügt, und Sie können das jederzeit unten mit Entfernen rückgängig machen.';

  @override
  String get familyAppsAddFamilyLink => 'Jedes Kind erhält eine Family Link-Benachrichtigung „App hinzugefügt“.';

  @override
  String get familyAppsAddApproval => 'Beim ersten Mal fragt der Fernseher „Debugging zulassen?“ – wählen Sie „Immer zulassen“; damit kann Hearth die Einrichtung vornehmen.';

  @override
  String get familyAppsAdd => 'Hinzufügen';

  @override
  String get familyAppsRemoveTitle => 'Hearth von anderen Profilen entfernen';

  @override
  String get familyAppsRemoveBody => 'Damit werden Hearth und HearthTube von Ihren anderen Profilen entfernt.';

  @override
  String get familyAppsRemoveFirst => 'Wenn Sie Hearth selbst deinstallieren möchten, führen Sie das zuerst aus – sonst können seine Kopien auf den Kinderprofilen zurückbleiben und nur mit einem Computer entfernt werden.';

  @override
  String get familyAppsUninstallTitle => 'Hearth deinstallieren';

  @override
  String get familyAppsUninstallBody => 'Damit werden zuerst Hearth und HearthTube von Ihren anderen Profilen entfernt und dann Hearth von diesem deinstalliert.';

  @override
  String get familyAppsUninstallWhyHere => 'Wenn Sie hier statt in den Android-Einstellungen deinstallieren, bleibt auf den Kinderprofilen nichts zurück.';

  @override
  String get familyAppsApprovalFirstTitle => 'Zuerst die einmalige Freigabe erteilen';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth konnte die anderen Profile noch nicht bereinigen – dafür ist die einmalige Freigabe „Debugging zulassen?“ auf dem Fernseher nötig.';

  @override
  String get familyAppsApprovalFirstRetry => 'Geben Sie die Freigabe und versuchen Sie dann erneut zu deinstallieren, damit auf den Kinderprofilen nichts zurückbleibt.';

  @override
  String get familyAppsAddDone => 'Hinzufügen abgeschlossen';

  @override
  String get familyAppsRemoveDone => 'Entfernen abgeschlossen';

  @override
  String get familyAppsAdded => 'Fertig. Hearth und HearthTube sind jetzt auf Ihren anderen Profilen – siehe Liste unten.';

  @override
  String get familyAppsRemoved => 'Fertig. Hearth und HearthTube wurden von Ihren anderen Profilen entfernt.';

  @override
  String get familyAppsNothingToSetUp => 'Es gibt noch keine anderen Profile zum Einrichten.';

  @override
  String get familyAppsFailedTitle => 'Profile konnten nicht eingerichtet werden';

  @override
  String get familyAppsFailedBody => 'Hearth braucht eine einmalige Freigabe auf dem Fernseher, bevor es die anderen Profile einrichten kann.';

  @override
  String get familyAppsFailedRetry => 'Wählen Sie auf dem Fernseher „Immer zulassen“, wenn er „Debugging zulassen?“ fragt, und versuchen Sie es dann erneut.';

  @override
  String get familyAppsAlsoAdults => 'Auch andere Erwachsenenprofile einrichten';

  @override
  String get familyAppsOn => 'An';

  @override
  String get familyAppsOff => 'Aus';

  @override
  String get familyAppsNoneYet => 'Noch keine anderen Profile eingerichtet.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: installiert';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: installiert, geschützt';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: nicht installiert';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: nicht installiert, geschützt';
  }

  @override
  String get familyAppsUnnamedKids => 'Ein Kinderprofil';

  @override
  String get familyAppsUnnamedAdult => 'Ein Erwachsenenprofil';
}
