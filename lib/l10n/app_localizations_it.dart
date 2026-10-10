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
  String get systemSettings => 'Impostazioni di Google TV';

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
  String get remoteAndSearchTitle => 'Telecomando';

  @override
  String get parentSettingsTitle => 'Impostazioni genitori';

  @override
  String get tvPowerTitle => 'TV e alimentazione';

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
  String get familyAppsAddTitle => 'Aggiungi Hearth agli altri profili';

  @override
  String get familyAppsAddKids => 'Così Hearth e HearthTube vanno sui profili dei tuoi figli: HearthTube funziona lì e Hearth può scegliere il profilo giusto nei servizi di streaming.';

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

  @override
  String setupAccessibilityInstructions(String service) {
    return 'Nella schermata successiva scorri fino a Servizi, seleziona \"$service\", poi attiva Attiva e conferma. Premi Indietro finché non torni alla schermata iniziale.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Se Android dice che l\'impostazione è limitata, esegui questo una volta da un computer:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth come app Home';

  @override
  String get setupDefaultLauncherWhy => 'Evita che i profili bambini blocchino Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'Nella schermata successiva scegli Hearth.';

  @override
  String get setupHomeFixTitle => 'Correzione tasto Home';

  @override
  String get setupHomeFixWhy => 'Il tasto Home apre Hearth invece di Google TV.';

  @override
  String get setupNotificationsTitle => 'Accesso alle notifiche';

  @override
  String get setupNotificationsWhy => 'Mostra le notifiche e cosa è in riproduzione.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'Nella schermata successiva seleziona \"$service\" e consentilo.';
  }

  @override
  String get setupInstallTitle => 'Installazione aggiornamenti';

  @override
  String get setupInstallWhy => 'Permette a Hearth di aggiornarsi e di installare le app complementari.';

  @override
  String get setupInstallInstructions => 'Nella schermata successiva attiva Hearth.';

  @override
  String get setupPairingWhy => 'Sceglie il tuo profilo in Netflix, Disney+, Apple TV, HBO Max e Paramount+.';

  @override
  String get setupVoiceTitle => 'Voce di Hearth';

  @override
  String get setupVoiceWhy => 'Permette all\'abbinamento profili di sentire la schermata profili di Netflix. Le altre app mantengono la voce di Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'Nella schermata successiva, in Motore preferito, scegli \"$engine\", poi OK sull\'avviso (Hearth ascolta solo le app di streaming). Premi Indietro per tornare.';
  }

  @override
  String get setupOpenSettings => 'Apri impostazioni';

  @override
  String get setupAdbFallback => 'Questa TV non ha aperto quella schermata delle impostazioni. Esegui invece questo una volta da un computer:';

  @override
  String setupProgress(int done, int total) {
    return '$done di $total completati';
  }

  @override
  String get remoteButtonsRemapButton => 'Riassegna un tasto';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Tasto $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normale';

  @override
  String get remoteButtonsCaptureTitle => 'Premi un tasto del telecomando';

  @override
  String get remoteButtonsCaptureBody => 'Premi il tasto da riassegnare. Premi Indietro per annullare.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Prima attiva la Correzione tasto Home';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Per riassegnare serve la Correzione tasto Home ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Impossibile riassegnare questo tasto';

  @override
  String get remoteButtonsCantRemapBody => 'Frecce, OK, Indietro, Home e accensione mantengono la loro funzione normale.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Pressione: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Pressione lunga: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Premi per la ricerca di Hearth, tieni premuto per Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Solo nella schermata iniziale di Hearth: Attivo';

  @override
  String get remoteButtonsHomeOnlyOff => 'Solo nella schermata iniziale di Hearth: Disattivo';

  @override
  String get remoteButtonsRestore => 'Ripristina il tasto normale';

  @override
  String get remoteButtonsActionTitle => 'Azione';

  @override
  String get remoteButtonsActionApp => 'Apri un\'app…';

  @override
  String get remoteButtonsActionInput => 'Passa a un ingresso TV…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Cambia profilo (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Ricerca di Hearth (voce)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Ricerca di Hearth (tastiera)';

  @override
  String get remoteButtonsActionHome => 'Home di Hearth';

  @override
  String get remoteButtonsActionSleep => 'Sospensione';

  @override
  String get remoteButtonsActionAndroidSettings => 'Impostazioni Android';

  @override
  String get remoteButtonsPickAppTitle => 'Apri un\'app';

  @override
  String get remoteButtonsPickInputTitle => 'Passa a un ingresso TV';

  @override
  String get remoteButtonsHaConnectTitle => 'Prima collega Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Configura il pannello di Home Assistant ($panel > $row), poi riprova.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Scena: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Esegui: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Premi: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Attiva/disattiva: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nPressione: $press  ·  Pressione lunga: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nPressione: $press  ·  Pressione lunga: $hold  ·  Solo schermata iniziale';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Richiede la Correzione tasto Home ($path). Un tasto con solo un\'azione a pressione lunga la esegue anche con una pressione normale. La ricerca di Hearth apre la ricerca di HearthTube quando HearthTube è in primo piano. Le riassegnazioni si fermano mentre è visibile una schermata del tempo di utilizzo dei bambini.';
  }

  @override
  String get tvPowerScreensaver => 'Salvaschermo (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth usa il salvaschermo di Google TV. Lì scegli Google Photos (e quali album) o un\'altra fonte.';

  @override
  String get tvPowerSleepWhenIdle => 'Sospendi se inattivo';

  @override
  String get tvPowerSleepOff => 'Disattivo';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ore',
      one: '1 ora',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'La riproduzione di video o musica conta come attività. Richiede la Correzione tasto Home ($path).';
  }

  @override
  String get accentPurple => 'Viola';

  @override
  String get accentTeal => 'Verde acqua';

  @override
  String get accentBlue => 'Blu';

  @override
  String get accentOrange => 'Arancione';

  @override
  String get accentPink => 'Rosa';

  @override
  String get accentGreen => 'Verde';

  @override
  String get accentWhite => 'Bianco';

  @override
  String get accentYellow => 'Giallo';

  @override
  String get accentRed => 'Rosso';

  @override
  String get accentCyan => 'Ciano';

  @override
  String get accentIndigo => 'Indaco';

  @override
  String get accentLime => 'Lime';

  @override
  String get accentAmber => 'Ambra';

  @override
  String get accentRose => 'Rosa chiaro';

  @override
  String get accentIceBlue => 'Azzurro ghiaccio';

  @override
  String get accentSelected => 'Colore primario scelto';

  @override
  String get cardStyleDefault => 'Predefinito';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Bagliore';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Classico';

  @override
  String get cardStyleMinimal => 'Minimale';

  @override
  String get cardStyleCapsule => 'Capsula';

  @override
  String get dockFavoritesDock => 'Dock dei preferiti';

  @override
  String get dockFavoritesDockDescription => 'Mostra i preferiti come una barra in fondo alla schermata Home, con Continua a guardare sopra e le altre sezioni sotto. Gli angoli seguono lo stile delle schede.';

  @override
  String get dockFrosted => 'Dock smerigliato';

  @override
  String get dockDark => 'Dock scuro';

  @override
  String get dockShadow => 'Ombra del dock';

  @override
  String get dockBlurWallpaperBelow => 'Sfoca lo sfondo sotto il dock';

  @override
  String get wallpaperMatchSelectedApp => 'Abbina all\'app selezionata';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Foto del giorno di Bing';

  @override
  String get wallpaperRefreshNow => 'Aggiorna ora';

  @override
  String get wallpaperBingError => 'Impossibile raggiungere Bing. Controlla la connessione di rete.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Unità di temperatura: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Località meteo: non impostata';

  @override
  String weatherLocationValue(String place) {
    return 'Località meteo: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Impossibile caricare il meteo. Verrà riprovato automaticamente.';

  @override
  String get statusBarWeatherSourceHint => 'Scegli una località meteo qui sopra (meteo da Open-Meteo, gratuito, senza account). Senza, il meteo arriva dall\'app Breezy Weather se è installata con la condivisione Gadgetbridge attiva.';

  @override
  String get weatherLocationTitle => 'Località meteo';

  @override
  String get weatherLocationHint => 'Città o paese';

  @override
  String get weatherLocationNoResults => 'Nessuna località trovata';

  @override
  String get weatherLocationSearchError => 'Impossibile raggiungere il servizio meteo. Controlla la connessione di rete.';

  @override
  String get weatherLocationPrivacyNote => 'Meteo da Open-Meteo.com: gratuito, senza account. Vengono inviate solo le coordinate della località scelta.';

  @override
  String get weatherLocationSearch => 'Cerca';

  @override
  String get dateTimeInvalidFormat => 'Formato non valido';

  @override
  String get dateTimeSelectFormats => 'Scegli i formati qui sotto';

  @override
  String get dataUsageDaily => 'Giornaliero';

  @override
  String get dataUsageWeekly => 'Settimanale';

  @override
  String get dataUsageMonthly => 'Mensile';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Bloccate da Continua a guardare ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Bloccata da Continua a guardare';

  @override
  String get cwAppsUnblock => 'Sblocca';

  @override
  String get cwAppsUnblockAllApps => 'Sblocca tutte le app';

  @override
  String get cwAppsNoBlockedApps => 'Nessuna app bloccata';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Tutte le app supportate possono mostrare elementi in Continua a guardare.';

  @override
  String get cwAppsWithContinueWatching => 'App con Continua a guardare';

  @override
  String get cwAppsWithContinueWatchingHint => 'App che stanno fornendo elementi Watch Next nella schermata Home';

  @override
  String get cwAppsNoActiveApps => 'Al momento nessuna app fornisce elementi per Continua a guardare.\nQuando le app supportate (come SmartTube o i servizi di streaming) aggiungono elementi, appariranno qui.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi attivi',
      one: '1 elemento attivo',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Tutte le app installate';

  @override
  String get cwAppsAllInstalledAppsHint => 'Disattiva per impedire a un\'app di aggiungere elementi a Continua a guardare';

  @override
  String get cwAppsBlocked => 'Bloccata';

  @override
  String get cwAppsAllowed => 'Consentita';

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
  String get cwCardSizeExtraSmall => 'Extra piccolo';

  @override
  String get cwCardSizeVerySmall => 'Molto piccolo';

  @override
  String get cwCardSizeSmall => 'Piccolo';

  @override
  String get cwCardSizeCompact => 'Compatto';

  @override
  String get cwCardSizeMediumSmall => 'Medio piccolo';

  @override
  String get cwCardSizeMedium => 'Medio';

  @override
  String get cwCardSizeStandardDefault => 'Standard (predefinito)';

  @override
  String get cwCardSizeStandard => 'Standard';

  @override
  String get cwCardSizeMediumLarge => 'Medio grande';

  @override
  String get cwCardSizeLarge => 'Grande';

  @override
  String get cwCardSizeVeryLarge => 'Molto grande';

  @override
  String get cwCardSizeExtraLarge => 'Extra grande';

  @override
  String get cwCardSizeHuge => 'Enorme';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mostra fino a $count elementi recenti',
      one: 'Mostra fino a 1 elemento recente',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Predefinito';
  }

  @override
  String get cwUnlimited => 'Illimitati';

  @override
  String get cwMaxItemsAll => 'Mostra tutti gli elementi disponibili';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Barra di avanzamento riproduzione';

  @override
  String get cwPlaybackPercentage => 'Percentuale di riproduzione';

  @override
  String get cwEpisodeDetails => 'Dettagli episodio e video';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bloccate',
      one: '1 bloccata',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Gestisci';

  @override
  String get cwRestoreHiddenPrograms => 'Ripristina programmi nascosti';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nascosti',
      one: '1 nascosto',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'Tutti i programmi nascosti sono stati ripristinati';

  @override
  String get cwWatchNextAdbTitle => 'Accesso Watch Next (richiede ADB)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV richiede l\'autorizzazione READ_WRITE_WATCH_NEXT_PROGRAMS perché i launcher possano leggere e mostrare le righe Continua a guardare delle app installate.\n\nPer concederla, collega la TV tramite ADB ed esegui:';

  @override
  String get appsNoApplicationsFound => 'Nessuna app trovata';

  @override
  String get appDetailsAddToFavorites => 'Aggiungi ai preferiti';

  @override
  String get appDetailsRemoveFromFavorites => 'Rimuovi dai preferiti';

  @override
  String get appDetailsAddToCategory => 'Aggiungi a categoria';

  @override
  String get sectionsCustomOption => 'Personalizzato...';

  @override
  String get sectionsSelectName => 'Scegli un nome';

  @override
  String get sectionsCustomName => 'Nome personalizzato';

  @override
  String get sectionsSortLastUsed => 'Ultimo utilizzo';

  @override
  String get sectionsReorderHint => 'Seleziona con ◄ / ► e usa ▲ / ▼ per riordinare';

  @override
  String get inputsNoneDetected => 'Nessun ingresso rilevato';

  @override
  String get notifClearAll => 'Cancella tutto';

  @override
  String get notifAllCaughtUp => 'Tutto in ordine!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Blocca notifiche ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Apri $app';
  }

  @override
  String get notifAccessAdbTitle => 'Accesso notifiche (richiede ADB)';

  @override
  String get notifAccessAdbMessage => 'Android TV non offre una schermata delle impostazioni di sistema per \"Accesso notifiche\" (ascoltare le notifiche delle altre app).\n\nNota: attivare \"Mostra notifiche\" nelle impostazioni delle app della TV controlla solo le notifiche inviate da questa app, non l\'accesso alle notifiche.\n\nPer concedere l\'accesso alle notifiche, collega la TV tramite ADB ed esegui:';

  @override
  String get notifOpenAppInfo => 'Apri info app';

  @override
  String get notifOverlayPermissionTitle => 'Autorizzazione sovrapposizione';

  @override
  String get notifOverlayAdbMessage => 'Su questo dispositivo non è stato possibile aprire automaticamente la schermata delle impostazioni dell\'autorizzazione di sovrapposizione.\n\nPer attivare i popup in sovrapposizione, concedi l\'autorizzazione manualmente tramite ADB da un computer collegato alla TV:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'App bloccate ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'Usa Google TV per ora';

  @override
  String get backupShareText => 'Backup di Hearth';

  @override
  String get backupShareFailedTitle => 'Condivisione non riuscita';

  @override
  String backupShareFailed(String error) {
    return 'Impossibile condividere il backup: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Esportazione riuscita';

  @override
  String get backupExportFailedTitle => 'Esportazione non riuscita';

  @override
  String get backupImportSuccessTitle => 'Importazione riuscita';

  @override
  String get backupImportFailedTitle => 'Importazione non riuscita';

  @override
  String get backupImport => 'Importa';

  @override
  String backupLoadError(String error) {
    return 'Errore durante il caricamento dei backup: $error';
  }

  @override
  String get backupNoFiles => 'Nessun file di backup trovato.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date ($size)';
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
  String get updateCheckForUpdatesTitle => 'Verifica aggiornamenti';

  @override
  String updateCurrentVersion(String version) {
    return 'Versione attuale: $version';
  }

  @override
  String get updateChecking => 'Ricerca di una nuova versione su GitHub…';

  @override
  String get updateUpToDate => 'Hai la versione più recente.';

  @override
  String updateVersionAvailable(String version) {
    return 'È disponibile la versione $version';
  }

  @override
  String updateDownloading(String percent) {
    return 'Download in corso… $percent%';
  }

  @override
  String get updateDownloadedHint => 'Scaricato. Se il programma di installazione non si è aperto, sul dispositivo potrebbe servire\nconcedere a Hearth l\'autorizzazione \"Installa app sconosciute\".';

  @override
  String get updateSomethingWentWrong => 'Si è verificato un problema';

  @override
  String get updateDownloadAndInstall => 'Scarica e installa';

  @override
  String get updateRetryInstall => 'Riprova installazione';

  @override
  String get updateCheckAgain => 'Controlla di nuovo';

  @override
  String get updatesInstallPermissionTitle => 'Consenti a Hearth di installare app';

  @override
  String get updatesInstallPermissionMessage => 'Nella schermata successiva, trova Hearth e attivalo, poi premi Indietro. L\'installazione riprende quando torni qui.';

  @override
  String get updatesOpenSettings => 'Apri impostazioni';

  @override
  String get updatesCheckFailed => 'Verifica non riuscita';

  @override
  String get updatesInstallerNotStarted => 'L\'installer non si è avviato';

  @override
  String get updatesCheckForUpdates => 'Verifica aggiornamenti';

  @override
  String get updatesAutoUpdate => 'Aggiorna automaticamente';

  @override
  String get updatesAutoUpdateDescription => 'Hearth controlla ogni giorno e installa gli aggiornamenti delle app che ha installato, quando non sono in uso';

  @override
  String get updatesIncludePrereleases => 'Includi versioni preliminari';

  @override
  String get updatesIncludePrereleasesDescription => 'Build di prova iniziali di Hearth e HearthTube. Potrebbero essere incomplete.';

  @override
  String get updatesFooter => 'Installate dalle release GitHub di ciascuna app. Dopo che Hearth ha installato o aggiornato un\'app una volta, i suoi aggiornamenti si installano senza chiedere e l\'app lascia gli aggiornamenti a Hearth.';

  @override
  String get updatesChecking => 'Verifica in corso…';

  @override
  String get updatesInstall => 'Installa';

  @override
  String updatesUpdateTo(String version) {
    return 'Aggiorna a $version';
  }

  @override
  String get updatesUpToDate => 'Aggiornato';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Download $percent%';
  }

  @override
  String get updatesInstalling => 'Installazione…';

  @override
  String get updatesError => 'Errore';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'Basato su $launcher di $author e $original, con parti di $parts';
  }

  @override
  String get aboutDescription => 'Un launcher privato e adatto alle famiglie per Google TV, con profili Google TV e Home Assistant integrati. Senza pubblicità e senza tracker.';

  @override
  String get aboutHearthOnGitHub => 'Hearth su GitHub';

  @override
  String get aboutCredits => 'Riconoscimenti';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'Fork di FLauncher · $author';
  }

  @override
  String get aboutLicense => 'Software libero con licenza GNU GPL v3, come i progetti su cui si basa.';

  @override
  String get familyAppsStatusInstalled => 'Installato';

  @override
  String get familyAppsStatusPartial => 'Parziale';

  @override
  String get familyAppsStatusNotInstalled => 'Non installato';

  @override
  String get familyAppsStatusAtRisk => 'A rischio';

  @override
  String get familyAppsAtRiskDetail => 'Google TV rimuoverà da qui le app non protette al prossimo avvio di questo profilo. Usa di nuovo Aggiungi per proteggerle.';

  @override
  String get profilePinRow => 'PIN del profilo';

  @override
  String get profilePinNone => 'Nessuno';

  @override
  String get profilePinSaved => 'Salvato';

  @override
  String get profilePinRejected => 'Salvato – non accettato l’ultima volta';

  @override
  String get profilePinPaused => 'Salvato – in pausa (l’app è cambiata)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth non sa ancora digitare i PIN in $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'PIN di $profile in $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'Hearth lo digita dietro la scheda “Accesso come” quando $app lo chiede. Resta cifrato su questa TV e non viene mai mostrato.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Imposta prima un PIN genitore ($settings → $profiles → $parentPin): serve per salvare il PIN di un profilo.';
  }

  @override
  String get profilePinSaveFailed => 'Impossibile salvare il PIN.';

  @override
  String get profileLockNow => 'Blocca profilo';

  @override
  String get profileLockOnSleep => 'Blocca quando la TV va in standby';

  @override
  String get profileLockEveryTime => 'Ogni volta';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'Dopo $minutes min di standby';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Usa il blocco del profilo di Google TV: attivalo per il tuo account in Impostazioni di Google TV → Account e accesso → il tuo account → Blocco profilo.';

  @override
  String get aboutWallpaperPhoto => 'FOTO DI SFONDO';

  @override
  String get updateErrorWrongApp => 'Questo download non è un aggiornamento di questo Hearth';

  @override
  String get setupFlowFinishLater => 'Finisci più tardi';

  @override
  String get setupFlowStripEssentials => 'Essenziali';

  @override
  String get setupFlowWelcomeTitle => 'Benvenuto in Hearth';

  @override
  String get setupFlowWelcomeBody => 'Una schermata iniziale per tutta la famiglia: le tue app, cosa stavi guardando e il profilo giusto in ogni app di streaming.';

  @override
  String get setupFlowWelcomeTime => 'Circa 5 minuti. Puoi saltare qualsiasi passaggio.';

  @override
  String get setupFlowGetStarted => 'Inizia';

  @override
  String get setupFlowSetUpLater => 'Configura più tardi';

  @override
  String setupFlowLanguageLink(String language) {
    return 'Lingua: $language';
  }

  @override
  String get setupFlowRestoreLink => 'Ripristina da un backup';

  @override
  String get setupFlowHomeButtonTitle => 'Il tasto Home apre Hearth';

  @override
  String get setupFlowHomeButtonBody => 'Google TV tiene la propria schermata sul tasto Home. Un interruttore nelle impostazioni di Android lo risolve e permette anche a Hearth di:';

  @override
  String get setupFlowHomeButtonPoint1 => 'seguire i cambi di profilo e l\'ora della nanna dei bambini';

  @override
  String get setupFlowHomeButtonPoint2 => 'mostrare avvisi e spegnere la TV quando non è in uso';

  @override
  String get setupFlowOnNextScreen => 'Nella schermata successiva:';

  @override
  String get setupFlowStepServices => 'Scorri fino a Servizi';

  @override
  String setupFlowStepSelect(String name) {
    return 'Seleziona \"$name\"';
  }

  @override
  String get setupFlowStepEnable => 'Attiva Attiva, poi OK';

  @override
  String get setupFlowComesBack => 'Hearth torna da solo quando è attivo. Se Google TV chiede chi sta guardando, scegli te stesso.';

  @override
  String get setupFlowOpenAccessibility => 'Apri Accessibilità';

  @override
  String get setupFlowHomeButtonDone => 'Ora il tasto Home apre Hearth';

  @override
  String get setupFlowNotOnYetTitle => 'Non è ancora attivo';

  @override
  String get setupFlowNotOnYetBody => 'Riprova, oppure salta e fallo più tardi nelle Impostazioni.';

  @override
  String get setupFlowStuckTitle => 'È attivo ma non in esecuzione';

  @override
  String get setupFlowStuckBody => 'Android lo mostra come attivo, ma non è in esecuzione. Disattivalo e riattivalo.';

  @override
  String get setupFlowSkipHomeButtonTitle => 'Saltare il tasto Home?';

  @override
  String get setupFlowSkipHomeButtonBody => 'Senza, il tasto Home apre Google TV e Hearth non sa quando è in uso un profilo bambini.';

  @override
  String get setupFlowSkipAnyway => 'Salta comunque';

  @override
  String get setupFlowSkip => 'Salta';

  @override
  String get setupFlowNext => 'Avanti';

  @override
  String get setupFlowLostTitle => 'L\'aggiornamento ha disattivato il tasto Home';

  @override
  String get setupFlowLostBody => 'Android lo disattiva dopo alcuni aggiornamenti. Riattivalo in un passaggio.';

  @override
  String get setupFlowBlockedTitle => 'Android ha bloccato questo interruttore';

  @override
  String get setupFlowBlockedBody => 'Se l\'interruttore era grigio, è perché Hearth è stato installato da un file scaricato. La TV non ha un\'impostazione per consentirlo.';

  @override
  String get setupFlowBlockedComputer => 'Con un computer:';

  @override
  String get setupFlowBlockedComputerThen => 'Poi attiva l\'interruttore. Hearth se ne accorge da solo.';

  @override
  String get setupFlowBlockedSelfFixBody => 'Il debug è attivo, quindi Hearth può risolvere da solo. La TV chiederà \"Consentire il debug?\": scegli Consenti sempre e Hearth sbloccherà il suo interruttore e lo attiverà.';

  @override
  String get setupFlowSkipForNow => 'Salta per ora';

  @override
  String get setupFlowBlockedSkipLine => 'App, ricerca e Continua a guardare funzionano comunque. Tasto Home, profili, avvisi e timer di spegnimento no.';

  @override
  String get setupFlowLetHearthFix => 'Lascia che Hearth lo risolva';

  @override
  String get setupFlowFixConfirmBody => 'Hearth eseguirà questo sulla TV, tramite la propria connessione di debug:';

  @override
  String get setupFlowFixConfirmApproval => 'La prima volta la TV chiede \"Consentire il debug?\". Scegli Consenti sempre. Cambia solo i permessi di Hearth.';

  @override
  String get setupFlowFixRun => 'Esegui';

  @override
  String get setupFlowFixWaiting => 'In corso. Se la TV chiede \"Consentire il debug?\", scegli Consenti sempre.';

  @override
  String get setupFlowFixFailedTitle => 'Hearth non ci è riuscito';

  @override
  String get setupFlowFixFailedBody => 'Hearth non è riuscito a raggiungere il debug della TV. Se la TV ha chiesto \"Consentire il debug?\", scegli Consenti sempre e riprova. Il debug deve restare attivo nelle Opzioni sviluppatore.';

  @override
  String get setupFlowHomeAppTitle => 'Imposta Hearth come app Home';

  @override
  String get setupFlowHomeAppBody => 'Android mostrerà un elenco di app Home. Scegli Hearth. Così i profili bambini non bloccano Hearth.';

  @override
  String get setupFlowChooseHearth => 'Scegli Hearth';

  @override
  String get setupFlowHomeAppDone => 'Hearth è la tua app Home';

  @override
  String get setupFlowNotChosenTitle => 'Non ancora scelta';

  @override
  String get setupFlowFinishTitle => 'Hearth è pronto';

  @override
  String setupFlowFinishBody(String where) {
    return 'Ciò che hai saltato è nelle Impostazioni, e puoi ripetere tutto da $where.';
  }

  @override
  String get setupFlowFinishOn => 'Attivo';

  @override
  String get setupFlowFinishLaterHeading => 'Più tardi, nelle Impostazioni';

  @override
  String get setupFlowFinishMore => 'Altro nelle Impostazioni: tasti del telecomando, sezioni, notifiche e backup.';

  @override
  String get setupFlowGoHome => 'Vai alla mia Home';

  @override
  String get setupHearthTitle => 'Configura Hearth';

  @override
  String get setupRunAgain => 'Ripeti la configurazione';

  @override
  String get setupCardFamily => 'La tua famiglia';

  @override
  String get setupCardWatching => 'Guardare';

  @override
  String setupChipLeft(int count) {
    return 'Completa la configurazione · mancanti: $count';
  }

  @override
  String get setupChipFix => 'Il tasto Home va sistemato';

  @override
  String get setupChipHideTitle => 'Nascondere questo promemoria?';

  @override
  String setupChipHideBody(String where) {
    return 'Puoi sempre avviare la configurazione da $where.';
  }

  @override
  String get setupChipHide => 'Nascondi';

  @override
  String get setupFlowCardIncluded => 'Cosa include';

  @override
  String get setupFlowCardNeeds => 'Cosa serve';

  @override
  String get setupFlowCardSkipped => 'Saltato';

  @override
  String get setupFlowChange => 'Cambia';

  @override
  String get setupFlowKeep => 'Mantieni';

  @override
  String get setupFlowTurnOn => 'Attiva';

  @override
  String get setupFlowNeedsQuestion => 'Una domanda di Android';

  @override
  String get setupFlowNeedsOneSwitch => 'Un interruttore nelle impostazioni di Android';

  @override
  String get setupFlowNeedsAboutAMinute => 'Circa un minuto';

  @override
  String get setupFlowWatchingBenefit => 'Riprendi da dove avevi lasciato e scopri cosa è in riproduzione.';

  @override
  String get setupFlowWatchingIncluded1 => 'Continua a guardare nella schermata Home';

  @override
  String get setupFlowWatchingIncluded2 => 'Notifiche e cosa è in riproduzione';

  @override
  String get setupFlowSearchWorks => 'La ricerca funziona già: premi Cerca nella schermata Home.';

  @override
  String get setupFlowContinueBody => 'Mostra nella schermata Home cosa stavi guardando nelle tue app. Android lo chiederà una volta: scegli Consenti.';

  @override
  String get setupFlowContinueDone => 'Continua a guardare è attivo';

  @override
  String get setupFlowContinueDeniedTitle => 'Android non l\'ha consentito';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'Puoi attivarlo più tardi in $where.';
  }

  @override
  String get setupFlowNotificationsTitle => 'Cosa è in riproduzione e notifiche';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'Vedi le notifiche e cosa è in riproduzione. Nella schermata successiva, seleziona \"$name\" e consentilo.';
  }

  @override
  String get setupFlowNotificationsDone => 'Le notifiche sono attive';

  @override
  String get setupFlowTvTitle => 'Spegnere la TV quando nessuno guarda?';

  @override
  String get setupFlowTvBody => 'Dopo questo tempo senza premere il telecomando. Video o musica in riproduzione contano come visione.';

  @override
  String get setupFlowTvNeedsHomeButton => 'Serve l\'interruttore del tasto Home dei primi passaggi: senza, Hearth non sa quando si usa il telecomando.';

  @override
  String get setupFlowStartOnBoot => 'Avvia Hearth all\'accensione della TV';

  @override
  String get setupFlowScreensaver => 'Scegli le foto del salvaschermo';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth mantiene aggiornati sé stesso e le sue app complementari.';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth si aggiorna da solo';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, un\'app YouTube fatta per Hearth';

  @override
  String get setupFlowInstallTitle => 'Consenti a Hearth di installare aggiornamenti';

  @override
  String get setupFlowInstallBody => 'Nella schermata successiva, trova Hearth e attivalo, poi premi Indietro.';

  @override
  String get setupFlowInstallDone => 'Hearth può installare aggiornamenti';

  @override
  String get setupFlowTubeTitle => 'Installare HearthTube?';

  @override
  String get setupFlowTubeBody => 'Un\'app YouTube fatta per Hearth: segue i tuoi profili, lo stile dell\'orologio e l\'ora della nanna dei bambini.';

  @override
  String get setupFlowTubeInstalled => 'HearthTube è installato';

  @override
  String get setupCardHome => 'La tua Home';

  @override
  String get setupFlowLookTitle => 'Scegli uno stile';

  @override
  String setupFlowLookBody(String where) {
    return 'Ogni stile appare dietro questa scheda quando lo selezioni. Puoi cambiare qualsiasi parte più tardi in $where.';
  }

  @override
  String get setupFlowLookOtherTitle => 'Scegli uno stile per la tua Home';

  @override
  String get setupFlowLookOtherBody => 'Ogni profilo ha la sua Home. Scegli come appare la tua.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'Foto del giorno';

  @override
  String get setupLookCalmDark => 'Scuro e calmo';

  @override
  String get setupLookBold => 'Audace';

  @override
  String get setupFlowLookNow => 'Attuale';

  @override
  String get setupFlowLookUse => 'Usa questo stile';

  @override
  String get setupFlowLookKeep => 'Mantieni l\'attuale';

  @override
  String get setupFlowLookCustomize => 'Personalizza';

  @override
  String get setupFlowWeatherTitle => 'Mostrare il meteo?';

  @override
  String get setupFlowWeatherBody => 'Scegli la tua città. Viene inviata solo la sua posizione, a Open-Meteo; nessun account.';

  @override
  String get setupFlowWeatherChoose => 'Scegli città';

  @override
  String get setupFlowWeatherDone => 'Il meteo appare nella barra in alto';
}
