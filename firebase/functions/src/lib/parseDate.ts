import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Fase 8 (revisão geral) — `Timestamp.fromDate(new Date(input))` estava
 * espalhado por `createMember`/`createStaff`/`updateStaffProfile` com o
 * input validado só como `z.string()`. Com uma data malformada
 * ("ontem", "31/02/2020", ""), `new Date(...)` devolve `Invalid Date` e
 * `Timestamp.fromDate` rebenta com um `RangeError` cru — o cliente
 * recebia `INTERNAL` sem pista nenhuma do que estava errado, em vez do
 * `invalid-argument` que o resto das funções devolve para input mau.
 *
 * Devolve `null` para `undefined`/vazio (o campo é opcional em todos os
 * caminhos) e lança `invalid-argument` para lixo.
 */
export function parseOptionalDate(
  input: string | undefined,
  fieldName: string,
): Timestamp | null {
  if (input === undefined || input.trim() === '') return null;

  const parsed = new Date(input);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError(
      'invalid-argument',
      `\`${fieldName}\` não é uma data válida (recebido: "${input}"). ` +
        'Usa o formato ISO-8601, ex.: "1990-05-17".',
    );
  }
  return Timestamp.fromDate(parsed);
}
