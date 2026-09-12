import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

/** Um URL que o telemóvel consegue mesmo abrir. */
const httpUrl = z
  .string()
  .trim()
  .max(500)
  .refine(
    (value) =>
      value === '' || /^https?:\/\/.+/i.test(value),
    { message: 'O endereço tem de começar por http:// ou https://' },
  );

const inputSchema = z.object({
  address: z.string().trim().max(300),
  phone: z.string().trim().max(40),
  email: z.string().trim().max(200),
  mapsUrl: httpUrl,
  privacyPolicyUrl: httpUrl,
  openingHours: z
    .array(
      z.object({
        days: z.string().trim().max(60),
        hours: z.string().trim().max(60),
      }),
    )
    .max(7),
});

/**
 * A informação pública do estúdio: morada, contactos, horário de
 * funcionamento e a política de privacidade.
 *
 * ## Porque é uma Cloud Function e não escrita direta
 *
 * `tenants/{t}/public/{doc}` é o único caminho desta base de dados que
 * se lê **sem sessão nenhuma** — existe para a vitrina, o ecrã que a app
 * mostra a quem ainda não é membro. A regra fecha a escrita a toda a
 * gente, incluindo ao Gestor, e é de propósito: um documento público com
 * escrita direta do cliente é um convite a pôr lá o que não devia.
 *
 * Passando por aqui, há um sítio só onde validar o que é escrito — e a
 * validação que interessa não é de segurança, é de não deixar o Gestor
 * publicar um botão partido: um "URL" sem esquema abre uma página em
 * branco, e um campo de 10 000 caracteres rebenta o ecrã de quem o vê.
 *
 * ## Porque isto não vive na configuração da build
 *
 * Viveu, durante meia tarde. Estava lá com o argumento de que tem de
 * aparecer antes de haver sessão — o que é verdade, mas deixou de ser um
 * impedimento assim que a vitrina passou a ler de um caminho público.
 *
 * E na config era pior por uma razão que não se vê no código: mudar o
 * número de telefone do estúdio obrigava a um developer, uma build nova
 * e uma revisão da App Store. Um Gestor tem de conseguir mudar a morada
 * do próprio ginásio.
 *
 * ## Campos vazios
 *
 * São válidos e significam "não mostrar". A app esconde o que está
 * vazio em vez de desenhar um espaço em branco; o que garante que não
 * fica tudo vazio para sempre é o aviso no ecrã de gestão, não uma
 * recusa aqui — bloquear o Gestor de guardar a morada enquanto não tiver
 * o horário todo seria pior do que deixá-lo fazer uma coisa de cada vez.
 */
export const updateStudioInfo = onCall(async (request) => {
  const caller = requireManager(request);
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'updateStudioInfo',
    maxCalls: 30,
    windowSeconds: 60,
  });

  const input = parseInput(inputSchema, request.data ?? {});

  // Uma linha só conta se tiver HORAS. O ecrã de gestão sugere os dias
  // da semana pré-preenchidos, por isso "Sábado" com a hora em branco é
  // o caso normal de quem fecha ao fim de semana — e guardá-lo punha na
  // vitrina um dia seguido de nada, que se lê como um erro.
  const openingHours = input.openingHours.filter(
    (linha) => linha.hours !== '',
  );

  await getFirestore()
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('public')
    .doc('info')
    .set(
      {
        ...input,
        openingHours,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: caller.uid,
      },
      { merge: true },
    );

  return { ok: true, openingHours: openingHours.length };
});
