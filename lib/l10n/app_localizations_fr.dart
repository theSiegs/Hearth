import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get aboutFlauncher => 'À propos de Hearth';

  @override
  String get addSection => 'Ajouter une section';

  @override
  String get alphabetical => 'Alphabétique';

  @override
  String get appCardHighlightAnimation => 'Animation de surbrillance de la carte d\'application';

  @override
  String get appInfo => 'Infos sur l\'application';

  @override
  String get appKeyClick => 'Son de clic lors de l\'appui sur une touche';

  @override
  String get applications => 'Applications';

  @override
  String get autoHideAppBar => 'Masquer automatiquement la barre d\'état';

  @override
  String get backButtonAction => 'Action du bouton retour';

  @override
  String get category => 'Catégorie';

  @override
  String get columnCount => 'Nombre de colonnes';

  @override
  String get date => 'Date';

  @override
  String get dateAndTimeFormat => 'Format de la date et de l\'heure';

  @override
  String get delete => 'Supprimer';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Ne rien faire';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Afficher l\'écran de veille';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Afficher l\'horloge';

  @override
  String get dialogTextNoFileExplorer => 'Veuillez installer un explorateur de fichiers pour sélectionner une image.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Catégorie)';
  }

  @override
  String get gradient => 'Dégradé';

  @override
  String get favoriteApps => 'Applications favorites';

  @override
  String get grid => 'Grille';

  @override
  String get height => 'Hauteur';

  @override
  String get hide => 'Masquer';

  @override
  String get hiddenApplications => 'Applications masquées';

  @override
  String get launcherSections => 'Sections';

  @override
  String get layout => 'Disposition';

  @override
  String get loading => 'Chargement';

  @override
  String get manual => 'Manuel';

  @override
  String get modifySection => 'Modifier la section';

  @override
  String get name => 'Nom';

  @override
  String get newSection => 'Nouvelle section';

  @override
  String get nonTvApplications => 'Applications non TV';

  @override
  String get open => 'Ouvrir';

  @override
  String get picture => 'Image';

  @override
  String removeFrom(String name) {
    return 'Retirer de $name';
  }

  @override
  String get reorder => 'Réorganiser';

  @override
  String get row => 'Ligne';

  @override
  String get rowHeight => 'Hauteur de ligne';

  @override
  String get save => 'Enregistrer';

  @override
  String get spacer => 'Espace';

  @override
  String get statusBar => 'Barre d\'état';

  @override
  String get show => 'Afficher';

  @override
  String get showCategoryTitles => 'Afficher les titres des catégories';

  @override
  String get showCategoryAppCount => 'Afficher le nombre d\'applications dans les catégories';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Masquer le contour de surbrillance sur l\'écran d\'accueil';

  @override
  String get appSelectorTransitionAnimation => 'Animation de transition du sélecteur d\'application';

  @override
  String get sort => 'Trier';

  @override
  String get systemSettings => 'Paramètres système';

  @override
  String get textEmptyCategory => 'Cette catégorie est vide.';

  @override
  String get time => 'Heure';

  @override
  String get tvApplications => 'Applications TV';

  @override
  String get type => 'Type';

  @override
  String get uninstall => 'Désinstaller';

  @override
  String get wallpaper => 'Fond d\'écran';

  @override
  String get withEllipsisAddTo => 'Ajouter à...';

  @override
  String get timeBasedWallpaper => 'Fond d\'écran basé sur l\'heure';

  @override
  String get pickDayWallpaper => 'Choisir le fond d\'écran de jour';

  @override
  String get pickNightWallpaper => 'Choisir le fond d\'écran de nuit';

  @override
  String get inputs => 'Entrées';

  @override
  String get inputSources => 'Sources d\'entrée';

  @override
  String get backupAndRestore => 'Sauvegarde et restauration';

  @override
  String get exportBackup => 'Exporter la sauvegarde';

  @override
  String get importBackup => 'Importer la sauvegarde';

  @override
  String exportSuccess(String path) {
    return 'Sauvegarde exportée avec succès vers $path';
  }

  @override
  String get importSuccess => 'Sauvegarde importée avec succès';

  @override
  String get importConfirm => 'Voulez-vous vraiment importer la sauvegarde ? Cela remplacera vos paramètres et votre disposition actuels.';

  @override
  String importError(String error) {
    return 'Échec de l\'importation de la sauvegarde : $error';
  }

  @override
  String exportError(String error) {
    return 'Échec de l\'exportation de la sauvegarde : $error';
  }

  @override
  String get shareBackup => 'Partager la sauvegarde';

  @override
  String get notificationBell => 'Cloche de notification';

  @override
  String get autoHideNotificationBell => 'Masquer automatiquement la cloche de notification';

  @override
  String get continueWatching => 'Continuer à regarder';

  @override
  String get showContinueWatchingOnHome => 'Afficher Continuer à regarder sur l\'accueil';

  @override
  String get permissionDeniedContinueWatching => 'Autorisation requise pour afficher Continuer à regarder';

  @override
  String get system => 'Système';

  @override
  String get accentColor => 'Couleur d\'accentuation';

  @override
  String get dataUsagePeriod => 'Période d\'utilisation des données';

  @override
  String get notificationAccess => 'Accès aux notifications';

  @override
  String get watchNextAccess => 'Accès à Watch Next';

  @override
  String get granted => 'Accordé';

  @override
  String get permissionRequired => 'Autorisation requise';

  @override
  String get systemWidePopupAlert => 'Alerte contextuelle à l\'échelle du système';

  @override
  String get overlayPermissionRequired => 'Autorisation de superposition requise';

  @override
  String get enabled => 'Activé';

  @override
  String get disabled => 'Désactivé';

  @override
  String get showAppNamesBelowIcons => 'Afficher les noms des applications sous les icônes';

  @override
  String get dataUsage => 'Utilisation des données';

  @override
  String get networkIndicator => 'Indicateur réseau';

  @override
  String get startOnBoot => 'Lancer au démarrage (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Langue';

  @override
  String get systemDefault => 'Système par défaut';

  @override
  String get english => 'Anglais';

  @override
  String get spanish => 'Espagnol';

  @override
  String get ukrainian => 'Ukrainien';

  @override
  String get chinese => 'Chinois';

  @override
  String get french => 'Français';

  @override
  String get german => 'Allemand';

  @override
  String get japanese => 'Japonais';

  @override
  String get portuguese => 'Portugais';

  @override
  String get russian => 'Russe';

  @override
  String get italian => 'Italien';

  @override
  String get hindi => 'Hindi';

  @override
  String get korean => 'Coréen';

  @override
  String get arabic => 'Arabe';

  @override
  String get turkish => 'Turc';

  @override
  String get hidePersistentNotifications => 'Masquer les notifications persistantes';

  @override
  String get blockedNotificationApps => 'Applications bloquées';

  @override
  String get blockAppNotifications => 'Bloquer les notifications';

  @override
  String get unblockAppNotifications => 'Débloquer les notifications';

  @override
  String get noBlockedApps => 'Aucune application bloquée';

  @override
  String get persistentNotification => 'Persistante';

  @override
  String get unblockAll => 'Tout débloquer';

  @override
  String get weather => 'Météo';

  @override
  String get showWeatherWarnings => 'Afficher les alertes météo et pluie';

  @override
  String get temperatureUnit => 'Unité de température';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Notifications';

  @override
  String get continueWatchingDescription => 'Afficher les films et séries récemment regardés sur l\'écran d\'accueil';

  @override
  String get dismiss => 'Ignorer';

  @override
  String get openApp => 'Ouvrir';

  @override
  String get noBlockedAppsDesc => 'Toutes les applications sont actuellement autorisées à afficher des notifications';

  @override
  String get notificationsAllowed => 'Notifications autorisées';

  @override
  String get notificationsBlocked => 'Notifications bloquées';

  @override
  String get dpadDismissHint => 'Gauche: Ignorer • OK: Options';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get profilesTitle => 'Profils';

  @override
  String get homeScreenTitle => 'Écran d\'accueil';

  @override
  String get remoteAndSearchTitle => 'Télécommande et recherche';

  @override
  String get parentSettingsTitle => 'Paramètres parentaux';

  @override
  String get tvPowerTitle => 'TV et alimentation';

  @override
  String get setupPermissionsTitle => 'Configuration et autorisations';

  @override
  String get updatesTitle => 'Mises à jour';

  @override
  String get familyAppsTitle => 'Hearth sur les autres profils';

  @override
  String get cardStyleTitle => 'Style des cartes';

  @override
  String get dockLabelsTitle => 'Dock et libellés';

  @override
  String get animationsSoundTitle => 'Animations et son';

  @override
  String get haPanelTitle => 'Panneau du tableau de bord';

  @override
  String get lookTitle => 'Apparence';

  @override
  String get remoteButtonsTitle => 'Boutons de la télécommande';

  @override
  String get profilePairingTitle => 'Association des profils';

  @override
  String get haTvStatusTitle => 'État de la TV';

  @override
  String get continueWatchingAppsTitle => 'Applis Continuer à regarder';

  @override
  String get cardSizeTitle => 'Taille des cartes';

  @override
  String get maxItemsTitle => 'Nombre maximal d\'éléments';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuler';

  @override
  String get close => 'Fermer';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get notNow => 'Pas maintenant';

  @override
  String get done => 'Terminé';

  @override
  String get remove => 'Retirer';

  @override
  String get homeNothingToWatch => 'Rien à regarder pour le moment';

  @override
  String get errorScreenTitle => 'Un problème est survenu';

  @override
  String get appInfoAddToCategory => 'Ajouter à une catégorie';

  @override
  String get appInfoAddToFavorites => 'Ajouter aux favoris';

  @override
  String get appInfoRemoveFromFavorites => 'Retirer des favoris';

  @override
  String get appInfoSetCustomBanner => 'Définir une bannière personnalisée';

  @override
  String get appInfoClearCustomBanner => 'Supprimer la bannière personnalisée';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Impossible de définir la bannière : $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Impossible de supprimer la bannière : $error';
  }

  @override
  String get cwGridAll => 'Tout';

  @override
  String get cwRowSeeAll => 'Tout voir';

  @override
  String cwRowInProgress(int count) {
    return '$count en cours';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Encore $hours h $minutes min';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Encore $minutes min';
  }

  @override
  String get watchNextInfoRemove => 'Retirer de Continuer à regarder';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Masquer tout de $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Lire / Reprendre';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Ouvrir $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Infos sur l\'application';

  @override
  String get dataWidgetGrantPermission => 'Autoriser l\'accès à l\'utilisation';

  @override
  String dataWidgetDaily(String usage) {
    return 'Quotidien : $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Hebdomadaire : $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Mensuel : $usage';
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
        'today': 'Pluie aujourd\'hui',
        'tomorrow': 'Pluie demain',
        'other': 'Pluie $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Neige aujourd\'hui',
        'tomorrow': 'Neige demain',
        'other': 'Neige $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Orage aujourd\'hui',
        'tomorrow': 'Orage demain',
        'other': 'Orage $day',
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
    return 'Regarder sur $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Louer ou acheter sur $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Autres façons de regarder (Google TV)';

  @override
  String get searchListening => 'Écoute…';

  @override
  String get searchHint => 'Rechercher des films et des séries';

  @override
  String get searchEntryHelp => 'Saisissez, utilisez le micro ou tapez sur votre téléphone avec l\'appli Google TV.';

  @override
  String get searchTabWatchNow => 'À regarder';

  @override
  String get searchTabRentOrBuy => 'Louer ou acheter';

  @override
  String get searchTabOtherApps => 'Autres applis';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Louer ou acheter · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Où regarder : Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'Sur $services (pas sur ce téléviseur)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count résultats',
      one: '$count résultat',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'Rien ici pour « $query ».';
  }

  @override
  String get searchGridTmdbNotice => 'Où regarder : données TMDB (via JustWatch). Ce produit utilise l\'API TMDB mais n\'est ni approuvé ni certifié par TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps ou $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Demander à Google : « $query »';
  }

  @override
  String get searchAskGoogleDetail => 'Pour les questions, la météo et tout ce qui n\'est pas un programme';

  @override
  String searchSearchingFor(String query) {
    return 'Recherche de « $query »…';
  }

  @override
  String get searchFailed => 'Recherche impossible pour le moment. Vérifiez la connexion Internet.';

  @override
  String searchNothingFound(String query) {
    return 'Aucun résultat pour « $query »';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Rien pour « $query » dans vos applis pour le moment';
  }

  @override
  String get searchSeeMoreResults => 'Voyez où le trouver ailleurs dans Plus de résultats.';

  @override
  String get searchMoreResults => 'Plus de résultats';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '$count titre',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Demander à Google';

  @override
  String searchQuoted(String query) {
    return '« $query »';
  }

  @override
  String get searchKindFilm => 'Film';

  @override
  String get searchKindSeries => 'Série';

  @override
  String get gradientNamePitchBlack => 'Noir profond';

  @override
  String get gradientNameGreatWhale => 'Grande baleine';

  @override
  String get gradientNameViciousStance => 'Posture menaçante';

  @override
  String get gradientNameTeenNotebook => 'Carnet d\'ado';

  @override
  String get gradientNameOldHat => 'Vieux chapeau';

  @override
  String get gradientNameBurningSpring => 'Printemps ardent';

  @override
  String get gradientNameDesertHump => 'Dune du désert';

  @override
  String get gradientNameFarawayRiver => 'Rivière lointaine';

  @override
  String get gradientNameSaintPetersburg => 'Saint-Pétersbourg';

  @override
  String get gradientNameAfricanField => 'Champ africain';

  @override
  String get gradientNameGrassShampoo => 'Shampoing à l\'herbe';

  @override
  String get updateErrorNoApk => 'Aucune version ne propose d\'APK pour cet appareil';

  @override
  String get updateErrorCheckFailed => 'Impossible de rechercher des mises à jour';

  @override
  String get updateErrorDownloadFailed => 'Impossible de télécharger la mise à jour';

  @override
  String get serviceHearthTubeDescription => 'YouTube pour Hearth ; suit votre profil Hearth';

  @override
  String get haSummaryOn => 'Activé';

  @override
  String get haSummaryOff => 'Désactivé';

  @override
  String get haSummaryReporting => 'Envoi actif';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Activez le Correctif du bouton Accueil ($path) ; c\'est lui qui affiche les fenêtres.';
  }

  @override
  String get haNotificationsShow => 'Afficher les notifications Home Assistant';

  @override
  String get haNotificationsSendTest => 'Envoyer une notification de test';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'Dans Home Assistant, ajoutez l\'intégration \"Notifications for Android TV / Fire TV\" avec l\'hôte $host. Envoyez-lui ensuite des notifications depuis des automatisations, par exemple pour la sonnette ou quand la lessive est terminée.\n\nSeuls les appareils de votre réseau domestique peuvent les envoyer (port 7676). Les fenêtres s\'affichent par-dessus n\'importe quelle application et nécessitent le Correctif du bouton Accueil ($path) activé.';
  }

  @override
  String get haNotificationsThisTvIp => '(l\'adresse IP de cette TV)';

  @override
  String get haPanelSaved => 'Enregistré';

  @override
  String get haPanelSavedNoToken => 'Enregistré. Ajoutez un jeton d\'accès pour vous connecter.';

  @override
  String get haPanelReceived => 'Adresse et jeton reçus depuis votre téléphone';

  @override
  String get haPanelRightEdge => 'Droite au bord droit ouvre le panneau';

  @override
  String get haSetUpFromPhone => 'Configurer depuis votre téléphone';

  @override
  String get haPanelTokenLabel => 'Jeton d\'accès longue durée';

  @override
  String get haPanelTokenSavedHint => 'Enregistré (saisissez-en un nouveau pour le remplacer)';

  @override
  String get haPanelDashboardLabel => 'Tableau de bord';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Activé pour ce profil uniquement. Le panneau affiche un tableau de bord depuis l\'adresse indiquée dans $tvStatus, connecté avec le jeton. Créez le jeton dans Home Assistant en étant connecté avec un utilisateur non administrateur créé pour cette TV (page du profil, onglet Sécurité).';
  }

  @override
  String get haStatusReportingOff => 'L\'envoi de l\'état est désactivé';

  @override
  String get haStatusSaved => 'Enregistré : envoi vers Home Assistant';

  @override
  String get haStatusAddressLabel => 'Adresse de Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID du webhook';

  @override
  String get haStatusNowPlayingOn => 'En cours de lecture : activé';

  @override
  String get haStatusNowPlayingOff => 'En cours de lecture : activez l\'accès aux notifications';

  @override
  String get haStatusHelp => 'La TV indique à Home Assistant ce qui est affiché : l\'application, ce qui est en lecture, le profil Google TV et le temps d\'écran des enfants. Elle n\'envoie qu\'à l\'adresse ci-dessus, au fil des changements.';

  @override
  String get haPhoneSetupNoNetwork => 'Cette TV n\'est pas sur le réseau domestique, le téléphone ne peut donc pas la joindre.';

  @override
  String get haPhoneSetupScan => 'Scannez avec un téléphone connecté au même Wi-Fi, collez l\'adresse de Home Assistant et le jeton d\'accès, puis appuyez sur Send. La page ne fonctionne que tant que cette fenêtre est ouverte.';

  @override
  String get profilesSwitchProfile => 'Changer de profil';

  @override
  String get parentPinTitle => 'Code PIN parental';

  @override
  String get parentPinOn => 'Activé';

  @override
  String get parentPinOff => 'Désactivé';

  @override
  String get parentPinCurrent => 'Code PIN parental actuel';

  @override
  String get parentPinRemove => 'Supprimer le code PIN';

  @override
  String get parentPinChange => 'Modifier le code PIN';

  @override
  String get parentPinNew => 'Nouveau code PIN parental';

  @override
  String get parentPinNewSubtitle => 'Nécessaire pour modifier le lanceur dans les profils enfants Google TV';

  @override
  String get parentPinConfirm => 'Saisissez à nouveau le code PIN';

  @override
  String get parentPinAskTitle => 'Demande à un parent';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Les paramètres du lanceur sont verrouillés dans les profils enfants. Un parent peut définir un code PIN dans $settings → $profiles → $parentPin depuis son propre profil.';
  }

  @override
  String get parentPinKidsSubtitle => 'Profil enfant : saisissez le code PIN parental pour modifier le lanceur';

  @override
  String get parentPinWrong => 'CODE PIN INCORRECT';

  @override
  String get parentPinEnter => 'SAISISSEZ LE CODE PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Bonjour, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Configuration de ce profil…';

  @override
  String profilesKidsName(String name) {
    return '$name (enfant)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (adulte)';
  }

  @override
  String get pairingShowPicker => 'Afficher le sélecteur';

  @override
  String get pairingAlwaysShowPicker => 'Toujours afficher le sélecteur';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (associé par nom)';
  }

  @override
  String get pairingNoMatchYet => 'Pas encore d\'association : le sélecteur s\'affiche';

  @override
  String get pairingOffSetUp => 'L\'association des profils est désactivée. La configurer';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Quand Hearth ouvre l\'une de ces applications, il choisit le profil de l\'application associé au profil Google TV. Hearth associe les noms tout seul (\"$shortName\" va avec \"$fullName\") ; modifiez n\'importe quelle association ici. Sans correspondance, le sélecteur de l\'application s\'affiche.';
  }

  @override
  String get pairingAppNotInstalled => 'Non installée';

  @override
  String get pairingAppOff => 'Désactivé : le sélecteur de l\'application s\'affiche';

  @override
  String get pairingAppNotSeen => 'Ouvrez-la une fois depuis Hearth pour que Hearth découvre ses profils';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count profils trouvés',
      one: '1 profil trouvé',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Associer par nom ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Associer par nom (pas encore d\'association)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile dans $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Associer les profils dans $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth n\'a pas encore vu les profils de cette application. Ouvrez-la une fois depuis Hearth, puis revenez.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Profils de cette application : $profiles. Les profils Google TV apparaissent ici dès que Hearth les a vus.';
  }

  @override
  String get familyAppsIntro => 'Installez Hearth et HearthTube sur vos autres profils Google TV. Sur les profils enfants, c\'est nécessaire pour que HearthTube fonctionne et que Hearth choisisse le bon profil dans Netflix, Disney+ et d\'autres applications. Sur les profils adultes, c\'est juste pratique : pas besoin de les installer à la main.';

  @override
  String get familyAppsAddTitle => 'Ajouter Hearth aux autres profils';

  @override
  String get familyAppsAddKids => 'Cela installe Hearth et HearthTube sur les profils de vos enfants, pour que HearthTube y fonctionne et que Hearth puisse choisir le bon profil dans des applications comme Netflix et Disney+.';

  @override
  String get familyAppsAddAdults => 'Ils sont aussi installés sur les autres profils adultes de la TV, pour qu\'un autre adulte n\'ait pas à le faire lui-même.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Seules les deux applications de Hearth sont ajoutées, et vous pouvez annuler à tout moment avec Retirer ci-dessous.';

  @override
  String get familyAppsAddFamilyLink => 'Chaque enfant reçoit une notification Family Link « application ajoutée ».';

  @override
  String get familyAppsAddApproval => 'La première fois, la TV demande « Autoriser le débogage ? » : choisissez Toujours autoriser ; c\'est ce qui permet à Hearth de faire la configuration.';

  @override
  String get familyAppsAdd => 'Ajouter';

  @override
  String get familyAppsRemoveTitle => 'Retirer Hearth des autres profils';

  @override
  String get familyAppsRemoveBody => 'Cela retire Hearth et HearthTube de vos autres profils.';

  @override
  String get familyAppsRemoveFirst => 'Si vous comptez désinstaller Hearth lui-même, faites ceci d\'abord ; sinon ses copies sur les profils enfants peuvent rester bloquées et nécessiter un ordinateur pour être supprimées.';

  @override
  String get familyAppsUninstallTitle => 'Désinstaller Hearth';

  @override
  String get familyAppsUninstallBody => 'Cela retire d\'abord Hearth et HearthTube de vos autres profils, puis désinstalle Hearth de celui-ci.';

  @override
  String get familyAppsUninstallWhyHere => 'Désinstaller ici, plutôt que depuis les paramètres d\'Android, garantit que rien ne reste sur les profils enfants.';

  @override
  String get familyAppsApprovalFirstTitle => 'Terminez d\'abord l\'autorisation unique';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth n\'a pas encore pu nettoyer les autres profils : il lui faut l\'autorisation unique « Autoriser le débogage ? » sur la TV.';

  @override
  String get familyAppsApprovalFirstRetry => 'Autorisez-le, puis réessayez Désinstaller, pour que rien ne reste sur les profils enfants.';

  @override
  String get familyAppsAddDone => 'Ajout terminé';

  @override
  String get familyAppsRemoveDone => 'Retrait terminé';

  @override
  String get familyAppsAdded => 'Terminé. Hearth et HearthTube sont maintenant sur vos autres profils ; voir la liste ci-dessous.';

  @override
  String get familyAppsRemoved => 'Terminé. Hearth et HearthTube ont été retirés de vos autres profils.';

  @override
  String get familyAppsNothingToSetUp => 'Il n\'y a pas encore d\'autres profils à configurer.';

  @override
  String get familyAppsFailedTitle => 'Impossible de configurer les profils';

  @override
  String get familyAppsFailedBody => 'Hearth a besoin d\'une autorisation unique sur la TV avant de pouvoir configurer les autres profils.';

  @override
  String get familyAppsFailedRetry => 'Sur la TV, choisissez Toujours autoriser quand elle demande « Autoriser le débogage ? », puis réessayez.';

  @override
  String get familyAppsAlsoAdults => 'Configurer aussi les autres profils adultes';

  @override
  String get familyAppsOn => 'Activé';

  @override
  String get familyAppsOff => 'Désactivé';

  @override
  String get familyAppsNoneYet => 'Aucun autre profil configuré pour l\'instant.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app : installée';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app : installée, protégée';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app : non installée';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app : non installée, protégée';
  }

  @override
  String get familyAppsUnnamedKids => 'Un profil enfant';

  @override
  String get familyAppsUnnamedAdult => 'Un profil adulte';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'Sur l\'écran suivant, faites défiler jusqu\'à Services, sélectionnez \"$service\", puis activez Activer et confirmez. Appuyez sur Retour jusqu\'à revenir à l\'accueil.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Si Android indique que le paramètre est restreint, exécutez ceci une fois depuis un ordinateur :\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth comme application d\'accueil';

  @override
  String get setupDefaultLauncherWhy => 'Empêche les profils enfants de bloquer Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'Sur l\'écran suivant, choisissez Hearth.';

  @override
  String get setupHomeFixTitle => 'Correctif du bouton Accueil';

  @override
  String get setupHomeFixWhy => 'Le bouton Accueil ouvre Hearth au lieu de Google TV.';

  @override
  String get setupNotificationsTitle => 'Accès aux notifications';

  @override
  String get setupNotificationsWhy => 'Affiche les notifications et ce qui est en lecture.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'Sur l\'écran suivant, sélectionnez \"$service\" et autorisez-le.';
  }

  @override
  String get setupInstallTitle => 'Installation des mises à jour';

  @override
  String get setupInstallWhy => 'Permet à Hearth de se mettre à jour et d\'installer ses applications compagnons.';

  @override
  String get setupInstallInstructions => 'Sur l\'écran suivant, activez Hearth.';

  @override
  String get setupPairingWhy => 'Choisit votre profil dans Netflix, Disney+, Apple TV, HBO Max et Paramount+.';

  @override
  String get setupVoiceTitle => 'Voix Hearth';

  @override
  String get setupVoiceWhy => 'Permet à l\'association des profils d\'entendre l\'écran des profils de Netflix. Les autres applications gardent la voix de Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'Sur l\'écran suivant, sous Moteur préféré, choisissez \"$engine\", puis OK sur l\'avertissement (Hearth n\'écoute que les applications de streaming). Appuyez sur Retour pour revenir.';
  }

  @override
  String get setupOpenSettings => 'Ouvrir les paramètres';

  @override
  String get setupAdbFallback => 'Cette TV n\'a pas ouvert cet écran de paramètres. Exécutez plutôt ceci une fois depuis un ordinateur :';

  @override
  String setupProgress(int done, int total) {
    return '$done sur $total terminés';
  }

  @override
  String get setupOptional => 'Facultatif';

  @override
  String get homeButtonFixOffTitle => 'Le Correctif du bouton Accueil est désactivé';

  @override
  String get homeButtonFixOffBody => 'Le service d\'accessibilité de Hearth s\'est arrêté, généralement après une mise à jour. Tant qu\'il n\'est pas réactivé, le bouton Accueil peut ouvrir Google TV au lieu de Hearth, et les changements de profil ne sont pas suivis.';

  @override
  String get homeButtonFixStuck => 'Android l\'indique toujours comme activé, mais il ne tourne pas. Désactivez puis réactivez Hearth dans les paramètres d\'accessibilité pour le redémarrer.';

  @override
  String get homeButtonFixRestricted => 'Si l\'interrupteur de Hearth y est grisé, Android le bloque car cette mise à jour a été installée depuis un téléchargement. Exécutez ceci depuis un ordinateur connecté à la TV, puis activez Hearth :';

  @override
  String get homeButtonFixDontRemind => 'Ne plus me le rappeler';

  @override
  String get homeButtonFixOpenSettings => 'Ouvrir les paramètres d\'accessibilité';

  @override
  String get remoteButtonsRemapButton => 'Réattribuer un bouton';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Bouton $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normal';

  @override
  String get remoteButtonsCaptureTitle => 'Appuyez sur un bouton de la télécommande';

  @override
  String get remoteButtonsCaptureBody => 'Appuyez sur le bouton à réattribuer. Appuyez sur Retour pour annuler.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Activez d\'abord le Correctif du bouton Accueil';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'La réattribution nécessite le Correctif du bouton Accueil ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Impossible de réattribuer ce bouton';

  @override
  String get remoteButtonsCantRemapBody => 'Les flèches, OK, Retour, Accueil et Marche/Arrêt gardent leur fonction normale.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Appui : $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Appui long : $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Appui pour la recherche Hearth, appui long pour Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Uniquement sur l\'écran d\'accueil de Hearth : Activé';

  @override
  String get remoteButtonsHomeOnlyOff => 'Uniquement sur l\'écran d\'accueil de Hearth : Désactivé';

  @override
  String get remoteButtonsRestore => 'Rétablir le bouton normal';

  @override
  String get remoteButtonsActionTitle => 'Action';

  @override
  String get remoteButtonsActionApp => 'Ouvrir une application…';

  @override
  String get remoteButtonsActionInput => 'Passer à une entrée TV…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Changer de profil (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Recherche Hearth (voix)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Recherche Hearth (clavier)';

  @override
  String get remoteButtonsActionHome => 'Accueil Hearth';

  @override
  String get remoteButtonsActionSleep => 'Veille';

  @override
  String get remoteButtonsActionAndroidSettings => 'Paramètres Android';

  @override
  String get remoteButtonsPickAppTitle => 'Ouvrir une application';

  @override
  String get remoteButtonsPickInputTitle => 'Passer à une entrée TV';

  @override
  String get remoteButtonsHaConnectTitle => 'Connectez d\'abord Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Configurez le panneau Home Assistant ($panel > $row), puis réessayez.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Scène : $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Exécuter : $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Appuyer : $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Basculer : $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nAppui : $press  ·  Appui long : $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nAppui : $press  ·  Appui long : $hold  ·  Écran d\'accueil uniquement';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Nécessite le Correctif du bouton Accueil ($path). Un bouton qui n\'a qu\'une action d\'appui long l\'exécute aussi sur un appui simple. La recherche Hearth ouvre la recherche de HearthTube quand HearthTube est au premier plan. Les réattributions sont suspendues pendant l\'affichage d\'un écran de temps d\'écran pour enfants.';
  }

  @override
  String get tvPowerScreensaver => 'Économiseur d\'écran (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth utilise l\'économiseur d\'écran de Google TV. Choisissez-y Google Photos (et les albums) ou une autre source.';

  @override
  String get tvPowerSleepWhenIdle => 'Mise en veille en cas d\'inactivité';

  @override
  String get tvPowerSleepOff => 'Désactivé';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours heures',
      one: '1 heure',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'La lecture de vidéo ou de musique compte comme une activité. Nécessite le Correctif du bouton Accueil ($path).';
  }

  @override
  String get accentPurple => 'Violet';

  @override
  String get accentTeal => 'Bleu canard';

  @override
  String get accentBlue => 'Bleu';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentPink => 'Rose';

  @override
  String get accentGreen => 'Vert';

  @override
  String get accentWhite => 'Blanc';

  @override
  String get accentYellow => 'Jaune';

  @override
  String get accentRed => 'Rouge';

  @override
  String get accentCyan => 'Cyan';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentLime => 'Citron vert';

  @override
  String get accentAmber => 'Ambre';

  @override
  String get accentRose => 'Rose clair';

  @override
  String get accentIceBlue => 'Bleu glacier';

  @override
  String get accentSelected => 'Couleur d\'accentuation choisie';

  @override
  String get cardStyleDefault => 'Par défaut';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Lueur';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Classique';

  @override
  String get cardStyleMinimal => 'Minimal';

  @override
  String get cardStyleCapsule => 'Capsule';

  @override
  String get dockFavoritesDock => 'Dock des favoris';

  @override
  String get dockFavoritesDockDescription => 'Affiche les favoris dans une barre en bas de l\'écran d\'accueil, avec Continuer à regarder au-dessus et vos autres sections en dessous. Ses coins suivent le style des cartes.';

  @override
  String get dockFrosted => 'Dock givré';

  @override
  String get dockDark => 'Dock sombre';

  @override
  String get dockShadow => 'Ombre du dock';

  @override
  String get dockBlurWallpaperBelow => 'Flouter le fond d\'écran sous le dock';

  @override
  String get wallpaperMatchSelectedApp => 'Assortir à l\'application sélectionnée';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Photo du jour Bing';

  @override
  String get wallpaperRefreshNow => 'Actualiser maintenant';

  @override
  String get wallpaperBingError => 'Impossible de joindre Bing. Vérifiez votre connexion réseau.';

  @override
  String get gradientPitchBlack => 'Noir absolu';

  @override
  String get gradientGreatWhale => 'Grande baleine';

  @override
  String get gradientViciousStance => 'Posture féroce';

  @override
  String get gradientTeenNotebook => 'Cahier d\'ado';

  @override
  String get gradientOldHat => 'Vieux chapeau';

  @override
  String get gradientBurningSpring => 'Printemps brûlant';

  @override
  String get gradientDesertHump => 'Dune du désert';

  @override
  String get gradientFarawayRiver => 'Rivière lointaine';

  @override
  String get gradientSaintPetersburg => 'Saint-Pétersbourg';

  @override
  String get gradientAfricanField => 'Champ africain';

  @override
  String get gradientGrassShampoo => 'Shampooing d\'herbe';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Unité de température : $unit';
  }

  @override
  String get weatherLocationNotSet => 'Lieu météo : non défini';

  @override
  String weatherLocationValue(String place) {
    return 'Lieu météo : $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Impossible de charger la météo. Nouvelle tentative automatique.';

  @override
  String get statusBarWeatherSourceHint => 'Choisissez un lieu météo ci-dessus (météo d\'Open-Meteo, gratuite, sans compte). Sans lieu, la météo vient de l\'application Breezy Weather si elle est installée avec le partage Gadgetbridge activé.';

  @override
  String get weatherLocationTitle => 'Lieu météo';

  @override
  String get weatherLocationHint => 'Ville ou commune';

  @override
  String get weatherLocationNoResults => 'Aucun lieu trouvé';

  @override
  String get weatherLocationSearchError => 'Impossible de joindre le service météo. Vérifiez la connexion réseau.';

  @override
  String get weatherLocationPrivacyNote => 'Météo par Open-Meteo.com : gratuite, sans compte. Seules les coordonnées du lieu choisi sont envoyées.';

  @override
  String get weatherLocationSearch => 'Rechercher';

  @override
  String get dateTimeInvalidFormat => 'Format non valide';

  @override
  String get dateTimeSelectFormats => 'Choisissez les formats ci-dessous';

  @override
  String get dataUsageDaily => 'Quotidien';

  @override
  String get dataUsageWeekly => 'Hebdomadaire';

  @override
  String get dataUsageMonthly => 'Mensuel';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Bloquées dans Continuer à regarder ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Bloquée dans Continuer à regarder';

  @override
  String get cwAppsUnblock => 'Débloquer';

  @override
  String get cwAppsUnblockAllApps => 'Débloquer toutes les applications';

  @override
  String get cwAppsNoBlockedApps => 'Aucune application bloquée';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Toutes les applications compatibles peuvent afficher des éléments dans Continuer à regarder.';

  @override
  String get cwAppsWithContinueWatching => 'Applications avec Continuer à regarder';

  @override
  String get cwAppsWithContinueWatchingHint => 'Applications qui fournissent actuellement des éléments Watch Next sur votre écran d\'accueil';

  @override
  String get cwAppsNoActiveApps => 'Aucune application ne fournit actuellement d\'éléments Continuer à regarder.\nQuand des applications compatibles (comme SmartTube ou des services de streaming) en ajoutent, ils apparaîtront ici.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments actifs',
      one: '$count élément actif',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Toutes les applications installées';

  @override
  String get cwAppsAllInstalledAppsHint => 'Désactivez pour empêcher une application d\'ajouter des éléments à Continuer à regarder';

  @override
  String get cwAppsBlocked => 'Bloquée';

  @override
  String get cwAppsAllowed => 'Autorisée';

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
  String get cwCardSizeExtraSmall => 'Extra petit';

  @override
  String get cwCardSizeVerySmall => 'Très petit';

  @override
  String get cwCardSizeSmall => 'Petit';

  @override
  String get cwCardSizeCompact => 'Compact';

  @override
  String get cwCardSizeMediumSmall => 'Moyen-petit';

  @override
  String get cwCardSizeMedium => 'Moyen';

  @override
  String get cwCardSizeStandardDefault => 'Standard (par défaut)';

  @override
  String get cwCardSizeStandard => 'Standard';

  @override
  String get cwCardSizeMediumLarge => 'Moyen-grand';

  @override
  String get cwCardSizeLarge => 'Grand';

  @override
  String get cwCardSizeVeryLarge => 'Très grand';

  @override
  String get cwCardSizeExtraLarge => 'Extra grand';

  @override
  String get cwCardSizeHuge => 'Énorme';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '$count élément',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Afficher jusqu\'à $count éléments récents',
      one: 'Afficher jusqu\'à $count élément récent',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Par défaut';
  }

  @override
  String get cwUnlimited => 'Illimité';

  @override
  String get cwMaxItemsAll => 'Afficher tous les éléments disponibles';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '$count élément',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Barre de progression de lecture';

  @override
  String get cwPlaybackPercentage => 'Pourcentage de lecture';

  @override
  String get cwEpisodeDetails => 'Détails de l\'épisode et de la vidéo';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bloquées',
      one: '$count bloquée',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Gérer';

  @override
  String get cwRestoreHiddenPrograms => 'Restaurer les programmes masqués';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count masqués',
      one: '$count masqué',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'Tous les programmes masqués ont été restaurés';

  @override
  String get cwWatchNextAdbTitle => 'Accès à Watch Next (ADB requis)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV exige l\'autorisation READ_WRITE_WATCH_NEXT_PROGRAMS pour que les lanceurs lisent et affichent les rangées Continuer à regarder des applications installées.\n\nPour l\'accorder, connectez votre téléviseur via ADB et exécutez :';

  @override
  String get appsNoApplicationsFound => 'Aucune application trouvée';

  @override
  String get appDetailsAddToFavorites => 'Ajouter aux favoris';

  @override
  String get appDetailsRemoveFromFavorites => 'Retirer des favoris';

  @override
  String get appDetailsAddToCategory => 'Ajouter à une catégorie';

  @override
  String get sectionsCustomOption => 'Personnalisé...';

  @override
  String get sectionsSelectName => 'Choisissez un nom';

  @override
  String get sectionsCustomName => 'Nom personnalisé';

  @override
  String get sectionsSortLastUsed => 'Dernière utilisation';

  @override
  String get sectionsReorderHint => 'Sélectionnez avec ◄ / ► puis utilisez ▲ / ▼ pour réorganiser';

  @override
  String get inputsNoneDetected => 'Aucune entrée détectée';

  @override
  String get notifClearAll => 'Tout effacer';

  @override
  String get notifAllCaughtUp => 'Tout est à jour !';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Bloquer les notifications ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Ouvrir $app';
  }

  @override
  String get notifAccessAdbTitle => 'Accès aux notifications (ADB requis)';

  @override
  String get notifAccessAdbMessage => 'Android TV ne propose pas d\'écran de paramètres système pour « Accès aux notifications » (lire les notifications des autres applications).\n\nRemarque : activer « Afficher les notifications » dans les paramètres des applications du téléviseur ne contrôle que les notifications envoyées par cette application, pas l\'accès aux notifications.\n\nPour accorder l\'accès aux notifications, connectez votre téléviseur via ADB et exécutez :';

  @override
  String get notifOpenAppInfo => 'Ouvrir les infos de l\'application';

  @override
  String get notifOverlayPermissionTitle => 'Autorisation de superposition';

  @override
  String get notifOverlayAdbMessage => 'Sur cet appareil, l\'écran des paramètres d\'autorisation de superposition n\'a pas pu s\'ouvrir automatiquement.\n\nPour activer les fenêtres superposées, accordez l\'autorisation manuellement via ADB depuis un ordinateur connecté au téléviseur :';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Applications bloquées ($count)';
  }
}
