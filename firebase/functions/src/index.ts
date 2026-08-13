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
