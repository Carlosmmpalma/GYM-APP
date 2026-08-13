import '../domain/entities/member_summary.dart';

/// Fase 3 — lista mínima de membros do tenant, usada pelo ecrã de
/// atribuição de Plan/Subscription (Gestor).
abstract class MemberRepository {
  Stream<List<MemberSummary>> watchMembers();
}
