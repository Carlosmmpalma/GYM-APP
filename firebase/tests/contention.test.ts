// Contenção: "agora não" tem de soar diferente de "não".
//
// Marcações da mesma aula disputam o documento onde vive o contador de
// lugares. Quando muita gente marca ao mesmo tempo, a transação pode
// desistir — e essa desistência subia daqui como uma exceção qualquer,
// que o Firebase embrulha em `internal`. Ao aluno chegava uma mensagem
// genérica de erro numa aula que ainda podia ter lugares, e ninguém
// tenta outra vez depois de um erro genérico.

import { describe, expect, it } from 'vitest';

import { isContentionError } from '../functions/src/lib/bookingLogic';

describe('isContentionError', () => {
  it('reconhece os códigos numéricos do Firestore', () => {
    // 10 = ABORTED (alguém mexeu no documento entre a leitura e a
    // escrita), 4 = DEADLINE_EXCEEDED (passou o tempo a tentar).
    expect(isContentionError({ code: 10 })).toBe(true);
    expect(isContentionError({ code: 4 })).toBe(true);
  });

  it('reconhece os códigos por nome', () => {
    expect(isContentionError({ code: 'aborted' })).toBe(true);
    expect(isContentionError({ code: 'deadline-exceeded' })).toBe(true);
  });

  it('reconhece a mensagem quando não há código', () => {
    expect(
      isContentionError(new Error('Transaction failed: too much contention')),
    ).toBe(true);
  });

  it('NÃO confunde uma recusa de negócio com contenção', () => {
    // Isto é o que importa não errar: dizer "tenta outra vez" a quem não
    // tem plano manda a pessoa bater na mesma porta para sempre.
    expect(isContentionError({ code: 7 })).toBe(false);
    expect(isContentionError({ code: 'permission-denied' })).toBe(false);
    expect(isContentionError({ code: 'resource-exhausted' })).toBe(false);
    expect(isContentionError(new Error('Já não há vagas'))).toBe(false);
  });

  it('não rebenta com o que não é um erro', () => {
    expect(isContentionError(null)).toBe(false);
    expect(isContentionError(undefined)).toBe(false);
    expect(isContentionError('texto')).toBe(false);
  });
});
