import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get aboutFlauncher => 'Acerca de Hearth';

  @override
  String get addSection => 'Agregar sección';

  @override
  String get alphabetical => 'Alfabético';

  @override
  String get appCardHighlightAnimation => 'Resaltar aplicaciones';

  @override
  String get appInfo => 'Datos de la aplicación';

  @override
  String get appKeyClick => 'Sonido al presionar una tecla';

  @override
  String get applications => 'Aplicaciones';

  @override
  String get autoHideAppBar => 'Ocultar barra de estado automáticamente';

  @override
  String get backButtonAction => 'Acción del botón \'Atrás\'';

  @override
  String get category => 'Categoría';

  @override
  String get columnCount => 'Cantidad de columnas';

  @override
  String get date => 'Fecha';

  @override
  String get dateAndTimeFormat => 'Formato de fecha y hora';

  @override
  String get delete => 'Eliminar';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Nada';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Mostrar salvapantallas';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Mostrar reloj';

  @override
  String get dialogTextNoFileExplorer => 'Por favor, instale un gestor de archivos para seleccionar una imagen.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Categoría)';
  }

  @override
  String get gradient => 'Gradiente';

  @override
  String get favoriteApps => 'Apps Favoritas';

  @override
  String get grid => 'Cuadrícula';

  @override
  String get height => 'Altura';

  @override
  String get hide => 'Ocultar';

  @override
  String get hiddenApplications => 'Aplicaciones ocultas';

  @override
  String get launcherSections => 'Secciones';

  @override
  String get layout => 'Distribución';

  @override
  String get loading => 'Cargando';

  @override
  String get manual => 'Manual';

  @override
  String get modifySection => 'Modificar sección';

  @override
  String get name => 'Nombre';

  @override
  String get newSection => 'Nueva sección';

  @override
  String get nonTvApplications => 'Otras aplicaciones';

  @override
  String get open => 'Abrir';

  @override
  String get picture => 'Imagen';

  @override
  String removeFrom(String name) {
    return 'Eliminar de $name';
  }

  @override
  String get reorder => 'Reordenar';

  @override
  String get row => 'Fila';

  @override
  String get rowHeight => 'Altura de fila';

  @override
  String get save => 'Guardar';

  @override
  String get spacer => 'Espaciador';

  @override
  String get statusBar => 'Barra de estado';

  @override
  String get show => 'Mostrar';

  @override
  String get showCategoryTitles => 'Mostrar títulos de categorías';

  @override
  String get showCategoryAppCount => 'Mostrar recuento de aplicaciones en categorías';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Ocultar el contorno de resaltado en la pantalla de inicio';

  @override
  String get appSelectorTransitionAnimation => 'Animación de transición del selector de aplicaciones';

  @override
  String get sort => 'Orden';

  @override
  String get systemSettings => 'Ajustes de Google TV';

  @override
  String get textEmptyCategory => 'Esta categoría está vacía.';

  @override
  String get time => 'Hora';

  @override
  String get tvApplications => 'Aplicaciones del televisor';

  @override
  String get type => 'Tipo';

  @override
  String get uninstall => 'Desinstalar';

  @override
  String get wallpaper => 'Fondo de pantalla';

  @override
  String get withEllipsisAddTo => 'Añadir a...';

  @override
  String get timeBasedWallpaper => 'Fondo de pantalla según hora';

  @override
  String get pickDayWallpaper => 'Elegir fondo de pantalla diurno';

  @override
  String get pickNightWallpaper => 'Elegir fondo de pantalla nocturno';

  @override
  String get inputs => 'Entradas';

  @override
  String get inputSources => 'Fuentes de Entrada';

  @override
  String get backupAndRestore => 'Copia de seguridad y restauración';

  @override
  String get exportBackup => 'Exportar copia de seguridad';

  @override
  String get importBackup => 'Importar copia de seguridad';

  @override
  String exportSuccess(String path) {
    return 'Copia de seguridad exportada con éxito a $path';
  }

  @override
  String get importSuccess => 'Copia de seguridad importada con éxito';

  @override
  String get importConfirm => '¿Está seguro de que desea importar la copia de seguridad? Esto sobrescribirá su configuración y diseño actuales.';

  @override
  String importError(String error) {
    return 'Error al importar la copia de seguridad: $error';
  }

  @override
  String exportError(String error) {
    return 'Error al exportar la copia de seguridad: $error';
  }

  @override
  String get shareBackup => 'Compartir copia';

  @override
  String get notificationBell => 'Campana de notificaciones';

  @override
  String get autoHideNotificationBell => 'Ocultar campana de notificaciones automáticamente';

  @override
  String get continueWatching => 'Continuar viendo';

  @override
  String get showContinueWatchingOnHome => 'Mostrar Continuar viendo en Inicio';

  @override
  String get permissionDeniedContinueWatching => 'Se requiere permiso para mostrar Continuar viendo';

  @override
  String get system => 'Sistema';

  @override
  String get accentColor => 'Color de acento';

  @override
  String get dataUsagePeriod => 'Período de uso de datos';

  @override
  String get notificationAccess => 'Acceso a notificaciones';

  @override
  String get watchNextAccess => 'Acceso a Watch Next';

  @override
  String get granted => 'Concedido';

  @override
  String get permissionRequired => 'Permiso requerido';

  @override
  String get systemWidePopupAlert => 'Alerta emergente del sistema';

  @override
  String get overlayPermissionRequired => 'Permiso de superposición requerido';

  @override
  String get enabled => 'Habilitado';

  @override
  String get disabled => 'Deshabilitado';

  @override
  String get showAppNamesBelowIcons => 'Mostrar nombres debajo de los iconos';

  @override
  String get dataUsage => 'Uso de datos';

  @override
  String get networkIndicator => 'Indicador de red';

  @override
  String get startOnBoot => 'Iniciar al encender (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Idioma';

  @override
  String get systemDefault => 'Predeterminado del sistema';

  @override
  String get english => 'Inglés';

  @override
  String get spanish => 'Español';

  @override
  String get ukrainian => 'Ucraniano';

  @override
  String get chinese => 'Chino';

  @override
  String get french => 'Francés';

  @override
  String get german => 'Alemán';

  @override
  String get japanese => 'Japonés';

  @override
  String get portuguese => 'Portugués';

  @override
  String get russian => 'Ruso';

  @override
  String get italian => 'Italiano';

  @override
  String get hindi => 'Hindi';

  @override
  String get korean => 'Coreano';

  @override
  String get arabic => 'Árabe';

  @override
  String get turkish => 'Turco';

  @override
  String get hidePersistentNotifications => 'Ocultar notificaciones persistentes';

  @override
  String get blockedNotificationApps => 'Aplicaciones bloqueadas';

  @override
  String get unblockAppNotifications => 'Desbloquear notificaciones';

  @override
  String get noBlockedApps => 'No hay aplicaciones bloqueadas';

  @override
  String get persistentNotification => 'Persistente';

  @override
  String get unblockAll => 'Desbloquear todo';

  @override
  String get weather => 'Clima';

  @override
  String get showWeatherWarnings => 'Mostrar alertas de lluvia y clima';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Notificaciones';

  @override
  String get continueWatchingDescription => 'Mostrar películas y series vistas recientemente en la pantalla de inicio';

  @override
  String get dismiss => 'Descartar';

  @override
  String get noBlockedAppsDesc => 'Todas las aplicaciones tienen permitido mostrar notificaciones';

  @override
  String get notificationsAllowed => 'Notificaciones permitidas';

  @override
  String get notificationsBlocked => 'Notificaciones bloqueadas';

  @override
  String get dpadDismissHint => 'Izquierda: Descartar • OK: Opciones';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get profilesTitle => 'Perfiles';

  @override
  String get homeScreenTitle => 'Pantalla de inicio';

  @override
  String get remoteAndSearchTitle => 'Mando';

  @override
  String get parentSettingsTitle => 'Ajustes para padres';

  @override
  String get tvPowerTitle => 'TV y energía';

  @override
  String get updatesTitle => 'Actualizaciones';

  @override
  String get familyAppsTitle => 'Hearth en otros perfiles';

  @override
  String get cardStyleTitle => 'Estilo de tarjetas';

  @override
  String get dockLabelsTitle => 'Dock y etiquetas';

  @override
  String get animationsSoundTitle => 'Animaciones y sonido';

  @override
  String get haPanelTitle => 'Panel del dashboard';

  @override
  String get lookTitle => 'Aspecto';

  @override
  String get remoteButtonsTitle => 'Botones del mando';

  @override
  String get profilePairingTitle => 'Vinculación de perfiles';

  @override
  String get haTvStatusTitle => 'Estado de la TV';

  @override
  String get continueWatchingAppsTitle => 'Apps de Continuar viendo';

  @override
  String get cardSizeTitle => 'Tamaño de tarjeta';

  @override
  String get maxItemsTitle => 'Máximo de elementos';

  @override
  String get ok => 'Aceptar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get notNow => 'Ahora no';

  @override
  String get done => 'Listo';

  @override
  String get remove => 'Quitar';

  @override
  String get homeNothingToWatch => 'No hay nada para ver ahora';

  @override
  String get errorScreenTitle => 'Algo salió mal';

  @override
  String get appInfoAddToCategory => 'Añadir a categoría';

  @override
  String get appInfoAddToFavorites => 'Añadir a favoritos';

  @override
  String get appInfoRemoveFromFavorites => 'Quitar de favoritos';

  @override
  String get appInfoSetCustomBanner => 'Establecer banner personalizado';

  @override
  String get appInfoClearCustomBanner => 'Quitar banner personalizado';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'No se pudo establecer el banner: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'No se pudo quitar el banner: $error';
  }

  @override
  String get cwGridAll => 'Todo';

  @override
  String get cwRowSeeAll => 'Ver todo';

  @override
  String cwRowInProgress(int count) {
    return '$count en curso';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Quedan $hours h $minutes min';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Quedan $minutes min';
  }

  @override
  String get watchNextInfoRemove => 'Quitar de Continuar viendo';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Ocultar todo de $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Reproducir / Reanudar';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Abrir $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Datos de la aplicación';

  @override
  String get dataWidgetGrantPermission => 'Conceder permiso de uso';

  @override
  String dataWidgetDaily(String usage) {
    return 'Diario: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Semanal: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Mensual: $usage';
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
        'today': 'Lluvia hoy',
        'tomorrow': 'Lluvia mañana',
        'other': 'Lluvia el $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Nieve hoy',
        'tomorrow': 'Nieve mañana',
        'other': 'Nieve el $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextStorm(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Tormenta hoy',
        'tomorrow': 'Tormenta mañana',
        'other': 'Tormenta el $day',
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
    return 'Ver en $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Alquilar o comprar en $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Más formas de ver (Google TV)';

  @override
  String get searchListening => 'Escuchando…';

  @override
  String get searchHint => 'Buscar películas y series';

  @override
  String get searchEntryHelp => 'Escriba, use el micrófono o escriba en su teléfono con la app Google TV.';

  @override
  String get searchTabWatchNow => 'Ver ahora';

  @override
  String get searchTabRentOrBuy => 'Alquilar o comprar';

  @override
  String get searchTabOtherApps => 'Otras apps';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Alquilar o comprar · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Dónde ver: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'En $services (no en este televisor)';
  }

  @override
  String searchGridResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '$count resultado',
    );
    return '$_temp0';
  }

  @override
  String searchGridNothingHere(String query) {
    return 'No hay nada aquí para «$query».';
  }

  @override
  String get searchGridTmdbNotice => 'Dónde ver, según TMDB (a través de JustWatch). Este producto usa la API de TMDB, pero TMDB no lo respalda ni lo certifica.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps o $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Preguntar a Google: «$query»';
  }

  @override
  String get searchAskGoogleDetail => 'Para preguntas, el clima y todo lo que no sea un programa';

  @override
  String searchSearchingFor(String query) {
    return 'Buscando «$query»…';
  }

  @override
  String get searchFailed => 'No se puede buscar ahora. Compruebe la conexión a internet.';

  @override
  String searchNothingFound(String query) {
    return 'No se encontró nada para «$query»';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Nada de «$query» en sus apps ahora mismo';
  }

  @override
  String get searchSeeMoreResults => 'Vea dónde más está disponible en Más resultados.';

  @override
  String get searchMoreResults => 'Más resultados';

  @override
  String searchTitles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count títulos',
      one: '$count título',
    );
    return '$_temp0';
  }

  @override
  String get searchAskGoogle => 'Preguntar a Google';

  @override
  String searchQuoted(String query) {
    return '«$query»';
  }

  @override
  String get searchKindFilm => 'Película';

  @override
  String get searchKindSeries => 'Serie';

  @override
  String get gradientNamePitchBlack => 'Negro azabache';

  @override
  String get gradientNameGreatWhale => 'Gran ballena';

  @override
  String get gradientNameViciousStance => 'Postura feroz';

  @override
  String get gradientNameTeenNotebook => 'Cuaderno adolescente';

  @override
  String get gradientNameOldHat => 'Sombrero viejo';

  @override
  String get gradientNameBurningSpring => 'Primavera ardiente';

  @override
  String get gradientNameDesertHump => 'Duna del desierto';

  @override
  String get gradientNameFarawayRiver => 'Río lejano';

  @override
  String get gradientNameSaintPetersburg => 'San Petersburgo';

  @override
  String get gradientNameAfricanField => 'Campo africano';

  @override
  String get gradientNameGrassShampoo => 'Champú de hierba';

  @override
  String get updateErrorNoApk => 'Ninguna versión tiene un APK para este dispositivo';

  @override
  String get updateErrorCheckFailed => 'No se pudieron buscar actualizaciones';

  @override
  String get updateErrorDownloadFailed => 'No se pudo descargar la actualización';

  @override
  String get serviceHearthTubeDescription => 'YouTube para Hearth; sigue su perfil de Hearth';

  @override
  String get haSummaryOn => 'Activado';

  @override
  String get haSummaryOff => 'Desactivado';

  @override
  String get haSummaryReporting => 'Informando';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Active la Corrección del botón Inicio ($path); es la que muestra los avisos.';
  }

  @override
  String get haNotificationsShow => 'Mostrar notificaciones de Home Assistant';

  @override
  String get haNotificationsSendTest => 'Enviar una notificación de prueba';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'En Home Assistant, añada la integración \"Notifications for Android TV / Fire TV\" con el host $host. Después envíele notificaciones desde automatizaciones, por ejemplo para el timbre o cuando termine la colada.\n\nSolo los dispositivos de su red doméstica pueden enviarlas (puerto 7676). Los avisos aparecen sobre cualquier aplicación y necesitan la Corrección del botón Inicio ($path) activada.';
  }

  @override
  String get haNotificationsThisTvIp => '(la dirección IP de esta TV)';

  @override
  String get haPanelSaved => 'Guardado';

  @override
  String get haPanelSavedNoToken => 'Guardado. Añada un token de acceso para iniciar sesión.';

  @override
  String get haPanelReceived => 'Se recibieron la dirección y el token desde su teléfono';

  @override
  String get haPanelRightEdge => 'Derecha en el borde derecho abre el panel';

  @override
  String get haSetUpFromPhone => 'Configurar desde el teléfono';

  @override
  String get haPanelTokenLabel => 'Token de acceso de larga duración';

  @override
  String get haPanelTokenSavedHint => 'Guardado (escriba uno nuevo para reemplazarlo)';

  @override
  String get haPanelDashboardLabel => 'Dashboard';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Solo para este perfil. El panel muestra un dashboard de la dirección indicada en $tvStatus, con sesión iniciada mediante el token. Cree el token en Home Assistant con la sesión de un usuario no administrador creado para esta TV (página de perfil, pestaña Seguridad).';
  }

  @override
  String get haStatusReportingOff => 'El envío de estado está desactivado';

  @override
  String get haStatusSaved => 'Guardado: enviando a Home Assistant';

  @override
  String get haStatusAddressLabel => 'Dirección de Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID del webhook';

  @override
  String get haStatusNowPlayingOn => 'Reproduciendo ahora: activado';

  @override
  String get haStatusNowPlayingOff => 'Reproduciendo ahora: active el acceso a notificaciones';

  @override
  String get haStatusHelp => 'La TV envía a Home Assistant lo que hay en pantalla: la aplicación, lo que se reproduce, el perfil de Google TV y el tiempo de pantalla infantil. Solo lo envía a la dirección de arriba, a medida que cambia.';

  @override
  String get haPhoneSetupNoNetwork => 'Esta TV no está en la red doméstica, así que el teléfono no puede conectarse a ella.';

  @override
  String get haPhoneSetupScan => 'Escanee con un teléfono conectado a la misma red Wi-Fi, pegue la dirección de Home Assistant y el token de acceso, y toque Send. La página solo funciona mientras esto esté abierto.';

  @override
  String get profilesSwitchProfile => 'Cambiar de perfil';

  @override
  String get parentPinTitle => 'PIN parental';

  @override
  String get parentPinOn => 'Activado';

  @override
  String get parentPinOff => 'Desactivado';

  @override
  String get parentPinCurrent => 'PIN parental actual';

  @override
  String get parentPinRemove => 'Quitar PIN';

  @override
  String get parentPinChange => 'Cambiar PIN';

  @override
  String get parentPinNew => 'Nuevo PIN parental';

  @override
  String get parentPinNewSubtitle => 'Necesario para cambiar el launcher en los perfiles infantiles de Google TV';

  @override
  String get parentPinConfirm => 'Vuelva a introducir el PIN';

  @override
  String get parentPinAskTitle => 'Pídeselo a un adulto';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'Los ajustes del launcher están bloqueados en los perfiles infantiles. Un adulto puede establecer un PIN en $settings → $profiles → $parentPin desde su propio perfil.';
  }

  @override
  String get parentPinKidsSubtitle => 'Perfil infantil: introduzca el PIN parental para cambiar el launcher';

  @override
  String get parentPinWrong => 'PIN INCORRECTO';

  @override
  String get parentPinEnter => 'INTRODUZCA EL PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Hola, $name';
  }

  @override
  String get profileSwitchSettingUp => 'Configurando este perfil…';

  @override
  String profilesKidsName(String name) {
    return '$name (infantil)';
  }

  @override
  String profilesAdultName(String name) {
    return '$name (adulto)';
  }

  @override
  String get pairingShowPicker => 'Mostrar el selector';

  @override
  String get pairingAlwaysShowPicker => 'Mostrar siempre el selector';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (coincide por nombre)';
  }

  @override
  String get pairingNoMatchYet => 'Aún sin coincidencia: se muestra el selector';

  @override
  String get pairingOffSetUp => 'La vinculación de perfiles está desactivada. Configúrela';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Cuando Hearth abre una de estas aplicaciones, elige el perfil de la aplicación vinculado al perfil de Google TV. Hearth relaciona los nombres por sí mismo (\"$shortName\" va con \"$fullName\"); puede cambiar cualquier vinculación aquí. Sin coincidencia, aparece el selector de la propia aplicación.';
  }

  @override
  String get pairingAppNotInstalled => 'No instalada';

  @override
  String get pairingAppOff => 'Desactivado: aparece el selector de la aplicación';

  @override
  String get pairingAppNotSeen => 'Ábrala una vez desde Hearth para que Hearth conozca sus perfiles';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count perfiles encontrados',
      one: '1 perfil encontrado',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Por nombre ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Por nombre (aún sin coincidencia)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile en $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Vincular perfiles en $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'Hearth aún no ha visto los perfiles de esta aplicación. Ábrala una vez desde Hearth y vuelva.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Perfiles de esta aplicación: $profiles. Los perfiles de Google TV aparecen aquí cuando Hearth los ha visto.';
  }

  @override
  String get familyAppsAddTitle => 'Añadir Hearth a otros perfiles';

  @override
  String get familyAppsAddKids => 'Esto pone Hearth y HearthTube en los perfiles de sus hijos, para que HearthTube funcione allí y Hearth pueda elegir el perfil correcto en los servicios de streaming.';

  @override
  String get familyAppsAddAdults => 'También las instala en los demás perfiles de adultos de la TV, para que otro adulto no tenga que configurarlo por su cuenta.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Solo añade las dos aplicaciones de Hearth, y puede deshacerlo en cualquier momento con Quitar, más abajo.';

  @override
  String get familyAppsAddFamilyLink => 'Cada niño recibe una notificación de Family Link de \"aplicación añadida\".';

  @override
  String get familyAppsAddApproval => 'La primera vez, la TV pregunta \"¿Permitir depuración?\": elija Permitir siempre; eso es lo que permite a Hearth hacer la configuración.';

  @override
  String get familyAppsAdd => 'Añadir';

  @override
  String get familyAppsRemoveTitle => 'Quitar Hearth de otros perfiles';

  @override
  String get familyAppsRemoveBody => 'Esto quita Hearth y HearthTube de sus otros perfiles.';

  @override
  String get familyAppsRemoveFirst => 'Si piensa desinstalar Hearth, haga esto primero; si no, sus copias en los perfiles infantiles pueden quedarse atascadas y necesitar un ordenador para borrarlas.';

  @override
  String get familyAppsUninstallTitle => 'Desinstalar Hearth';

  @override
  String get familyAppsUninstallBody => 'Primero quita Hearth y HearthTube de sus otros perfiles y después desinstala Hearth de este.';

  @override
  String get familyAppsUninstallWhyHere => 'Desinstalar desde aquí, y no desde los ajustes de Android, garantiza que no quede nada en los perfiles infantiles.';

  @override
  String get familyAppsApprovalFirstTitle => 'Primero complete la aprobación única';

  @override
  String get familyAppsApprovalFirstBody => 'Hearth aún no ha podido limpiar los otros perfiles: necesita la aprobación única de \"¿Permitir depuración?\" en la TV.';

  @override
  String get familyAppsApprovalFirstRetry => 'Apruébela y vuelva a intentar Desinstalar, para que no quede nada en los perfiles infantiles.';

  @override
  String get familyAppsAddDone => 'Añadido';

  @override
  String get familyAppsRemoveDone => 'Quitado';

  @override
  String get familyAppsAdded => 'Listo. Hearth y HearthTube ya están en sus otros perfiles; consulte la lista de abajo.';

  @override
  String get familyAppsRemoved => 'Listo. Hearth y HearthTube se han quitado de sus otros perfiles.';

  @override
  String get familyAppsNothingToSetUp => 'Aún no hay otros perfiles que configurar.';

  @override
  String get familyAppsFailedTitle => 'No se pudieron configurar los perfiles';

  @override
  String get familyAppsFailedBody => 'Hearth necesita una aprobación única en la TV antes de poder configurar los otros perfiles.';

  @override
  String get familyAppsFailedRetry => 'En la TV, elija Permitir siempre cuando pregunte \"¿Permitir depuración?\" y vuelva a intentarlo.';

  @override
  String get familyAppsAlsoAdults => 'Configurar también otros perfiles de adultos';

  @override
  String get familyAppsOn => 'Activado';

  @override
  String get familyAppsOff => 'Desactivado';

  @override
  String get familyAppsNoneYet => 'Aún no hay otros perfiles configurados.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: instalada';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: instalada, protegida';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: no instalada';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: no instalada, protegida';
  }

  @override
  String get familyAppsUnnamedKids => 'Un perfil infantil';

  @override
  String get familyAppsUnnamedAdult => 'Un perfil de adulto';

  @override
  String setupAccessibilityInstructions(String service) {
    return 'En la siguiente pantalla, desplácese hasta Servicios, seleccione \"$service\", active Habilitar y confirme. Pulse Atrás hasta volver a la pantalla de inicio.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Si Android dice que el ajuste está restringido, ejecute esto una vez desde un ordenador:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth como aplicación de inicio';

  @override
  String get setupDefaultLauncherWhy => 'Evita que los perfiles infantiles bloqueen Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'En la siguiente pantalla, elija Hearth.';

  @override
  String get setupHomeFixTitle => 'Corrección del botón Inicio';

  @override
  String get setupHomeFixWhy => 'El botón Inicio abre Hearth en lugar de Google TV.';

  @override
  String get setupNotificationsTitle => 'Acceso a notificaciones';

  @override
  String get setupNotificationsWhy => 'Muestra las notificaciones y lo que se está reproduciendo.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'En la siguiente pantalla, seleccione \"$service\" y permítalo.';
  }

  @override
  String get setupInstallTitle => 'Instalar actualizaciones';

  @override
  String get setupInstallWhy => 'Permite que Hearth se actualice y que instale sus aplicaciones complementarias.';

  @override
  String get setupInstallInstructions => 'En la siguiente pantalla, active Hearth.';

  @override
  String get setupPairingWhy => 'Elige su perfil en Netflix, Disney+, Apple TV, HBO Max y Paramount+.';

  @override
  String get setupVoiceTitle => 'Voz de Hearth';

  @override
  String get setupVoiceWhy => 'Permite que la vinculación de perfiles escuche la pantalla de perfiles de Netflix. Las demás aplicaciones mantienen la voz de Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'En la siguiente pantalla, en Motor preferido, elija \"$engine\" y luego Aceptar en la advertencia (Hearth solo escucha las aplicaciones de streaming). Pulse Atrás para volver.';
  }

  @override
  String get setupOpenSettings => 'Abrir ajustes';

  @override
  String get setupAdbFallback => 'Esta TV no ha abierto esa pantalla de ajustes. Ejecute esto una vez desde un ordenador:';

  @override
  String setupProgress(int done, int total) {
    return '$done de $total listos';
  }

  @override
  String get remoteButtonsRemapButton => 'Reasignar un botón';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Botón $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normal';

  @override
  String get remoteButtonsCaptureTitle => 'Pulse un botón del mando';

  @override
  String get remoteButtonsCaptureBody => 'Pulse el botón que quiere reasignar. Pulse Atrás para cancelar.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Primero active la Corrección del botón Inicio';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Para reasignar se necesita la Corrección del botón Inicio ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Ese botón no se puede reasignar';

  @override
  String get remoteButtonsCantRemapBody => 'Las flechas, OK, Atrás, Inicio y el encendido mantienen su función normal.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Pulsar: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Mantener: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Pulsar para buscar en Hearth, mantener para Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Solo en la pantalla de inicio de Hearth: Activado';

  @override
  String get remoteButtonsHomeOnlyOff => 'Solo en la pantalla de inicio de Hearth: Desactivado';

  @override
  String get remoteButtonsRestore => 'Restaurar el botón normal';

  @override
  String get remoteButtonsActionTitle => 'Acción';

  @override
  String get remoteButtonsActionApp => 'Abrir una aplicación…';

  @override
  String get remoteButtonsActionInput => 'Cambiar a una entrada de la TV…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Cambiar de perfil (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Búsqueda de Hearth (voz)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Búsqueda de Hearth (teclado)';

  @override
  String get remoteButtonsActionHome => 'Inicio de Hearth';

  @override
  String get remoteButtonsActionSleep => 'Suspender';

  @override
  String get remoteButtonsActionAndroidSettings => 'Ajustes de Android';

  @override
  String get remoteButtonsPickAppTitle => 'Abrir una aplicación';

  @override
  String get remoteButtonsPickInputTitle => 'Cambiar a una entrada de la TV';

  @override
  String get remoteButtonsHaConnectTitle => 'Primero conecte Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Configure el panel de Home Assistant ($panel > $row) y vuelva a intentarlo.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Escena: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Ejecutar: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Pulsar: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Alternar: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nPulsar: $press  ·  Mantener: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nPulsar: $press  ·  Mantener: $hold  ·  Solo pantalla de inicio';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Necesita la Corrección del botón Inicio ($path). Un botón que solo tiene acción al mantener la hace también al pulsar. La búsqueda de Hearth abre la búsqueda de HearthTube mientras HearthTube está en primer plano. Las reasignaciones se pausan mientras se muestra una pantalla de tiempo de pantalla infantil.';
  }

  @override
  String get tvPowerScreensaver => 'Salvapantallas (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'Hearth usa el salvapantallas de Google TV. Elija allí Google Photos (y qué álbumes) u otra fuente.';

  @override
  String get tvPowerSleepWhenIdle => 'Suspender por inactividad';

  @override
  String get tvPowerSleepOff => 'Desactivado';

  @override
  String tvPowerMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String tvPowerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String tvPowerSleepNote(String path) {
    return 'Reproducir vídeo o música cuenta como actividad. Necesita la Corrección del botón Inicio ($path).';
  }

  @override
  String get accentPurple => 'Morado';

  @override
  String get accentTeal => 'Verde azulado';

  @override
  String get accentBlue => 'Azul';

  @override
  String get accentOrange => 'Naranja';

  @override
  String get accentPink => 'Rosa';

  @override
  String get accentGreen => 'Verde';

  @override
  String get accentWhite => 'Blanco';

  @override
  String get accentYellow => 'Amarillo';

  @override
  String get accentRed => 'Rojo';

  @override
  String get accentCyan => 'Cian';

  @override
  String get accentIndigo => 'Índigo';

  @override
  String get accentLime => 'Lima';

  @override
  String get accentAmber => 'Ámbar';

  @override
  String get accentRose => 'Rosa claro';

  @override
  String get accentIceBlue => 'Azul hielo';

  @override
  String get accentSelected => 'Color de acento elegido';

  @override
  String get cardStyleDefault => 'Predeterminado';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Brillo';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Clásico';

  @override
  String get cardStyleMinimal => 'Minimalista';

  @override
  String get cardStyleCapsule => 'Cápsula';

  @override
  String get dockFavoritesDock => 'Dock de favoritos';

  @override
  String get dockFavoritesDockDescription => 'Muestra Favoritos como una barra en la parte inferior de la pantalla de inicio, con Continuar viendo encima y tus otras secciones debajo. Sus esquinas siguen el estilo de tarjetas.';

  @override
  String get dockFrosted => 'Dock esmerilado';

  @override
  String get dockDark => 'Dock oscuro';

  @override
  String get dockShadow => 'Sombra del dock';

  @override
  String get dockBlurWallpaperBelow => 'Desenfocar el fondo de pantalla bajo el dock';

  @override
  String get wallpaperMatchSelectedApp => 'Igual que la app seleccionada';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Foto del día de Bing';

  @override
  String get wallpaperRefreshNow => 'Actualizar ahora';

  @override
  String get wallpaperBingError => 'No se pudo conectar con Bing. Comprueba tu conexión de red.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Unidad de temperatura: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Ubicación del clima: sin definir';

  @override
  String weatherLocationValue(String place) {
    return 'Ubicación del clima: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'No se pudo cargar el clima. Se volverá a intentar automáticamente.';

  @override
  String get statusBarWeatherSourceHint => 'Elige una ubicación del clima arriba (clima de Open-Meteo, gratis, sin cuenta). Sin ella, el clima viene de la app Breezy Weather si está instalada con el uso compartido de Gadgetbridge activado.';

  @override
  String get weatherLocationTitle => 'Ubicación del clima';

  @override
  String get weatherLocationHint => 'Ciudad o pueblo';

  @override
  String get weatherLocationNoResults => 'No se encontraron lugares';

  @override
  String get weatherLocationSearchError => 'No se pudo conectar con el servicio del clima. Comprueba la conexión de red.';

  @override
  String get weatherLocationPrivacyNote => 'Clima de Open-Meteo.com: gratis, sin cuenta. Solo se envían las coordenadas del lugar elegido.';

  @override
  String get weatherLocationSearch => 'Buscar';

  @override
  String get dateTimeInvalidFormat => 'Formato no válido';

  @override
  String get dateTimeSelectFormats => 'Elige los formatos abajo';

  @override
  String get dataUsageDaily => 'Diario';

  @override
  String get dataUsageWeekly => 'Semanal';

  @override
  String get dataUsageMonthly => 'Mensual';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Bloqueadas en Continuar viendo ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Bloqueada en Continuar viendo';

  @override
  String get cwAppsUnblock => 'Desbloquear';

  @override
  String get cwAppsUnblockAllApps => 'Desbloquear todas las apps';

  @override
  String get cwAppsNoBlockedApps => 'No hay apps bloqueadas';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Todas las apps compatibles pueden mostrar elementos en Continuar viendo.';

  @override
  String get cwAppsWithContinueWatching => 'Apps con Continuar viendo';

  @override
  String get cwAppsWithContinueWatchingHint => 'Apps que ahora ofrecen elementos de Watch Next en tu pantalla de inicio';

  @override
  String get cwAppsNoActiveApps => 'Ninguna app ofrece ahora elementos de Continuar viendo.\nCuando las apps compatibles (como SmartTube o servicios de streaming) añadan elementos, aparecerán aquí.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos activos',
      one: '1 elemento activo',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Todas las apps instaladas';

  @override
  String get cwAppsAllInstalledAppsHint => 'Desactívalo para impedir que una app añada elementos a Continuar viendo';

  @override
  String get cwAppsBlocked => 'Bloqueada';

  @override
  String get cwAppsAllowed => 'Permitida';

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
  String get cwCardSizeExtraSmall => 'Extrapequeño';

  @override
  String get cwCardSizeVerySmall => 'Muy pequeño';

  @override
  String get cwCardSizeSmall => 'Pequeño';

  @override
  String get cwCardSizeCompact => 'Compacto';

  @override
  String get cwCardSizeMediumSmall => 'Mediano pequeño';

  @override
  String get cwCardSizeMedium => 'Mediano';

  @override
  String get cwCardSizeStandardDefault => 'Estándar (predeterminado)';

  @override
  String get cwCardSizeStandard => 'Estándar';

  @override
  String get cwCardSizeMediumLarge => 'Mediano grande';

  @override
  String get cwCardSizeLarge => 'Grande';

  @override
  String get cwCardSizeVeryLarge => 'Muy grande';

  @override
  String get cwCardSizeExtraLarge => 'Extragrande';

  @override
  String get cwCardSizeHuge => 'Enorme';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mostrar hasta $count elementos recientes',
      one: 'Mostrar hasta 1 elemento reciente',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Predeterminado';
  }

  @override
  String get cwUnlimited => 'Ilimitado';

  @override
  String get cwMaxItemsAll => 'Mostrar todos los elementos disponibles';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Barra de progreso de reproducción';

  @override
  String get cwPlaybackPercentage => 'Porcentaje de reproducción';

  @override
  String get cwEpisodeDetails => 'Detalles del episodio y del vídeo';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bloqueadas',
      one: '1 bloqueada',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Gestionar';

  @override
  String get cwRestoreHiddenPrograms => 'Restaurar programas ocultos';

  @override
  String cwHiddenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ocultos',
      one: '1 oculto',
    );
    return '$_temp0';
  }

  @override
  String get cwHiddenProgramsRestored => 'Se restauraron todos los programas ocultos';

  @override
  String get cwWatchNextAdbTitle => 'Acceso a Watch Next (requiere ADB)';

  @override
  String get cwWatchNextAdbMessage => 'Android TV requiere el permiso READ_WRITE_WATCH_NEXT_PROGRAMS para que los launchers lean y muestren las filas de Continuar viendo de las apps instaladas.\n\nPara concederlo, conecta tu TV por ADB y ejecuta:';

  @override
  String get appsNoApplicationsFound => 'No se encontraron aplicaciones';

  @override
  String get appDetailsAddToFavorites => 'Añadir a favoritos';

  @override
  String get appDetailsRemoveFromFavorites => 'Quitar de favoritos';

  @override
  String get appDetailsAddToCategory => 'Añadir a categoría';

  @override
  String get sectionsCustomOption => 'Personalizado...';

  @override
  String get sectionsSelectName => 'Elige un nombre';

  @override
  String get sectionsCustomName => 'Nombre personalizado';

  @override
  String get sectionsSortLastUsed => 'Último uso';

  @override
  String get sectionsReorderHint => 'Selecciona con ◄ / ► y usa ▲ / ▼ para reordenar';

  @override
  String get inputsNoneDetected => 'No se detectaron entradas';

  @override
  String get notifClearAll => 'Borrar todo';

  @override
  String get notifAllCaughtUp => '¡Estás al día!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Bloquear notificaciones ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Abrir $app';
  }

  @override
  String get notifAccessAdbTitle => 'Acceso a notificaciones (requiere ADB)';

  @override
  String get notifAccessAdbMessage => 'Android TV no ofrece una pantalla de ajustes del sistema para «Acceso a notificaciones» (leer las notificaciones de otras apps).\n\nNota: activar «Mostrar notificaciones» en los ajustes de apps del TV solo controla las notificaciones que envía esta app, no el acceso a notificaciones.\n\nPara conceder el acceso a notificaciones, conecta tu TV por ADB y ejecuta:';

  @override
  String get notifOpenAppInfo => 'Abrir datos de la app';

  @override
  String get notifOverlayPermissionTitle => 'Permiso de superposición';

  @override
  String get notifOverlayAdbMessage => 'En este dispositivo no se pudo abrir automáticamente la pantalla de ajustes del permiso de superposición.\n\nPara activar las ventanas emergentes superpuestas, concede el permiso manualmente por ADB desde un ordenador conectado al TV:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Aplicaciones bloqueadas ($count)';
  }

  @override
  String get backupShareText => 'Copia de seguridad de Hearth';

  @override
  String get backupShareFailedTitle => 'Error al compartir';

  @override
  String backupShareFailed(String error) {
    return 'Error al compartir la copia de seguridad: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Exportación correcta';

  @override
  String get backupExportFailedTitle => 'Error de exportación';

  @override
  String get backupImportSuccessTitle => 'Importación correcta';

  @override
  String get backupImportFailedTitle => 'Error de importación';

  @override
  String get backupImport => 'Importar';

  @override
  String backupLoadError(String error) {
    return 'Error al cargar las copias de seguridad: $error';
  }

  @override
  String get backupNoFiles => 'No se encontraron copias de seguridad.';

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
  String get updateCheckForUpdatesTitle => 'Buscar actualizaciones';

  @override
  String updateCurrentVersion(String version) {
    return 'Versión actual: $version';
  }

  @override
  String get updateChecking => 'Buscando una nueva versión en GitHub…';

  @override
  String get updateUpToDate => 'Tienes la versión más reciente.';

  @override
  String updateVersionAvailable(String version) {
    return 'La versión $version está disponible';
  }

  @override
  String updateDownloading(String percent) {
    return 'Descargando… $percent %';
  }

  @override
  String get updateDownloadedHint => 'Descargado. Si el instalador no se abrió, puede que tu dispositivo necesite\nconceder a Hearth el permiso «Instalar apps desconocidas».';

  @override
  String get updateSomethingWentWrong => 'Algo salió mal';

  @override
  String get updateDownloadAndInstall => 'Descargar e instalar';

  @override
  String get updateRetryInstall => 'Reintentar instalación';

  @override
  String get updateCheckAgain => 'Volver a comprobar';

  @override
  String get updatesInstallPermissionTitle => 'Permitir que Hearth instale apps';

  @override
  String get updatesInstallPermissionMessage => 'En la siguiente pantalla, busca Hearth y actívalo; luego pulsa Atrás. La instalación continuará cuando vuelvas aquí.';

  @override
  String get updatesOpenSettings => 'Abrir ajustes';

  @override
  String get updatesCheckFailed => 'No se pudo comprobar';

  @override
  String get updatesInstallerNotStarted => 'El instalador no se inició';

  @override
  String get updatesCheckForUpdates => 'Buscar actualizaciones';

  @override
  String get updatesAutoUpdate => 'Actualizar automáticamente';

  @override
  String get updatesAutoUpdateDescription => 'Hearth busca a diario e instala las actualizaciones de las apps que instaló, cuando no están en uso';

  @override
  String get updatesIncludePrereleases => 'Incluir versiones preliminares';

  @override
  String get updatesIncludePrereleasesDescription => 'Versiones de prueba tempranas de Hearth y HearthTube. Pueden estar sin terminar.';

  @override
  String get updatesFooter => 'Se instalan desde las versiones de GitHub de cada app. Cuando Hearth instala o actualiza una app una vez, sus actualizaciones se instalan sin preguntar y la app deja las actualizaciones en manos de Hearth.';

  @override
  String get updatesChecking => 'Comprobando…';

  @override
  String get updatesInstall => 'Instalar';

  @override
  String updatesUpdateTo(String version) {
    return 'Actualizar a $version';
  }

  @override
  String get updatesUpToDate => 'Actualizado';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Descargando $percent %';
  }

  @override
  String get updatesInstalling => 'Instalando…';

  @override
  String get updatesError => 'Error';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'Basado en $launcher de $author y $original, con partes de $parts';
  }

  @override
  String get aboutDescription => 'Un launcher privado y familiar para Google TV, con perfiles de Google TV y Home Assistant integrados. Sin anuncios ni rastreadores.';

  @override
  String get aboutHearthOnGitHub => 'Hearth en GitHub';

  @override
  String get aboutCredits => 'Créditos';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'Fork de FLauncher · $author';
  }

  @override
  String get aboutLicense => 'Software libre bajo la GNU GPL v3, como los proyectos en los que se basa.';

  @override
  String get familyAppsStatusInstalled => 'Instalado';

  @override
  String get familyAppsStatusPartial => 'Parcial';

  @override
  String get familyAppsStatusNotInstalled => 'No instalado';

  @override
  String get familyAppsStatusAtRisk => 'En riesgo';

  @override
  String get familyAppsAtRiskDetail => 'Google TV quitará de aquí las apps sin proteger la próxima vez que se inicie este perfil. Use Añadir de nuevo para protegerlas.';

  @override
  String get profilePinRow => 'PIN del perfil';

  @override
  String get profilePinNone => 'Ninguno';

  @override
  String get profilePinSaved => 'Guardado';

  @override
  String get profilePinRejected => 'Guardado: no se aceptó la última vez';

  @override
  String get profilePinPaused => 'Guardado: en pausa (la app cambió)';

  @override
  String profilePinUnsupported(String app) {
    return 'Hearth aún no puede escribir PIN en $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'PIN de $profile en $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'Hearth lo escribe detrás de la tarjeta «Iniciando sesión como» cuando $app lo pide. Se queda cifrado en esta TV y nunca se muestra.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Primero configura un PIN parental ($settings → $profiles → $parentPin): hace falta para guardar el PIN de un perfil.';
  }

  @override
  String get profilePinSaveFailed => 'No se pudo guardar el PIN.';

  @override
  String get profileLockNow => 'Bloquear perfil';

  @override
  String get profileLockOnSleep => 'Bloquear cuando la TV se suspende';

  @override
  String get profileLockEveryTime => 'Siempre';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'Tras $minutes min suspendida';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Usa el bloqueo de perfil de Google TV: actívalo para tu cuenta en Ajustes de Google TV → Cuentas e inicio de sesión → tu cuenta → Bloqueo de perfil.';

  @override
  String get aboutWallpaperPhoto => 'FOTO DE FONDO';

  @override
  String get updateErrorWrongApp => 'Esta descarga no es una actualización de este Hearth';

  @override
  String get notifOpen => 'Abrir';

  @override
  String get notifOpenHint => 'OK: Abrir · Izquierda: Descartar · Derecha: Más';

  @override
  String get tvPowerGoogleTvHome => 'Usar la pantalla de inicio de Google TV';

  @override
  String get tvPowerGoogleTvHomeNote => 'Hearth no interviene hasta que desactives esto. El botón de inicio sigue abriendo Hearth.';

  @override
  String get setupFlowFinishLater => 'Terminar más tarde';

  @override
  String get setupFlowStripEssentials => 'Lo esencial';

  @override
  String get setupFlowWelcomeTitle => 'Bienvenido a Hearth';

  @override
  String get setupFlowWelcomeBody => 'Una pantalla de inicio para toda la familia: sus aplicaciones, lo que estaba viendo y el perfil correcto en cada aplicación de streaming.';

  @override
  String get setupFlowWelcomeTime => 'Lleva unos 5 minutos. Puede omitir lo que quiera.';

  @override
  String get setupFlowGetStarted => 'Empezar';

  @override
  String get setupFlowSetUpLater => 'Configurar más tarde';

  @override
  String setupFlowLanguageLink(String language) {
    return 'Idioma: $language';
  }

  @override
  String get setupFlowRestoreLink => 'Restaurar desde una copia de seguridad';

  @override
  String get setupFlowHomeButtonTitle => 'Que el botón de inicio abra Hearth';

  @override
  String get setupFlowHomeButtonBody => 'Google TV reserva el botón de inicio para su propia pantalla. Un interruptor en los ajustes de Android lo arregla y además permite a Hearth:';

  @override
  String get setupFlowHomeButtonPoint1 => 'seguir los cambios de perfil y la hora de dormir de los niños';

  @override
  String get setupFlowHomeButtonPoint2 => 'mostrar avisos emergentes y apagar el televisor cuando no se usa';

  @override
  String get setupFlowOnNextScreen => 'En la siguiente pantalla:';

  @override
  String get setupFlowStepServices => 'Desplácese hasta Servicios';

  @override
  String setupFlowStepSelect(String name) {
    return 'Seleccione \"$name\"';
  }

  @override
  String get setupFlowStepEnable => 'Active Habilitar y luego Aceptar';

  @override
  String get setupFlowComesBack => 'Hearth vuelve solo cuando está activado. Si Google TV pregunta quién está viendo, elíjase a usted.';

  @override
  String get setupFlowOpenAccessibility => 'Abrir Accesibilidad';

  @override
  String get setupFlowHomeButtonDone => 'El botón de inicio ahora abre Hearth';

  @override
  String get setupFlowNotOnYetTitle => 'Aún no está activado';

  @override
  String get setupFlowNotOnYetBody => 'Inténtelo de nuevo, u omítalo y hágalo más tarde en Ajustes.';

  @override
  String get setupFlowStuckTitle => 'Está activado pero no funciona';

  @override
  String get setupFlowStuckBody => 'Android lo muestra activado, pero no está funcionando. Desactívelo y vuelva a activarlo.';

  @override
  String get setupFlowSkipHomeButtonTitle => '¿Omitir el botón de inicio?';

  @override
  String get setupFlowSkipHomeButtonBody => 'Sin él, el botón de inicio abre Google TV y Hearth no puede saber cuándo se usa un perfil infantil.';

  @override
  String get setupFlowSkipAnyway => 'Omitir de todos modos';

  @override
  String get setupFlowSkip => 'Omitir';

  @override
  String get setupFlowNext => 'Siguiente';

  @override
  String get setupFlowLostTitle => 'La actualización desactivó el botón de inicio';

  @override
  String get setupFlowLostBody => 'Android lo desactiva tras algunas actualizaciones. Vuelva a activarlo en un paso.';

  @override
  String get setupFlowBlockedTitle => 'Android bloqueó este interruptor';

  @override
  String get setupFlowBlockedBody => 'Si el interruptor estaba en gris, es porque Hearth se instaló desde un archivo descargado. El televisor no tiene ningún ajuste para permitirlo.';

  @override
  String get setupFlowBlockedComputer => 'Con un ordenador:';

  @override
  String get setupFlowBlockedComputerThen => 'Después active el interruptor. Hearth lo detecta solo.';

  @override
  String get setupFlowBlockedSelfFixBody => 'La depuración está activada, así que Hearth puede arreglarlo solo. El televisor preguntará \"¿Permitir depuración?\": elija Permitir siempre y Hearth desbloqueará su interruptor y lo activará.';

  @override
  String get setupFlowSkipForNow => 'Omitir por ahora';

  @override
  String get setupFlowBlockedSkipLine => 'Las aplicaciones, la búsqueda y Seguir viendo siguen funcionando. El botón de inicio, los perfiles, los avisos y el temporizador de apagado no.';

  @override
  String get setupFlowLetHearthFix => 'Dejar que Hearth lo arregle';

  @override
  String get setupFlowFixConfirmBody => 'Hearth ejecutará esto en el televisor, mediante su propia conexión de depuración:';

  @override
  String get setupFlowFixConfirmApproval => 'La primera vez, el televisor pregunta \"¿Permitir depuración?\". Elija Permitir siempre. Solo cambia los permisos del propio Hearth.';

  @override
  String get setupFlowFixRun => 'Ejecutar';

  @override
  String get setupFlowFixWaiting => 'En curso. Si el televisor pregunta \"¿Permitir depuración?\", elija Permitir siempre.';

  @override
  String get setupFlowFixFailedTitle => 'Hearth no pudo hacerlo';

  @override
  String get setupFlowFixFailedBody => 'Hearth no pudo conectar con la depuración del televisor. Si el televisor preguntó \"¿Permitir depuración?\", elija Permitir siempre e inténtelo de nuevo. La depuración debe seguir activada en Opciones para desarrolladores.';

  @override
  String get setupFlowHomeAppTitle => 'Haga de Hearth su aplicación de inicio';

  @override
  String get setupFlowHomeAppBody => 'Android mostrará una lista de aplicaciones de inicio. Elija Hearth. Así los perfiles infantiles no bloquean Hearth.';

  @override
  String get setupFlowChooseHearth => 'Elegir Hearth';

  @override
  String get setupFlowHomeAppDone => 'Hearth es su aplicación de inicio';

  @override
  String get setupFlowNotChosenTitle => 'Aún no elegida';

  @override
  String get setupFlowFinishTitle => 'Hearth está listo';

  @override
  String setupFlowFinishBody(String where) {
    return 'Lo que haya omitido está en Ajustes, y puede volver a hacer esto desde $where.';
  }

  @override
  String get setupFlowFinishOn => 'Activado';

  @override
  String get setupFlowFinishLaterHeading => 'Para más tarde, en Ajustes';

  @override
  String get setupFlowFinishMore => 'Más en Ajustes: botones del mando, secciones, notificaciones y copia de seguridad.';

  @override
  String get setupFlowGoHome => 'Ir a mi inicio';

  @override
  String get setupHearthTitle => 'Configurar Hearth';

  @override
  String get setupRunAgain => 'Volver a configurar';

  @override
  String get setupCardFamily => 'Su familia';

  @override
  String get setupCardWatching => 'Ver';

  @override
  String setupChipLeft(int count) {
    return 'Terminar la configuración · faltan: $count';
  }

  @override
  String get setupChipFix => 'El botón de inicio necesita un ajuste';

  @override
  String get setupChipHideTitle => '¿Ocultar este recordatorio?';

  @override
  String setupChipHideBody(String where) {
    return 'Puede seguir configurándolo desde $where.';
  }

  @override
  String get setupChipHide => 'Ocultar';

  @override
  String get setupFlowCardIncluded => 'Qué incluye';

  @override
  String get setupFlowCardNeeds => 'Qué necesita';

  @override
  String get setupFlowTurnOn => 'Activar';

  @override
  String get setupFlowNeedsQuestion => 'Una pregunta de Android';

  @override
  String get setupFlowNeedsOneSwitch => 'Un interruptor en los ajustes de Android';

  @override
  String get setupFlowNeedsAboutAMinute => 'Un minuto, más o menos';

  @override
  String get setupFlowWatchingBenefit => 'Sigue donde lo dejaste y mira qué se está reproduciendo.';

  @override
  String get setupFlowWatchingIncluded1 => 'Seguir viendo en la pantalla de inicio';

  @override
  String get setupFlowWatchingIncluded2 => 'Notificaciones y lo que se reproduce';

  @override
  String get setupFlowSearchWorks => 'La búsqueda ya funciona: pulsa Buscar en la pantalla de inicio.';

  @override
  String get setupFlowContinueBody => 'Muestra en la pantalla de inicio lo que estabas viendo en tus apps. Android preguntará una vez; elige Permitir.';

  @override
  String get setupFlowContinueDone => 'Seguir viendo está activado';

  @override
  String get setupFlowContinueDeniedTitle => 'Android no lo permitió';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'Puedes activarlo más tarde en $where.';
  }

  @override
  String get setupFlowNotificationsTitle => 'Lo que se reproduce y notificaciones';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'Mira tus notificaciones y lo que se reproduce. En la siguiente pantalla, selecciona \"$name\" y permítelo.';
  }

  @override
  String get setupFlowNotificationsDone => 'Las notificaciones están activadas';

  @override
  String get setupFlowTvTitle => '¿Apagar la tele cuando nadie la esté viendo?';

  @override
  String get setupFlowTvBody => 'Tras este tiempo sin pulsar el mando. Reproducir vídeo o música cuenta como ver.';

  @override
  String get setupFlowTvNeedsHomeButton => 'Necesita el interruptor del botón de inicio de los primeros pasos: sin él, Hearth no sabe cuándo se usa el mando.';

  @override
  String get setupFlowStartOnBoot => 'Iniciar Hearth al encender la tele';

  @override
  String get setupFlowScreensaver => 'Elegir fotos del salvapantallas';

  @override
  String get setupFlowUpdatesBenefit => 'Hearth se mantiene al día, y también sus apps complementarias.';

  @override
  String get setupFlowUpdatesIncluded1 => 'Hearth se actualiza solo';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, una app de YouTube hecha para Hearth';

  @override
  String get setupFlowInstallTitle => 'Permitir que Hearth instale actualizaciones';

  @override
  String get setupFlowInstallBody => 'En la siguiente pantalla, busca Hearth, actívalo y pulsa Atrás.';

  @override
  String get setupFlowInstallDone => 'Hearth puede instalar actualizaciones';

  @override
  String get setupFlowTubeTitle => '¿Instalar HearthTube?';

  @override
  String get setupFlowTubeBody => 'Una app de YouTube hecha para Hearth: sigue tus perfiles, el estilo del reloj y la hora de dormir de los niños.';

  @override
  String get setupFlowTubeInstalled => 'HearthTube está instalado';

  @override
  String get setupCardHome => 'Tu inicio';

  @override
  String get setupFlowLookTitle => 'Elige un estilo';

  @override
  String setupFlowLookBody(String where) {
    return 'Cada uno se ve detrás de esta tarjeta al moverte a él. Puedes cambiar cualquier parte más tarde en $where.';
  }

  @override
  String get setupFlowLookOtherTitle => 'Elige un estilo para tu inicio';

  @override
  String get setupFlowLookOtherBody => 'Cada perfil tiene su propio inicio. Elige cómo se ve el tuyo.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'Foto del día';

  @override
  String get setupLookCalmDark => 'Oscuro sereno';

  @override
  String get setupLookBold => 'Atrevido';

  @override
  String get setupFlowLookNow => 'Actual';

  @override
  String get setupFlowLookUse => 'Usar este estilo';

  @override
  String get setupFlowLookKeep => 'Mantener el actual';

  @override
  String get setupFlowLookCustomize => 'Personalizar';

  @override
  String get setupFlowWeatherTitle => '¿Mostrar el tiempo?';

  @override
  String get setupFlowWeatherBody => 'Elige tu localidad. Solo se envía su ubicación, a Open-Meteo; sin cuenta.';

  @override
  String get setupFlowWeatherChoose => 'Elegir localidad';

  @override
  String get setupFlowWeatherDone => 'El tiempo aparece en la barra superior';

  @override
  String get setupFlowFamilyBenefit => 'Las apps de streaming se abren con la persona correcta y los niños no pueden cambiar Hearth.';

  @override
  String get setupFlowFamilyIncluded1 => 'Un PIN parental, para que los niños no cambien Hearth';

  @override
  String get setupFlowFamilyIncluded2 => 'El perfil correcto en Netflix, Disney+, Apple TV, Max y Paramount+';

  @override
  String get setupFlowFamilyIncluded3 => 'Hearth se queda en los perfiles de tus hijos';

  @override
  String get setupFlowNeedsPin => 'Cuatro dígitos que tú eliges';

  @override
  String get setupFlowNeedsTwoMinutes => 'Unos 2 minutos';

  @override
  String get setupFlowPinTitle => 'Elige un PIN parental';

  @override
  String get setupFlowPinBody => 'Los niños lo necesitan para cambiar Hearth. Elige cuatro dígitos que un niño no adivine.';

  @override
  String get setupFlowPinChoose => 'Elegir PIN';

  @override
  String get setupFlowPinDone => 'El PIN parental está configurado';

  @override
  String get setupFlowPairingTitle => 'El perfil correcto en las apps de streaming';

  @override
  String setupFlowPairingBody(String name) {
    return 'Hearth elige el perfil de cada persona en Netflix, Disney+, Apple TV, Max y Paramount+. Necesita otro interruptor en la misma pantalla de Android: \"$name\".';
  }

  @override
  String get setupFlowPairingDone => 'El emparejamiento de perfiles está activado';

  @override
  String get setupFlowPairingDoneBody => 'Hearth empareja los nombres solo: \"Alex\" va con \"Alex Morgan\". Los perfiles de cada app aparecen después de que su pantalla \"¿Quién está viendo?\" se haya mostrado una vez.';

  @override
  String get setupFlowCheckPairings => 'Revisar emparejamientos';

  @override
  String get setupFlowVoiceTitle => 'Un paso más para Netflix';

  @override
  String setupFlowVoiceBody(String name) {
    return 'Netflix lee en voz alta su pantalla de perfiles, así que Hearth escucha con su propia voz. En la siguiente pantalla, en Motor preferido, elige \"$name\" y luego Aceptar. Las demás apps mantienen la voz de Google.';
  }

  @override
  String get setupFlowVoiceDone => 'La voz de Hearth está activada';

  @override
  String get setupFlowKidsTitle => 'Mantener Hearth en los perfiles de tus hijos';

  @override
  String get setupFlowKidsBody => 'Google TV quita de los perfiles infantiles, cada vez que se inician, las apps que no instaló. Hearth puede protegerse a sí mismo y a HearthTube allí. Cada niño recibe un aviso de Family Link de \"app añadida\"; puedes deshacerlo cuando quieras en Ajustes.';

  @override
  String get setupFlowKidsApprove => 'La tele preguntará \"¿Permitir depuración?\". Marca Permitir siempre y luego Permitir. Solo se hace una vez.';

  @override
  String get setupFlowKidsAdd => 'Añadir a sus perfiles';

  @override
  String get setupFlowKidsDone => 'Hearth está en los perfiles de tus hijos';

  @override
  String get setupFlowKidsKeepDebugging => 'Deja la depuración activada: Hearth la necesita de nuevo para un perfil infantil nuevo y para quitarse o desinstalarse.';

  @override
  String get setupFlowDebugTitle => 'Activa primero la depuración';

  @override
  String get setupFlowDebugBody => 'Hearth necesita el interruptor de depuración de la tele para configurar los perfiles infantiles. En la siguiente pantalla, selecciona \"Compilación de Android TV OS\" siete veces. Luego, en Ajustes > Sistema > Opciones para desarrolladores, activa Depuración por USB y vuelve. Déjala activada: Hearth la necesita de nuevo para un perfil infantil nuevo.';

  @override
  String get setupFlowDebugOpen => 'Abrir Información';

  @override
  String get setupCardSmartHome => 'Hogar inteligente';

  @override
  String get setupFlowHaBenefit => 'El timbre y otros avisos en la tele, y tu panel de Home Assistant a un clic.';

  @override
  String get setupFlowHaIncluded1 => 'El timbre y otros avisos sobre cualquier app';

  @override
  String get setupFlowHaIncluded2 => 'Tu panel, a un clic';

  @override
  String get setupFlowHaIncluded3 => 'Lo que se ve, enviado a Home Assistant';

  @override
  String get setupFlowNeedsPhone => 'Un móvil en la misma red Wi-Fi';

  @override
  String get setupFlowNeedsFewMinutes => 'Unos minutos';

  @override
  String get setupFlowHaUse => 'Uso Home Assistant';

  @override
  String get setupFlowHaAlertsTitle => 'Avisos de Home Assistant';

  @override
  String setupFlowHaAlertsBody(String ip) {
    return 'En Home Assistant, añade \"Notifications for Android TV / Fire TV\" con la dirección de esta tele: $ip. Luego envía una prueba.';
  }

  @override
  String get setupFlowHaAlertsDone => 'Los avisos están activados';

  @override
  String get setupFlowHaDashboardTitle => 'Tu panel en la tele';

  @override
  String get setupFlowHaDashboardBody => 'Escanea con el móvil, pega la dirección de Home Assistant y un token, y pulsa Enviar. Usa un usuario de Home Assistant creado para la tele, no un administrador.';

  @override
  String get setupFlowHaDashboardDone => 'Tu panel está configurado';

  @override
  String get setupFlowHaStatusTitle => 'Decirle a Home Assistant qué se ve';

  @override
  String get setupFlowHaStatusBody => 'La tele puede enviar a Home Assistant lo que se reproduce y el perfil activo. En la misma página del móvil, añade el ID de una automatización con webhook de Home Assistant.';

  @override
  String get setupFlowHaStatusNoWebhook => 'El móvil no envió un ID de webhook. Rellena la última casilla de la página.';

  @override
  String get setupFlowHaStatusDone => 'La tele le dice a Home Assistant qué se ve';

  @override
  String setupChipNewOne(String feature) {
    return 'Novedad en Hearth: $feature';
  }

  @override
  String setupChipNewMany(int count) {
    return 'Novedades en Hearth · $count';
  }

  @override
  String get setupFlowKidsNotAll => 'Hearth aún no está en todos los perfiles infantiles';

  @override
  String get setupFlowLeaveAsIs => 'Dejarlo como está';

  @override
  String get setupFlowSetUpMissing => 'Configurar lo que falta';

  @override
  String get setupFlowChooseAgain => 'Volver a elegir';

  @override
  String get weatherForecastNextHours => 'Próximas horas';

  @override
  String get weatherForecastNextDays => 'Próximos 5 días';

  @override
  String get weatherForecastShowDays => 'OK: próximos 5 días';

  @override
  String get weatherForecastShowHours => 'OK: próximas horas';

  @override
  String get weatherForecastNow => 'Ahora';

  @override
  String get weatherForecastToday => 'Hoy';

  @override
  String get weatherForecastNone => 'Todavía no hay pronóstico';
}
