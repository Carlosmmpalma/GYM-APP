/**
 * Espelho em TypeScript de lib/core/config/login_identifier.dart.
 *
 * ⚠️ Os dois lados têm de gerar exatamente o mesmo email para o mesmo
 * (tenantId, número) — se alterares um, altera o outro.
 */
export function buildSyntheticEmail(tenantId: string, memberNumber: string): string {
  const normalizedNumber = memberNumber.trim().toLowerCase();
  return `member-${normalizedNumber}@${toDomainLabel(tenantId)}.gymsaas.internal`;
}

/**
 * Converte o `tenantId` num rótulo de domínio válido — só letras,
 * dígitos e hífenes, sem começar nem acabar em hífen.
 *
 * ⚠️ O emulador de Auth aceita `_` no domínio; o Firebase Auth **real
 * recusa** com `auth/invalid-email`. Sem isto, num projeto a sério
 * `createMember` falhava para qualquer tenant com underscore no id.
 */
function toDomainLabel(tenantId: string): string {
  const collapsed = tenantId
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return collapsed === '' ? 'tenant' : collapsed;
}
