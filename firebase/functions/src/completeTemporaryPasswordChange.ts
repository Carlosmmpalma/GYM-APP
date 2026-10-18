import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireAuthenticated } from './lib/callerContext';
import { enforceRateLimit } from './lib/rateLimit';
import { parseInput } from './lib/validation';

const inputSchema = z.object({
  newPassword: z.string().min(8).max(128),
});

/**
 * UC22 — a pessoa define a sua password definitiva, no primeiro login.
 *
 * ## O ciclo que isto fecha
 *
 * O ecrã `ForcePasswordChangeScreen` fazia duas chamadas do cliente:
 *
 *     await authRepository.updatePassword(novaPassword);       // passava
 *     await accountRepository.clearTemporaryPasswordFlag(user); // NÃO passava
 *
 * A segunda é uma escrita direta em `members/{uid}` ou `staff/{uid}`, e
 * as Rules só deixam o próprio mexer numa lista curta de campos:
 * `fcmTokens` no staff, mais `phone`/`email`/`updatedAt` nos membros.
 * `passwordTemporaria` não está em nenhuma das duas.
 *
 * Resultado: a password MUDAVA mesmo no Firebase Auth, a flag ficava
 * `true`, e o `AuthGate` mandava a pessoa de volta ao mesmo ecrã. Um
 * ciclo fechado, sem forma de entrar na app. E como mudar a password
 * invalida o token, às vezes nem chegava ao ecrã — caía no login, onde
 * a password antiga já não servia.
 *
 * Afetava Instrutores e Alunos. O Gestor escapava por bater no
 * `allow write: if isManager(tenantId)` — que é exatamente o tipo de
 * bug que não aparece a quem testa com a conta de administração.
 *
 * ## Porque é uma função e não duas linhas nas Rules
 *
 * Acrescentar `passwordTemporaria` às listas de `hasOnly` resolvia o
 * sintoma e deixava a flag ao alcance de qualquer cliente: bastava
 * escrevê-la a `false` para saltar a troca obrigatória e continuar com
 * a password temporária, que é precisamente o que o UC22 existe para
 * impedir.
 *
 * Aqui, as duas coisas acontecem do mesmo lado: ou a password muda E a
 * flag é limpa, ou não muda nenhuma. A flag deixa de ser uma afirmação
 * em que é preciso confiar e passa a ser consequência.
 *
 * ## A ordem importa
 *
 * A password primeiro. Se a limpeza da flag falhar a seguir, a pessoa
 * fica com a password nova e volta a ver o ecrã uma vez — chato, mas
 * recuperável, porque a troca é idempotente. Ao contrário: flag limpa
 * e password por mudar deixava a conta com a temporária para sempre e
 * sem nada a lembrá-la disso.
 */
export const completeTemporaryPasswordChange = onCall(async (request) => {
  const caller = requireAuthenticated(request);
  const { newPassword } = parseInput(inputSchema, request.data);

  // Trocar a password é operação de uma vez por sessão, não de repetir.
  // O limite serve contra uso automatizado da função, não contra a
  // pessoa que se enganou a escrever.
  await enforceRateLimit({
    uid: caller.uid,
    operation: 'completeTemporaryPasswordChange',
    maxCalls: 10,
    windowSeconds: 3600,
  });

  try {
    await getAuth().updateUser(caller.uid, { password: newPassword });
  } catch (err) {
    // O Firebase recusa passwords fracas e tem as suas próprias regras
    // além do mínimo de 8 que validamos acima. A mensagem dele é mais
    // útil do que uma nossa genérica.
    throw new HttpsError(
      'invalid-argument',
      err instanceof Error ? err.message : 'Não foi possível definir a password.',
    );
  }

  // A pessoa pode ter documento em `members`, em `staff`, ou nos dois
  // (um instrutor que também treina no estúdio). A flag é limpa onde
  // existir — deixar uma para trás repõe o ciclo.
  const firestore = getFirestore();
  const tenantRef = firestore.collection('tenants').doc(caller.tenantId);
  const refs = [
    tenantRef.collection('members').doc(caller.uid),
    tenantRef.collection('staff').doc(caller.uid),
  ];

  const snaps = await firestore.getAll(...refs);
  const existentes = snaps.filter((snap) => snap.exists);
  if (existentes.length === 0) {
    // Autenticado, com tenant no token, e sem documento em lado nenhum.
    // A password já mudou; dizer que correu bem seria mentir, porque a
    // próxima entrada volta a cair no mesmo ecrã.
    throw new HttpsError(
      'failed-precondition',
      'A tua conta não está associada a nenhum perfil neste estúdio. '
        + 'Fala com o gestor.',
    );
  }

  const batch = firestore.batch();
  for (const snap of existentes) {
    batch.update(snap.ref, { passwordTemporaria: false });
  }
  await batch.commit();

  return { cleared: existentes.length };
});
