import 'package:equatable/equatable.dart';

/// Uma linha do horário de funcionamento, já escrita para ler
/// ("Segunda a sexta", "07:00 – 22:00").
///
/// Uma estrutura mais fina — abertura e fecho como horas — não valia a
/// pena: isto é para se ler num ecrã, não para se calcular com ele, e
/// obrigaria o Gestor a preencher campos para dizer "encerrado".
class OpeningHours extends Equatable {
  const OpeningHours({required this.days, required this.hours});

  final String days;
  final String hours;

  /// Uma linha só diz alguma coisa se tiver HORAS.
  ///
  /// O dia sozinho não informa ninguém: "Sábado" seguido de nada, num
  /// ecrã público, lê-se como um erro. E o ecrã de gestão sugere os dias
  /// da semana pré-preenchidos, por isso este caso não é raro — é o
  /// normal para quem preenche o horário de segunda a sexta e fecha ao
  /// fim de semana.
  bool get isEmpty => hours.trim().isEmpty;

  @override
  List<Object?> get props => [days, hours];
}

/// A informação pública do estúdio.
///
/// Vive em `tenants/{t}/public/info`, o caminho que se lê **sem sessão**
/// — é o que permite à vitrina (`StudioShowcaseScreen`) mostrar morada,
/// contactos e horário a quem ainda não é membro, e à app ligar para a
/// política de privacidade a partir do ecrã de consentimento.
///
/// Esteve em configuração da build durante meia tarde, com o argumento
/// de que tem de aparecer antes de haver sessão. O argumento era
/// verdadeiro e deixou de ser um impedimento assim que a vitrina passou
/// a ler de um caminho público — e na config era pior por uma razão
/// prática: mudar o telefone do estúdio obrigava a um developer, uma
/// build nova e uma revisão da App Store.
///
/// Quem a escreve é a Cloud Function `updateStudioInfo`, a partir do
/// ecrã de gestão. Campos vazios são válidos e querem dizer "não
/// mostrar".
class StudioInfo extends Equatable {
  const StudioInfo({
    this.address = '',
    this.phone = '',
    this.email = '',
    this.mapsUrl = '',
    this.privacyPolicyUrl = '',
    this.openingHours = const [],
  });

  final String address;
  final String phone;
  final String email;

  /// Para o botão "Como chegar". Vazio esconde o botão.
  final String mapsUrl;

  /// Onde o estúdio publicou a política, se a publicou.
  ///
  /// **Opcional**, e é importante perceber porquê: a política vive
  /// dentro da app, em código e versionada (ver `PrivacyPolicyScreen`),
  /// porque é a versão mostrada que o registo de consentimento
  /// identifica. A app nunca fica sem política por este campo estar
  /// vazio.
  ///
  /// Serve para o App Store Connect, que exige um endereço público para
  /// a ficha da loja — e para o dia em que exista uma versão revista
  /// alojada num site.
  final String privacyPolicyUrl;

  final List<OpeningHours> openingHours;

  /// Só as linhas com alguma coisa escrita.
  List<OpeningHours> get visibleHours =>
      openingHours.where((l) => !l.isEmpty).toList();

  /// O que ainda falta preencher, em português, para o ecrã de gestão
  /// poder dizê-lo em vez de o Gestor ter de adivinhar.
  ///
  /// O URL da política NÃO entra aqui: a app tem sempre política, em
  /// código. Falta só para a ficha da loja, e isso não é trabalho deste
  /// ecrã.
  List<String> get missing => [
        if (address.trim().isEmpty) 'Morada',
        if (phone.trim().isEmpty) 'Telefone',
        if (email.trim().isEmpty) 'Email',
        if (visibleHours.isEmpty) 'Horário de funcionamento',
      ];

  bool get isComplete => missing.isEmpty;

  @override
  List<Object?> get props =>
      [address, phone, email, mapsUrl, privacyPolicyUrl, openingHours];
}
