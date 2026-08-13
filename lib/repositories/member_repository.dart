import '../domain/entities/member_summary.dart';

/// Fase 3 — lista mínima de membros do tenant, usada pelo ecrã de
/// atribuição de Plan/Subscription (Gestor).
abstract class MemberRepository {
  Stream<List<MemberSummary>> watchMembers();

  /// Desativa/reativa um membro — nunca elimina (o `uid` continua
  /// referenciado por subscriptions/bookings passados). Escreve
  /// `status: 'active'|'inactive'`, o mesmo campo que já é lido em
  /// `_fromDoc` (`firebase_member_repository.dart`).
  Future<void> setMemberActive({
    required String memberId,
    required bool active,
  });
}
