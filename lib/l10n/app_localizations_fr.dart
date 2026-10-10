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
  String get systemSettings => 'Paramètres Google TV';

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
  String get remoteAndSearchTitle => 'Télécommande';

  @override
  String get parentSettingsTitle => 'Paramètres parentaux';

  @override
  String get tvPowerTitle => 'TV et alimentation';

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
  String get familyAppsAddTitle => 'Ajouter Hearth aux autres profils';

  @override
  String get familyAppsAddKids => 'Cela installe Hearth et HearthTube sur les profils de vos enfants, pour que HearthTube y fonctionne et que Hearth choisisse le bon profil dans les services de streaming.';

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

  @override
  String get backupShareText => 'Sauvegarde Hearth';

  @override
  String get backupShareFailedTitle => 'Échec du partage';

  @override
  String backupShareFailed(String error) {
    return 'Échec du partage de la sauvegarde : $error';
  }

  @override
  String get backupExportSuccessTitle => 'Exportation réussie';

  @override
  String get backupExportFailedTitle => 'Échec de l\'exportation';

  @override
  String get backupImportSuccessTitle => 'Importation réussie';

  @override
  String get backupImportFailedTitle => 'Échec de l\'importation';

  @override
  String get backupImport => 'Importer';

  @override
  String backupLoadError(String error) {
    return 'Erreur lors du chargement des sauvegardes : $error';
  }

  @override
  String get backupNoFiles => 'Aucun fichier de sauvegarde trouvé.';

  @override
  String backupFileDetails(String date, String size) {
    return '$date ($size)';
  }

  @override
  String backupSizeBytes(String size) {
    return '$size o';
  }

  @override
  String backupSizeKilobytes(String size) {
    return '$size Ko';
  }

  @override
  String backupSizeMegabytes(String size) {
    return '$size Mo';
  }

  @override
  String get updateCheckForUpdatesTitle => 'Rechercher des mises à jour';

  @override
  String updateCurrentVersion(String version) {
    return 'Version actuelle : $version';
  }

  @override
  String get updateChecking => 'Recherche d\'une nouvelle version sur GitHub…';

  @override
  String get updateUpToDate => 'Vous avez la dernière version.';

  @override
  String updateVersionAvailable(String version) {
    return 'La version $version est disponible';
  }

  @override
  String updateDownloading(String percent) {
    return 'Téléchargement… $percent %';
  }

  @override
  String get updateDownloadedHint => 'Téléchargé. Si le programme d\'installation ne s\'est pas ouvert, votre appareil doit peut-être\naccorder à Hearth l\'autorisation « Installer des applis inconnues ».';

  @override
  String get updateSomethingWentWrong => 'Une erreur s\'est produite';

  @override
  String get updateDownloadAndInstall => 'Télécharger et installer';

  @override
  String get updateRetryInstall => 'Réessayer l\'installation';

  @override
  String get updateCheckAgain => 'Vérifier à nouveau';

  @override
  String get updatesInstallPermissionTitle => 'Autoriser Hearth à installer des applications';

  @override
  String get updatesInstallPermissionMessage => 'Sur l\'écran suivant, trouvez Hearth et activez-le, puis appuyez sur Retour. L\'installation reprend à votre retour ici.';

  @override
  String get updatesOpenSettings => 'Ouvrir les paramètres';

  @override
  String get updatesCheckFailed => 'Échec de la vérification';

  @override
  String get updatesInstallerNotStarted => 'L\'installateur n\'a pas démarré';

  @override
  String get updatesCheckForUpdates => 'Rechercher des mises à jour';

  @override
  String get updatesAutoUpdate => 'Mettre à jour automatiquement';

  @override
  String get updatesAutoUpdateDescription => 'Hearth vérifie chaque jour et installe les mises à jour des applications qu\'il a installées, quand elles ne sont pas utilisées';

  @override
  String get updatesIncludePrereleases => 'Inclure les préversions';

  @override
  String get updatesIncludePrereleasesDescription => 'Versions de test précoces de Hearth et HearthTube. Elles peuvent être inachevées.';

  @override
  String get updatesFooter => 'Installées depuis les versions GitHub de chaque application. Une fois que Hearth a installé ou mis à jour une application, ses mises à jour s\'installent sans confirmation et l\'application laisse Hearth s\'en charger.';

  @override
  String get updatesChecking => 'Vérification…';

  @override
  String get updatesInstall => 'Installer';

  @override
  String updatesUpdateTo(String version) {
    return 'Mettre à jour vers $version';
  }

  @override
  String get updatesUpToDate => 'À jour';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Téléchargement $percent %';
  }

  @override
  String get updatesInstalling => 'Installation…';

  @override
  String get updatesError => 'Erreur';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'Basé sur $launcher par $author et $original, avec des éléments de $parts';
  }

  @override
  String get aboutDescription => 'Un lanceur privé et familial pour Google TV, avec les profils Google TV et Home Assistant intégrés. Sans publicité ni traceurs.';

  @override
  String get aboutHearthOnGitHub => 'Hearth sur GitHub';

  @override
  String get aboutCredits => 'Crédits';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'Fork de FLauncher · $author';
  }

  @override
  String get aboutLicense => 'Logiciel libre sous GNU GPL v3, comme les projets sur lesquels il s\'appuie.';

  @override
  String get familyAppsStatusInstalled => 'Installé';

  @override
  String get familyAppsStatusPartial => 'Partiel';

  @override
  String get familyAppsStatusNotInstalled => 'Non installé';

  @override
  String get familyAppsStatusAtRisk => 'À risque';

  @override
  String get familyAppsAtRiskDetail => 'Google TV supprimera ici les applis non protégées au prochain démarrage de ce profil. Utilisez à nouveau Ajouter pour les protéger.';

  @override
  String get profilePinRow => 'Code PIN du profil';

  @override
  String get profilePinNone => 'Aucun';

  @override
  String get profilePinSaved => 'Enregistré';

  @override
  String get profilePinRejected => 'Enregistré – refusé la dernière fois';

  @override
  String get profilePinPaused => 'Enregistré – en pause (l’app a changé)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth ne sait pas encore saisir les codes dans $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'Code PIN de $profile dans $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'Hearth le saisit derrière la carte « Connexion en tant que » quand $app le demande. Il reste chiffré sur ce téléviseur et n’est jamais affiché.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Définissez d’abord un code parental ($settings → $profiles → $parentPin) : il est nécessaire pour enregistrer le code d’un profil.';
  }

  @override
  String get profilePinSaveFailed => 'Impossible d’enregistrer le code.';

  @override
  String get profileLockNow => 'Verrouiller le profil';

  @override
  String get profileLockOnSleep => 'Verrouiller quand le téléviseur se met en veille';

  @override
  String get profileLockEveryTime => 'À chaque fois';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'Après $minutes min de veille';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Utilise le verrouillage de profil de Google TV : activez-le pour votre compte dans Paramètres de Google TV → Comptes et connexion → votre compte → Verrouillage du profil.';

  @override
  String get aboutWallpaperPhoto => 'PHOTO DU FOND D\'ÉCRAN';

  @override
  String get updateErrorWrongApp => 'Ce téléchargement n\'est pas une mise à jour de ce Hearth';

  @override
  String get notifOpen => 'Ouvrir';

  @override
  String get notifOpenHint => 'OK : Ouvrir · Gauche : Ignorer · Droite : Plus';

  @override
  String get tvPowerGoogleTvHome => 'Utiliser l\'accueil de Google TV';

  @override
  String get tvPowerGoogleTvHomeNote => 'Hearth reste en retrait jusqu\'à ce que vous désactiviez ceci. Le bouton Accueil ouvre toujours Hearth.';

  @override
  String get setupFlowFinishLater => 'Terminer plus tard';

  @override
  String get setupFlowStripEssentials => 'L\'essentiel';

  @override
  String get setupFlowWelcomeTitle => 'Bienvenue dans Hearth';

  @override
  String get setupFlowWelcomeBody => 'Un écran d\'accueil pour toute la famille : vos applis, ce que vous regardiez, et le bon profil dans chaque appli de streaming.';

  @override
  String get setupFlowWelcomeTime => 'Environ 5 minutes. Tout peut être ignoré.';

  @override
  String get setupFlowGetStarted => 'Commencer';

  @override
  String get setupFlowSetUpLater => 'Configurer plus tard';

  @override
  String setupFlowLanguageLink(String language) {
    return 'Langue : $language';
  }

  @override
  String get setupFlowRestoreLink => 'Restaurer une sauvegarde';

  @override
  String get setupFlowHomeButtonTitle => 'Le bouton Accueil ouvre Hearth';

  @override
  String get setupFlowHomeButtonBody => 'Google TV garde son propre accueil sur le bouton Accueil. Un interrupteur dans les paramètres d\'Android corrige cela, et permet aussi à Hearth de :';

  @override
  String get setupFlowHomeButtonPoint1 => 'suivre les changements de profil et l\'heure du coucher des enfants';

  @override
  String get setupFlowHomeButtonPoint2 => 'afficher des fenêtres et éteindre la TV quand elle n\'est pas utilisée';

  @override
  String get setupFlowOnNextScreen => 'Sur l\'écran suivant :';

  @override
  String get setupFlowStepServices => 'Faites défiler jusqu\'à Services';

  @override
  String setupFlowStepSelect(String name) {
    return 'Sélectionnez « $name »';
  }

  @override
  String get setupFlowStepEnable => 'Activez Activer, puis OK';

  @override
  String get setupFlowComesBack => 'Hearth revient tout seul une fois activé. Si Google TV demande qui regarde, choisissez-vous.';

  @override
  String get setupFlowOpenAccessibility => 'Ouvrir Accessibilité';

  @override
  String get setupFlowHomeButtonDone => 'Le bouton Accueil ouvre maintenant Hearth';

  @override
  String get setupFlowNotOnYetTitle => 'Pas encore activé';

  @override
  String get setupFlowNotOnYetBody => 'Réessayez, ou passez et faites-le plus tard dans les Paramètres.';

  @override
  String get setupFlowStuckTitle => 'Activé mais pas en marche';

  @override
  String get setupFlowStuckBody => 'Android l\'indique comme activé, mais il ne tourne pas. Désactivez-le puis réactivez-le.';

  @override
  String get setupFlowSkipHomeButtonTitle => 'Ignorer le bouton Accueil ?';

  @override
  String get setupFlowSkipHomeButtonBody => 'Sans lui, le bouton Accueil ouvre Google TV, et Hearth ne peut pas savoir quand un profil enfant est utilisé.';

  @override
  String get setupFlowSkipAnyway => 'Ignorer quand même';

  @override
  String get setupFlowSkip => 'Ignorer';

  @override
  String get setupFlowNext => 'Suivant';

  @override
  String get setupFlowLostTitle => 'La mise à jour a désactivé le bouton Accueil';

  @override
  String get setupFlowLostBody => 'Android le désactive après certaines mises à jour. Réactivez-le en une étape.';

  @override
  String get setupFlowBlockedTitle => 'Android a bloqué cet interrupteur';

  @override
  String get setupFlowBlockedBody => 'Si l\'interrupteur était grisé, c\'est parce que Hearth a été installé depuis un fichier téléchargé. La TV n\'a aucun réglage pour l\'autoriser.';

  @override
  String get setupFlowBlockedComputer => 'Avec un ordinateur :';

  @override
  String get setupFlowBlockedComputerThen => 'Activez ensuite l\'interrupteur. Hearth le remarque tout seul.';

  @override
  String get setupFlowBlockedSelfFixBody => 'Le débogage est activé, Hearth peut donc régler cela lui-même. La TV demandera « Autoriser le débogage ? » : choisissez Toujours autoriser, et Hearth débloquera son interrupteur et l\'activera.';

  @override
  String get setupFlowSkipForNow => 'Ignorer pour l\'instant';

  @override
  String get setupFlowBlockedSkipLine => 'Les applis, la recherche et Reprendre la lecture fonctionnent toujours. Le bouton Accueil, les profils, les fenêtres et la mise en veille, non.';

  @override
  String get setupFlowLetHearthFix => 'Laisser Hearth corriger';

  @override
  String get setupFlowFixConfirmBody => 'Hearth va exécuter ceci sur la TV, via sa propre connexion de débogage :';

  @override
  String get setupFlowFixConfirmApproval => 'La première fois, la TV demande « Autoriser le débogage ? ». Choisissez Toujours autoriser. Cela ne change que les autorisations de Hearth.';

  @override
  String get setupFlowFixRun => 'Exécuter';

  @override
  String get setupFlowFixWaiting => 'En cours. Si la TV demande « Autoriser le débogage ? », choisissez Toujours autoriser.';

  @override
  String get setupFlowFixFailedTitle => 'Hearth n\'a pas pu le faire';

  @override
  String get setupFlowFixFailedBody => 'Hearth n\'a pas pu joindre le débogage de la TV. Si la TV a demandé « Autoriser le débogage ? », choisissez Toujours autoriser et réessayez. Le débogage doit rester activé dans les Options pour les développeurs.';

  @override
  String get setupFlowHomeAppTitle => 'Faites de Hearth votre appli d\'accueil';

  @override
  String get setupFlowHomeAppBody => 'Android va afficher une liste d\'applis d\'accueil. Choisissez Hearth. Cela évite que les profils enfants bloquent Hearth.';

  @override
  String get setupFlowChooseHearth => 'Choisir Hearth';

  @override
  String get setupFlowHomeAppDone => 'Hearth est votre appli d\'accueil';

  @override
  String get setupFlowNotChosenTitle => 'Pas encore choisie';

  @override
  String get setupFlowFinishTitle => 'Hearth est prêt';

  @override
  String setupFlowFinishBody(String where) {
    return 'Tout ce que vous avez ignoré se trouve dans les Paramètres, et vous pouvez relancer ceci depuis $where.';
  }

  @override
  String get setupFlowFinishOn => 'Activé';

  @override
  String get setupFlowFinishLaterHeading => 'Plus tard, dans les Paramètres';

  @override
  String get setupFlowFinishMore => 'Plus dans les Paramètres : boutons de la télécommande, sections, notifications et sauvegarde.';

  @override
  String get setupFlowGoHome => 'Aller à mon accueil';

  @override
  String get setupHearthTitle => 'Configurer Hearth';

  @override
  String get setupRunAgain => 'Relancer la configuration';

  @override
  String get setupCardFamily => 'Votre famille';

  @override
  String get setupCardWatching => 'Visionnage';

  @override
  String setupChipLeft(int count) {
    return 'Terminer la configuration · reste : $count';
  }

  @override
  String get setupChipFix => 'Le bouton Accueil est à réparer';

  @override
  String get setupChipHideTitle => 'Masquer ce rappel ?';

  @override
  String setupChipHideBody(String where) {
    return 'Vous pouvez toujours lancer la configuration depuis $where.';
  }

  @override
  String get setupChipHide => 'Masquer';

  @override
  String get setupFlowCardIncluded => 'Ce qui est inclus';

  @override
  String get setupFlowCardNeeds => 'Ce qu\'il faut';

  @override
  String get setupFlowTurnOn => 'Activer';

  @override
  String get setupFlowNeedsQuestion => 'Une question d\'Android';

  @override
  String get setupFlowNeedsOneSwitch => 'Un interrupteur dans les paramètres d\'Android';

  @override
  String get setupFlowNeedsAboutAMinute => 'Environ une minute';

  @override
  String get setupFlowWatchingBenefit => 'Reprenez là où vous en étiez et voyez ce qui est en cours de lecture.';

  @override
  String get setupFlowWatchingIncluded1 => 'Reprendre la lecture sur l\'écran d\'accueil';

  @override
  String get setupFlowWatchingIncluded2 => 'Notifications et lecture en cours';

  @override
  String get setupFlowSearchWorks => 'La recherche fonctionne déjà : appuyez sur Rechercher sur l\'écran d\'accueil.';

  @override
  String get setupFlowContinueBody => 'Affichez sur l\'écran d\'accueil ce que vous regardiez dans vos applis. Android vous le demandera une fois ; choisissez Autoriser.';

  @override
  String get setupFlowContinueDone => 'Reprendre la lecture est activé';

  @override
  String get setupFlowContinueDeniedTitle => 'Android ne l\'a pas autorisé';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'Vous pourrez l\'activer plus tard dans $where.';
  }

  @override
  String get setupFlowNotificationsTitle => 'Lecture en cours et notifications';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'Voyez vos notifications et ce qui est en cours de lecture. Sur l\'écran suivant, sélectionnez « $name » et autorisez-le.';
  }

  @override
  String get setupFlowNotificationsDone => 'Les notifications sont activées';

  @override
  String get setupFlowTvTitle => 'Éteindre la TV quand personne ne regarde ?';

  @override
  String get setupFlowTvBody => 'Après ce délai sans appui sur la télécommande. La lecture de vidéo ou de musique compte comme regarder.';

  @override
  String get setupFlowTvNeedsHomeButton => 'Il faut l\'interrupteur du bouton Accueil des premières étapes : sans lui, Hearth ne sait pas quand la télécommande est utilisée.';

  @override
  String get setupFlowStartOnBoot => 'Lancer Hearth au démarrage de la TV';

  @override
  String get setupFlowScreensaver => 'Choisir les photos de l\'écran de veille';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth se met à jour, ainsi que ses applis compagnons.';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth se met à jour tout seul';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, une appli YouTube conçue pour Hearth';

  @override
  String get setupFlowInstallTitle => 'Autoriser Hearth à installer les mises à jour';

  @override
  String get setupFlowInstallBody => 'Sur l\'écran suivant, trouvez Hearth, activez-le, puis appuyez sur Retour.';

  @override
  String get setupFlowInstallDone => 'Hearth peut installer les mises à jour';

  @override
  String get setupFlowTubeTitle => 'Installer HearthTube ?';

  @override
  String get setupFlowTubeBody => 'Une appli YouTube conçue pour Hearth : elle suit vos profils, le style d\'horloge et l\'heure du coucher des enfants.';

  @override
  String get setupFlowTubeInstalled => 'HearthTube est installé';

  @override
  String get setupCardHome => 'Votre accueil';

  @override
  String get setupFlowLookTitle => 'Choisissez un style';

  @override
  String setupFlowLookBody(String where) {
    return 'Chaque style s\'affiche derrière cette carte quand vous passez dessus. Vous pourrez modifier chaque élément plus tard dans $where.';
  }

  @override
  String get setupFlowLookOtherTitle => 'Choisissez un style pour votre accueil';

  @override
  String get setupFlowLookOtherBody => 'Chaque profil a son propre accueil. Choisissez l\'apparence du vôtre.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'Photo du jour';

  @override
  String get setupLookCalmDark => 'Sombre et sobre';

  @override
  String get setupLookBold => 'Audacieux';

  @override
  String get setupFlowLookNow => 'Actuel';

  @override
  String get setupFlowLookUse => 'Utiliser ce style';

  @override
  String get setupFlowLookKeep => 'Garder l\'actuel';

  @override
  String get setupFlowLookCustomize => 'Personnaliser';

  @override
  String get setupFlowWeatherTitle => 'Afficher la météo ?';

  @override
  String get setupFlowWeatherBody => 'Choisissez votre ville. Seule sa position est envoyée, à Open-Meteo ; aucun compte.';

  @override
  String get setupFlowWeatherChoose => 'Choisir la ville';

  @override
  String get setupFlowWeatherDone => 'La météo s\'affiche dans la barre du haut';

  @override
  String get setupFlowFamilyBenefit => 'Les applis de streaming s\'ouvrent sur la bonne personne, et les enfants ne peuvent pas modifier Hearth.';

  @override
  String get setupFlowFamilyIncluded1 => 'Un code parental, pour que les enfants ne modifient pas Hearth';

  @override
  String get setupFlowFamilyIncluded2 => 'Le bon profil dans Netflix, Disney+, Apple TV, Max et Paramount+';

  @override
  String get setupFlowFamilyIncluded3 => 'Hearth conservé sur les profils de vos enfants';

  @override
  String get setupFlowNeedsPin => 'Quatre chiffres de votre choix';

  @override
  String get setupFlowNeedsTwoMinutes => 'Environ 2 minutes';

  @override
  String get setupFlowPinTitle => 'Choisissez un code parental';

  @override
  String get setupFlowPinBody => 'Les enfants en ont besoin pour modifier Hearth. Choisissez quatre chiffres qu\'un enfant ne devinera pas.';

  @override
  String get setupFlowPinChoose => 'Choisir le code';

  @override
  String get setupFlowPinDone => 'Le code parental est défini';

  @override
  String get setupFlowPairingTitle => 'Le bon profil dans les applis de streaming';

  @override
  String setupFlowPairingBody(String name) {
    return 'Hearth choisit le profil de chacun dans Netflix, Disney+, Apple TV, Max et Paramount+. Il faut un autre interrupteur sur le même écran Android : « $name ».';
  }

  @override
  String get setupFlowPairingDone => 'L\'association des profils est activée';

  @override
  String get setupFlowPairingDoneBody => 'Hearth associe les noms tout seul : « Alex » va avec « Alex Morgan ». Les profils de chaque appli apparaissent après le premier affichage de son écran « Qui regarde ? ».';

  @override
  String get setupFlowCheckPairings => 'Vérifier les associations';

  @override
  String get setupFlowVoiceTitle => 'Une étape de plus pour Netflix';

  @override
  String setupFlowVoiceBody(String name) {
    return 'Netflix lit son écran de profils à voix haute, donc Hearth écoute avec sa propre voix. Sur l\'écran suivant, sous Moteur préféré, choisissez « $name », puis OK. Les autres applis gardent la voix de Google.';
  }

  @override
  String get setupFlowVoiceDone => 'La voix de Hearth est activée';

  @override
  String get setupFlowKidsTitle => 'Garder Hearth sur les profils de vos enfants';

  @override
  String get setupFlowKidsBody => 'Google TV retire des profils enfants, à chaque démarrage, les applis qu\'il n\'a pas installées. Hearth peut s\'y protéger, ainsi que HearthTube. Chaque enfant reçoit une notification Family Link « appli ajoutée » ; annulable à tout moment dans les Paramètres.';

  @override
  String get setupFlowKidsApprove => 'La TV demandera « Autoriser le débogage ? ». Cochez Toujours autoriser, puis Autoriser. À faire une seule fois.';

  @override
  String get setupFlowKidsAdd => 'Ajouter à leurs profils';

  @override
  String get setupFlowKidsDone => 'Hearth est sur les profils de vos enfants';

  @override
  String get setupFlowKidsKeepDebugging => 'Laissez le débogage activé : Hearth en aura besoin pour un nouveau profil enfant, et pour se retirer ou se désinstaller.';

  @override
  String get setupFlowDebugTitle => 'Activez d\'abord le débogage';

  @override
  String get setupFlowDebugBody => 'Hearth a besoin de l\'interrupteur de débogage de la TV pour configurer les profils enfants. Sur l\'écran suivant, sélectionnez sept fois « Build d\'Android TV OS ». Puis dans Paramètres > Système > Options pour les développeurs, activez Débogage USB, et revenez. Laissez-le activé : Hearth en aura besoin pour un nouveau profil enfant.';

  @override
  String get setupFlowDebugOpen => 'Ouvrir À propos';

  @override
  String get setupCardSmartHome => 'Maison connectée';

  @override
  String get setupFlowHaBenefit => 'La sonnette et d\'autres alertes sur la TV, et votre tableau de bord Home Assistant à une touche.';

  @override
  String get setupFlowHaIncluded1 => 'La sonnette et d\'autres alertes par-dessus toute appli';

  @override
  String get setupFlowHaIncluded2 => 'Votre tableau de bord, à une touche';

  @override
  String get setupFlowHaIncluded3 => 'Ce qui passe, envoyé à Home Assistant';

  @override
  String get setupFlowNeedsPhone => 'Un téléphone sur le même Wi-Fi';

  @override
  String get setupFlowNeedsFewMinutes => 'Quelques minutes';

  @override
  String get setupFlowHaUse => 'J\'utilise Home Assistant';

  @override
  String get setupFlowHaAlertsTitle => 'Alertes Home Assistant';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'Dans Home Assistant, ajoutez « Notifications for Android TV / Fire TV » avec l\'adresse de cette TV : $ip. Puis envoyez un test.';
  }

  @override
  String get setupFlowHaAlertsDone => 'Les alertes sont activées';

  @override
  String get setupFlowHaDashboardTitle => 'Votre tableau de bord sur la TV';

  @override
  String get setupFlowHaDashboardBody => 'Scannez avec votre téléphone, collez l\'adresse de Home Assistant et un jeton, puis Envoyer. Utilisez un utilisateur Home Assistant créé pour la TV, pas un administrateur.';

  @override
  String get setupFlowHaDashboardDone => 'Votre tableau de bord est configuré';

  @override
  String get setupFlowHaStatusTitle => 'Dire à Home Assistant ce qui passe';

  @override
  String get setupFlowHaStatusBody => 'La TV peut envoyer à Home Assistant ce qui est en lecture et le profil actif. Sur la même page du téléphone, ajoutez l\'ID d\'une automatisation webhook de Home Assistant.';

  @override
  String get setupFlowHaStatusNoWebhook => 'Le téléphone n\'a pas envoyé d\'ID de webhook. Remplissez la dernière case de la page.';

  @override
  String get setupFlowHaStatusDone => 'La TV dit à Home Assistant ce qui passe';

  @override
  String setupChipNewOne(String feature) {
    return 'Nouveau dans Hearth : $feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'Nouveau dans Hearth · $count';
  }

  @override
  String get setupFlowKidsNotAll => 'Hearth n\'est pas encore sur tous les profils enfants';

  @override
  String get setupFlowLeaveAsIs => 'Laisser tel quel';

  @override
  String get setupFlowSetUpMissing => 'Configurer ce qui manque';

  @override
  String get setupFlowChooseAgain => 'Choisir à nouveau';
}
