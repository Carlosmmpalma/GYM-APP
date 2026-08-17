import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';

import { requireManager } from './lib/callerContext';
import { parseOptionalDate } from './lib/parseDate';

const inputSchema = z.object({
  staffId: z.string().min(1),
  name: z.string().min(1),
  email: z.string().email(),
  phone: z.string().optional(),
  birthDate: z.string().optional(),
  address: z.string().optional(),
  nif: z.string().optional(),
  emergencyContact: z.string().optional(),
});

/**
 * Pedido pelo Carlo depois de testar "Criar utilizador": até aqui,
 * `StaffDetailScreen` não tinha NENHUMA forma de editar nome/email/
 * dados pessoais depois da criação — só o toggle ativo/inativo e as
 * modalidades. Ao contrário de `MemberRepository.updateMemberProfile`
 * (escrita direta do cliente — o email do membro é só contacto, nunca
 * o login), aqui o `email` É o login real (Firebase Auth, decisão
 * fechada da Fase 3). Por isso isto tem de ser Cloud Function (Admin
 * SDK): se o Gestor mudar o email, `auth.updateUser` atualiza também a
 * credencial de login, para nunca divergir do que fica em
 * `staff/{id}.email` — editar só o Firestore deixaria o staff a tentar
 * entrar com um email que já não bate certo com o Firestore.
 */
export const updateStaffProfile = onCall(async (request) => {
  const caller = requireManager(request);

  const parsed = inputSchema.safeParse(request.data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.message);
  }
  const { staffId, name, email, phone, birthDate, address, nif, emergencyContact } = parsed.data;

  const firestore = getFirestore();
  const auth = getAuth();
  const staffRef = firestore
    .collection('tenants')
    .doc(caller.tenantId)
    .collection('staff')
    .doc(staffId);

  const snap = await staffRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Este membro de staff já não existe.');
  }
  const current = snap.data() as { name?: string; email?: string };

  // Fase 8 (revisão geral) — validado ANTES de tocar no Auth. A ordem
  // aqui é `auth.updateUser` (que muda a CREDENCIAL DE LOGIN) e só
  // depois o Firestore; com a data validada apenas no momento da
  // escrita, uma data malformada rebentava DEPOIS de o email de login
  // já ter mudado — o staff ficava a não conseguir entrar com o email
  // antigo, e `staff/{id}.email` continuava a mostrar esse email
  // antigo ao Gestor, sem sinal nenhum de que estavam dessincronizados.
  const birthTimestamp = parseOptionalDate(birthDate, 'birthDate');

  const authUpdate: { email?: string; displayName?: string } = {};
  if (email !== current.email) authUpdate.email = email;
  if (name !== current.name) authUpdate.displayName = name;

  if (Object.keys(authUpdate).length > 0) {
    try {
      await auth.updateUser(staffId, authUpdate);
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'Já existe outra conta com este email.');
      }
      throw error;
    }
  }

  await staffRef.update({
    name,
    email,
    phone: phone ?? '',
    birthDate: birthTimestamp,
    address: address ?? '',
    nif: nif ?? '',
    emergencyContact: emergencyContact ?? '',
  });

  return { updated: true };
});
