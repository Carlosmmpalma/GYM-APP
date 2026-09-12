import { defineConfig } from 'vitest/config';

// Estes testes falam com o Firebase Emulator Suite a sério — não há
// mocks nenhuns. Uma chamada a uma Cloud Function em arranque a frio,
// com todos os ficheiros a correr em paralelo contra um emulador de
// funções que serializa arranques, passa facilmente dos 5 segundos que
// o vitest dá por omissão.
//
// Isto apanhou-me: `gdpr.test.ts` e `manager-powers.test.ts` passavam
// sozinhos e falhavam na suite completa, com "Test timed out in
// 5000ms" — o que parece contaminação entre testes e é só lentidão. Os
// ficheiros mais antigos resolviam-no com um timeout por teste
// (`}, 30_000)`); esta configuração trata o problema de uma vez, para
// o próximo ficheiro não voltar a tropeçar no mesmo.
//
// `hookTimeout` é maior porque os `beforeAll` semeiam dados e criam
// utilizadores no Auth antes de qualquer teste correr.
//
// Subiu de 30 para 60 segundos quando a suite passou dos 340 testes,
// pelo mesmo sintoma: `extra-session-usage.test.ts` passava sozinho e
// estourava na suite completa.
//
// ## `maxThreads`, e porque subir o timeout era a resposta errada
//
// O mesmo ficheiro voltou a estourar, agora aos 60 segundos — passando
// sozinho em 1,4 s. Subir para 90 seria a terceira vez a perseguir a
// mesma causa, e o timeout deixaria de significar seja o que for.
//
// A causa nunca foi o tempo: são 32 ficheiros a disputar UM emulador de
// funções, que serializa invocações. Numa máquina de 16 núcleos o
// vitest lançava até 16 ficheiros ao mesmo tempo contra uma fila de um.
// Medido, a suite inteira:
//
//   maxThreads | tempo em testes | relógio de parede
//   -----------|-----------------|------------------
//        2     |      65 s       |     45,3 s
//        4     |    70–79 s      |    26–30 s
//        8     |     126 s       |     28,9 s
//       16     |     127 s       |     23,4 s
//
// A coluna que decide é a do meio. De 8 para cima cada teste passa
// quase o DOBRO do tempo à espera da fila — e é essa espera, não o
// trabalho, que empurra um ficheiro para lá dos 60 segundos. O relógio
// de parede engana: 16 chega a parecer o mais rápido porque sobrepõe as
// esperas, e é exatamente essa sobreposição que produz a
// intermitência.
//
// Com 4: seis corridas seguidas verdes, e a mais rápida de sempre.
//
// O `testTimeout` fica nos 60 segundos — deixou de ser um alvo a
// roçar e voltou a ser o que devia: a rede que apanha um teste que
// NUNCA acaba.
//
// Nota para quem vier medir isto: eu creditei esta correção ao
// `maxAttempts` das transações de marcação, que tinha mexido na mesma
// ronda. Passou uma vez, dei por resolvido, e falhou logo a seguir. As
// duas coisas eram reais e independentes — ver `bookingLogic.ts`.
export default defineConfig({
  test: {
    // `minThreads` tem de vir junto: por omissão iguala o número de
    // núcleos, e o tinypool recusa-se a arrancar com mínimo acima do
    // máximo ("options.minThreads and options.maxThreads must not
    // conflict") — sem correr um único teste, e com "no tests" como
    // resultado, que é fácil de ler como sucesso.
    poolOptions: { threads: { minThreads: 1, maxThreads: 4 } },
    testTimeout: 60_000,
    hookTimeout: 60_000,
    // Ver `globalSetup.ts`: os contadores do rate limiter sobrevivem
    // entre corridas no emulador, e faziam a suite falhar à segunda
    // vez com "Demasiados pedidos em pouco tempo".
    globalSetup: ['./globalSetup.ts'],
  },
});
