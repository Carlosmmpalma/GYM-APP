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
    this.phone = '',
    this.birthDate,
    this.address = '',
    this.nif = '',
    this.emergencyContact = '',
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

  /// Pedido pelo Carlo depois de testar "Criar utilizador": mesmos
  /// dados pessoais do Aluno (`MemberSummary`), para o staff deixar de
  /// ser um cidadão de segunda classe em termos de ficha pessoal.
  final String phone;
  final DateTime? birthDate;
  final String address;
  final String nif;
  final String emergencyContact;

  @override
  List<Object?> get props => [
        uid,
        name,
        email,
        roles,
        active,
        modalityIds,
        phone,
        birthDate,
        address,
        nif,
        emergencyContact,
      ];
}
