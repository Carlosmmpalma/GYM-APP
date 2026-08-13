import { Firestore } from 'firebase-admin/firestore';

/**
 * UC22 (fechado): "Nº de sócio é gerado automaticamente" — o Gestor não
 * o escreve. Gerado via transação sobre um contador por tenant, para
 * garantir unicidade mesmo com criações concorrentes
 * (Platform Foundation §17 — Concorrência).
 *
 * Formato: zero-padded a 6 dígitos ("000123"), consistente com o
 * mockup (nxt-studio-screens.html mostra "Nº de sócio 0142").
 */
export async function nextMemberNumber(
  firestore: Firestore,
  tenantId: string,
): Promise<string> {
  const counterRef = firestore
    .collection('tenants')
    .doc(tenantId)
    .collection('config')
    .doc('counters');

  const next = await firestore.runTransaction(async (tx) => {
    const snapshot = await tx.get(counterRef);
    const current = (snapshot.data()?.memberNumberSeq as number | undefined) ?? 0;
    const updated = current + 1;
    tx.set(counterRef, { memberNumberSeq: updated }, { merge: true });
    return updated;
  });

  return next.toString().padStart(6, '0');
}
