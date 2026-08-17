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

  /// Pedido pelo Carlo depois de testar "Criar utilizador" — o Gestor
  /// edita TODOS os dados pessoais de qualquer membro (`MemberDetailScreen`),
  /// ao contrário de [updateOwnContact] (o próprio, só phone/email).
  /// Escrita direta do cliente — `firestore.rules` já dá ao Manager
  /// escrita ampla em `members/{id}` desde a Fase 1, e ao contrário do
  /// staff (`StaffRepository.updateStaffProfile`), o email do membro
  /// nunca é o login (é sempre sintético), por isso não há nada no
  /// Firebase Auth para sincronizar aqui.
  Future<void> updateMemberProfile({
    required String memberId,
    required String name,
    required String phone,
    required String email,
    DateTime? birthDate,
    required String address,
    required String nif,
    required String emergencyContact,
  });

  /// Fase 6 (UC21) — regista este token de FCM no próprio documento
  /// (`arrayUnion`, um dispositivo pode ter mais do que um token ao
  /// longo do tempo — reinstalação, etc.; nunca removemos tokens
  /// antigos aqui, só acrescentamos). Falha silenciosa esperada em
  /// plataformas/browsers sem VAPID key configurada — ver
  /// `notification_providers.dart`.
  Future<void> registerFcmToken({
    required String memberId,
    required String token,
  });
}
