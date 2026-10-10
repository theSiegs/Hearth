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
  String get systemSettings => 'Configurações do Google TV';

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
  String get remoteAndSearchTitle => 'Controle remoto';

  @override
  String get parentSettingsTitle => 'Configurações dos pais';

  @override
  String get tvPowerTitle => 'TV e energia';

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
  String get familyAppsAddTitle => 'Adicionar o Hearth a outros perfis';

  @override
  String get familyAppsAddKids => 'Isso coloca o Hearth e o HearthTube nos perfis dos seus filhos, para que o HearthTube funcione lá e o Hearth possa escolher o perfil certo nos serviços de streaming.';

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

  @override
  String setupAccessibilityInstructions(String service) {
    return 'Na próxima tela, role até Serviços, selecione \"$service\", ative Ativar e confirme. Pressione Voltar até chegar à tela inicial.';
  }

  @override
  String setupRestrictedWarning(String command) {
    return 'Se o Android disser que a configuração está restrita, execute isto uma vez em um computador:\n$command';
  }

  @override
  String get setupDefaultLauncherTitle => 'Hearth como app de início';

  @override
  String get setupDefaultLauncherWhy => 'Impede que os perfis infantis bloqueiem o Hearth.';

  @override
  String get setupDefaultLauncherInstructions => 'Na próxima tela, escolha o Hearth.';

  @override
  String get setupHomeFixTitle => 'Correção do botão Início';

  @override
  String get setupHomeFixWhy => 'O botão Início abre o Hearth em vez do Google TV.';

  @override
  String get setupNotificationsTitle => 'Acesso a notificações';

  @override
  String get setupNotificationsWhy => 'Mostra as notificações e o que está tocando.';

  @override
  String setupNotificationsInstructions(String service) {
    return 'Na próxima tela, selecione \"$service\" e permita.';
  }

  @override
  String get setupInstallTitle => 'Instalar atualizações';

  @override
  String get setupInstallWhy => 'Permite que o Hearth se atualize e instale aplicativos complementares.';

  @override
  String get setupInstallInstructions => 'Na próxima tela, ative o Hearth.';

  @override
  String get setupPairingWhy => 'Escolhe seu perfil no Netflix, Disney+, Apple TV, HBO Max e Paramount+.';

  @override
  String get setupVoiceTitle => 'Voz do Hearth';

  @override
  String get setupVoiceWhy => 'Permite que o pareamento de perfis ouça a tela de perfis do Netflix. Os outros aplicativos continuam com a voz do Google.';

  @override
  String setupVoiceInstructions(String engine) {
    return 'Na próxima tela, em Mecanismo preferencial, escolha \"$engine\" e depois OK no aviso (o Hearth só escuta os aplicativos de streaming). Pressione Voltar para retornar.';
  }

  @override
  String get setupOpenSettings => 'Abrir configurações';

  @override
  String get setupAdbFallback => 'Esta TV não abriu essa tela de configurações. Em vez disso, execute isto uma vez em um computador:';

  @override
  String setupProgress(int done, int total) {
    return '$done de $total concluídos';
  }

  @override
  String get remoteButtonsRemapButton => 'Remapear um botão';

  @override
  String remoteButtonsButtonNumber(String keyCode) {
    return 'Botão $keyCode';
  }

  @override
  String get remoteButtonsNormal => 'Normal';

  @override
  String get remoteButtonsCaptureTitle => 'Pressione um botão do controle';

  @override
  String get remoteButtonsCaptureBody => 'Pressione o botão que quer remapear. Pressione Voltar para cancelar.';

  @override
  String get remoteButtonsNeedsFixTitle => 'Primeiro ative a Correção do botão Início';

  @override
  String remoteButtonsNeedsFixBody(String path) {
    return 'Para remapear é preciso a Correção do botão Início ($path).';
  }

  @override
  String get remoteButtonsCantRemapTitle => 'Não é possível remapear esse botão';

  @override
  String get remoteButtonsCantRemapBody => 'As setas, OK, Voltar, Início e o botão liga/desliga mantêm a função normal.';

  @override
  String remoteButtonsPressOption(String action) {
    return 'Toque: $action';
  }

  @override
  String remoteButtonsHoldOption(String action) {
    return 'Segurar: $action';
  }

  @override
  String get remoteButtonsSearchPreset => 'Toque para a busca do Hearth, segure para o Google';

  @override
  String get remoteButtonsHomeOnlyOn => 'Só na tela inicial do Hearth: Ativado';

  @override
  String get remoteButtonsHomeOnlyOff => 'Só na tela inicial do Hearth: Desativado';

  @override
  String get remoteButtonsRestore => 'Restaurar o botão normal';

  @override
  String get remoteButtonsActionTitle => 'Ação';

  @override
  String get remoteButtonsActionApp => 'Abrir um aplicativo…';

  @override
  String get remoteButtonsActionInput => 'Mudar para uma entrada da TV…';

  @override
  String get remoteButtonsActionSwitchProfile => 'Trocar de perfil (Google TV)';

  @override
  String get remoteButtonsActionSearchVoice => 'Busca do Hearth (voz)';

  @override
  String get remoteButtonsActionSearchKeyboard => 'Busca do Hearth (teclado)';

  @override
  String get remoteButtonsActionHome => 'Início do Hearth';

  @override
  String get remoteButtonsActionSleep => 'Suspender';

  @override
  String get remoteButtonsActionAndroidSettings => 'Configurações do Android';

  @override
  String get remoteButtonsPickAppTitle => 'Abrir um aplicativo';

  @override
  String get remoteButtonsPickInputTitle => 'Mudar para uma entrada da TV';

  @override
  String get remoteButtonsHaConnectTitle => 'Primeiro conecte o Home Assistant';

  @override
  String remoteButtonsHaConnectBody(String panel, String row) {
    return 'Configure o painel do Home Assistant ($panel > $row) e tente de novo.';
  }

  @override
  String remoteButtonsHaScene(String name) {
    return 'Cena: $name';
  }

  @override
  String remoteButtonsHaRun(String name) {
    return 'Executar: $name';
  }

  @override
  String remoteButtonsHaPress(String name) {
    return 'Pressionar: $name';
  }

  @override
  String remoteButtonsHaToggle(String name) {
    return 'Alternar: $name';
  }

  @override
  String remoteButtonsRowSummary(String button, String press, String hold) {
    return '$button\nToque: $press  ·  Segurar: $hold';
  }

  @override
  String remoteButtonsRowSummaryHomeOnly(String button, String press, String hold) {
    return '$button\nToque: $press  ·  Segurar: $hold  ·  Só na tela inicial';
  }

  @override
  String remoteButtonsFooter(String path) {
    return 'Precisa da Correção do botão Início ($path). Um botão que só tem ação ao segurar também a executa com um toque. A busca do Hearth abre a busca do próprio HearthTube enquanto o HearthTube está na frente. Os remapeamentos pausam enquanto uma tela de tempo de tela infantil estiver aparecendo.';
  }

  @override
  String get tvPowerScreensaver => 'Protetor de tela (Google Photos)';

  @override
  String get tvPowerScreensaverNote => 'O Hearth usa o protetor de tela do Google TV. Escolha lá o Google Photos (e quais álbuns) ou outra fonte.';

  @override
  String get tvPowerSleepWhenIdle => 'Suspender quando inativo';

  @override
  String get tvPowerSleepOff => 'Desativado';

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
    return 'Reproduzir vídeo ou música conta como atividade. Precisa da Correção do botão Início ($path).';
  }

  @override
  String get accentPurple => 'Roxo';

  @override
  String get accentTeal => 'Verde-azulado';

  @override
  String get accentBlue => 'Azul';

  @override
  String get accentOrange => 'Laranja';

  @override
  String get accentPink => 'Rosa';

  @override
  String get accentGreen => 'Verde';

  @override
  String get accentWhite => 'Branco';

  @override
  String get accentYellow => 'Amarelo';

  @override
  String get accentRed => 'Vermelho';

  @override
  String get accentCyan => 'Ciano';

  @override
  String get accentIndigo => 'Índigo';

  @override
  String get accentLime => 'Lima';

  @override
  String get accentAmber => 'Âmbar';

  @override
  String get accentRose => 'Rosa-claro';

  @override
  String get accentIceBlue => 'Azul-gelo';

  @override
  String get accentSelected => 'Cor de destaque escolhida';

  @override
  String get cardStyleDefault => 'Padrão';

  @override
  String get cardStylePremium => 'Premium';

  @override
  String get cardStyleGlow => 'Brilho';

  @override
  String get cardStyleSquircle => 'Squircle';

  @override
  String get cardStyleClassic => 'Clássico';

  @override
  String get cardStyleMinimal => 'Minimalista';

  @override
  String get cardStyleCapsule => 'Cápsula';

  @override
  String get dockFavoritesDock => 'Dock de favoritos';

  @override
  String get dockFavoritesDockDescription => 'Mostra os Favoritos como uma barra na parte inferior da tela inicial, com Continuar assistindo acima e suas outras seções abaixo. Os cantos seguem o estilo dos cartões.';

  @override
  String get dockFrosted => 'Dock fosco';

  @override
  String get dockDark => 'Dock escuro';

  @override
  String get dockShadow => 'Sombra do dock';

  @override
  String get dockBlurWallpaperBelow => 'Desfocar o papel de parede sob o dock';

  @override
  String get wallpaperMatchSelectedApp => 'Combinar com o app selecionado';

  @override
  String get wallpaperBingPhotoOfTheDay => 'Foto do dia do Bing';

  @override
  String get wallpaperRefreshNow => 'Atualizar agora';

  @override
  String get wallpaperBingError => 'Não foi possível acessar o Bing. Verifique sua conexão de rede.';

  @override
  String statusBarTemperatureUnitValue(String unit) {
    return 'Unidade de temperatura: $unit';
  }

  @override
  String get weatherLocationNotSet => 'Local do clima: não definido';

  @override
  String weatherLocationValue(String place) {
    return 'Local do clima: $place';
  }

  @override
  String get statusBarWeatherLoadFailed => 'Não foi possível carregar o clima. Uma nova tentativa será feita automaticamente.';

  @override
  String get statusBarWeatherSourceHint => 'Escolha um local do clima acima (clima do Open-Meteo, grátis, sem conta). Sem um local, o clima vem do app Breezy Weather, se estiver instalado com o compartilhamento do Gadgetbridge ativado.';

  @override
  String get weatherLocationTitle => 'Local do clima';

  @override
  String get weatherLocationHint => 'Cidade';

  @override
  String get weatherLocationNoResults => 'Nenhum local encontrado';

  @override
  String get weatherLocationSearchError => 'Não foi possível acessar o serviço de clima. Verifique a conexão de rede.';

  @override
  String get weatherLocationPrivacyNote => 'Clima por Open-Meteo.com: grátis, sem conta. Somente as coordenadas do local escolhido são enviadas.';

  @override
  String get weatherLocationSearch => 'Pesquisar';

  @override
  String get dateTimeInvalidFormat => 'Formato inválido';

  @override
  String get dateTimeSelectFormats => 'Escolha os formatos abaixo';

  @override
  String get dataUsageDaily => 'Diário';

  @override
  String get dataUsageWeekly => 'Semanal';

  @override
  String get dataUsageMonthly => 'Mensal';

  @override
  String cwAppsBlockedHeading(int count) {
    return 'Bloqueados em Continuar assistindo ($count)';
  }

  @override
  String get cwAppsBlockedFromContinueWatching => 'Bloqueado em Continuar assistindo';

  @override
  String get cwAppsUnblock => 'Desbloquear';

  @override
  String get cwAppsUnblockAllApps => 'Desbloquear todos os apps';

  @override
  String get cwAppsNoBlockedApps => 'Nenhum app bloqueado';

  @override
  String get cwAppsNoBlockedAppsMessage => 'Todos os apps compatíveis podem mostrar itens em Continuar assistindo.';

  @override
  String get cwAppsWithContinueWatching => 'Apps com Continuar assistindo';

  @override
  String get cwAppsWithContinueWatchingHint => 'Apps que estão fornecendo itens do Watch Next na sua tela inicial';

  @override
  String get cwAppsNoActiveApps => 'Nenhum app está fornecendo itens de Continuar assistindo no momento.\nQuando apps compatíveis (como SmartTube ou serviços de streaming) adicionarem itens, eles aparecerão aqui.';

  @override
  String cwAppsActiveItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens ativos',
      one: '1 item ativo',
    );
    return '$_temp0';
  }

  @override
  String get cwAppsAllInstalledApps => 'Todos os apps instalados';

  @override
  String get cwAppsAllInstalledAppsHint => 'Desative para impedir que um app adicione itens a Continuar assistindo';

  @override
  String get cwAppsBlocked => 'Bloqueado';

  @override
  String get cwAppsAllowed => 'Permitido';

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
  String get cwCardSizeExtraSmall => 'Extrapequeno';

  @override
  String get cwCardSizeVerySmall => 'Muito pequeno';

  @override
  String get cwCardSizeSmall => 'Pequeno';

  @override
  String get cwCardSizeCompact => 'Compacto';

  @override
  String get cwCardSizeMediumSmall => 'Médio pequeno';

  @override
  String get cwCardSizeMedium => 'Médio';

  @override
  String get cwCardSizeStandardDefault => 'Normal (padrão)';

  @override
  String get cwCardSizeStandard => 'Normal';

  @override
  String get cwCardSizeMediumLarge => 'Médio grande';

  @override
  String get cwCardSizeLarge => 'Grande';

  @override
  String get cwCardSizeVeryLarge => 'Muito grande';

  @override
  String get cwCardSizeExtraLarge => 'Extragrande';

  @override
  String get cwCardSizeHuge => 'Enorme';

  @override
  String cwMaxItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsUpTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mostrar até $count itens recentes',
      one: 'Mostrar até 1 item recente',
    );
    return '$_temp0';
  }

  @override
  String cwMaxItemsDefaultNote(String description) {
    return '$description • Padrão';
  }

  @override
  String get cwUnlimited => 'Ilimitado';

  @override
  String get cwMaxItemsAll => 'Mostrar todos os itens disponíveis';

  @override
  String cwMaxItemsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get cwPlaybackProgressBar => 'Barra de progresso da reprodução';

  @override
  String get cwPlaybackPercentage => 'Porcentagem da reprodução';

  @override
  String get cwEpisodeDetails => 'Detalhes do episódio e do vídeo';

  @override
  String cwBlockedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bloqueados',
      one: '1 bloqueado',
    );
    return '$_temp0';
  }

  @override
  String get cwManage => 'Gerenciar';

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
  String get cwHiddenProgramsRestored => 'Todos os programas ocultos foram restaurados';

  @override
  String get cwWatchNextAdbTitle => 'Acesso ao Watch Next (requer ADB)';

  @override
  String get cwWatchNextAdbMessage => 'O Android TV exige a permissão READ_WRITE_WATCH_NEXT_PROGRAMS para que launchers leiam e exibam as fileiras de Continuar assistindo dos apps instalados.\n\nPara conceder essa permissão, conecte sua TV via ADB e execute:';

  @override
  String get appsNoApplicationsFound => 'Nenhum app encontrado';

  @override
  String get appDetailsAddToFavorites => 'Adicionar aos favoritos';

  @override
  String get appDetailsRemoveFromFavorites => 'Remover dos favoritos';

  @override
  String get appDetailsAddToCategory => 'Adicionar à categoria';

  @override
  String get sectionsCustomOption => 'Personalizado...';

  @override
  String get sectionsSelectName => 'Escolha um nome';

  @override
  String get sectionsCustomName => 'Nome personalizado';

  @override
  String get sectionsSortLastUsed => 'Último uso';

  @override
  String get sectionsReorderHint => 'Selecione com ◄ / ► e use ▲ / ▼ para reordenar';

  @override
  String get inputsNoneDetected => 'Nenhuma entrada detectada';

  @override
  String get notifClearAll => 'Limpar tudo';

  @override
  String get notifAllCaughtUp => 'Tudo em dia!';

  @override
  String notifBlockAppNotifications(String app) {
    return 'Bloquear notificações ($app)';
  }

  @override
  String notifOpenApp(String app) {
    return 'Abrir $app';
  }

  @override
  String get notifAccessAdbTitle => 'Acesso a notificações (requer ADB)';

  @override
  String get notifAccessAdbMessage => 'O Android TV não oferece uma tela de configurações do sistema para \"Acesso a notificações\" (ler notificações de outros apps).\n\nObservação: ativar \"Mostrar notificações\" nas configurações de apps da TV controla apenas as notificações enviadas por este app, não o acesso a notificações.\n\nPara conceder o acesso a notificações, conecte sua TV via ADB e execute:';

  @override
  String get notifOpenAppInfo => 'Abrir informações do app';

  @override
  String get notifOverlayPermissionTitle => 'Permissão de sobreposição';

  @override
  String get notifOverlayAdbMessage => 'Neste dispositivo, não foi possível abrir automaticamente a tela de configurações da permissão de sobreposição.\n\nPara ativar os pop-ups sobrepostos, conceda a permissão manualmente via ADB de um computador conectado à TV:';

  @override
  String blockedNotificationsHeading(int count) {
    return 'Aplicativos bloqueados ($count)';
  }

  @override
  String get systemPageUseGoogleTv => 'Usar o Google TV por enquanto';

  @override
  String get backupShareText => 'Backup do Hearth';

  @override
  String get backupShareFailedTitle => 'Falha ao compartilhar';

  @override
  String backupShareFailed(String error) {
    return 'Falha ao compartilhar backup: $error';
  }

  @override
  String get backupExportSuccessTitle => 'Exportação concluída';

  @override
  String get backupExportFailedTitle => 'Falha na exportação';

  @override
  String get backupImportSuccessTitle => 'Importação concluída';

  @override
  String get backupImportFailedTitle => 'Falha na importação';

  @override
  String get backupImport => 'Importar';

  @override
  String backupLoadError(String error) {
    return 'Erro ao carregar backups: $error';
  }

  @override
  String get backupNoFiles => 'Nenhum arquivo de backup encontrado.';

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
  String get updateCheckForUpdatesTitle => 'Verificar atualizações';

  @override
  String updateCurrentVersion(String version) {
    return 'Versão atual: $version';
  }

  @override
  String get updateChecking => 'Procurando uma nova versão no GitHub…';

  @override
  String get updateUpToDate => 'Você está na versão mais recente.';

  @override
  String updateVersionAvailable(String version) {
    return 'A versão $version está disponível';
  }

  @override
  String updateDownloading(String percent) {
    return 'Baixando… $percent%';
  }

  @override
  String get updateDownloadedHint => 'Baixado. Se o instalador não abriu, talvez seja preciso conceder ao Hearth\na permissão \"Instalar apps desconhecidos\" no seu dispositivo.';

  @override
  String get updateSomethingWentWrong => 'Algo deu errado';

  @override
  String get updateDownloadAndInstall => 'Baixar e instalar';

  @override
  String get updateRetryInstall => 'Tentar instalar novamente';

  @override
  String get updateCheckAgain => 'Verificar novamente';

  @override
  String get updatesInstallPermissionTitle => 'Permitir que o Hearth instale apps';

  @override
  String get updatesInstallPermissionMessage => 'Na próxima tela, encontre o Hearth e ative-o; depois pressione Voltar. A instalação continua quando você voltar aqui.';

  @override
  String get updatesOpenSettings => 'Abrir configurações';

  @override
  String get updatesCheckFailed => 'Falha ao verificar';

  @override
  String get updatesInstallerNotStarted => 'O instalador não foi iniciado';

  @override
  String get updatesCheckForUpdates => 'Verificar atualizações';

  @override
  String get updatesAutoUpdate => 'Atualizar automaticamente';

  @override
  String get updatesAutoUpdateDescription => 'O Hearth verifica diariamente e instala atualizações dos apps que instalou, quando não estão em uso';

  @override
  String get updatesIncludePrereleases => 'Incluir pré-lançamentos';

  @override
  String get updatesIncludePrereleasesDescription => 'Versões de teste iniciais do Hearth e do HearthTube. Podem estar inacabadas.';

  @override
  String get updatesFooter => 'Instalados a partir das versões do GitHub de cada app. Depois que o Hearth instala ou atualiza um app uma vez, as atualizações dele são instaladas sem perguntar e o app deixa as atualizações com o Hearth.';

  @override
  String get updatesChecking => 'Verificando…';

  @override
  String get updatesInstall => 'Instalar';

  @override
  String updatesUpdateTo(String version) {
    return 'Atualizar para $version';
  }

  @override
  String get updatesUpToDate => 'Atualizado';

  @override
  String updatesDownloadingPercent(int percent) {
    return 'Baixando $percent%';
  }

  @override
  String get updatesInstalling => 'Instalando…';

  @override
  String get updatesError => 'Erro';

  @override
  String updatesDescriptionWithVersion(String description, String version) {
    return '$description · $version';
  }

  @override
  String aboutBuiltOn(String launcher, String author, String original, String parts) {
    return 'Baseado no $launcher de $author e no $original, com partes do $parts';
  }

  @override
  String get aboutDescription => 'Um launcher privado e para toda a família para Google TV, com perfis do Google TV e Home Assistant integrados. Sem anúncios e sem rastreadores.';

  @override
  String get aboutHearthOnGitHub => 'Hearth no GitHub';

  @override
  String get aboutCredits => 'Créditos';

  @override
  String aboutFlauncherForkCredit(String author) {
    return 'Fork do FLauncher · $author';
  }

  @override
  String get aboutLicense => 'Software livre sob a GNU GPL v3, como os projetos em que se baseia.';

  @override
  String get familyAppsStatusInstalled => 'Instalado';

  @override
  String get familyAppsStatusPartial => 'Parcial';

  @override
  String get familyAppsStatusNotInstalled => 'Não instalado';

  @override
  String get familyAppsStatusAtRisk => 'Em risco';

  @override
  String get familyAppsAtRiskDetail => 'O Google TV vai remover daqui os apps sem proteção na próxima vez que este perfil for iniciado. Use Adicionar de novo para protegê-los.';

  @override
  String get profilePinRow => 'PIN do perfil';

  @override
  String get profilePinNone => 'Nenhum';

  @override
  String get profilePinSaved => 'Salvo';

  @override
  String get profilePinRejected => 'Salvo — não aceito da última vez';

  @override
  String get profilePinPaused => 'Salvo — pausado (o app mudou)';

  @override
  String profilePinUnsupported(String app) {
    return 'O Hearth ainda não digita PINs no $app';
  }

  @override
  String profilePinEnterTitle(String profile, String app) {
    return 'PIN de $profile no $app';
  }

  @override
  String profilePinEnterSubtitle(String app) {
    return 'O Hearth o digita atrás do cartão “Entrando como” quando o $app pede. Fica criptografado nesta TV e nunca é mostrado.';
  }

  @override
  String profilePinNeedsParentPin(String settings, String profiles, String parentPin) {
    return 'Defina antes um PIN dos pais ($settings → $profiles → $parentPin): ele é necessário para salvar o PIN de um perfil.';
  }

  @override
  String get profilePinSaveFailed => 'Não foi possível salvar o PIN.';

  @override
  String get profileLockNow => 'Bloquear perfil';

  @override
  String get profileLockOnSleep => 'Bloquear quando a TV dormir';

  @override
  String get profileLockEveryTime => 'Sempre';

  @override
  String profileLockAfterMinutes(int minutes) {
    return 'Após $minutes min dormindo';
  }

  @override
  String get profileLockNeedsGoogleLock => 'Usa o bloqueio de perfil do próprio Google TV: ative-o para sua conta em Configurações do Google TV → Contas e login → sua conta → Bloqueio de perfil.';

  @override
  String get aboutWallpaperPhoto => 'FOTO DO PLANO DE FUNDO';

  @override
  String get updateErrorWrongApp => 'Este download não é uma atualização deste Hearth';

  @override
  String get setupFlowFinishLater => 'Terminar depois';

  @override
  String get setupFlowStripEssentials => 'Essenciais';

  @override
  String get setupFlowWelcomeTitle => 'Bem-vindo ao Hearth';

  @override
  String get setupFlowWelcomeBody => 'Uma tela inicial para toda a família: seus apps, o que você estava assistindo e o perfil certo em cada app de streaming.';

  @override
  String get setupFlowWelcomeTime => 'Leva cerca de 5 minutos. Pule o que quiser.';

  @override
  String get setupFlowGetStarted => 'Começar';

  @override
  String get setupFlowSetUpLater => 'Configurar depois';

  @override
  String setupFlowLanguageLink(String language) {
    return 'Idioma: $language';
  }

  @override
  String get setupFlowRestoreLink => 'Restaurar de um backup';

  @override
  String get setupFlowHomeButtonTitle => 'O botão Início abre o Hearth';

  @override
  String get setupFlowHomeButtonBody => 'O Google TV mantém a própria tela inicial no botão Início. Um interruptor nas configurações do Android resolve isso e também permite que o Hearth:';

  @override
  String get setupFlowHomeButtonPoint1 => 'acompanhar as trocas de perfil e a hora de dormir das crianças';

  @override
  String get setupFlowHomeButtonPoint2 => 'mostrar pop-ups e desligar a TV quando ninguém está usando';

  @override
  String get setupFlowOnNextScreen => 'Na próxima tela:';

  @override
  String get setupFlowStepServices => 'Role até Serviços';

  @override
  String setupFlowStepSelect(String name) {
    return 'Selecione \"$name\"';
  }

  @override
  String get setupFlowStepEnable => 'Ative Ativar e depois OK';

  @override
  String get setupFlowComesBack => 'O Hearth volta sozinho quando estiver ativado. Se o Google TV perguntar quem está assistindo, escolha você.';

  @override
  String get setupFlowOpenAccessibility => 'Abrir Acessibilidade';

  @override
  String get setupFlowHomeButtonDone => 'Agora o botão Início abre o Hearth';

  @override
  String get setupFlowNotOnYetTitle => 'Ainda não está ativado';

  @override
  String get setupFlowNotOnYetBody => 'Tente de novo, ou pule e faça depois nas Configurações.';

  @override
  String get setupFlowStuckTitle => 'Está ativado, mas não está rodando';

  @override
  String get setupFlowStuckBody => 'O Android mostra como ativado, mas não está rodando. Desative e ative de novo.';

  @override
  String get setupFlowSkipHomeButtonTitle => 'Pular o botão Início?';

  @override
  String get setupFlowSkipHomeButtonBody => 'Sem ele, o botão Início abre o Google TV e o Hearth não consegue saber quando um perfil infantil está em uso.';

  @override
  String get setupFlowSkipAnyway => 'Pular mesmo assim';

  @override
  String get setupFlowSkip => 'Pular';

  @override
  String get setupFlowNext => 'Avançar';

  @override
  String get setupFlowLostTitle => 'A atualização desativou o botão Início';

  @override
  String get setupFlowLostBody => 'O Android o desativa depois de algumas atualizações. Ative de novo em um passo.';

  @override
  String get setupFlowBlockedTitle => 'O Android bloqueou este interruptor';

  @override
  String get setupFlowBlockedBody => 'Se o interruptor estava cinza, é porque o Hearth foi instalado de um arquivo baixado. A TV não tem uma configuração para permitir.';

  @override
  String get setupFlowBlockedComputer => 'Com um computador:';

  @override
  String get setupFlowBlockedComputerThen => 'Depois ative o interruptor. O Hearth percebe sozinho.';

  @override
  String get setupFlowBlockedSelfFixBody => 'A depuração está ativada, então o Hearth pode resolver sozinho. A TV vai perguntar \"Permitir depuração?\": escolha Sempre permitir e o Hearth vai desbloquear o interruptor e ativá-lo.';

  @override
  String get setupFlowSkipForNow => 'Pular por enquanto';

  @override
  String get setupFlowBlockedSkipLine => 'Apps, busca e Continuar assistindo continuam funcionando. O botão Início, os perfis, os pop-ups e o timer de desligamento, não.';

  @override
  String get setupFlowLetHearthFix => 'Deixar o Hearth resolver';

  @override
  String get setupFlowFixConfirmBody => 'O Hearth vai executar isto na TV, pela própria conexão de depuração:';

  @override
  String get setupFlowFixConfirmApproval => 'Na primeira vez, a TV pergunta \"Permitir depuração?\". Escolha Sempre permitir. Só muda as permissões do próprio Hearth.';

  @override
  String get setupFlowFixRun => 'Executar';

  @override
  String get setupFlowFixWaiting => 'Em andamento. Se a TV perguntar \"Permitir depuração?\", escolha Sempre permitir.';

  @override
  String get setupFlowFixFailedTitle => 'O Hearth não conseguiu';

  @override
  String get setupFlowFixFailedBody => 'O Hearth não conseguiu acessar a depuração da TV. Se a TV perguntou \"Permitir depuração?\", escolha Sempre permitir e tente de novo. A depuração precisa continuar ativada nas Opções do desenvolvedor.';

  @override
  String get setupFlowHomeAppTitle => 'Defina o Hearth como app de início';

  @override
  String get setupFlowHomeAppBody => 'O Android vai mostrar uma lista de apps de início. Escolha o Hearth. Isso impede que perfis infantis bloqueiem o Hearth.';

  @override
  String get setupFlowChooseHearth => 'Escolher o Hearth';

  @override
  String get setupFlowHomeAppDone => 'O Hearth é seu app de início';

  @override
  String get setupFlowNotChosenTitle => 'Ainda não escolhido';

  @override
  String get setupFlowFinishTitle => 'O Hearth está pronto';

  @override
  String setupFlowFinishBody(String where) {
    return 'O que você pulou está nas Configurações, e você pode fazer isto de novo em $where.';
  }

  @override
  String get setupFlowFinishOn => 'Ativado';

  @override
  String get setupFlowFinishLaterHeading => 'Depois, nas Configurações';

  @override
  String get setupFlowFinishMore => 'Mais nas Configurações: botões do controle, seções, notificações e backup.';

  @override
  String get setupFlowGoHome => 'Ir para meu início';

  @override
  String get setupHearthTitle => 'Configurar o Hearth';

  @override
  String get setupRunAgain => 'Configurar de novo';

  @override
  String get setupCardFamily => 'Sua família';

  @override
  String get setupCardWatching => 'Assistir';

  @override
  String setupChipLeft(int count) {
    return 'Concluir a configuração · faltam: $count';
  }

  @override
  String get setupChipFix => 'O botão Início precisa de ajuste';

  @override
  String get setupChipHideTitle => 'Ocultar este lembrete?';

  @override
  String setupChipHideBody(String where) {
    return 'Você ainda pode configurar em $where.';
  }

  @override
  String get setupChipHide => 'Ocultar';

  @override
  String get setupFlowCardIncluded => 'O que inclui';

  @override
  String get setupFlowCardNeeds => 'O que é preciso';

  @override
  String get setupFlowCardSkipped => 'Ignorado';

  @override
  String get setupFlowChange => 'Alterar';

  @override
  String get setupFlowKeep => 'Manter';

  @override
  String get setupFlowTurnOn => 'Ativar';

  @override
  String get setupFlowNeedsQuestion => 'Uma pergunta do Android';

  @override
  String get setupFlowNeedsOneSwitch => 'Um interruptor nas configurações do Android';

  @override
  String get setupFlowNeedsAboutAMinute => 'Cerca de um minuto';

  @override
  String get setupFlowWatchingBenefit => 'Continue de onde parou e veja o que está tocando.';

  @override
  String get setupFlowWatchingIncluded1 => 'Continuar assistindo na tela inicial';

  @override
  String get setupFlowWatchingIncluded2 => 'Notificações e o que está tocando';

  @override
  String get setupFlowSearchWorks => 'A pesquisa já funciona: pressione Pesquisar na tela inicial.';

  @override
  String get setupFlowContinueBody => 'Mostre na tela inicial o que você estava assistindo nos seus apps. O Android vai perguntar uma vez; escolha Permitir.';

  @override
  String get setupFlowContinueDone => 'Continuar assistindo está ativado';

  @override
  String get setupFlowContinueDeniedTitle => 'O Android não permitiu';

  @override
  String setupFlowContinueDeniedBody(String where) {
    return 'Você pode ativar depois em $where.';
  }

  @override
  String get setupFlowNotificationsTitle => 'O que está tocando e notificações';

  @override
  String setupFlowNotificationsBody(String name) {
    return 'Veja suas notificações e o que está tocando. Na próxima tela, selecione \"$name\" e permita.';
  }

  @override
  String get setupFlowNotificationsDone => 'As notificações estão ativadas';

  @override
  String get setupFlowTvTitle => 'Desligar a TV quando ninguém estiver assistindo?';

  @override
  String get setupFlowTvBody => 'Após esse tempo sem apertar o controle. Vídeo ou música tocando conta como assistir.';

  @override
  String get setupFlowTvNeedsHomeButton => 'Isto precisa do interruptor do botão Início dos primeiros passos: sem ele, o Hearth não sabe quando o controle é usado.';

  @override
  String get setupFlowStartOnBoot => 'Iniciar o Hearth quando a TV ligar';

  @override
  String get setupFlowScreensaver => 'Escolher fotos do protetor de tela';

  @override
  String get setupFlowUpdatesBenefit => 'O Hearth mantém a si mesmo e seus apps complementares atualizados.';

  @override
  String get setupFlowUpdatesIncluded1 => 'O Hearth se atualiza sozinho';

  @override
  String get setupFlowUpdatesIncluded2 => 'HearthTube, um app do YouTube feito para o Hearth';

  @override
  String get setupFlowInstallTitle => 'Permitir que o Hearth instale atualizações';

  @override
  String get setupFlowInstallBody => 'Na próxima tela, encontre o Hearth, ative-o e pressione Voltar.';

  @override
  String get setupFlowInstallDone => 'O Hearth pode instalar atualizações';

  @override
  String get setupFlowTubeTitle => 'Instalar o HearthTube?';

  @override
  String get setupFlowTubeBody => 'Um app do YouTube feito para o Hearth: segue seus perfis, o estilo do relógio e a hora de dormir das crianças.';

  @override
  String get setupFlowTubeInstalled => 'O HearthTube está instalado';

  @override
  String get setupCardHome => 'Sua tela inicial';

  @override
  String get setupFlowLookTitle => 'Escolha um visual';

  @override
  String setupFlowLookBody(String where) {
    return 'Cada um aparece atrás deste cartão quando você passa por ele. Você pode mudar qualquer parte depois em $where.';
  }

  @override
  String get setupFlowLookOtherTitle => 'Escolha um visual para sua tela inicial';

  @override
  String get setupFlowLookOtherBody => 'Cada perfil tem sua própria tela inicial. Escolha como a sua fica.';

  @override
  String get setupLookHearth => 'Hearth';

  @override
  String get setupLookPhoto => 'Foto do dia';

  @override
  String get setupLookCalmDark => 'Escuro calmo';

  @override
  String get setupLookBold => 'Vibrante';

  @override
  String get setupFlowLookNow => 'Atual';

  @override
  String get setupFlowLookUse => 'Usar este visual';

  @override
  String get setupFlowLookKeep => 'Manter o atual';

  @override
  String get setupFlowLookCustomize => 'Personalizar';

  @override
  String get setupFlowWeatherTitle => 'Mostrar o tempo?';

  @override
  String get setupFlowWeatherBody => 'Escolha sua cidade. Só a localização dela é enviada, ao Open-Meteo; sem conta.';

  @override
  String get setupFlowWeatherChoose => 'Escolher cidade';

  @override
  String get setupFlowWeatherDone => 'O tempo aparece na barra superior';

  @override
  String get setupFlowFamilyBenefit => 'Os apps de streaming abrem na pessoa certa, e as crianças não podem mudar o Hearth.';

  @override
  String get setupFlowFamilyIncluded1 => 'Um PIN dos pais, para as crianças não mudarem o Hearth';

  @override
  String get setupFlowFamilyIncluded2 => 'O perfil certo no Netflix, Disney+, Apple TV, Max e Paramount+';

  @override
  String get setupFlowFamilyIncluded3 => 'O Hearth mantido nos perfis das crianças';

  @override
  String get setupFlowNeedsPin => 'Quatro dígitos que você escolhe';

  @override
  String get setupFlowNeedsTwoMinutes => 'Cerca de 2 minutos';

  @override
  String get setupFlowPinTitle => 'Escolha um PIN dos pais';

  @override
  String get setupFlowPinBody => 'As crianças precisam dele para mudar o Hearth. Escolha quatro dígitos que uma criança não vá adivinhar.';

  @override
  String get setupFlowPinChoose => 'Escolher PIN';

  @override
  String get setupFlowPinDone => 'O PIN dos pais foi definido';

  @override
  String get setupFlowPairingTitle => 'O perfil certo nos apps de streaming';

  @override
  String setupFlowPairingBody(String name) {
    return 'O Hearth escolhe o perfil de cada pessoa no Netflix, Disney+, Apple TV, Max e Paramount+. Ele precisa de mais um interruptor na mesma tela do Android: \"$name\".';
  }

  @override
  String get setupFlowPairingDone => 'O pareamento de perfis está ativado';

  @override
  String get setupFlowPairingDoneBody => 'O Hearth combina os nomes sozinho: \"Alex\" vai com \"Alex Morgan\". Os perfis de cada app aparecem depois que a tela \"Quem está assistindo?\" dele aparecer uma vez.';

  @override
  String get setupFlowCheckPairings => 'Verificar pareamentos';

  @override
  String get setupFlowVoiceTitle => 'Mais um passo para o Netflix';

  @override
  String setupFlowVoiceBody(String name) {
    return 'O Netflix lê a tela de perfis em voz alta, então o Hearth escuta pela própria voz. Na próxima tela, em Mecanismo preferencial, escolha \"$name\" e depois OK. Os outros apps mantêm a voz do Google.';
  }

  @override
  String get setupFlowVoiceDone => 'A voz do Hearth está ativada';

  @override
  String get setupFlowKidsTitle => 'Manter o Hearth nos perfis das crianças';

  @override
  String get setupFlowKidsBody => 'O Google TV remove dos perfis infantis, toda vez que eles iniciam, os apps que não instalou. O Hearth pode proteger a si mesmo e o HearthTube lá. Cada criança recebe um aviso do Family Link de \"app adicionado\"; desfaça quando quiser nas Configurações.';

  @override
  String get setupFlowKidsApprove => 'A TV vai perguntar \"Permitir depuração?\". Marque Sempre permitir e depois Permitir. Você só faz isso uma vez.';

  @override
  String get setupFlowKidsAdd => 'Adicionar aos perfis delas';

  @override
  String get setupFlowKidsDone => 'O Hearth está nos perfis das crianças';

  @override
  String get setupFlowKidsKeepDebugging => 'Deixe a depuração ativada: o Hearth precisa dela de novo para um novo perfil infantil e para se remover ou desinstalar.';

  @override
  String get setupFlowDebugTitle => 'Ative a depuração primeiro';

  @override
  String get setupFlowDebugBody => 'O Hearth precisa do interruptor de depuração da TV para configurar os perfis infantis. Na próxima tela, selecione \"Versão do Android TV OS\" sete vezes. Depois, em Configurações > Sistema > Opções do desenvolvedor, ative Depuração USB e volte. Deixe ativado: o Hearth precisa dele de novo para um novo perfil infantil.';

  @override
  String get setupFlowDebugOpen => 'Abrir Sobre';
}
