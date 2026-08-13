import 'package:equatable/equatable.dart';

import 'role.dart';

/// Representa "CurrentUser + CurrentTenant + CurrentRole" (Platform
/// Foundation §9 — Tenant Context) já resolvidos a partir do ID token.
///
/// Isto NÃO é o documento de negócio do membro/staff (esse vive em
/// Firestore, ver [Tenant]/repositories) — é só o contexto mínimo de
/// autorização derivado do Firebase Auth, disponível assim que o login
/// completa, sem esperar por uma leitura adicional ao Firestore.
class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.tenantId,
    required this.roles,
  });

  final String uid;
  final String tenantId;
  final Set<Role> roles;

  bool get isManager => roles.contains(Role.manager);
  bool get isInstructor => roles.contains(Role.instructor);
  bool get isMember => roles.contains(Role.member);

  @override
  List<Object?> get props => [uid, tenantId, roles];
}
