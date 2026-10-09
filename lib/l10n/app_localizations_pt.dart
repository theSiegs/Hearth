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

  @override
  String get haSummaryOn => 'Ativado';

  @override
  String get haSummaryOff => 'Desativado';

  @override
  String get haSummaryReporting => 'Enviando';

  @override
  String haNotificationsNeedsFix(String path) {
    return 'Ative a Correção do botão Início ($path); é ela que mostra os pop-ups.';
  }

  @override
  String get haNotificationsShow => 'Mostrar notificações do Home Assistant';

  @override
  String get haNotificationsSendTest => 'Enviar uma notificação de teste';

  @override
  String haNotificationsHelp(String host, String path) {
    return 'No Home Assistant, adicione a integração \"Notifications for Android TV / Fire TV\" com o host $host. Depois envie notificações para ela a partir de automações, por exemplo para a campainha ou quando a roupa terminar de lavar.\n\nSó dispositivos da sua rede doméstica podem enviá-las (porta 7676). Os pop-ups aparecem sobre qualquer aplicativo e precisam da Correção do botão Início ($path) ativada.';
  }

  @override
  String get haNotificationsThisTvIp => '(o endereço IP desta TV)';

  @override
  String get haPanelSaved => 'Salvo';

  @override
  String get haPanelSavedNoToken => 'Salvo. Adicione um token de acesso para entrar.';

  @override
  String get haPanelReceived => 'Endereço e token recebidos do seu telefone';

  @override
  String get haPanelRightEdge => 'Direita na borda direita abre o painel';

  @override
  String get haSetUpFromPhone => 'Configurar pelo telefone';

  @override
  String get haPanelTokenLabel => 'Token de acesso de longa duração';

  @override
  String get haPanelTokenSavedHint => 'Salvo (digite um novo para substituí-lo)';

  @override
  String get haPanelDashboardLabel => 'Dashboard';

  @override
  String haPanelHelp(String tvStatus) {
    return 'Ativado só para este perfil. O painel mostra um dashboard do endereço informado em $tvStatus, conectado com o token. Crie o token no Home Assistant conectado como um usuário não administrador criado para esta TV (página do perfil, aba Segurança).';
  }

  @override
  String get haStatusReportingOff => 'O envio de status está desativado';

  @override
  String get haStatusSaved => 'Salvo: enviando para o Home Assistant';

  @override
  String get haStatusAddressLabel => 'Endereço do Home Assistant';

  @override
  String get haStatusWebhookLabel => 'ID do webhook';

  @override
  String get haStatusNowPlayingOn => 'Reproduzindo agora: ativado';

  @override
  String get haStatusNowPlayingOff => 'Reproduzindo agora: ative o acesso a notificações';

  @override
  String get haStatusHelp => 'A TV informa ao Home Assistant o que está na tela: o aplicativo, o que está tocando, o perfil do Google TV e o tempo de tela infantil. Ela só envia para o endereço acima, conforme as mudanças acontecem.';

  @override
  String get haPhoneSetupNoNetwork => 'Esta TV não está na rede doméstica, então o telefone não consegue acessá-la.';

  @override
  String get haPhoneSetupScan => 'Escaneie com um telefone na mesma rede Wi-Fi, cole o endereço do Home Assistant e o token de acesso e toque em Send. A página só funciona enquanto isto estiver aberto.';

  @override
  String get profilesSwitchProfile => 'Trocar de perfil';

  @override
  String get parentPinTitle => 'PIN dos pais';

  @override
  String get parentPinOn => 'Ativado';

  @override
  String get parentPinOff => 'Desativado';

  @override
  String get parentPinCurrent => 'PIN atual dos pais';

  @override
  String get parentPinRemove => 'Remover PIN';

  @override
  String get parentPinChange => 'Alterar PIN';

  @override
  String get parentPinNew => 'Novo PIN dos pais';

  @override
  String get parentPinNewSubtitle => 'Necessário para alterar o launcher nos perfis infantis do Google TV';

  @override
  String get parentPinConfirm => 'Digite o PIN novamente';

  @override
  String get parentPinAskTitle => 'Peça a um adulto';

  @override
  String parentPinAskBody(String settings, String profiles, String parentPin) {
    return 'As configurações do launcher ficam bloqueadas nos perfis infantis. Um adulto pode definir um PIN em $settings → $profiles → $parentPin no próprio perfil.';
  }

  @override
  String get parentPinKidsSubtitle => 'Perfil infantil: digite o PIN dos pais para alterar o launcher';

  @override
  String get parentPinWrong => 'PIN INCORRETO';

  @override
  String get parentPinEnter => 'DIGITE O PIN';

  @override
  String profileSwitchGreeting(String name) {
    return 'Olá, $name';
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
  String get pairingShowPicker => 'Mostrar o seletor';

  @override
  String get pairingAlwaysShowPicker => 'Sempre mostrar o seletor';

  @override
  String pairingMatchedByName(String profile) {
    return '$profile (correspondência por nome)';
  }

  @override
  String get pairingNoMatchYet => 'Ainda sem correspondência: mostra o seletor';

  @override
  String get pairingOffSetUp => 'O pareamento de perfis está desativado. Configure';

  @override
  String pairingFooter(String shortName, String fullName) {
    return 'Quando o Hearth abre um desses aplicativos, ele escolhe o perfil do aplicativo pareado com o perfil do Google TV. O Hearth associa os nomes sozinho (\"$shortName\" combina com \"$fullName\"); altere qualquer pareamento aqui. Sem correspondência, aparece o seletor do próprio aplicativo.';
  }

  @override
  String get pairingAppNotInstalled => 'Não instalado';

  @override
  String get pairingAppOff => 'Desativado: aparece o seletor do aplicativo';

  @override
  String get pairingAppNotSeen => 'Abra uma vez pelo Hearth para que o Hearth conheça os perfis';

  @override
  String pairingAppProfilesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count perfis encontrados',
      one: '1 perfil encontrado',
    );
    return '$_temp0';
  }

  @override
  String pairingMatchByName(String profile) {
    return 'Associar por nome ($profile)';
  }

  @override
  String get pairingMatchByNameNone => 'Associar por nome (ainda sem correspondência)';

  @override
  String pairingProfileInApp(String profile, String app) {
    return '$profile no $app';
  }

  @override
  String pairingPairIn(String app) {
    return 'Parear perfis no $app';
  }

  @override
  String get pairingAppNotSeenFooter => 'O Hearth ainda não viu os perfis deste aplicativo. Abra uma vez pelo Hearth e depois volte.';

  @override
  String pairingAppProfilesFooter(String profiles) {
    return 'Perfis neste aplicativo: $profiles. Os perfis do Google TV aparecem aqui quando o Hearth os vê.';
  }

  @override
  String get familyAppsIntro => 'Coloque o Hearth e o HearthTube nos seus outros perfis do Google TV. Nos perfis infantis, isso é necessário para o HearthTube funcionar e para o Hearth escolher o perfil certo no Netflix, no Disney+ e em outros aplicativos. Nos perfis de adultos, é só uma comodidade, para não precisar instalá-los manualmente.';

  @override
  String get familyAppsAddTitle => 'Adicionar o Hearth a outros perfis';

  @override
  String get familyAppsAddKids => 'Isso coloca o Hearth e o HearthTube nos perfis dos seus filhos, para o HearthTube funcionar lá e o Hearth escolher o perfil certo em aplicativos como Netflix e Disney+.';

  @override
  String get familyAppsAddAdults => 'Também os instala nos outros perfis de adultos da TV, para que outro adulto não precise configurar sozinho.';

  @override
  String get familyAppsAddOnlyOwnApps => 'Só adiciona os dois aplicativos do próprio Hearth, e você pode desfazer a qualquer momento com Remover, abaixo.';

  @override
  String get familyAppsAddFamilyLink => 'Cada criança recebe uma notificação do Family Link de \"app adicionado\".';

  @override
  String get familyAppsAddApproval => 'Na primeira vez, a TV pergunta \"Permitir depuração?\": escolha Sempre permitir; é isso que permite ao Hearth fazer a configuração.';

  @override
  String get familyAppsAdd => 'Adicionar';

  @override
  String get familyAppsRemoveTitle => 'Remover o Hearth de outros perfis';

  @override
  String get familyAppsRemoveBody => 'Isso remove o Hearth e o HearthTube dos seus outros perfis.';

  @override
  String get familyAppsRemoveFirst => 'Se você pretende desinstalar o próprio Hearth, faça isto antes; caso contrário, as cópias nos perfis infantis podem ficar presas e precisar de um computador para remover.';

  @override
  String get familyAppsUninstallTitle => 'Desinstalar o Hearth';

  @override
  String get familyAppsUninstallBody => 'Primeiro remove o Hearth e o HearthTube dos seus outros perfis e depois desinstala o Hearth deste.';

  @override
  String get familyAppsUninstallWhyHere => 'Desinstalar por aqui, e não pelas configurações do Android, garante que nada fique para trás nos perfis infantis.';

  @override
  String get familyAppsApprovalFirstTitle => 'Primeiro conclua a aprovação única';

  @override
  String get familyAppsApprovalFirstBody => 'O Hearth ainda não conseguiu limpar os outros perfis: ele precisa da aprovação única de \"Permitir depuração?\" na TV.';

  @override
  String get familyAppsApprovalFirstRetry => 'Aprove e tente Desinstalar de novo, para que nada fique nos perfis infantis.';

  @override
  String get familyAppsAddDone => 'Adição concluída';

  @override
  String get familyAppsRemoveDone => 'Remoção concluída';

  @override
  String get familyAppsAdded => 'Pronto. O Hearth e o HearthTube agora estão nos seus outros perfis; veja a lista abaixo.';

  @override
  String get familyAppsRemoved => 'Pronto. O Hearth e o HearthTube foram removidos dos seus outros perfis.';

  @override
  String get familyAppsNothingToSetUp => 'Ainda não há outros perfis para configurar.';

  @override
  String get familyAppsFailedTitle => 'Não foi possível configurar os perfis';

  @override
  String get familyAppsFailedBody => 'O Hearth precisa de uma aprovação única na TV antes de configurar os outros perfis.';

  @override
  String get familyAppsFailedRetry => 'Na TV, escolha Sempre permitir quando ela perguntar \"Permitir depuração?\" e tente de novo.';

  @override
  String get familyAppsAlsoAdults => 'Configurar também outros perfis de adultos';

  @override
  String get familyAppsOn => 'Ativado';

  @override
  String get familyAppsOff => 'Desativado';

  @override
  String get familyAppsNoneYet => 'Nenhum outro perfil configurado ainda.';

  @override
  String familyAppsAppInstalled(String app) {
    return '$app: instalado';
  }

  @override
  String familyAppsAppInstalledKept(String app) {
    return '$app: instalado, protegido';
  }

  @override
  String familyAppsAppNotInstalled(String app) {
    return '$app: não instalado';
  }

  @override
  String familyAppsAppNotInstalledKept(String app) {
    return '$app: não instalado, protegido';
  }

  @override
  String get familyAppsUnnamedKids => 'Um perfil infantil';

  @override
  String get familyAppsUnnamedAdult => 'Um perfil de adulto';
}
