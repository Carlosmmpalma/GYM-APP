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
  final normalizedNumber = memberNumber.trim().toLowerCase();
  return 'member-$normalizedNumber@${_toDomainLabel(tenantId)}.gymsaas.internal';
}

/// Converte o `tenantId` num rótulo de domínio válido.
///
/// O `tenantId` é escolhido por nós e segue convenções de identificador
/// (`nxt_performance_studio`) — mas isto vai parar ao lado direito de um
/// `@`, e aí valem as regras de nomes de domínio: só letras, dígitos e
/// hífenes, sem começar nem acabar em hífen.
///
/// ⚠️ Isto não é cosmética. O emulador de Auth aceita `_` no domínio; o
/// Firebase Auth **real recusa** com `auth/invalid-email`. Sem esta
/// conversão, num projeto a sério nenhum aluno com um `tenantId` assim
/// conseguia ser criado nem entrar — e os testes não apanhavam, porque
/// usavam o tenant `nxt`, que por acaso já era um rótulo válido.
///
/// Nota: dois `tenantId` diferentes podem colapsar no mesmo rótulo
/// (`a_b` e `a-b`). Como os ids são escolhidos por nós, evita-se ao
/// nomear; não vale a pena complicar o esquema por isso.
String _toDomainLabel(String tenantId) {
  final collapsed = tenantId
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return collapsed.isEmpty ? 'tenant' : collapsed;
}
