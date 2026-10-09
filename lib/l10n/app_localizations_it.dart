import 'package:intl/intl.dart' as intl;

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

  @override
  String get dataWidgetGrantPermission => 'Concedi autorizzazione di utilizzo';

  @override
  String dataWidgetDaily(String usage) {
    return 'Giornaliero: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Settimanale: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Mensile: $usage';
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
        'today': 'Pioggia oggi',
        'tomorrow': 'Pioggia domani',
        'other': 'Pioggia $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Neve oggi',
        'tomorrow': 'Neve domani',
        'other': 'Neve $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Temporale oggi',
        'tomorrow': 'Temporale domani',
        'other': 'Temporale $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextChance(int percent, String forecast) {
    return '$percent% $forecast';
  }

  @override
  String searchWatchOn(String apps) {
    return 'Guarda su $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Noleggia o acquista su $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Altri modi per guardare (Google TV)';

  @override
  String get searchListening => 'In ascolto…';

  @override
  String get searchHint => 'Cerca film e serie';

  @override
  String get searchEntryHelp => 'Digita, usa il microfono o scrivi sul telefono con l\'app Google TV.';

  @override
  String get searchTabWatchNow => 'Guarda ora';

  @override
  String get searchTabRentOrBuy => 'Noleggia o acquista';

  @override
  String get searchTabOtherApps => 'Altre app';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Noleggia o acquista · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Dove guardare: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'Su $services (non su questa TV)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count risultati',
      one: '$count risultato',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Niente qui per «$query».';
  }

  @override
  String get searchGridTmdbNotice => 'Dove guardare da TMDB (tramite JustWatch). Questo prodotto utilizza l\'API di TMDB ma non è approvato né certificato da TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps o $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Chiedi a Google: «$query»';
  }

  @override
  String get searchAskGoogleDetail => 'Per domande, il meteo e tutto ciò che non è un programma';

  @override
  String searchSearchingFor(String query) {
    return 'Ricerca di «$query»…';
  }

  @override
  String get searchFailed => 'Impossibile cercare ora. Controlla la connessione a Internet.';

  @override
  String searchNothingFound(String query) {
    return 'Nessun risultato per «$query»';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Al momento niente per «$query» nelle tue app';
  }

  @override
  String get searchSeeMoreResults => 'Scopri dove altro è disponibile in Altri risultati.';

  @override
  String get searchMoreResults => 'Altri risultati';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titoli',
      one: '$count titolo',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Chiedi a Google';

  @override
  String searchQuoted(String query) {
    return '«$query»';
  }

  @override
  String get searchKindFilm => 'Film';

  @override
  String get searchKindSeries => 'Serie';

  @override
  String get gradientNamePitchBlack => 'Nero pece';

  @override
  String get gradientNameGreatWhale => 'Grande balena';

  @override
  String get gradientNameViciousStance => 'Posa feroce';

  @override
  String get gradientNameTeenNotebook => 'Quaderno da teenager';

  @override
  String get gradientNameOldHat => 'Vecchio cappello';

  @override
  String get gradientNameBurningSpring => 'Primavera ardente';

  @override
  String get gradientNameDesertHump => 'Duna del deserto';

  @override
  String get gradientNameFarawayRiver => 'Fiume lontano';

  @override
  String get gradientNameSaintPetersburg => 'San Pietroburgo';

  @override
  String get gradientNameAfricanField => 'Campo africano';

  @override
  String get gradientNameGrassShampoo => 'Shampoo all\'erba';

  @override
  String get updateErrorNoApk => 'Nessuna versione ha un APK per questo dispositivo';

  @override
  String get updateErrorCheckFailed => 'Impossibile cercare aggiornamenti';

  @override
  String get updateErrorDownloadFailed => 'Impossibile scaricare l\'aggiornamento';

  @override
  String get serviceHearthTubeDescription => 'YouTube per Hearth; segue il tuo profilo Hearth';

  @override
  String get haSummaryOn => 'Attivo';

  @override
  String get haSummaryOff => 'Disattivo';

  @override
  String get haSummaryReporting => 'Invio attivo';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Attiva la Correzione tasto Home ($path); è lei a mostrare i pop-up.';
  }

  @override
  String get haNotificationsShow => 'Mostra le notifiche di Home Assistant';

  @override
  String get haNotificationsSendTest => 'Invia una notifica di prova';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'In Home Assistant, aggiungi l\'integrazione \"Notifications for Android TV / Fire TV\" con host $host. Poi inviale notifiche dalle automazioni, per esempio per il campanello o quando il bucato è pronto.\n\nSolo i dispositivi della tua rete di casa possono inviarle (porta 7676). I pop-up compaiono sopra qualsiasi app e richiedono la Correzione tasto Home ($path) attiva.';
  }

  @override
  String get haNotificationsThisTvIp => '(l\'indirizzo IP di questa TV)';

  @override
  String get haPanelSaved => 'Salvato';

  @override
  String get haPanelSavedNoToken => 'Salvato. Aggiungi un token di accesso per accedere.';

  @override
  String get haPanelReceived => 'Indirizzo e token ricevuti dal telefono';

  @override
  String get haPanelRightEdge => 'Destra sul bordo destro apre il pannello';

  @override
  String get haSetUpFromPhone => 'Configura dal telefono';

  @override
  String get haPanelTokenLabel => 'Token di accesso a lunga durata';

  @override
  String get haPanelTokenSavedHint => 'Salvato (scrivine uno nuovo per sostituirlo)';

  @override
  String get haPanelDashboardLabel => 'Dashboard';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Attivo solo per questo profilo. Il pannello mostra una dashboard dall\'indirizzo indicato in $tvStatus, con accesso tramite il token. Crea il token in Home Assistant accedendo con un utente non amministratore creato per questa TV (pagina del profilo, scheda Sicurezza).';
  }

  @override
  String get haStatusReportingOff => 'L\'invio dello stato è disattivato';

  @override
  String get haStatusSaved => 'Salvato: invio a Home Assistant';

  @override
  String get haStatusAddressLabel => 'Indirizzo di Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID webhook';

  @override
  String get haStatusNowPlayingOn => 'In riproduzione: attivo';

  @override
  String get haStatusNowPlayingOff => 'In riproduzione: attiva l\'accesso alle notifiche';

  @override
  String get haStatusHelp => 'La TV comunica a Home Assistant cosa c\'è sullo schermo: l\'app, cosa è in riproduzione, il profilo Google TV e il tempo di utilizzo dei bambini. Invia solo all\'indirizzo sopra, man mano che le cose cambiano.';

  @override
  String get haPhoneSetupNoNetwork => 'Questa TV non è sulla rete di casa, quindi il telefono non può raggiungerla.';

  @override
  String get haPhoneSetupScan => 'Scansiona con un telefono sulla stessa rete Wi-Fi, incolla l\'indirizzo di Home Assistant e il token di accesso e tocca Send. La pagina funziona solo finché questa finestra è aperta.';

  @override
  String get profilesSwitchProfile => 'Cambia profilo';

  @override
  String get parentPinTitle => 'PIN genitori';

  @override
  String get parentPinOn => 'Attivo';

  @override
  String get parentPinOff => 'Disattivo';

  @override
  String get parentPinCurrent => 'PIN genitori attuale';

  @override
  String get parentPinRemove => 'Rimuovi PIN';

  @override
  String get parentPinChange => 'Cambia PIN';

  @override
  String get parentPinNew => 'Nuovo PIN genitori';

  @override
  String get parentPinNewSubtitle => 'Serve per modificare il launcher nei profili bambini di Google TV';

  @override
  String get parentPinConfirm => 'Inserisci di nuovo il PIN';

  @override
  String get parentPinAskTitle => 'Chiedi a un genitore';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Le impostazioni del launcher sono bloccate nei profili bambini. Un genitore può impostare un PIN in $settings → $profiles → $parentPin dal proprio profilo.';
  }

  @override
  String get parentPinKidsSubtitle => 'Profilo bambini: inserisci il PIN genitori per modificare il launcher';

  @override
  String get parentPinWrong => 'PIN ERRATO';

  @override
  String get parentPinEnter => 'INSERISCI IL PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Ciao, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Configurazione del profilo…';

  @override
  String profilesKidsName(String name) {
    return '$name (bambini)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (adulti)';
  }

  @override
  String get pairingShowPicker => 'Mostra la scelta profilo';

  @override
  String get pairingAlwaysShowPicker => 'Mostra sempre la scelta profilo';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (abbinato per nome)';
  }

  @override
  String get pairingNoMatchYet => 'Nessun abbinamento: compare la scelta profilo';

  @override
  String get pairingOffSetUp => 'L\'abbinamento profili è disattivato. Configuralo';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Quando Hearth apre una di queste app, sceglie il profilo dell\'app abbinato al profilo Google TV. Hearth abbina i nomi da solo (\"$shortName\" va con \"$fullName\"); puoi cambiare qualsiasi abbinamento qui. Senza abbinamento, compare la scelta profilo dell\'app.';
  }

  @override
  String get pairingAppNotInstalled => 'Non installata';

  @override
  String get pairingAppOff => 'Disattivo: compare la scelta profilo dell\'app';

  @override
  String get pairingAppNotSeen => 'Aprila una volta da Hearth così Hearth ne impara i profili';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profili trovati',
      one: '1 profilo trovato',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Abbina per nome ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Abbina per nome (nessun abbinamento)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile in $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Abbina i profili in $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth non ha ancora visto i profili di questa app. Aprila una volta da Hearth, poi torna qui.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Profili in questa app: $profiles. I profili Google TV compaiono qui quando Hearth li ha visti.';
  }

  @override
  String get familyAppsIntro => 'Porta Hearth e HearthTube sugli altri profili Google TV. Sui profili bambini serve perché HearthTube funzioni e perché Hearth scelga il profilo giusto in Netflix, Disney+ e altre app. Sui profili adulti è solo una comodità, così non vanno installate a mano.';

  @override
  String get familyAppsAddTitle => 'Aggiungi Hearth agli altri profili';

  @override
  String get familyAppsAddKids => 'Così Hearth e HearthTube vanno sui profili dei tuoi figli: HearthTube funziona lì e Hearth può scegliere il profilo giusto in app come Netflix e Disney+.';

  @override
  String get familyAppsAddAdults => 'Le installa anche sugli altri profili adulti della TV, così un altro adulto non deve configurarle da solo.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Aggiunge solo le due app di Hearth e puoi annullare in qualsiasi momento con Rimuovi qui sotto.';

  @override
  String get familyAppsAddFamilyLink => 'Ogni bambino riceve una notifica di Family Link \"app aggiunta\".';

  @override
  String get familyAppsAddApproval => 'La prima volta la TV chiede \"Consentire il debug?\": scegli Consenti sempre; è ciò che permette a Hearth di fare la configurazione.';

  @override
  String get familyAppsAdd => 'Aggiungi';

  @override
  String get familyAppsRemoveTitle => 'Rimuovi Hearth dagli altri profili';

  @override
  String get familyAppsRemoveBody => 'Rimuove Hearth e HearthTube dagli altri profili.';

  @override
  String get familyAppsRemoveFirst => 'Se vuoi disinstallare Hearth, fai prima questo: altrimenti le sue copie sui profili bambini possono restare bloccate e servirà un computer per rimuoverle.';

  @override
  String get familyAppsUninstallTitle => 'Disinstalla Hearth';

  @override
  String get familyAppsUninstallBody => 'Prima rimuove Hearth e HearthTube dagli altri profili, poi disinstalla Hearth da questo.';

  @override
  String get familyAppsUninstallWhyHere => 'Disinstallare da qui, invece che dalle impostazioni di Android, garantisce che non resti nulla sui profili bambini.';

  @override
  String get familyAppsApprovalFirstTitle => 'Prima completa l\'approvazione una tantum';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth non è ancora riuscito a ripulire gli altri profili: serve l\'approvazione una tantum \"Consentire il debug?\" sulla TV.';

  @override
  String get familyAppsApprovalFirstRetry => 'Approvala, poi riprova Disinstalla, così sui profili bambini non resta nulla.';

  @override
  String get familyAppsAddDone => 'Aggiunta completata';

  @override
  String get familyAppsRemoveDone => 'Rimozione completata';

  @override
  String get familyAppsAdded => 'Fatto. Hearth e HearthTube ora sono sugli altri profili: guarda l\'elenco qui sotto.';

  @override
  String get familyAppsRemoved => 'Fatto. Hearth e HearthTube sono stati rimossi dagli altri profili.';

  @override
  String get familyAppsNothingToSetUp => 'Non ci sono ancora altri profili da configurare.';

  @override
  String get familyAppsFailedTitle => 'Impossibile configurare i profili';

  @override
  String get familyAppsFailedBody => 'Hearth ha bisogno di un\'approvazione una tantum sulla TV prima di poter configurare gli altri profili.';

  @override
  String get familyAppsFailedRetry => 'Sulla TV scegli Consenti sempre quando chiede \"Consentire il debug?\", poi riprova.';

  @override
  String get familyAppsAlsoAdults => 'Configura anche gli altri profili adulti';

  @override
  String get familyAppsOn => 'Attivo';

  @override
  String get familyAppsOff => 'Disattivo';

  @override
  String get familyAppsNoneYet => 'Nessun altro profilo ancora configurato.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: installata';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: installata, protetta';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: non installata';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: non installata, protetta';
  }

  @override
  String get familyAppsUnnamedKids => 'Un profilo bambini';

  @override
  String get familyAppsUnnamedAdult => 'Un profilo adulti';
}
