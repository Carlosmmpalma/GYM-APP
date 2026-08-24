import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  kind: z.enum(['service', 'plan', 'modality']),
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
 * ## O que NÃO cobre
 *
 * Exercícios da biblioteca. As referências (`planEntries`,
 * `loadHistory`) vivem em subcoleções de cada membro e a contagem
 * exigiria índices de grupo de coleção novos — fica assinalado, não
 * escondido. A biblioteca já permite editar um exercício, que é o que
 * resolve o caso comum de "escrevi o nome errado".
 */
export const deleteCatalogueEntry = onCall(async (request) => {
  const caller = requireManager(request);
  const { kind, id } = parseInput(inputSchema, request.data);

  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);

  const collection = { service: 'services', plan: 'plans', modality: 'modalities' }[kind];
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

  await docRef.delete();
  return { deleted: true };
});
