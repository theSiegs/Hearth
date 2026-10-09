import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get aboutFlauncher => 'Sobre o Hearth';

  @override
  String get addSection => 'Adicionar seção';

  @override
  String get alphabetical => 'Alfabético';

  @override
  String get appCardHighlightAnimation => 'Animação de destaque do cartão do app';

  @override
  String get appInfo => 'Informações do app';

  @override
  String get appKeyClick => 'Som de clique ao pressionar tecla';

  @override
  String get applications => 'Aplicativos';

  @override
  String get autoHideAppBar => 'Ocultar barra de status automaticamente';

  @override
  String get backButtonAction => 'Ação do botão voltar';

  @override
  String get category => 'Categoria';

  @override
  String get columnCount => 'Contagem de colunas';

  @override
  String get date => 'Data';

  @override
  String get dateAndTimeFormat => 'Formato de data e hora';

  @override
  String get delete => 'Excluir';

  @override
  String get dialogOptionBackButtonActionDoNothing => 'Não fazer nada';

  @override
  String get dialogOptionBackButtonActionShowScreensaver => 'Mostrar protetor de tela';

  @override
  String get dialogOptionBackButtonActionShowClock => 'Mostrar relógio';

  @override
  String get dialogTextNoFileExplorer => 'Por favor, instale um explorador de arquivos para escolher uma imagem.';

  @override
  String disambiguateCategoryTitle(String title) {
    return '$title (Categoria)';
  }

  @override
  String get gradient => 'Gradiente';

  @override
  String get favoriteApps => 'Apps favoritos';

  @override
  String get grid => 'Grade';

  @override
  String get height => 'Altura';

  @override
  String get hide => 'Ocultar';

  @override
  String get hiddenApplications => 'Apps ocultos';

  @override
  String get launcherSections => 'Seções';

  @override
  String get layout => 'Layout';

  @override
  String get loading => 'Carregando';

  @override
  String get manual => 'Manual';

  @override
  String get modifySection => 'Modificar seção';

  @override
  String get name => 'Nome';

  @override
  String get newSection => 'Nova seção';

  @override
  String get nonTvApplications => 'Apps não-TV';

  @override
  String get open => 'Abrir';

  @override
  String get picture => 'Imagem';

  @override
  String removeFrom(String name) {
    return 'Remover de $name';
  }

  @override
  String get reorder => 'Reordenar';

  @override
  String get row => 'Linha';

  @override
  String get rowHeight => 'Altura da linha';

  @override
  String get save => 'Salvar';

  @override
  String get spacer => 'Espaçador';

  @override
  String get statusBar => 'Barra de status';

  @override
  String get show => 'Mostrar';

  @override
  String get showCategoryTitles => 'Mostrar títulos das categorias';

  @override
  String get showCategoryAppCount => 'Mostrar contagem de apps nas categorias';

  @override
  String get hideHighlightOutlineOnHomescreen => 'Ocultar contorno de destaque na tela inicial';

  @override
  String get appSelectorTransitionAnimation => 'Animação de transição do seletor de apps';

  @override
  String get sort => 'Ordenar';

  @override
  String get systemSettings => 'Configurações do sistema';

  @override
  String get textEmptyCategory => 'Esta categoria está vazia.';

  @override
  String get time => 'Hora';

  @override
  String get tvApplications => 'Apps de TV';

  @override
  String get type => 'Tipo';

  @override
  String get uninstall => 'Desinstalar';

  @override
  String get wallpaper => 'Papel de parede';

  @override
  String get withEllipsisAddTo => 'Adicionar a...';

  @override
  String get timeBasedWallpaper => 'Papel de parede baseado no tempo';

  @override
  String get pickDayWallpaper => 'Escolher papel de parede diurno';

  @override
  String get pickNightWallpaper => 'Escolher papel de parede noturno';

  @override
  String get inputs => 'Entradas';

  @override
  String get inputSources => 'Fontes de entrada';

  @override
  String get backupAndRestore => 'Backup e Restauração';

  @override
  String get exportBackup => 'Exportar Backup';

  @override
  String get importBackup => 'Importar Backup';

  @override
  String exportSuccess(String path) {
    return 'Backup exportado com sucesso para $path';
  }

  @override
  String get importSuccess => 'Backup importado com sucesso';

  @override
  String get importConfirm => 'Tem certeza de que deseja importar o backup? Isso substituirá suas configurações e layout atuais.';

  @override
  String importError(String error) {
    return 'Falha ao importar backup: $error';
  }

  @override
  String exportError(String error) {
    return 'Falha ao exportar backup: $error';
  }

  @override
  String get shareBackup => 'Compartilhar Backup';

  @override
  String get notificationBell => 'Sino de Notificação';

  @override
  String get autoHideNotificationBell => 'Ocultar Sino de Notificação automaticamente';

  @override
  String get continueWatching => 'Continuar assistindo';

  @override
  String get showContinueWatchingOnHome => 'Mostrar Continuar assistindo na tela inicial';

  @override
  String get permissionDeniedContinueWatching => 'Permissão necessária para mostrar Continuar assistindo';

  @override
  String get system => 'Sistema';

  @override
  String get accentColor => 'Cor de destaque';

  @override
  String get dataUsagePeriod => 'Período de uso de dados';

  @override
  String get notificationAccess => 'Acesso a notificações';

  @override
  String get watchNextAccess => 'Acesso ao Watch Next';

  @override
  String get granted => 'Concedido';

  @override
  String get permissionRequired => 'Permissão Necessária';

  @override
  String get systemWidePopupAlert => 'Alerta pop-up de todo o sistema';

  @override
  String get overlayPermissionRequired => 'Permissão de sobreposição necessária';

  @override
  String get enabled => 'Ativado';

  @override
  String get disabled => 'Desativado';

  @override
  String get showAppNamesBelowIcons => 'Mostrar nomes dos apps abaixo dos ícones';

  @override
  String get dataUsage => 'Uso de dados';

  @override
  String get networkIndicator => 'Indicador de rede';

  @override
  String get startOnBoot => 'Iniciar ao ligar (Google TV / Fire TV)';

  @override
  String get appLanguage => 'Idioma';

  @override
  String get systemDefault => 'Padrão do sistema';

  @override
  String get english => 'Inglês';

  @override
  String get spanish => 'Espanhol';

  @override
  String get ukrainian => 'Ucraniano';

  @override
  String get chinese => 'Chinês';

  @override
  String get french => 'Francês';

  @override
  String get german => 'Alemão';

  @override
  String get japanese => 'Japonês';

  @override
  String get portuguese => 'Português';

  @override
  String get russian => 'Russo';

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
  String get hidePersistentNotifications => 'Ocultar notificações persistentes';

  @override
  String get blockedNotificationApps => 'Aplicativos bloqueados';

  @override
  String get blockAppNotifications => 'Bloquear notificações';

  @override
  String get unblockAppNotifications => 'Desbloquear notificações';

  @override
  String get noBlockedApps => 'Nenhum aplicativo bloqueado';

  @override
  String get persistentNotification => 'Persistente';

  @override
  String get unblockAll => 'Desbloquear tudo';

  @override
  String get weather => 'Clima';

  @override
  String get showWeatherWarnings => 'Mostrar alertas de chuva e clima';

  @override
  String get temperatureUnit => 'Unidade de temperatura';

  @override
  String get celsius => 'Celsius (°C)';

  @override
  String get fahrenheit => 'Fahrenheit (°F)';

  @override
  String get notifications => 'Notificações';

  @override
  String get continueWatchingDescription => 'Mostrar filmes e programas assistidos recentemente na tela inicial';

  @override
  String get dismiss => 'Descartar';

  @override
  String get openApp => 'Abrir';

  @override
  String get noBlockedAppsDesc => 'Todos os aplicativos estão atualmente autorizados a exibir notificações';

  @override
  String get notificationsAllowed => 'Notificações permitidas';

  @override
  String get notificationsBlocked => 'Notificações bloqueadas';

  @override
  String get dpadDismissHint => 'Esquerda: Descartar • OK: Opções';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get profilesTitle => 'Perfis';

  @override
  String get homeScreenTitle => 'Tela inicial';

  @override
  String get remoteAndSearchTitle => 'Controle remoto e pesquisa';

  @override
  String get parentSettingsTitle => 'Configurações dos pais';

  @override
  String get tvPowerTitle => 'TV e energia';

  @override
  String get setupPermissionsTitle => 'Configuração e permissões';

  @override
  String get updatesTitle => 'Atualizações';

  @override
  String get familyAppsTitle => 'Hearth em outros perfis';

  @override
  String get cardStyleTitle => 'Estilo dos cartões';

  @override
  String get dockLabelsTitle => 'Dock e rótulos';

  @override
  String get animationsSoundTitle => 'Animações e som';

  @override
  String get haPanelTitle => 'Painel do dashboard';

  @override
  String get lookTitle => 'Aparência';

  @override
  String get remoteButtonsTitle => 'Botões do controle remoto';

  @override
  String get profilePairingTitle => 'Pareamento de perfis';

  @override
  String get haTvStatusTitle => 'Status da TV';

  @override
  String get continueWatchingAppsTitle => 'Apps de Continuar assistindo';

  @override
  String get cardSizeTitle => 'Tamanho do cartão';

  @override
  String get maxItemsTitle => 'Máximo de itens';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Fechar';

  @override
  String get tryAgain => 'Tentar novamente';

  @override
  String get notNow => 'Agora não';

  @override
  String get done => 'Concluído';

  @override
  String get remove => 'Remover';

  @override
  String get homeNothingToWatch => 'Nada para assistir agora';

  @override
  String get errorScreenTitle => 'Algo deu errado';

  @override
  String get appInfoAddToCategory => 'Adicionar à categoria';

  @override
  String get appInfoAddToFavorites => 'Adicionar aos favoritos';

  @override
  String get appInfoRemoveFromFavorites => 'Remover dos favoritos';

  @override
  String get appInfoSetCustomBanner => 'Definir banner personalizado';

  @override
  String get appInfoClearCustomBanner => 'Remover banner personalizado';

  @override
  String appInfoSetBannerFailed(String error) {
    return 'Falha ao definir o banner: $error';
  }

  @override
  String appInfoClearBannerFailed(String error) {
    return 'Falha ao remover o banner: $error';
  }

  @override
  String get cwGridAll => 'Tudo';

  @override
  String get cwRowSeeAll => 'Ver tudo';

  @override
  String cwRowInProgress(int count) {
    return '$count em andamento';
  }

  @override
  String cwRowHoursMinutesLeft(int hours, int minutes) {
    return 'Faltam $hours h $minutes min';
  }

  @override
  String cwRowMinutesLeft(int minutes) {
    return 'Faltam $minutes min';
  }

  @override
  String get watchNextInfoRemove => 'Remover de Continuar assistindo';

  @override
  String watchNextInfoHideAllFrom(String appName) {
    return 'Ocultar tudo de $appName';
  }

  @override
  String get watchNextInfoPlayResume => 'Reproduzir / Retomar';

  @override
  String watchNextInfoOpenApp(String appName) {
    return 'Abrir $appName';
  }

  @override
  String get watchNextInfoAppInfo => 'Informações do app';

  @override
  String get dataWidgetGrantPermission => 'Conceder permissão de uso';

  @override
  String dataWidgetDaily(String usage) {
    return 'Diário: $usage';
  }

  @override
  String dataWidgetWeekly(String usage) {
    return 'Semanal: $usage';
  }

  @override
  String dataWidgetMonthly(String usage) {
    return 'Mensal: $usage';
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
        'today': 'Chuva hoje',
        'tomorrow': 'Chuva amanhã',
        'other': 'Chuva $day',
      },
    );
    return '$_temp0';
  }

  @override
  String weatherTextSnow(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(
      when,
      {
        'today': 'Neve hoje',
        'tomorrow': 'Neve amanhã',
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
        'today': 'Tempestade hoje',
        'tomorrow': 'Tempestade amanhã',
        'other': 'Tempestade $day',
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
    return 'Assistir em $apps';
  }

  @override
  String searchRentOrBuyOn(String app) {
    return 'Alugar ou comprar em $app';
  }

  @override
  String get searchMoreWaysToWatch => 'Mais formas de assistir (Google TV)';

  @override
  String get searchListening => 'Ouvindo…';

  @override
  String get searchHint => 'Pesquisar filmes e séries';

  @override
  String get searchEntryHelp => 'Digite, use o microfone ou digite no celular com o app Google TV.';

  @override
  String get searchTabWatchNow => 'Assistir agora';

  @override
  String get searchTabRentOrBuy => 'Alugar ou comprar';

  @override
  String get searchTabOtherApps => 'Outros apps';

  @override
  String searchGridRentOrBuyApps(String apps) {
    return 'Alugar ou comprar · $apps';
  }

  @override
  String get searchGridWhereToWatchGoogleTv => 'Onde assistir: Google TV';

  @override
  String searchGridElsewhere(String services) {
    return 'Em $services (não nesta TV)';
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
    return 'Nada aqui para “$query”.';
  }

  @override
  String get searchGridTmdbNotice => 'Onde assistir, pelo TMDB (via JustWatch). Este produto usa a API do TMDB, mas não é endossado nem certificado pelo TMDB.';

  @override
  String searchAppsOr(String apps, String last) {
    return '$apps ou $last';
  }

  @override
  String get searchListSeparator => ', ';

  @override
  String searchAskGoogleQuery(String query) {
    return 'Perguntar ao Google: “$query”';
  }

  @override
  String get searchAskGoogleDetail => 'Para perguntas, o clima e tudo o que não for um programa';

  @override
  String searchSearchingFor(String query) {
    return 'Pesquisando “$query”…';
  }

  @override
  String get searchFailed => 'Não foi possível pesquisar agora. Verifique a conexão com a internet.';

  @override
  String searchNothingFound(String query) {
    return 'Nada encontrado para “$query”';
  }

  @override
  String searchNothingInYourApps(String query) {
    return 'Nada de “$query” nos seus apps agora';
  }

  @override
  String get searchSeeMoreResults => 'Veja onde mais está disponível em Mais resultados.';

  @override
  String get searchMoreResults => 'Mais resultados';

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
  String get searchAskGoogle => 'Perguntar ao Google';

  @override
  String searchQuoted(String query) {
    return '“$query”';
  }

  @override
  String get searchKindFilm => 'Filme';

  @override
  String get searchKindSeries => 'Série';

  @override
  String get gradientNamePitchBlack => 'Preto absoluto';

  @override
  String get gradientNameGreatWhale => 'Grande baleia';

  @override
  String get gradientNameViciousStance => 'Postura feroz';

  @override
  String get gradientNameTeenNotebook => 'Caderno adolescente';

  @override
  String get gradientNameOldHat => 'Chapéu velho';

  @override
  String get gradientNameBurningSpring => 'Primavera ardente';

  @override
  String get gradientNameDesertHump => 'Duna do deserto';

  @override
  String get gradientNameFarawayRiver => 'Rio distante';

  @override
  String get gradientNameSaintPetersburg => 'São Petersburgo';

  @override
  String get gradientNameAfricanField => 'Campo africano';

  @override
  String get gradientNameGrassShampoo => 'Xampu de grama';

  @override
  String get updateErrorNoApk => 'Nenhuma versão tem um APK para este dispositivo';

  @override
  String get updateErrorCheckFailed => 'Não foi possível verificar atualizações';

  @override
  String get updateErrorDownloadFailed => 'Não foi possível baixar a atualização';

  @override
  String get serviceHearthTubeDescription => 'YouTube para o Hearth; segue seu perfil do Hearth';
}
