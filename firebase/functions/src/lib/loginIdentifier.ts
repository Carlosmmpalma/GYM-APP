/**
 * Espelho em TypeScript de lib/core/config/login_identifier.dart.
 *
 * ⚠️ Os dois lados têm de gerar exatamente o mesmo email para o mesmo
 * (tenantId, número) — se alterares um, altera o outro.
 */
export function buildSyntheticEmail(tenantId: string, memberNumber: string): string {
  const normalizedTenant = tenantId.trim().toLowerCase();
  const normalizedNumber = memberNumber.trim().toLowerCase();
  return `member-${normalizedNumber}@${normalizedTenant}.gymsaas.internal`;
}
