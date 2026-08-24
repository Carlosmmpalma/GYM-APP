import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  /** Janela para taxas (ocupação e faltas). */
  windowDays: z.number().int().min(7).max(180).optional(),
  /** Sem presença há mais do que isto = em risco. */
  riskWeeks: z.number().int().min(1).max(26).optional(),
});

/**
 * Fase 11 — painel de retenção do Gestor.
 *
 * Num ginásio de proximidade, quem desaparece não cancela: deixa de
 * aparecer, continua a pagar dois ou três meses, e só depois cancela.
 * Nessa altura já não há conversa possível. O sinal existia nos dados
 * desde a Fase 6 (presenças e faltas), mas não havia nenhum ecrã que o
 * lesse — só se via presença aula a aula, olhando uma de cada vez.
 *
 * Três números e uma lista, que é o que o Gestor consegue mesmo usar:
 *  - **ocupação** — as aulas estão a encher? decide horário e capacidade;
 *  - **taxa de faltas** — marcam e não aparecem? decide a política de
 *    cancelamento e a lista de espera;
 *  - **quem não aparece há X semanas** — a única lista que se traduz
 *    diretamente numa ação (ligar, mandar mensagem), e por isso a que
 *    ocupa mais espaço no ecrã.
 *
 * A lista de risco só inclui quem TEM subscrição ativa: quem já não
 * tem plano não está em risco de sair, já saiu. Contar essas pessoas
 * inflacionava o número e enterrava as que ainda dá para recuperar.
 *
 * **Custo.** Percorre as ocorrências da janela e lê a subcoleção de
 * presenças de cada uma — para um estúdio (poucas centenas de sessões
 * por mês) é um punhado de leituras por abertura do painel, e evita
 * denormalizar contadores em todo o lado. Se o volume crescer, o passo
 * seguinte é um agregado escrito por uma função agendada; até lá isto
 * é mais simples e nunca fica dessincronizado.
 */
export const getRetentionOverview =
    onCall({ timeoutSeconds: 120 }, async (request) => {
  const caller = requireManager(request);
  // Esta é a função mais cara do projeto: percorre as sessões do mês e
  // lê as presenças de cada uma. Um ecrã com um bug de refrescamento,
  // ou alguém a carregar no "atualizar" em ciclo, custa leituras a
  // sério. O teto é generoso para uso humano e absurdo para um ciclo.
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'getRetentionOverview',
    maxCalls: 60,
    windowSeconds: 60,
  });
  const { windowDays = 30, riskWeeks = 3 } = parseInput(inputSchema, 
    request.data ?? {},
  );

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  const now = new Date();
  const riskDays = riskWeeks * 7;
  const scanDays = Math.max(windowDays, riskDays);
  const scanFrom = new Date(now.getTime() - scanDays * 86_400_000);
  const windowFrom = new Date(now.getTime() - windowDays * 86_400_000);

  // Só sessões que JÁ COMEÇARAM: uma aula de amanhã com duas marcações
  // não é uma aula com 20% de ocupação, é uma aula que ainda não
  // aconteceu. Incluí-la puxava todas as taxas para baixo.
  const occurrencesSnap = await tenantRef
    .collection('sessionOccurrences')
    .where('startAt', '>=', scanFrom)
    .where('startAt', '<=', now)
    .get();

  let sessions = 0;
  let capacitySum = 0;
  let bookedSum = 0;

  let recorded = 0;
  let attended = 0;
  let noShows = 0;

  /** memberId → instante da última presença conhecida na janela. */
  const lastAttendance = new Map<string, Date>();

  // Em lotes: um estúdio com aulas de hora a hora tem centenas de
  // ocorrências no mês, e disparar tudo de uma vez esgota as ligações.
  const CHUNK = 20;
  for (let i = 0; i < occurrencesSnap.docs.length; i += CHUNK) {
    const chunk = occurrencesSnap.docs.slice(i, i + CHUNK);
    const attendanceSnaps = await Promise.all(
      chunk.map((doc) => doc.ref.collection('attendance').get()),
    );

    chunk.forEach((occurrence, index) => {
      const startAt = (
        occurrence.get('startAt') as FirebaseFirestore.Timestamp
      ).toDate();
      const cancelled = (occurrence.get('status') as string) === 'cancelled';

      // Ocupação e faltas contam-se só na janela pedida; o resto do
      // intervalo lido serve apenas para saber quem apareceu.
      const inWindow = startAt >= windowFrom;
      if (inWindow && !cancelled) {
        sessions += 1;
        capacitySum += (occurrence.get('capacity') as number) ?? 0;
        bookedSum += (occurrence.get('activeBookingCount') as number) ?? 0;
      }

      for (const doc of attendanceSnaps[index].docs) {
        const memberId = (doc.get('memberId') as string) ?? doc.id;
        const isAttended = (doc.get('status') as string) === 'attended';

        if (inWindow) {
          recorded += 1;
          if (isAttended) attended += 1;
          else noShows += 1;
        }

        if (isAttended) {
          const previous = lastAttendance.get(memberId);
          if (!previous || startAt > previous) {
            lastAttendance.set(memberId, startAt);
          }
        }
      }
    });
  }

  // Quem tem plano ativo — ver docstring sobre porquê só estes.
  const subscriptionsSnap = await tenantRef
    .collection('subscriptions')
    .where('status', '==', 'active')
    .get();
  const withActivePlan = new Set(
    subscriptionsSnap.docs.map((doc) => doc.get('memberId') as string),
  );

  const membersSnap = await tenantRef
    .collection('members')
    .where('status', '==', 'active')
    .get();

  const riskCutoff = new Date(now.getTime() - riskDays * 86_400_000);
  const atRisk = membersSnap.docs
    .filter((doc) => withActivePlan.has(doc.id))
    .map((doc) => {
      const last = lastAttendance.get(doc.id) ?? null;
      return {
        memberId: doc.id,
        name: (doc.get('name') as string) ?? '',
        memberNumber: (doc.get('memberNumber') as string) ?? '',
        lastAttendanceAt: last ? last.toISOString() : null,
      };
    })
    .filter((member) => {
      const last = member.lastAttendanceAt
        ? new Date(member.lastAttendanceAt)
        : null;
      return last == null || last < riskCutoff;
    })
    // Sem presença nenhuma primeiro (é o caso mais grave), depois do
    // mais antigo para o mais recente.
    .sort((a, b) => {
      if (a.lastAttendanceAt == null && b.lastAttendanceAt == null) {
        return a.name.localeCompare(b.name, 'pt');
      }
      if (a.lastAttendanceAt == null) return -1;
      if (b.lastAttendanceAt == null) return 1;
      return a.lastAttendanceAt.localeCompare(b.lastAttendanceAt);
    });

  return {
    windowDays,
    riskWeeks,
    // `scanDays` diz até onde se procurou presença: uma pessoa sem
    // presença nenhuma pode ter vindo antes disso, e o ecrã tem de
    // poder dizer "sem presença nos últimos N dias" em vez de "nunca
    // veio", que seria mentira.
    scanDays,
    membersWithActivePlan: membersSnap.docs.filter((doc) =>
      withActivePlan.has(doc.id),
    ).length,
    occupancy: {
      sessions,
      capacity: capacitySum,
      booked: bookedSum,
      ratePercent: capacitySum > 0
        ? Math.round((bookedSum / capacitySum) * 100)
        : null,
    },
    attendance: {
      recorded,
      attended,
      noShows,
      noShowRatePercent: recorded > 0
        ? Math.round((noShows / recorded) * 100)
        : null,
    },
    atRisk,
  };
});
