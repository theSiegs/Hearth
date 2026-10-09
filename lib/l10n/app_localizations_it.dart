import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get aboutFlauncher => 'Informazioni su Hearth';

  @override
  String get addSection => 'Aggiungi sezione';

  @override
  String get alphabetical => 'Alfabetico';

  @override
  String get appCardHighlightAnimation => 'Animazione evidenziazione scheda app';

  @override
  String get appInfo => 'Info app';

  @override
  String get appKeyClick => 'Suono clic alla pressione del tasto';

  @override
  String get applications => 'Applicazioni';

  @override
  String get autoHideAppBar => 'Nascondi automaticamente barra di stato';

  @override
  String get backButtonAction => 'Azione pulsante Indietro';

  @override
  String get category => 'Categoria';

  @override
  String get columnCount => 'Numero di colonne';

  @override
  String get date => 'Data';

  @override
  String get dateAndTimeFormat => 'Formato data e ora';

  @override
  String get delete => 'Elimina';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Non fare nulla';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Mostra salvaschermo';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Mostra orologio';

  @override
  String get dialogTextNoFileExplorer => 'Installa un file manager per selezionare un\'immagine.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Categoria)';
  }

  @override
  String get gradient => 'Sfumatura';

  @override
  String get favoriteApps => 'App preferite';

  @override
  String get grid => 'Griglia';

  @override
  String get height => 'Altezza';

  @override
  String get hide => 'Nascondi';

  @override
  String get hiddenApplications => 'App nascoste';

  @override
  String get launcherSections => 'Sezioni';

  @override
  String get layout => 'Layout';

  @override
  String get loading => 'Caricamento';

  @override
  String get manual => 'Manuale';

  @override
  String get modifySection => 'Modifica sezione';

  @override
  String get name => 'Nome';

  @override
  String get newSection => 'Nuova sezione';

  @override
  String get nonTvApplications => 'App non TV';

  @override
  String get open => 'Apri';

  @override
  String get picture => 'Immagine';

  @override
  String removeFrom(String name) {
    return 'Rimuovi da $name';
  }

  @override
  String get reorder => 'Riordina';

  @override
  String get row => 'Riga';

  @override
  String get rowHeight => 'Altezza riga';

  @override
  String get save => 'Salva';

  @override
  String get spacer => 'Spaziatore';

  @override
  String get statusBar => 'Barra di stato';

  @override
  String get show => 'Mostra';

  @override
  String get showCategoryTitles => 'Mostra titoli delle categorie';

  @override
  String get showCategoryAppCount => 'Mostra numero di app nelle categorie';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Nascondi contorno evidenziazione nella schermata Home';

  @override
  String get appSelectorTransitionAnimation => 'Animazione transizione selettore app';

  @override
  String get sort => 'Ordina';

  @override
  String get systemSettings => 'Impostazioni di sistema';

  @override
  String get textEmptyCategory => 'Questa categoria è vuota.';

  @override
  String get time => 'Ora';

  @override
  String get tvApplications => 'App TV';

  @override
  String get type => 'Tipo';

  @override
  String get uninstall => 'Disinstalla';

  @override
  String get wallpaper => 'Sfondo';

  @override
  String get withEllipsisAddTo => 'Aggiungi a...';

  @override
  String get timeBasedWallpaper => 'Sfondo basato sull\'ora';

  @override
  String get pickDayWallpaper => 'Scegli sfondo diurno';

  @override
  String get pickNightWallpaper => 'Scegli sfondo notturno';

  @override
  String get inputs => 'Ingressi';

  @override
  String get inputSources => 'Sorgenti di ingresso';

  @override
  String get backupAndRestore => 'Backup e Ripristino';

  @override
  String get exportBackup => 'Esporta Backup';

  @override
  String get importBackup => 'Importa Backup';

  @override
  String exportSuccess(String path) {
    return 'Backup esportato con successo in $path';
  }

  @override
  String get importSuccess => 'Backup importato con successo';

  @override
  String get importConfirm => 'Sei sicuro di voler importare il backup? Questo sovrascriverà le tue impostazioni e il layout attuali.';

  @override
  String importError(String error) {
    return 'Impossibile importare il backup: $error';
  }

  @override
  String exportError(String error) {
    return 'Impossibile esportare il backup: $error';
  }

  @override
  String get shareBackup => 'Condividi Backup';

  @override
  String get notificationBell => 'Campanella notifiche';

  @override
  String get autoHideNotificationBell => 'Nascondi automaticamente campanella notifiche';

  @override
  String get continueWatching => 'Continua a guardare';

  @override
  String get showContinueWatchingOnHome => 'Mostra Continua a guardare nella Home';

  @override
  String get permissionDeniedContinueWatching => 'Autorizzazione richiesta per mostrare Continua a guardare';

  @override
  String get system => 'Sistema';

  @override
  String get accentColor => 'Colore primario';

  @override
  String get dataUsagePeriod => 'Periodo utilizzo dati';

  @override
  String get notificationAccess => 'Accesso notifiche';

  @override
  String get watchNextAccess => 'Accesso Watch Next';

  @override
  String get granted => 'Concesso';

  @override
  String get permissionRequired => 'Autorizzazione richiesta';

  @override
  String get systemWidePopupAlert => 'Avviso popup di sistema';

  @override
  String get overlayPermissionRequired => 'Autorizzazione sovrapposizione richiesta';

  @override
  String get enabled => 'Abilitato';

  @override
  String get disabled => 'Disabilitato';

  @override
  String get showAppNamesBelowIcons => 'Mostra nomi app sotto le icone';

  @override
  String get dataUsage => 'Utilizzo dati';

  @override
  String get networkIndicator => 'Indicatore di rete';

  @override
  String get startOnBoot => 'Avvia all\'accensione (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Lingua';

  @override
  String get systemDefault => 'Predefinito di sistema';

  @override
  String get english => 'Inglese';

  @override
  String get spanish => 'Spagnolo';

  @override
  String get ukrainian => 'Ucraino';

  @override
  String get chinese => 'Cinese';

  @override
  String get french => 'Francese';

  @override
  String get german => 'Tedesco';

  @override
  String get japanese => 'Giapponese';

  @override
  String get portuguese => 'Portoghese';

  @override
  String get russian => 'Russo';

  @override
  String get italian => 'Italiano';

  @override
  String get hindi => 'Hindi';

  @override
  String get korean => 'Coreano';

  @override
  String get arabic => 'Arabo';

  @override
  String get turkish => 'Turco';

  @override
  String get hidePersistentNotifications => 'Nascondi notifiche persistenti';

  @override
  String get blockedNotificationApps => 'App bloccate';

  @override
  String get blockAppNotifications => 'Blocca notifiche';

  @override
  String get unblockAppNotifications => 'Sblocca notifiche';

  @override
  String get noBlockedApps => 'Nessuna app bloccata';

  @override
  String get persistentNotification => 'Persistente';

  @override
  String get unblockAll => 'Sblocca tutto';

  @override
  String get weather => 'Meteo';

  @override
  String get showWeatherWarnings => 'Mostra avvisi meteo e pioggia';

  @override
  String get temperatureUnit => 'Unità di temperatura';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Notifiche';

  @override
  String get continueWatchingDescription => 'Mostra film e programmi TV visti di recente sulla schermata iniziale';

  @override
  String get dismiss => 'Ignora';

  @override
  String get openApp => 'Apri';

  @override
  String get noBlockedAppsDesc => 'Tutte le applicazioni possono attualmente mostrare notifiche';

  @override
  String get notificationsAllowed => 'Notifiche consentite';

  @override
  String get notificationsBlocked => 'Notifiche bloccate';

  @override
  String get dpadDismissHint => 'Sinistra: Ignora • OK: Opzioni';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get profilesTitle => 'Profili';

  @override
  String get homeScreenTitle => 'Schermata Home';

  @override
  String get remoteAndSearchTitle => 'Telecomando e ricerca';

  @override
  String get parentSettingsTitle => 'Impostazioni genitori';

  @override
  String get tvPowerTitle => 'TV e alimentazione';

  @override
  String get setupPermissionsTitle => 'Configurazione e autorizzazioni';

  @override
  String get updatesTitle => 'Aggiornamenti';

  @override
  String get familyAppsTitle => 'Hearth su altri profili';

  @override
  String get cardStyleTitle => 'Stile schede';

  @override
  String get dockLabelsTitle => 'Dock ed etichette';

  @override
  String get animationsSoundTitle => 'Animazioni e suoni';

  @override
  String get haPanelTitle => 'Pannello dashboard';

  @override
  String get lookTitle => 'Aspetto';

  @override
  String get remoteButtonsTitle => 'Tasti del telecomando';

  @override
  String get profilePairingTitle => 'Abbinamento profili';

  @override
  String get haTvStatusTitle => 'Stato della TV';

  @override
  String get continueWatchingAppsTitle => 'App di Continua a guardare';

  @override
  String get cardSizeTitle => 'Dimensione schede';

  @override
  String get maxItemsTitle => 'Numero massimo di elementi';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annulla';

  @override
  String get close => 'Chiudi';

  @override
  String get tryAgain => 'Riprova';

  @override
  String get notNow => 'Non ora';

  @override
  String get done => 'Fatto';

  @override
  String get remove => 'Rimuovi';

  @override
  String get homeNothingToWatch => 'Niente da guardare al momento';

  @override
  String get errorScreenTitle => 'Si è verificato un problema';

  @override
  String get appInfoAddToCategory => 'Aggiungi a categoria';

  @override
  String get appInfoAddToFavorites => 'Aggiungi ai preferiti';

  @override
  String get appInfoRemoveFromFavorites => 'Rimuovi dai preferiti';

  @override
  String get appInfoSetCustomBanner => 'Imposta banner personalizzato';

  @override
  String get appInfoClearCustomBanner => 'Rimuovi banner personalizzato';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Impossibile impostare il banner: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Impossibile rimuovere il banner: $error';
  }

  @override
  String get cwGridAll => 'Tutti';

  @override
  String get cwRowSeeAll => 'Vedi tutti';

  @override
  String cwRowInProgress(int count) {
    return '$count in corso';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Mancano $hours h $minutes min';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Mancano $minutes min';
  }

  @override
  String get watchNextInfoRemove => 'Rimuovi da Continua a guardare';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Nascondi tutto da $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Riproduci / Riprendi';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Apri $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Info app';
}
