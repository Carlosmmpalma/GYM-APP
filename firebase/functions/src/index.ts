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

// Fase 6 — Operações do dia a dia. removeMembersFromOccurrence (UC18
// atualizado, reduzir vagas) e cancelOccurrenceForStudio (UC18/UC10,
// substitui a escrita direta da Fase 5 — agora cascata para bookings/
// usage) partilham `lib/bookingLogic.ts#prepareRelease`/`applyRelease`.
export { removeMembersFromOccurrence } from './removeMembersFromOccurrence';
export { cancelOccurrenceForStudio } from './cancelOccurrenceForStudio';
export { deactivateInstructor } from './deactivateInstructor';
export { rescheduleBooking } from './rescheduleBooking';
export { sendNotification } from './sendNotification';

// Pedido pelo Carlo depois de testar "Criar utilizador" — dados
// pessoais editáveis pelo Gestor depois da criação (ver nota de
// arquitetura em updateStaffProfile.ts sobre porque o staff precisa de
// Cloud Function e o membro não).
export { updateStaffProfile } from './updateStaffProfile';

// Fase 7 — Treino livre (UC09/UC17-A). suggestFreeTrainingSchedule +
// publishFreeTrainingSchedule controlam o estado draft/suggested/
// published da grelha semanal; book/cancel/assign reutilizam
// `lib/bookingLogic.ts` (mesma transação de capacidade/elegibilidade/
// limite semanal da Fase 2/4/5), só apontando para
// `freeTrainingSchedules/{weekId}/slots/{slotId}` em vez de
// `sessionOccurrences/{id}`.
export { suggestFreeTrainingSchedule } from './suggestFreeTrainingSchedule';
export { publishFreeTrainingSchedule } from './publishFreeTrainingSchedule';
export { bookFreeTrainingSlot } from './bookFreeTrainingSlot';
export { cancelFreeTrainingBooking } from './cancelFreeTrainingBooking';
export { assignMembersToFreeTrainingSlot } from './assignMembersToFreeTrainingSlot';
