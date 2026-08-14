import '../domain/entities/member_summary.dart';

/// Fase 3 — lista mínima de membros do tenant, usada pelo ecrã de
/// atribuição de Plan/Subscription (Gestor).
abstract class MemberRepository {
  Stream<List<MemberSummary>> watchMembers();

  /// UC02 — o próprio membro a ver o seu perfil (`MyProfileScreen`).
  /// `null` se o documento não existir (não deveria acontecer para um
  /// utilizador autenticado com role `member`, mas o ecrã trata isso
  /// como estado de erro, não assume).
  Stream<MemberSummary?> watchMember(String memberId);

  /// Desativa/reativa um membro — nunca elimina (o `uid` continua
  /// referenciado por subscriptions/bookings passados). Escreve
  /// `status: 'active'|'inactive'`, o mesmo campo que já é lido em
  /// `_fromDoc` (`firebase_member_repository.dart`).
  Future<void> setMemberActive({
    required String memberId,
    required bool active,
  });

  /// UC02 — o próprio membro a atualizar `phone`/`email` (só isto;
  /// `memberNumber`/`status`/`name` continuam geridos pelo Gestor). As
  /// Security Rules (`firestore.rules`) fazem cumprir esta restrição
  /// do lado do servidor — este método não é a única barreira.
  Future<void> updateOwnContact({
    required String memberId,
    required String phone,
    required String email,
  });
}
