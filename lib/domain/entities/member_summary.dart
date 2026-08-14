import 'package:equatable/equatable.dart';

/// Perfil mínimo de um membro, para listas/pickers de gestão (Fase 3 —
/// ecrã "atribuir plano a um membro"). Não é o [AppUser] (que
/// representa a identidade autenticada + custom claims) — este é o
/// próprio documento `tenants/{tenantId}/members/{uid}`, tal como a
/// Fase 1 o criou (Cloud Function `createMember`). Ver nota em
/// `account_repository.dart`: o perfil completo do membro (contactos,
/// avaliações, etc.) fica para quando existir um ecrã que precise de
/// mais do que isto.
class MemberSummary extends Equatable {
  const MemberSummary({
    required this.uid,
    required this.memberNumber,
    required this.name,
    required this.active,
    this.phone = '',
    this.email = '',
  });

  final String uid;
  final String memberNumber;
  final String name;
  final bool active;

  /// UC02 — contacto real do membro, editável por ele próprio
  /// (`MyProfileScreen`). Distinto do email SINTÉTICO usado só para
  /// login (`login_identifier.dart`) — esse nunca é mostrado nem
  /// editável aqui. `''` quando o membro ainda não preencheu.
  final String phone;
  final String email;

  @override
  List<Object?> get props => [uid, memberNumber, name, active, phone, email];
}
