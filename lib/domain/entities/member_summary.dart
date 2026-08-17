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
    this.birthDate,
    this.address = '',
    this.nif = '',
    this.emergencyContact = '',
  });

  final String uid;
  final String memberNumber;
  final String name;
  final bool active;

  /// UC02 — contacto real do membro, editável por ele próprio
  /// (`MyProfileScreen`) ou pelo Gestor (`MemberDetailScreen`).
  /// Distinto do email SINTÉTICO usado só para login
  /// (`login_identifier.dart`) — esse nunca é mostrado nem editável
  /// aqui. `''` quando ainda não preenchido.
  final String phone;
  final String email;

  /// Pedido pelo Carlo depois de testar "Criar utilizador": dados
  /// pessoais adicionais, todos opcionais (`''`/`null` até serem
  /// preenchidos), editáveis só pelo Gestor por agora (`MemberDetailScreen`
  /// — `MyProfileScreen`, self-service, continua limitado a
  /// `phone`/`email`).
  final DateTime? birthDate;
  final String address;
  final String nif;

  /// Texto livre (ex.: "Mãe — 912345678") — não vale a pena modelar
  /// como nome+telefone separados para um único campo de apoio.
  final String emergencyContact;

  @override
  List<Object?> get props => [
        uid,
        memberNumber,
        name,
        active,
        phone,
        email,
        birthDate,
        address,
        nif,
        emergencyContact,
      ];
}
