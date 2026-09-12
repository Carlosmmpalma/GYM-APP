import 'package:equatable/equatable.dart';

import 'role.dart';

/// Perfil mínimo de staff (Instrutor/Gestor), para o ecrã "Staff" do
/// Gestor (`ManageStaffScreen`/`StaffDetailScreen`). Mesma lógica de
/// `MemberSummary`: não é o [AppUser] autenticado, é o documento
/// `tenants/{tenantId}/staff/{uid}` tal como `createStaff.ts` o cria.
class StaffSummary extends Equatable {
  const StaffSummary({
    required this.uid,
    required this.name,
    required this.email,
    required this.roles,
    required this.active,
    this.modalityIds = const {},
    this.serviceIds = const {},
    this.photoPath,
    this.photoUrl,
    this.photoUpdatedAt,
  });

  final String uid;
  final String name;

  /// Ao contrário de `MemberSummary.email` (contacto puro), este É o
  /// email de login real (Firebase Auth) — editá-lo por
  /// `StaffDetailScreen` chama a Cloud Function `updateStaffProfile`,
  /// que sincroniza Firestore E Auth juntos, para nunca divergirem.
  final String email;
  final Set<Role> roles;
  final bool active;

  /// Fase 6 (UC12/22 fechado: "instrutor pode ter várias modalidades")
  /// — só tem sentido para quem tem `Role.instructor`, mas fica no
  /// mesmo documento de sempre; um Gestor puro simplesmente nunca
  /// preenche isto.
  final Set<String> modalityIds;

  /// Ver `MemberSummary.photoPath` — o avatar é a mesma coisa para
  /// alunos e para staff, e vive no mesmo sítio.
  final String? photoPath;
  final String? photoUrl;
  final int? photoUpdatedAt;

  /// Fase 11 — os serviços que este instrutor pode lecionar.
  ///
  /// As modalidades já existiam desde a Fase 6, mas eram informativas:
  /// diziam "a Ana dá Pilates" e mais nada. Os serviços são o que
  /// **autoriza**: um instrutor só cria aulas dos serviços que tem
  /// associados, e as Security Rules verificam-no no servidor.
  ///
  /// Vazio = não pode criar aulas nenhumas. É o valor por omissão de
  /// propósito: um instrutor recém-criado não deve poder pôr aulas no
  /// horário do estúdio antes de alguém decidir quais.
  final Set<String> serviceIds;

  // Os restantes dados pessoais (telefone, data de nascimento, morada,
  // NIF, contacto de emergência) NÃO vivem aqui — ver
  // [StaffPrivateProfile]. Este documento é legível por todo o tenant
  // porque é dele que sai o nome do instrutor no cartão de uma aula.

  @override
  List<Object?> get props => [
        uid,
        name,
        email,
        roles,
        active,
        modalityIds,
        serviceIds,
        photoPath,
        photoUrl,
        photoUpdatedAt,
      ];
}
