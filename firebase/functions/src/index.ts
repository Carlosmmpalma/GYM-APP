import { initializeApp } from 'firebase-admin/app';
import { setGlobalOptions } from 'firebase-functions/v2/options';

initializeApp();

// Fase 11 — região e teto de instâncias, para TODAS as funções.
//
// **Região.** Por omissão as Cloud Functions v2 nascem em
// `us-central1` (Iowa), enquanto o Firestore vai ficar em
// `europe-west1` (ver LANCAMENTO.md — decisão tomada por causa do RGPD
// e da latência a partir de Portugal). Sem isto, cada marcação feita
// num telemóvel em Lisboa viaja até ao Iowa, e a função atravessa o
// Atlântico OUTRA VEZ a cada leitura/escrita da transação. Uma
// transação de booking faz várias — o custo em latência multiplica-se,
// e ainda se paga tráfego entre regiões.
//
// É sensível ao tempo: uma função já implantada **não muda de região**.
// A migração obriga a apagar e recriar, com janela de indisponibilidade.
// Fazer isto antes do primeiro deploy custa uma linha; depois, custa
// uma manutenção.
//
// **`maxInstances`.** No plano Blaze não há teto por omissão: um ciclo
// infinito num cliente, ou um pico inesperado, escala até onde a conta
// aguentar. 10 instâncias servem folgadamente um estúdio (cada uma
// aguenta pedidos concorrentes) e transformam um bug caro num bug
// lento, que é o lado certo para errar.
setGlobalOptions({
  region: 'europe-west1',
  maxInstances: 10,
});

// Estas funções percorrem um número de documentos que cresce com o
// ginásio, uma transação de cada vez. Com o tempo-limite por omissão
// (60 segundos) um estúdio grande podia vê-las MORRER a meio: metade
// das sessões canceladas, metade não — e nada a dizer que ficou assim.
// Nenhuma delas é interativa ao ponto de alguém estar à espera com o
// dedo no ecrã.
// Por isso levam `timeoutSeconds` explícito, uma a uma, em vez de um
// valor global: o teto por omissão é a proteção certa para tudo o
// resto, e uma marcação que demore 60 segundos é um bug, não um
// caso a acomodar.

// Fase 10 — saiu daqui o `healthCheck` da Fase 0. Era um `onCall` SEM
// guard nenhum (a única função do projeto assim) que devolvia o
// `GCLOUD_PROJECT` a quem o chamasse — em produção, um endpoint público
// a dizer o id do projeto. Servia para provar que a base de Cloud
// Functions compilava e corria; hoje há 19 funções reais a prová-lo, e
// nenhum cliente o chamava.

// Fase 1 — Identidade, Tenant e isolamento.
export { createMember } from './createMember';
export { createStaff } from './createStaff';

// Fase 3 — Planos, serviços e subscriptions.
export { createSubscription } from './createSubscription';
export { deleteCatalogueEntry } from './deleteCatalogueEntry';
export { resizeAvatar, clearAvatarOnDelete } from './resizeAvatar';

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

// Varredura de funcionalidades — mudar a hora de uma aula era uma
// escrita direta do cliente que só tocava no documento da aula. As
// marcações guardam uma cópia da data e a semana em que foram contadas,
// e o limite semanal vive num documento por semana: mover uma aula para
// outra semana deixava a utilização na semana errada e devolvia ao aluno
// a semana de destino inteira.
export { updateOccurrenceSchedule } from './updateOccurrenceSchedule';
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

// Fase 11 — RGPD. A app trata dados de saúde (avaliações físicas:
// pressão arterial, massa gorda, gordura visceral), que o artigo 9.º
// coloca numa categoria especial: exigem consentimento EXPLÍCITO, e o
// artigo 7.º, n.º 1 exige poder demonstrá-lo. `recordConsent` é a única
// via de escrita desse registo — as Security Rules não deixam o cliente
// tocar no campo `consent`, senão o timestamp da prova seria escolhido
// por quem consente.
export { recordConsent } from './recordConsent';
// Artigos 15.º/20.º (acesso e portabilidade) e 17.º (apagamento).
export { exportMemberData } from './exportMemberData';
export { deleteMemberData } from './deleteMemberData';

// Fase 11 — poderes do Gestor. Cada uma destas fechou um caso em que
// operar o ginásio obrigava a chamar um developer: repor a password de
// quem se esqueceu, mexer no estado de uma subscrição (sem isto, trocar
// um aluno de nível de plano era impossível dentro da app — ver
// `updateSubscriptionStatus.ts`), e promover/despromover staff.
export { resetUserPassword } from './resetUserPassword';
export { updateSubscriptionStatus } from './updateSubscriptionStatus';
export { updateStaffRoles } from './updateStaffRoles';

// Fase 11 (bug reportado) — acrescentar um serviço a um plano não fazia
// nada a quem já tinha esse plano: `activeServiceIds` era uma cópia
// tirada na criação da subscrição e nunca mais atualizada. Ver
// `syncPlanSubscriptions.ts`.
export { syncPlanSubscriptions } from './syncPlanSubscriptions';

// Preparação para as lojas — a informação pública do estúdio (morada,
// contactos, horário, política de privacidade), que alimenta a vitrina
// que a app mostra a quem ainda não tem conta. Vive num caminho que se
// lê sem sessão, e por isso a escrita passa por aqui e não pelo cliente.
export { updateStudioInfo } from './updateStudioInfo';

// Fase 11 — lista de espera. A app impõe capacidade por desenho, logo
// aulas cheias são o normal; sem fila, um cancelamento deixava um lugar
// vazio que ninguém sabia que existia. A promoção acontece dentro de
// `cancelBooking` (ver `lib/waitlist.ts`), não é chamada pelo cliente.
export { joinWaitlist, leaveWaitlist } from './waitlist';

// Fase 11 — lembrete antes da aula. A falta sem aviso é o custo real
// de um estúdio com capacidade limitada: o lugar ficou ocupado e
// ninguém o pôde usar. O lembrete serve tanto para quem vem confirmar
// como para quem já não pode vir cancelar a tempo — libertando o lugar
// para a lista de espera. Ver `lib/reminders.ts`.
export {
  sendSessionReminders,
  sendSessionRemindersNow,
} from './sendSessionReminders';

// Fase 11 — painel de retenção. Num ginásio de proximidade quem
// desaparece não cancela: deixa de aparecer e só cancela meses depois,
// quando já não há conversa possível. O sinal existia nos dados desde
// a Fase 6 (presenças) mas não havia ecrã que o lesse.
export { getRetentionOverview } from './getRetentionOverview';

// Fase 11 (última ronda) — abrir mais vagas numa aula cheia puxa a
// lista de espera. A promoção automática só existia no cancelamento;
// o caso mais comum no estúdio é o instrutor decidir que "cabem mais
// dois", e esses dois lugares ficavam vazios com gente na fila.
export { onOccurrenceCapacityChanged } from './onOccurrenceCapacityChanged';
