import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager, requireManagerOrInstructor } from './lib/callerContext';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  kind: z.enum([
    'service',
    'plan',
    'modality',
    'exercise',
    'series',
    'staff',
    'occurrence',
  ]),
  id: z.string().min(1),
});

/**
 * Elimina uma entrada do catálogo do estúdio — serviço, plano ou
 * modalidade — mas só quando nada a referencia.
 *
 * ## Porque é que isto não existia
 *
 * A regra até aqui era "nunca eliminar, só desativar", e a razão é boa:
 * um plano eliminado deixa as subscriptions que apontam para ele sem
 * nome nem preço, e o histórico financeiro do membro passa a mostrar
 * ids em vez de "Aulas de Grupo — 44,90 €". O mesmo para um serviço com
 * aulas passadas.
 *
 * Mas a regra estava a ser aplicada a tudo, incluindo ao caso que
 * acontece mais vezes na vida real: alguém cria um serviço com o nome
 * errado, ou um plano em duplicado, dá-se conta no minuto seguinte, e
 * fica com ele para sempre. Desativar não resolve — continua nas
 * listas de gestão, continua a confundir, e a única saída era pedir a
 * um programador.
 *
 * ## O que isto faz em vez disso
 *
 * Conta as referências primeiro. Se houver alguma, RECUSA e diz quais
 * são — em português, com números — para o Gestor perceber que o que
 * quer é desativar, não eliminar. Se não houver nenhuma, elimina.
 *
 * A contagem corre no servidor e não no cliente por dois motivos:
 * é a única forma de a recusa ser uma garantia e não uma sugestão da
 * UI, e algumas destas coleções (subscriptions, ocorrências) não são
 * coisas que faça sentido carregar inteiras para o telemóvel de alguém
 * só para desenhar um botão.
 *
 * ## O que fica de fora, e porquê
 *
 * Membros têm caminho próprio (`deleteMemberData`): apagar alguém é
 * matéria de RGPD, com exportação, anonimização de registos com
 * retenção fiscal e confirmação pelo número de sócio. Nada disso cabe
 * aqui.
 *
 * Aulas concretas e blocos de treino livre também não: aí a condição é
 * "não ter ninguém inscrito", e isso as Security Rules conseguem
 * garantir sozinhas (`activeBookingCount == 0`), sem gastar uma
 * chamada de função.
 */
