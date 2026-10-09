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
  String get systemSettings => 'Ajustes del sistema';

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
  String get blockAppNotifications => 'Bloquear notificaciones';

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
  String get temperatureUnit => 'Unidad de temperatura';

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
  String get openApp => 'Abrir';

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
  String get remoteAndSearchTitle => 'Mando y búsqueda';

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
}
