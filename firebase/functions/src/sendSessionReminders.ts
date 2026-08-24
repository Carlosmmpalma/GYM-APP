import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { requireManager } from './lib/callerContext';
import { sendSessionRemindersForTenant } from './lib/reminders';

/**
 * Fase 11 — lembretes antes da aula. A regra de negócio e o porquê
 * estão em `lib/reminders.ts`; aqui só ficam os dois gatilhos.
 *
 * De hora a hora e não de dez em dez minutos: a antecedência
 * configurada é em HORAS, portanto correr mais vezes só antecipa o
 * aviso em minutos e multiplica leituras por nada.
 */
async function runForAllTenants() {
  const firestore = getFirestore();
  const tenants = await firestore.collection('tenants').get();

  let occurrences = 0;
  let notified = 0;
  for (const tenant of tenants.docs) {
    const result = await sendSessionRemindersForTenant({ tenantRef: tenant.ref });
    occurrences += result.occurrences;
    notified += result.notified;
  }
  return { tenants: tenants.size, occurrences, notified };
}

export const sendSessionReminders = onSchedule(
  { schedule: 'every 60 minutes', timeoutSeconds: 540 },
  async () => {
    const summary = await runForAllTenants();
    console.log('sendSessionReminders', summary);
  },
);

/**
 * Callable equivalente, restrito ao tenant do chamador — mesmo par
 * que `generateRecurringOccurrences`/`...Now`: o Functions Emulator
 * não dispara `onSchedule` por temporizador, por isso esta é a única
 * forma de testar isto localmente (e de o Gestor forçar um envio).
 */
export const sendSessionRemindersNow = onCall(async (request) => {
  const caller = requireManager(request);
  return sendSessionRemindersForTenant({
    tenantRef: getFirestore().collection('tenants').doc(caller.tenantId),
  });
});
