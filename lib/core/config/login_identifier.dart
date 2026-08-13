/// Converte um nº de sócio num email sintético aceite pelo Firebase Auth.
///
/// UC01 exige login por nº de sócio, não por email — mas o Firebase Auth
/// (email/password, decisão da Fase 1) só aceita email. Em vez de um
/// email real, geramos um determinístico e nunca mostrado ao
/// utilizador: `member-<numero>@<tenantId>.gymsaas.internal`.
///
/// Isto NÃO é uma lookup — não faz nenhuma leitura à base de dados, por
/// isso não há forma de um atacante usar isto para descobrir se um nº de
/// sócio existe (UC01: "não confirmar/negar se o nº de sócio existe").
/// A confirmação real (existe ou não, password certa ou não) só
/// acontece no `signInWithEmailAndPassword`, e o erro devolvido ao
/// utilizador é sempre genérico (ver [InvalidCredentialsException]).
///
/// ⚠️ Mantido em sincronia manualmente com a mesma função em
/// `firebase/functions/src/lib/loginIdentifier.ts` — os dois lados têm
/// de gerar exatamente o mesmo email para o mesmo (tenantId, número).
String buildSyntheticEmail({
  required String tenantId,
  required String memberNumber,
}) {
  final normalizedTenant = tenantId.trim().toLowerCase();
  final normalizedNumber = memberNumber.trim().toLowerCase();
  return 'member-$normalizedNumber@$normalizedTenant.gymsaas.internal';
}
