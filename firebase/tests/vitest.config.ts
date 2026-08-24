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
export default defineConfig({
  test: {
    testTimeout: 30_000,
    hookTimeout: 60_000,
    // Ver `globalSetup.ts`: os contadores do rate limiter sobrevivem
    // entre corridas no emulador, e faziam a suite falhar à segunda
    // vez com "Demasiados pedidos em pouco tempo".
    globalSetup: ['./globalSetup.ts'],
  },
});
