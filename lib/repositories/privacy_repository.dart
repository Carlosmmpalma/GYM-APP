/// Fase 11 (RGPD) — as três operações que a lei obriga a existir:
/// registar o consentimento (artigo 7.º), dar ao titular os seus dados
/// (artigos 15.º/20.º) e apagá-los (artigo 17.º).
///
/// Todas passam por Cloud Functions e nenhuma é escrita direta: o
/// consentimento precisa de um timestamp que o cliente não escolha, a
/// exportação atravessa coleções que o cliente não pode listar, e o
/// apagamento mexe no Firebase Auth, que só o Admin SDK alcança.
abstract class PrivacyRepository {
  /// Regista a aceitação da política de privacidade e a decisão sobre
  /// dados de saúde, para o utilizador autenticado.
  Future<void> recordConsent({
    required int privacyPolicyVersion,
    required bool healthDataGranted,
  });

  /// Tudo o que a app guarda sobre um membro. `memberId` nulo = o
  /// próprio; um Gestor pode pedir o de qualquer membro do tenant.
  Future<Map<String, dynamic>> exportMemberData({String? memberId});

  /// Apagamento (Manager-only). [confirmMemberNumber] tem de bater
  /// certo com o número de sócio — é a salvaguarda contra o clique
  /// errado numa ação sem retorno.
  ///
  /// Devolve o que foi apagado e quantos registos de pagamento ficaram
  /// anonimizados em vez de apagados (retenção fiscal obrigatória).
  Future<MemberDeletionReport> deleteMemberData({
    required String memberId,
    required String confirmMemberNumber,
  });
}

class MemberDeletionReport {
  const MemberDeletionReport({
    required this.deletedByCollection,
    required this.anonymizedPaymentRecords,
  });

  final Map<String, int> deletedByCollection;
  final int anonymizedPaymentRecords;

  int get totalDeleted =>
      deletedByCollection.values.fold(0, (sum, value) => sum + value);
}
