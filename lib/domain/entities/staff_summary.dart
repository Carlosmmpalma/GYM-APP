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
  });

  final String uid;
  final String name;
  final String email;
  final Set<Role> roles;
  final bool active;

  @override
  List<Object?> get props => [uid, name, email, roles, active];
}
