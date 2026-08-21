import 'package:equatable/equatable.dart';

/// A versão da política de privacidade que a app apresenta hoje.
///
/// Subir este número volta a pedir aceitação a toda a gente no próximo
/// arranque — é o mecanismo previsto pelo RGPD para quando o tratamento
/// muda (novo tipo de dados, novo destinatário, nova finalidade). Nunca
/// o subir por uma correção de gralhas: pedir consentimento outra vez
/// sem motivo treina as pessoas a carregar em "aceito" sem ler.
const int kPrivacyPolicyVersion = 1;

/// RGPD, artigo 7.º, n.º 1: "o responsável pelo tratamento deve poder
/// **demonstrar** que o titular deu o seu consentimento". Não basta a
/// app ter mostrado um ecrã — tem de ficar registado o quê, quando e
/// sobre que versão do texto.
///
/// Dois consentimentos separados, e a separação é deliberada:
///
/// - [privacyPolicyVersion]/[acceptedAt]: aceitação do aviso de
///   privacidade. Cobre o tratamento necessário à relação com o ginásio
///   (marcações, mensalidades) — cuja base legal é a execução do
///   contrato, não o consentimento.
/// - [healthDataGranted]: consentimento EXPLÍCITO para dados de saúde
///   (artigo 9.º) — peso, massa gorda, pressão arterial, tudo o que uma
///   avaliação física regista. É opcional de propósito: o artigo 7.º,
///   n.º 4 diz que o consentimento não é livre se for condição para um
///   serviço que não precisa dele. Um aluno tem de poder marcar aulas
///   sem autorizar avaliações físicas — e por isso as Security Rules
///   recusam escrever avaliações sem este consentimento, em vez de a UI
///   apenas esconder o botão.
class MemberConsent extends Equatable {
  const MemberConsent({
    this.privacyPolicyVersion,
    this.acceptedAt,
    this.healthDataGranted = false,
    this.healthDataUpdatedAt,
  });

  final int? privacyPolicyVersion;
  final DateTime? acceptedAt;
  final bool healthDataGranted;
  final DateTime? healthDataUpdatedAt;

  /// Não há registo nenhum: conta criada antes de existir consentimento,
  /// ou pessoa que ainda não passou pelo ecrã.
  bool get isEmpty => privacyPolicyVersion == null;

  /// Aceitou a versão que está em vigor. Uma versão anterior conta como
  /// não aceite — é o ponto de subir [kPrivacyPolicyVersion].
  bool get isCurrent => privacyPolicyVersion == kPrivacyPolicyVersion;

  @override
  List<Object?> get props => [
        privacyPolicyVersion,
        acceptedAt,
        healthDataGranted,
        healthDataUpdatedAt,
      ];
}
