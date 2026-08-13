import { randomBytes } from 'crypto';

/**
 * Password temporária inicial (UC22: "válida só até à primeira troca").
 * Não é mostrada a ninguém pela app — é devolvida uma única vez na
 * resposta da Cloud Function para o Gestor comunicar ao novo
 * membro/staff fora da app (SMS/papel/verbalmente), conforme o processo
 * do estúdio.
 */
export function generateTemporaryPassword(): string {
  return randomBytes(9).toString('base64url'); // 12 chars, sem ambiguidade
}
