import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

export interface AuthenticatedManager {
  uid: string;
  tenantId: string;
}

/**
 * Platform Foundation §15 — Autorização: "uma operação administrativa
 * deverá ser rejeitada pelo backend mesmo que o utilizador consiga
 * construir manualmente o pedido". createMember/createStaff só podem
 * ser chamadas por quem já é 'manager' do tenant — nunca confiamos no
 * cliente para decidir isso (não há parâmetro `tenantId` vindo do
 * pedido: usamos sempre o tenantId dos custom claims do chamador).
 */
export function requireManager(request: CallableRequest): AuthenticatedManager {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Autenticação necessária.');
  }

  const tenantId = auth.token.tenantId as string | undefined;
  const roles = (auth.token.roles as string[] | undefined) ?? [];

  if (!tenantId || !roles.includes('manager')) {
    throw new HttpsError(
      'permission-denied',
      'Só um Gestor do tenant pode executar esta operação.',
    );
  }

  return { uid: auth.uid, tenantId };
}