export const deleteCatalogueEntry = onCall(async (request) => {
  const { kind, id } = parseInput(inputSchema, request.data);

  // A biblioteca de exercícios é partilhada e o Instrutor já a pode
  // criar e editar (`firestore.rules`); poder eliminar da mesma é
  // coerente. Tudo o resto — o que se vende, quem dá aulas — continua
  // exclusivo do Gestor.
  const caller = kind === 'exercise' ? requireManagerOrInstructor(request) : requireManager(request);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  const collection = {
    service: 'services',
    plan: 'plans',
    modality: 'modalities',
    exercise: 'exercises',
    series: 'sessionSeries',
    staff: 'staff',
    occurrence: 'sessionOccurrences',
  }[kind];
  const docRef = tenantRef.collection(collection).doc(id);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    throw new HttpsError('not-found', 'Já não existe — alguém pode tê-lo eliminado entretanto.');
  }

  // Uma referência chega para recusar, mas contamo-las todas: dizer
  // "3 aulas e 12 subscrições" poupa ao Gestor descobrir o problema
  // seguinte só depois de resolver o primeiro.
  const blockers: string[] = [];

  // `count()` em vez de `get()`: uma agregação é faturada como uma
  // leitura por cada mil documentos, enquanto trazer os documentos para
  // os contar são leituras a sério. Nenhuma destas contagens precisa do
  // conteúdo.
  async function count(
    query: FirebaseFirestore.Query,
    describe: (n: number) => string,
  ): Promise<void> {
    const result = await query.count().get();
    const total = result.data().count;
    if (total > 0) blockers.push(describe(total));
  }

  if (kind === 'service') {
    await count(tenantRef.collection('sessionSeries').where('serviceId', '==', id), (n) => `${n} série(s) de aulas`);
    await count(tenantRef.collection('sessionOccurrences').where('serviceId', '==', id), (n) => `${n} aula(s) marcadas ou já realizadas`);
    await count(
      tenantRef.collection('subscriptions').where('activeServiceIds', 'array-contains', id),
      (n) => `${n} subscrição(ões) de membros`);
    // Um `collectionGroup('services')` seria mais curto mas atravessa
    // TENANTS — e `services` é ao mesmo tempo coleção de topo e
    // subcoleção de `plans`, o que tornaria o resultado ambíguo. Os
    // planos de um estúdio são poucos e o id do documento na subcoleção
    // é o próprio `serviceId`, por isso isto é um `getAll` exato.
    const plans = await tenantRef.collection('plans').get();
    if (plans.size > 0) {
      const planServiceDocs = await firestore.getAll(
        ...plans.docs.map((plan) => plan.ref.collection('services').doc(id)),
      );
      const including = planServiceDocs.filter((doc) => doc.exists).length;
      if (including > 0) blockers.push(`${including} plano(s) que o incluem`);
    }
    await count(tenantRef.collection('modalities').where('serviceIds', 'array-contains', id), (n) => `${n} modalidade(s)`);
    await count(tenantRef.collection('staff').where('serviceIds', 'array-contains', id), (n) => `${n} instrutor(es) com este serviço atribuído`);

    // O serviço de treino livre não é referenciado por nenhuma query
    // acima — vive num campo de configuração. Eliminá-lo deixava o
    // treino livre a apontar para o vazio, sem nada a dizer porquê.
    const policy = await tenantRef.collection('config').doc('bookingPolicy').get();
    if (policy.exists && policy.data()?.freeTrainingServiceId === id) {
      blockers.push('a definição de serviço de treino livre');
    }
  }

  if (kind === 'plan') {
    await count(tenantRef.collection('subscriptions').where('planId', '==', id), (n) => `${n} subscrição(ões) de membros`);
  }

  if (kind === 'exercise') {
    // As prescrições e o histórico de cargas vivem em subcoleções de
    // CADA membro, por isso a contagem tem de ser por grupo de coleção
    // — daí os `fieldOverrides` novos em `firestore.indexes.json`.
    //
    // Um grupo de coleção atravessa tenants, e aqui isso importa a
    // sério: sem o filtro, um exercício com o mesmo id noutro ginásio
    // bloqueava a eliminação neste. Como os ids são gerados pelo
    // Firestore a colisão é improvável, mas "improvável" não é
    // "impossível" e o seed usa ids fixos (`ex_agachamento_barra`),
    // que são iguais em todos os estúdios. O filtro por caminho
    // resolve.
    const prefix = `tenants/${caller.tenantId}/members/`;
    const inThisTenant = (docs: FirebaseFirestore.QueryDocumentSnapshot[]) =>
      docs.filter((doc) => doc.ref.path.startsWith(prefix)).length;

    const entries = await firestore
      .collectionGroup('planEntries')
      .where('exerciseId', '==', id)
      .get();
    const prescribed = inThisTenant(entries.docs);
    if (prescribed > 0) blockers.push(`${prescribed} prescrição(ões) em planos de alunos`);

    const history = await firestore
      .collectionGroup('loadHistory')
      .where('exerciseId', '==', id)
      .get();
    const recorded = inThisTenant(history.docs);
    if (recorded > 0) blockers.push(`${recorded} registo(s) de carga no histórico`);
  }

  if (kind === 'series') {
    // Uma série gera ocorrências, e são elas que têm marcações. Apagar
    // a série deixava-as sem origem — e a app mostra "parte da série
    // X" em cada uma.
    await count(
      tenantRef.collection('sessionOccurrences').where('seriesId', '==', id),
      (n) => `${n} aula(s) já geradas por esta série`,
    );
  }

  if (kind === 'staff') {
    if (id === caller.uid) {
      throw new HttpsError(
        'failed-precondition',
        'Não te podes eliminar a ti próprio — ficarias sem forma de entrar.',
      );
    }
    await count(tenantRef.collection('sessionSeries').where('instructorId', '==', id), (n) =>
      `${n} série(s) de aulas`,
    );
    await count(tenantRef.collection('sessionOccurrences').where('instructorId', '==', id), (n) =>
      `${n} aula(s) marcadas ou já realizadas`,
    );
  }

  if (kind === 'occurrence') {
    // Uma aula sem ninguém inscrito é o caso "criei por engano". Com
    // inscritos, o caminho é `cancelOccurrenceForStudio`, que liberta
    // as marcações e devolve as utilizações — apagar saltava tudo isso.
    const active = (snapshot.get('activeBookingCount') as number | undefined) ?? 0;
    if (active > 0) {
      blockers.push(`${active} aluno(s) inscritos`);
    }

    // Aulas geradas por uma série têm id determinístico
    // (`{seriesId}_{data}`): o cron da noite recria-as com o mesmo id, e
    // apagá-las é trabalho que se desfaz sozinho — pior, faria
    // reaparecer as marcações antigas agarradas à aula nova. Para essas,
    // cancelar é a operação certa; eliminar a SÉRIE é a outra.
    if (snapshot.get('seriesId') != null) {
      blockers.push('a série que a gera (voltaria a ser criada esta noite)');
    }
  }

  if (kind === 'modality') {
    await count(tenantRef.collection('sessionSeries').where('modalityId', '==', id), (n) => `${n} série(s) de aulas`);
    await count(tenantRef.collection('sessionOccurrences').where('modalityId', '==', id), (n) => `${n} aula(s) marcadas ou já realizadas`);
    await count(tenantRef.collection('staff').where('modalityIds', 'array-contains', id), (n) => `${n} instrutor(es) com esta modalidade atribuída`);
  }

  if (blockers.length > 0) {
    throw new HttpsError(
      'failed-precondition',
      'Não dá para eliminar: há coisas que dependem disto. ' +
        'Desativar mantém o histórico intacto e tira-o das listas de escolha.',
      { blockers },
    );
  }

  // Um plano guarda os serviços que concede numa subcoleção. Apagar só
  // o documento deixava-a órfã — invisível na consola, e a renascer
  // com os mesmos dados se alguém voltasse a criar um plano com o
  // mesmo id.
  if (kind === 'plan') {
    const planServices = await docRef.collection('services').get();
    if (!planServices.empty) {
      const batch = firestore.batch();
      for (const doc of planServices.docs) batch.delete(doc.ref);
      await batch.commit();
    }
  }

  // O staff tem dados pessoais numa subcoleção `private` e uma conta de
  // autenticação. Apagar só o documento deixava a conta a conseguir
  // entrar numa app onde já não existe perfil nenhum.
  if (kind === 'staff') {
    const privateDocs = await docRef.collection('private').get();
    if (!privateDocs.empty) {
      const batch = firestore.batch();
      for (const doc of privateDocs.docs) batch.delete(doc.ref);
      await batch.commit();
    }
  }

  // As subcoleções não desaparecem com o documento pai — ficariam
  // invisíveis na consola e voltavam a aparecer se algo recriasse o
  // documento com o mesmo id. `bookings` e `waitlist` são `write:
  // false` nas Rules, por isso isto só se pode fazer aqui.
  if (kind === 'occurrence') {
    await firestore.recursiveDelete(docRef);
    return { deleted: true };
  }

  await docRef.delete();

  // Depois do documento, nunca antes: uma falha a meio não pode deixar
  // uma conta capaz de autenticar-se sem perfil. Mesmo raciocínio de
  // `deleteMemberData.ts`.
  if (kind === 'staff') {
    await getAuth()
      .deleteUser(id)
      .catch(() => undefined);
  }

  return { deleted: true };
});
