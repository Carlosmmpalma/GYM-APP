import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { requireManager } from './lib/callerContext';
import { resolveEligibility, runBookingTransaction } from './lib/bookingLogic';
import { publishPublicSchedule } from './lib/publicSchedule';
import { tenantTimeZone, zonedWallClockToUtc } from './lib/timeZone';

/** O guia (Fase 5) pede "materializa as próximas N semanas... 4-8 semanas". */
const HORIZON_WEEKS = 8;

function parseStartTime(startTime: string): { hour: number; minute: number } {
  const [hour, minute] = startTime.split(':').map(Number);
  return { hour, minute };
}

function dateOnlyUtc(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/** segunda=1 … domingo=7 — mesma convenção de `lib/isoWeek.ts`. */
function weekdayUtc(date: Date): number {
  const day = date.getUTCDay();
  return day === 0 ? 7 : day;
}

function occurrenceDateKey(date: Date): string {
  return date.toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Datas (00:00 UTC) em que a série deve ter ocorrência, entre
 * `max(series.startDate, from)` e `to` (inclusive), caindo sempre no
 * `dayOfWeek` da série.
 */
function datesForSeries(
  series: { dayOfWeek: number; startDate: Date },
  from: Date,
  to: Date,
): Date[] {
  const rangeStart = dateOnlyUtc(
    series.startDate.getTime() > from.getTime() ? series.startDate : from,
  );
  const dates: Date[] = [];
  const cursor = new Date(rangeStart);
  const offset = (series.dayOfWeek - weekdayUtc(cursor) + 7) % 7;
  cursor.setUTCDate(cursor.getUTCDate() + offset);
  while (cursor.getTime() <= to.getTime()) {
    dates.push(new Date(cursor));
    cursor.setUTCDate(cursor.getUTCDate() + 7);
  }
  return dates;
}

interface SeriesData {
  id: string;
  tenantRef: FirebaseFirestore.DocumentReference;
  serviceId: string;
  instructorId: string | null;
  modalityId: string | null;
  dayOfWeek: number;
  startTime: string;
  durationMinutes: number;
  capacity: number;
  startDate: Date;
  preAssignedMemberIds: string[];
}

function seriesFromDoc(doc: FirebaseFirestore.QueryDocumentSnapshot): SeriesData {
  const data = doc.data();
  return {
    id: doc.id,
    // `sessionSeries` está sempre em `tenants/{tenantId}/sessionSeries/{id}`
    // — o pai da collection é sempre o documento do tenant, mesmo truque
    // já usado em `firebase_booking_repository.dart#_fromDoc` para obter
    // o `occurrenceId` a partir do path.
    tenantRef: doc.ref.parent.parent!,
    serviceId: data.serviceId as string,
    instructorId: (data.instructorId as string | null | undefined) ?? null,
    modalityId: (data.modalityId as string | null | undefined) ?? null,
    dayOfWeek: data.dayOfWeek as number,
    startTime: data.startTime as string,
    durationMinutes: data.durationMinutes as number,
    capacity: data.capacity as number,
    startDate: (data.startDate as Timestamp).toDate(),
    preAssignedMemberIds: (data.preAssignedMemberIds as string[] | undefined) ?? [],
  };
}

export interface GenerationSummary {
  seriesProcessed: number;
  occurrencesCreated: number;
  assignments: { assigned: number; skipped: number };
  /** Aulas anunciadas na vitrina pública — ver `lib/publicSchedule.ts`. */
  publicScheduleEntries: number;
}

async function generateForSeries(
  firestore: FirebaseFirestore.Firestore,
  series: SeriesData,
  now: Date,
  summary: GenerationSummary,
  timeZone: string,
): Promise<void> {
  const horizonEnd = new Date(now.getTime());
  horizonEnd.setUTCDate(horizonEnd.getUTCDate() + HORIZON_WEEKS * 7);

  const dates = datesForSeries(series, dateOnlyUtc(now), horizonEnd);
  if (dates.length === 0) return;

  const occurrencesCollection = series.tenantRef.collection('sessionOccurrences');
  const { hour, minute } = parseStartTime(series.startTime);
  // Chave determinística `{seriesId}_{YYYY-MM-DD}` — é isto que torna a
  // função idempotente: correr duas vezes no mesmo dia (ou repetir por
  // causa de um retry) nunca duplica a ocorrência, só confirma que já
  // existe e passa à seguinte.
  const refs = dates.map((date) =>
    occurrencesCollection.doc(`${series.id}_${occurrenceDateKey(date)}`),
  );
  const existingSnaps = await firestore.getAll(...refs);

  for (let i = 0; i < dates.length; i++) {
    if (existingSnaps[i].exists) continue;

    // `startTime` é a hora do RELÓGIO do estúdio ("19:00"), não uma
    // hora UTC. Fazer `setUTCHours(19)` punha a aula às 20:00 em
    // Lisboa durante os sete meses de horário de verão — ver
    // `lib/timeZone.ts`.
    const day = dates[i];
    const startAt = zonedWallClockToUtc({
      year: day.getUTCFullYear(),
      month: day.getUTCMonth() + 1,
      day: day.getUTCDate(),
      hour,
      minute,
      timeZone,
    });
    const endAt = new Date(startAt.getTime() + series.durationMinutes * 60 * 1000);

    await refs[i].set({
      serviceId: series.serviceId,
      instructorId: series.instructorId,
      modalityId: series.modalityId,
      seriesId: series.id,
      startAt: Timestamp.fromDate(startAt),
      endAt: Timestamp.fromDate(endAt),
      capacity: series.capacity,
      status: 'scheduled',
      activeBookingCount: 0,
      // Explicitamente `null`, e não ausente: é o que permite aos
      // lembretes procurarem SÓ as aulas por avisar. O Firestore não
      // encontra `== null` em documentos onde o campo não existe, por
      // isso um campo em falta aqui fazia a aula nunca ser avisada.
      reminderSentAt: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    summary.occurrencesCreated += 1;

    // UC17/UC19 (fechado) — modelo híbrido: os membros pré-atribuídos
    // da série ficam marcados automaticamente em CADA ocorrência nova,
    // com a mesma validação de elegibilidade/limite/capacidade de um
    // booking normal (source: manager). A falha de UM membro (deixou
    // de ter o serviço contratado, atingiu o limite semanal) não pode
    // impedir a geração da ocorrência nem a atribuição dos restantes —
    // por isso cada tentativa é isolada e o resultado só entra no
    // resumo devolvido, nunca lança.
    for (const memberId of series.preAssignedMemberIds) {
      const eligibility = await resolveEligibility(series.tenantRef, memberId, series.serviceId);
      if (!eligibility) {
        summary.assignments.skipped += 1;
        continue;
      }
      const result = await runBookingTransaction(firestore, {
        tenantRef: series.tenantRef,
        occurrenceRef: refs[i],
        bookingRef: refs[i].collection('bookings').doc(memberId),
        memberId,
        serviceId: series.serviceId,
        startAt,
        source: 'manager',
        eligibility,
      });
      if (result.kind === 'booked') {
        summary.assignments.assigned += 1;
      } else {
        summary.assignments.skipped += 1;
      }
    }
  }
}

/**
 * Fase 5 (guia-desenvolvimento.md) — "Cloud Function agendada
 * generateRecurringOccurrences: materializa as próximas N semanas a
 * partir das séries ativas. Idempotente (chave determinística por
 * série+data)."
 *
 * `tenantId` omitido: corre para TODOS os tenants (o cron diário,
 * abaixo) via `collectionGroup('sessionSeries')` — precisa do
 * `fieldOverride` declarado em `firestore.indexes.json` (por omissão o
 * Firestore só mantém o índice de campo único ao nível da collection,
 * não do collection group). `tenantId` presente: só esse tenant (o
 * callable manual, abaixo).
 *
 * As DATAS são calculadas em UTC (que dia da semana é), mas a HORA de
 * cada ocorrência é convertida a partir do relógio do estúdio — ver
 * `lib/timeZone.ts`. Antes não era, e no horário de verão todas as
 * aulas de todas as séries apareciam uma hora depois do que o Gestor
 * tinha configurado.
 */
export async function runGenerateRecurringOccurrences(
  tenantId?: string,
): Promise<GenerationSummary> {
  const firestore = getFirestore();
  const now = new Date();
  const summary: GenerationSummary = {
    seriesProcessed: 0,
    occurrencesCreated: 0,
    assignments: { assigned: 0, skipped: 0 },
    publicScheduleEntries: 0,
  };

  const seriesSnap = tenantId
    ? await firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('sessionSeries')
        .where('status', '==', 'active')
        .get()
    : await firestore.collectionGroup('sessionSeries').where('status', '==', 'active').get();

  // O fuso é do estúdio e lê-se uma vez por tenant, não uma vez por
  // série: numa corrida diária com dezenas de séries seriam dezenas de
  // leituras do mesmo documento.
  const timeZoneByTenant = new Map<string, string>();

  // As séries de cada tenant, para a vitrina pública ser reescrita uma
  // vez por tenant e não uma vez por série.
  const seriesByTenant = new Map<
    string,
    { ref: FirebaseFirestore.DocumentReference; series: SeriesData[] }
  >();

  for (const doc of seriesSnap.docs) {
    const series = seriesFromDoc(doc);
    let timeZone = timeZoneByTenant.get(series.tenantRef.path);
    if (timeZone === undefined) {
      timeZone = await tenantTimeZone(series.tenantRef);
      timeZoneByTenant.set(series.tenantRef.path, timeZone);
    }
    await generateForSeries(firestore, series, now, summary, timeZone);
    summary.seriesProcessed += 1;

    const bucket = seriesByTenant.get(series.tenantRef.path);
    if (bucket) {
      bucket.series.push(series);
    } else {
      seriesByTenant.set(series.tenantRef.path, {
        ref: series.tenantRef,
        series: [series],
      });
    }
  }

  // O mapa de aulas que se vê sem conta, derivado das mesmas séries
  // ativas — ver `lib/publicSchedule.ts` sobre porque é derivado e não
  // escrito à mão.
  //
  // Falhar aqui não pode deitar abaixo a geração das aulas, que é o que
  // esta função existe para fazer: uma vitrina desatualizada é um
  // incómodo, um dia sem aulas geradas é um estúdio parado.
  for (const { ref, series } of seriesByTenant.values()) {
    try {
      summary.publicScheduleEntries += await publishPublicSchedule(ref, series);
    } catch (error) {
      console.error('publishPublicSchedule falhou', ref.path, error);
    }
  }

  return summary;
}

export const generateRecurringOccurrences = onSchedule(
  { schedule: 'every day 03:00', timeoutSeconds: 540 },
  async () => {
    const summary = await runGenerateRecurringOccurrences();
    console.log('generateRecurringOccurrences', summary);
  },
);

/**
 * Callable equivalente, restrito ao tenant do chamador. É o caminho
 * principal para testar isto localmente — o Functions Emulator não
 * dispara `onSchedule` por temporizador — e serve também como
 * ferramenta operacional para o Gestor forçar uma geração sem esperar
 * pelo cron diário, mesmo padrão de `recalculateUsage`.
 */
export const generateRecurringOccurrencesNow = onCall(async (request) => {
  const caller = requireManager(request);
  return runGenerateRecurringOccurrences(caller.tenantId);
});
