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
  String get setupPermissionsTitle => 'Configuración y permisos';

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
  String get setupOptional => 'Opcional';

  @override
  String get homeButtonFixOffTitle => 'La Corrección del botón Inicio está desactivada';

  @override
  String get homeButtonFixOffBody => 'El servicio de accesibilidad de Hearth se ha detenido, normalmente tras una actualización. Hasta que vuelva a activarse, el botón Inicio puede abrir Google TV en lugar de Hearth y no se siguen los cambios de perfil.';

  @override
  String get homeButtonFixStuck => 'Android aún lo muestra como activado, pero no está en ejecución. Desactive y vuelva a activar Hearth en los ajustes de accesibilidad para reiniciarlo.';

  @override
  String get homeButtonFixRestricted => 'Si el interruptor de Hearth aparece en gris, Android lo bloquea porque esta actualización se instaló desde una descarga. Ejecute esto desde un ordenador conectado a la TV y luego active Hearth:';

  @override
  String get homeButtonFixDontRemind => 'No recordármelo';

  @override
  String get homeButtonFixOpenSettings => 'Abrir ajustes de accesibilidad';

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
  String get systemPageUseGoogleTv => 'Usar Google TV por ahora';

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
  String aboutForkOf(String launcher, String author, String parts) {
    return 'Un fork de $launcher de $author, con partes de $parts';
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
  String get profileLockNow => 'Bloquear mi perfil';

  @override
  String get profileLockNowSubtitle => 'Google TV pide el PIN de tu perfil para volver. Mantener pulsado el botón de perfil también lo hace.';

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
}
