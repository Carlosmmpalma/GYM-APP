import { initializeApp } from 'firebase-admin/app';
import { onCall } from 'firebase-functions/v2/https';

initializeApp();

/**
 * Função de diagnóstico da Fase 0 — confirma que a base de Cloud Functions
 * (Platform Foundation §18, §28) está a compilar e a correr no emulador.
 *
 * As funções reais de negócio (createMember, createBooking, etc., ver
 * Technical/Firestore Data Model v1 §53) ficam para a Fase 1+.
 */
export const healthCheck = onCall((request) => {
  return {
    status: 'ok',
    project: process.env.GCLOUD_PROJECT ?? 'unknown',
    calledBy: request.auth?.uid ?? null,
    timestamp: new Date().toISOString(),
  };
});

// Fase 1 — Identidade, Tenant e isolamento.
export { createMember } from './createMember';
export { createStaff } from './createStaff';

// Fase 3 — Planos, serviços e subscriptions.
export { createSubscription } from './createSubscription';

// Fase 4 — Usage tracking e limite semanal. createBooking/cancelBooking
// substituem as transações client-side da Fase 2 (ver nota de
// arquitetura em createBooking.ts).
export { createBooking } from './createBooking';
export { cancelBooking } from './cancelBooking';
export { recalculateUsage } from './recalculateUsage';

// Fase 5 — Sessões recorrentes (séries). generateRecurringOccurrences
// materializa as próximas semanas a partir de sessionSeries ativas
// (cron diário); generateRecurringOccurrencesNow é o equivalente
// callable, restrito ao tenant do chamador (testar sem esperar pelo
// cron). assignMembersToOccurrence é a atribuição manual pelo Gestor
// (modelo híbrido, UC17/UC19).
export {
  generateRecurringOccurrences,
  generateRecurringOccurrencesNow,
} from './generateRecurringOccurrences';
export { assignMembersToOccurrence } from './assignMembersToOccurrence';
