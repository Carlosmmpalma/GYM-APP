/// Papéis suportados na Fase 1 (Domain Model v1 §6 — Staff / Roles).
///
/// Uma pessoa pode ter mais do que um papel dentro do mesmo tenant (ex:
/// instrutor que também é membro). Por isso [AppUser.roles] é um conjunto,
/// não um valor único.
enum Role {
  member,
  instructor,
  manager;

  static Role fromClaim(String value) => Role.values.firstWhere(
        (r) => r.name == value,
        orElse: () => throw ArgumentError('Role desconhecida: $value'),
      );
}
