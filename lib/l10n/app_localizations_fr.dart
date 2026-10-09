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
}
