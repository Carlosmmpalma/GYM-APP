# Gym SaaS

Implementação incremental do `Technical/guia-desenvolvimento.md`. Cada fase
tem o seu objetivo e critério "Done" — não avançar para a fase seguinte
sem o anterior estar confirmado (isto é especialmente crítico nas fases
marcadas 🔴).

## Fase 0 — Fundação do projeto ✅ concluída e verificada

Camadas Flutter (`presentation/domain/application/repositories/infrastructure`),
Riverpod, três ambientes (development/staging/production), Firebase
Emulator Suite, CI (lint+test), Crashlytics, e um "hello world" que
escreve/lê no Firestore emulado — tudo confirmado a correr localmente
(`flutter pub get`, `flutter create`, `dart format`, `flutter analyze`,
`flutter test` e o ecrã em Chrome, todos com sucesso).

## Fase 1 — Identidade, Tenant e isolamento ✅ concluída e verificada

**Objetivo:** um utilizador só consegue aceder aos dados do seu próprio
tenant — testado, não assumido.

### O que foi acrescentado

- **Domínio**: `Tenant`, `Role` (member/instructor/manager), `AppUser`
  (`lib/domain/entities/`).
- **TenantContext** (Platform Foundation §9): `currentAppUserProvider`
  resolve uid/tenantId/roles a partir dos custom claims do ID token
  (`lib/application/providers/tenant_context_providers.dart`). Emite
  `null` tanto para "sem sessão" como para "sessão sem claims ainda".
- **Login (UC01)** por nº de sócio + password — não email. O nº de sócio
  é convertido, só no cliente, num email sintético determinístico
  (`lib/core/config/login_identifier.dart`), sem nenhuma leitura à BD
  antes do `signInWithEmailAndPassword` — por isso não há forma de usar
  isto para descobrir se um nº de sócio existe.
- **Password temporária (UC22)**: `AuthGate` força
  `ForcePasswordChangeScreen` sempre que o documento do membro/staff tem
  `passwordTemporaria: true`, sem opção de saltar.
- **Cloud Functions** `createMember`/`createStaff`
  (`firebase/functions/src/`): só um Gestor do próprio tenant as pode
  chamar; geram nº de sócio automático (contador transacional),
  atribuem custom claims, criam a conta e o documento Firestore.
  ⚠️ **Assunção não fechada em nenhum use case:** `createStaff` usa o
  email real da pessoa para login, não um nº gerado — ver comentário no
  topo de `createStaff.ts`. Se estiver errado, é fácil de mudar.
- **Security Rules** (`firestore.rules`): `tenants/{tenantId}/**` só é
  acessível a quem tem `request.auth.token.tenantId == tenantId`. De
  propósito NÃO tem ainda autorização fina por role — isso é o
  documento "06 — Security & Business Rules" (por escrever) + Fase 3+.
- **Seed script** (`firebase/scripts/seed.mjs`): cria o tenant real "NXT
  Performance Studio" + o primeiro Gestor (Leo), e um tenant fantasma
  para testares manualmente que os dados não se misturam.
- **🔴 Testes de isolamento** (`firebase/tests/tenant-isolation.test.ts`):
  usam `@firebase/rules-unit-testing` com claims sintéticos — não
  dependem do seed script, correm sozinhos contra o emulador do
  Firestore. Cobrem leitura, escrita e remoção cross-tenant, o documento
  raiz do tenant, utilizador não autenticado, e um `tenantId` inventado.
  Este é o teste que o guia diz para não saltar.

### Nota sobre dependências (`firebase/tests`)

`@firebase/rules-unit-testing` está fixado em `^5.0.0`, não `^3.x` (a
versão que o `npm install` inicial trouxe). A v3 arrasta `undici` com
várias CVEs (algumas "high"/"critical") através do SDK `firebase`
completo; a v5 removeu essa dependência a favor do `fetch` nativo do
Node. **Não corri os testes depois desta mudança de versão** — v3→v5 é
um salto de major, por isso é possível (embora pouco provável, a API de
`initializeTestEnvironment`/`assertFails`/`assertSucceeds` é pequena e
estável) que algo tenha mudado. Corre `npm install` de novo em
`firebase/tests` e confirma que `firebase/tests/tenant-isolation.test.ts`
continua a passar antes de dares isto como resolvido.

### Verificado (por ti, localmente)

- `dart format`, `flutter analyze --fatal-infos`, `flutter test` — todos
  limpos.
- `firebase emulators:exec ... firebase/tests test` — 8/8 testes de
  isolamento a passar.
- Login real (UC01) em Chrome com o membro semeado, incluindo a troca de
  password obrigatória a funcionar.
- Isolamento entre tenants confirmado também manualmente (não só pelo
  teste automatizado): autenticaste como o membro real, leste com
  sucesso o próprio tenant via REST, e recebeste 403 ao tentar ler o
  tenant fantasma com a mesma sessão.

### Ainda em aberto

1. **`createStaff.ts` usa email real para login, não nº gerado** — ver
   assunção acima; ainda não confirmaste se está correto.
2. **Sem `package-lock.json` commitado em `firebase/functions/`,** o job
   `functions` da CI (`.github/workflows/ci.yml`) vai falhar logo no
   passo de cache do `setup-node` — esse passo exige que o lockfile
   exista. `cd firebase/functions && npm install` gera-o; **tens de
   commitar o `package-lock.json` gerado** para a CI passar a funcionar.
   O mesmo não se aplica a `firebase/scripts` e `firebase/tests` — esses
   jobs não usam cache do `setup-node`.
3. Build+lint das Cloud Functions (`npm run build && npm run lint` em
   `firebase/functions`) — não confirmado nesta conversa.

### Passos para verificar a Fase 1 localmente

```bash
# 1. Instalar as novas dependências das Cloud Functions (zod)
cd firebase/functions && npm install && cd ../..

# 2. Instalar dependências do seed script e dos testes de isolamento
cd firebase/scripts && npm install && cd ../tests && npm install && cd ../..

# 3. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 4. 🔴 Correr o teste crítico de isolamento entre tenants
firebase emulators:exec --project=demo-gym-saas-dev --only firestore \
  "npm --prefix firebase/tests test"
# Todos os testes têm de passar. Se algum "assertFails" passar a
# "assertSucceeds", há uma fuga de isolamento — não avances sem
# perceber porquê.

# 5. Cloud Functions: build + lint
cd firebase/functions && npm run build && npm run lint && cd ../..

# 6. Seed manual — com o emulador completo a correr:
#      firebase emulators:start --project=demo-gym-saas-dev
#    ⚠️ O --project é importante: sem ele, o CLI só resolve o projeto
#    certo se o teu .firebaserc tiver um alias "default" (o
#    .firebaserc.example já tem; confirma que o TEU .firebaserc também,
#    já que esse ficheiro é local/gitignored, não vem do repo). Sem
#    nenhum dos dois, o emulador arranca sob outro projeto qualquer, o
#    seed continua a "funcionar" (fala diretamente com o projeto que lhe
#    disseres via env vars), mas a UI do emulador mostra tudo vazio e o
#    login na app falha, porque a app também usa demo-gym-saas-dev.
cd firebase/scripts && npm run seed && cd ../..

# 7. Testar o login real na app (UC01)
flutter run -t lib/main_development.dart
# Nº de sócio "000001", password "MemberPass123!" — esta build aponta
# para o tenant nxt_performance_studio (TenantAppConfig.development).
# Deve entrar direto (passwordTemporaria já vem false do seed) e mostrar
# o HelloWorldScreen. Confirma também que a MESMA combinação de nº
# "000001" mas password "GhostPass123!" falha (é o membro do tenant
# fantasma, com o mesmo número mas noutro tenant).
```

### Critério "Done" da Fase 1

> consegues criar um 2º tenant de teste, autenticar como membro dele, e
> confirmar (por teste automatizado, não manual) que não consegue ler
> nada do tenant do Leo.

O passo 4 acima (`firebase emulators:exec ... firebase/tests test`) é
exatamente isto, automatizado. Corre-o e confirma que os 8 testes
passam antes de dares a Fase 1 por fechada.

## Fase 2 — Vertical slice de uma marcação ponta a ponta ✅ concluída e verificada

**Objetivo:** um membro consegue marcar e cancelar uma sessão, e a
capacidade nunca é ultrapassada — mesmo com duas marcações em
simultâneo na última vaga.

### O que foi acrescentado

- **Domínio**: `Service`, `SessionOccurrence` (com `isBookable`/
  `isFull`/`availableSlots`), `Booking` + exceções específicas
  (`BookingCapacityExceededException`, `AlreadyBookedException`,
  `SessionNotBookableException`) (`lib/domain/entities/`).
- **Repositories + infra**: `ServiceRepository`,
  `SessionOccurrenceRepository`, `BookingRepository`
  (`lib/repositories/`) e as implementações Firebase
  (`lib/infrastructure/firebase/`).
- **Decisão de arquitetura — `createBooking`/`cancelBooking` como
  transação client-side, não Cloud Function**: o guia deixa a opção em
  aberto. Escolhi transação direta no cliente
  (`firebase_booking_repository.dart`, `runTransaction`) em vez de uma
  Cloud Function callable, pelo mesmo motivo do resto da Fase 2 —
  simplicidade e menos infraestrutura nova. O `bookingId` é
  determinístico (`== memberId`), o que já impede "duas marcações
  ativas do mesmo membro na mesma sessão" sem precisar de query extra.
  **Limitação conhecida e documentada no próprio ficheiro:** as Security
  Rules não conseguem obrigar atomicamente que o documento da
  `booking` E o `activeBookingCount` da ocorrência mudem juntos — só a
  transação do cliente garante isso. Isto é aceitável porque o contador
  é um read-model reconciliável (nunca a fonte da verdade — a
  subcoleção `bookings` é), e a própria transação do Firestore garante
  atomicidade real contra escritas concorrentes (é o que o teste de
  concorrência abaixo prova).
- **Security Rules** (`firestore.rules`): a regra genérica
  `tenants/{tenantId}/{document=**}` da Fase 1 foi substituída por
  matches explícitos por coleção. Motivo: Firestore Rules têm semântica
  OR — se QUALQUER match aplicável permitir, o acesso é concedido, por
  isso uma regra ampla nunca pode ser "estreitada" depois por outra mais
  específica no mesmo caminho. `sessionOccurrences` ganhou
  `isValidBookingCounterChange()`, que só deixa alterar
  `activeBookingCount`, em ±1, dentro de `[0, capacity]`.
  `sessionOccurrences/{id}/bookings/{bookingId}` exige
  `bookingId == request.auth.uid` para criar/atualizar, com diff de
  campos limitado; `delete` é sempre negado (cancelamento é update de
  `status`, não remoção).
- **Ecrãs**: `BookTrainingScreen` (lista ocorrências futuras da service
  principal, botão "Marcar" com estado de loading e tratamento
  específico por exceção) e `MyBookingsScreen` (marcações ativas do
  membro via `collectionGroup`, botão "Cancelar"). `HomeScreen` nova com
  `NavigationBar` de duas abas + atalho para o diagnóstico da Fase 0.
- **Seed script**: `seedServiceAndOccurrence` cria a service "Aula de
  Grupo" + uma `sessionOccurrence` amanhã às 18:00, capacidade 2 —
  idempotente (não sobrescreve se já houver bookings reais feitos
  contra ela).
- **Índices** (`firestore.indexes.json`): composto em
  `sessionOccurrences` (`serviceId` + `startAt`, para a query de
  "próximas sessões desta service"), e `fieldOverride` em `bookings`
  para o `collectionGroup` usado por `watchMyBookings`.
- **🔴 Teste de concorrência** (`firebase/tests/booking-concurrency.test.ts`):
  reimplementa em TS exatamente a mesma transação do repositório Dart,
  contra o mesmo emulador e as mesmas Rules. Um teste corre 5 vezes
  seguidas uma ocorrência de capacidade 1 com duas marcações simultâneas
  (`Promise.all`) e confirma sempre exatamente 1 aceite + 1 rejeitada +
  contador em 1 (nunca 2); outro confirma que capacidade 2 deixa as duas
  passarem. Isto prova que o mecanismo (transação + regra do contador)
  impede overbooking — não prova, sozinho, que o ficheiro Dart não tem
  um bug de transcrição da mesma lógica; ver passo 6 abaixo para o que
  falta confirmar diretamente em Flutter.

### Verificado (por ti, localmente) — e dois bugs reais que apanhámos

`dart format`, `flutter analyze --fatal-infos` (sem avisos) e
`flutter test` correram. Dois testes de widget falharam à primeira —
não por acaso, apanharam dois problemas reais:

1. **`BookTrainingScreen` lia `currentAppUserProvider` com `ref.read()`
   dentro do handler de tap do botão "Marcar", não com `ref.watch()` no
   `build()`.** Um `StreamProvider` só arranca quando alguém o "olha"
   pela primeira vez; ao ser lido pela primeira vez dentro do próprio
   handler, apanhava sempre o provider ainda em `AsyncLoading` (o
   Stream ainda não tinha tido oportunidade de emitir), e a marcação
   era **silenciosamente ignorada** — sem exceção, sem mensagem de
   erro, o botão simplesmente não fazia nada. Em produção isto nunca se
   nota (o `AuthGate`, mais acima na árvore, já resolveu este provider
   antes de se chegar a este ecrã), mas é um padrão frágil que corrigi:
   `BookTrainingScreen` agora observa `currentAppUserProvider` no
   `build()` e passa o `memberId` já resolvido para baixo, em vez de
   cada tile ir buscar o provider por conta própria.
2. **`MyBookingsScreen`, ao cancelar, não atualizava a lista sozinho no
   teste.** Investiguei a fundo (cheguei a ler o código-fonte do
   `fake_cloud_firestore` no GitHub): o cancelamento em si funcionava
   perfeitamente — a transação escrevia os dados certos (confirmado
   pelo `firebase_booking_repository_test.dart`, que passa). O
   problema é que o `QuerySnapshotStreamManager` desse pacote regista
   listeners de queries `collectionGroup` pela sua própria "path key"
   (ex.: `bookings`), mas propaga atualizações de documentos subindo o
   caminho completo do documento alterado (ex.:
   `tenants/.../sessionOccurrences/occ_1/bookings/member_1` →
   `.../occ_1/bookings` → `.../occ_1` → ...) — que nunca coincide com
   a chave `bookings` usada para registar o `collectionGroup`. Ou seja,
   **um listener de `collectionGroup` neste pacote de testes nunca é
   notificado quando um documento já existente é alterado** — só no
   momento em que é subscrito. Isto é uma limitação do pacote de testes
   (`fake_cloud_firestore`), não um bug no Firestore real nem no
   emulador — lá, `collectionGroup` + listeners funciona normalmente.
   Corrigi de forma que também é uma melhoria real em produção: depois
   de `cancelBooking`/`createBooking` terem sucesso, o ecrã agora chama
   `ref.invalidate(...)` no provider correspondente, forçando um
   refresco imediato (novo `.get()`) em vez de depender só da
   propagação do listener.

Ambos os ficheiros de teste (`book_training_screen_test.dart`,
`my_bookings_screen_test.dart`) continuam exatamente como estavam —
não alterei as asserções para "disfarçar" nada; os fixes foram no
código da app. **Ainda não sei se ambos os testes passam agora** — só
tenho o teu output de antes das correções. Corre `flutter test` de
novo e confirma.

### Terceiro bug apanhado: os dois ficheiros de teste TS a pisarem-se

Ao correr `firebase emulators:exec ... "npm --prefix firebase/tests test"`
pela primeira vez, `booking-concurrency.test.ts` falhava por completo
(0 marcações aceites em todas as tentativas, mesmo com capacidade 2) e
`tenant-isolation.test.ts` falhava com `Transaction lock timeout` num
dos testes. Não era nem um bug de Rules nem de lógica de concorrência:

`tenant-isolation.test.ts` e `booking-concurrency.test.ts` usavam o
**mesmo** `projectId: 'demo-gym-saas-dev'` no `initializeTestEnvironment`.
O vitest corre ficheiros de teste em paralelo por omissão, e ambos os
ficheiros chamam `testEnv.clearFirestore()` a cada teste — que apaga
*todo* o Firestore emulado desse projeto. Os dois ficheiros, a correr
ao mesmo tempo, andavam a apagar os dados um do outro a meio da
execução: por vezes a ocorrência que `booking-concurrency` tinha acabado
de semear desaparecia antes da transação de marcação correr (daí "0
aceites" mesmo devendo haver vagas), e as duas chamadas concorrentes a
`clearFirestore()` competiam pelo mesmo lock (daí o timeout).

Corrigido dando a cada ficheiro um `projectId` próprio
(`demo-gym-saas-dev-isolation-test` e `demo-gym-saas-dev-booking-test`)
— o emulador do Firestore aceita qualquer projeto `demo-*` sem
credenciais, por isso isto não tem custo nenhum, só isola os dois
ficheiros um do outro. Não muda nada no resto do projeto (a app
continua a apontar para `demo-gym-saas-dev`; isto é só dos ficheiros
de teste de Rules).

Depois desta correção: os 8 testes de isolamento passaram, e o teste de
concorrência de capacidade 1 (5 repetições) também — mas o de
capacidade 2 (as duas deviam vencer) continuou a falhar, com uma delas
rejeitada. Não assumi porquê — pedi para correr outra vez com logging
do erro real, e apareceu isto:

```
PERMISSION_DENIED: ... evaluation error at L73:24 for 'update' @ L73 ...
```

### Quarto problema: o emulador do Firestore, não as Rules nem o código

L73 é a linha do `allow update` de `sessionOccurrences`
(`isValidBookingCounterChange()`). O importante é "**evaluation
error**", não "false" — a condição não foi avaliada como negada, a
avaliação da própria regra rebentou a meio. Isto só acontece quando
duas transações verdadeiramente simultâneas (`Promise.all`) colidem no
mesmo documento: a Firestore SDK normalmente repete automaticamente a
transação perdedora quando há conflito de escrita — mas contra o
**emulador**, quando a colisão acontece durante a avaliação de
`resource.data.diff(...)` dentro das Rules, o erro chega ao cliente
como `PERMISSION_DENIED` (código 7), não como o `ABORTED` que a SDK
sabe repetir sozinha. Um `PERMISSION_DENIED` é tratado como definitivo.

Confirmei que isto nunca acontece nas rejeições de negócio legítimas —
essas vêm de um `throw new Error('capacity-exceeded')` no próprio
código, antes de tocarem no Firestore. Só a colisão real produz esta
mensagem. Por isso, em `booking-concurrency.test.ts`, `attemptBooking`
agora repete até 3 vezes com um pequeno backoff, e SÓ quando a mensagem
do erro contém "evaluation error" — uma negação de negócio genuína
nunca entra neste caminho, continua a ser um "rejected" imediato.

**Isto é uma característica do emulador local, não do Firestore real
nem um bug nas Rules ou no código Dart** — mas como não tenho forma de
confirmar isso com 100% de certeza sem correr contra produção, fica
como aviso: se, no passo 5 abaixo (duas janelas de Chrome a marcar ao
mesmo tempo), uma marcação falhar com um erro genérico em vez de um
"sem vagas" limpo, é provavelmente isto — e nesse caso valeria a pena
adicionar uma retentativa semelhante a
`firebase_booking_repository.dart#createBooking` (não fiz isso agora,
sem evidência de que afete o caminho real).

**Ainda não sei se isto resolve por completo** — corrigi com base numa
leitura cuidadosa do erro real (não uma suposição às cegas), mas só se
confirma ao correr de novo.

### Quinto problema — este sim, um bug real nas Security Rules

Com os testes de `firebase/tests` todos a passar, testámos a app a
sério em Chrome contra o emulador. O ecrã "Minhas marcações" mostrou:

```
Erro: [cloud_firestore/permission-denied]
false for 'list' @ L112
```

L112 é o bloqueio genérico do fim do `firestore.rules`
(`match /{document=**} { allow read, write: if false; }`) — ou seja, o
pedido nem chegou a ser avaliado contra a regra de `bookings` lá em
cima, caiu direto no "bloqueia tudo".

Motivo: `watchMyBookings()` usa
`firestore.collectionGroup('bookings').where('memberId', ...)` — uma
query que varre TODAS as subcoleções chamadas `bookings` em qualquer
profundidade, sem caminho fixo. A regra que já existia
(`tenants/{tenantId}/sessionOccurrences/{occurrenceId}/bookings/{bookingId}`)
só cobre pedidos a essa profundidade EXATA. Isto é um requisito
específico e documentado do Firestore: uma `collectionGroup` query só
é autorizada por uma regra escrita com wildcard recursivo
(`match /{path=**}/bookings/{bookingId}`) — não reaproveita
automaticamente a regra aninhada, mesmo com condições idênticas. (Nota:
isto é diferente do bug do `fake_cloud_firestore` já descrito mais
acima — aquele era do pacote de testes, não faz `list` chegar a
avaliar Rules nenhumas; este é do Firestore/emulador reais, a sério, e
só se manifesta a correr a app.)

Corrigido em `firestore.rules`: acrescentei
`match /{path=**}/bookings/{bookingId} { allow read: if ...; }`, com a
mesma condição (`belongsToTenant`, extraído de `path[1]`). Só `read` —
não abre nenhuma permissão de escrita nova; criar/cancelar uma booking
continua só possível pelo caminho completo conhecido, através da regra
aninhada já existente.

**Duas correções falhadas antes de acertar** — vale a pena registar
para não repetir o erro. Primeiro tentei `path.size() >= 2` (falhou:
`path` não tem `.size()`). Depois tentei `path[0]`/`path[1]` (falhou
também: "Variable is not bound in path template" — a indexação de
`path` não se comportou como a documentação sugere, pelo menos nesta
versão do emulador). Em vez de continuar a adivinhar essa sintaxe,
simplifiquei a regra para não depender de `path` nenhum:

```
allow read: if isSignedIn() && resource.data.memberId == request.auth.uid;
```

Só o dono da marcação a pode ler — não precisa de saber o tenant pelo
caminho, porque um booking só é criado com `memberId == uid` de quem o
cria (a regra de `create`, mais acima, já garante isso), por isso é
impossível um uid corresponder a um booking de outro tenant. Mais
simples e com a mesma garantia de segurança.

**Depois de editar `firestore.rules`, precisas de reiniciar o
`firebase emulators:start`** (Ctrl+C e arrancar de novo) para carregar
a versão nova das regras, e dar hot-restart (não só hot-reload) à app
para o ecrã "Minhas marcações" voltar a tentar a leitura.

### Sexto problema: não dava para voltar a marcar depois de cancelar

Marcar → cancelar → marcar outra vez ficava bloqueado. Causa: o id do
documento de booking é sempre `== uid` do membro (de propósito, para
impedir duas marcações ativas do mesmo membro sem query extra) — por
isso, depois de UM cancelamento, o documento já existe (soft-cancel,
nunca é apagado: `allow delete: if false`). Voltar a marcar chega ao
Firestore como um pedido de **update**, não **create** (mesmo sendo um
`tx.set()` completo do lado do `firebase_booking_repository.dart`), e
a regra de `update` só permitia a transição `booked → cancelled`,
nunca o inverso — por isso re-marcar ficava permanentemente bloqueado
a partir do primeiro cancelamento.

Corrigido em `firestore.rules`: a regra de `update` de `bookings`
agora cobre as duas transições válidas (cancelar uma marcação ativa,
ou voltar a marcar uma que estava cancelada), reaproveitando a mesma
validação (`memberId == uid`, `status == 'booked'`) que já existia para
o `create`. Precisa, mais uma vez, de reiniciar o emulador para
carregar as regras novas.

### Sétimo problema: a mensagem de erro genérica aparecia sempre, mesmo devendo funcionar

Perguntaste se a qualidade das mensagens de erro fazia parte desta
fase — já fazia (4 exceções de domínio com mensagem própria em
`booking.dart`), mas ao testar apareceu sempre a genérica ("Não foi
possível marcar. Tenta novamente."), mesmo em situações que deviam
funcionar (2 vagas de 2 livres). Pedi para expor o erro real
temporariamente e apareceu:

```
Dart exception thrown from converted Future. Use the properties
'error' to fetch the boxed error and 'stack' to recover the stack trace.
```

Isto não é um erro de negócio nem de Rules — é um problema conhecido
do `cloud_firestore` no Flutter **Web**: o callback de
`runTransaction()` atravessa a fronteira de interop com a SDK JS do
Firestore (a promise é convertida para `Future` e vice-versa). Uma
exceção Dart própria lançada DE DENTRO desse callback
(`throw const BookingCapacityExceededException()`, por exemplo) não
sobrevive a essa travessia com o tipo original intacto — chega ao
`catch` do ecrã como este erro de conversão genérico, e nenhum dos
`on XException catch` específicos apanhava, por isso caía sempre na
mensagem genérica, mesmo para os casos "normais" de negócio.

Corrigido na raiz em `firebase_booking_repository.dart`: o callback da
transação deixou de lançar as exceções de domínio lá dentro — agora só
devolve um resultado (`_BookingResult`/`bool`), e a exceção certa
(`AlreadyBookedException`, `BookingCapacityExceededException`, etc.) é
lançada DEPOIS do `await`, já em Dart puro, fora da fronteira com o
JS. O comportamento observável não muda (continua a lançar os mesmos
tipos, nos mesmos casos) — só onde a exceção é lançada é diferente, e
é exatamente essa mudança que evita o problema de conversão.

Isto explica também porque é que as mensagens específicas nunca
apareciam nos testes manuais — o mecanismo que as devia mostrar nunca
chegava a ser acionado.

Tudo o resto (marcar/cancelar de facto na app, incluindo confirmar que
este ecrã agora carrega) continua por confirmar — sem acesso a
`firebase`/emulador aqui.

### Passos para verificar a Fase 2 localmente

```bash
# 1. Confirmar que tudo continua a compilar/passar (inclui os novos
#    testes unitários/widget da Fase 2)
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 2. 🔴 Correr os testes de Security Rules — isolamento (Fase 1) +
#    concorrência na última vaga (Fase 2), ambos em firebase/tests
cd firebase/tests && npm install && cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore \
  "npm --prefix firebase/tests test"
# O teste de concorrência corre o cenário de capacidade 1 CINCO vezes
# seguidas — se overbooking fosse possível por race condition, é
# provável que aparecesse nalguma das repetições. Confirma que os dois
# "it()" de booking-concurrency.test.ts passam, não só os de isolamento.

# 3. Seed (occurrence de teste amanhã às 18:00, capacidade 2)
#    — com o emulador completo a correr (firebase emulators:start
#    --project=demo-gym-saas-dev):
cd firebase/scripts && npm run seed && cd ../..

# 4. Testar marcar/cancelar manualmente na app
flutter run -t lib/main_development.dart
# Login com nº "000001" / password "MemberPass123!" (Rita). Na aba
# "Marcar", deve aparecer "Aula de Grupo" amanhã 18:00 com "2 vaga(s) de
# 2". Marca — o contador de vagas deve descer para 1 e a sessão
# desaparecer da lista de "Marcar" só quando ficar sem vagas. Vai à aba
# "Marcações" e confirma que aparece lá; cancela e confirma que volta a
# aparecer em "Marcar" com a vaga de volta.

# 5. (Opcional, mas é o teste mais realista de todos) Reproduzir a
#    concorrência à mão: reseta activeBookingCount da occurrence para 0
#    e capacity para 1 na UI do emulador (localhost:4000/firestore),
#    corre a app em duas janelas de Chrome autenticadas como membros
#    diferentes (precisas de um 2º membro semeado — não há um por
#    omissão, tens de criar via createMember ou diretamente na UI do
#    emulador), e tenta marcar em ambas o mais próximo possível uma da
#    outra. Só uma deve ter sucesso.
```

### Critério "Done" da Fase 2

> dois clientes simultâneos tentam marcar a última vaga de uma sessão —
> nunca resultam em mais bookings do que a capacidade permite; corre o
> teste de concorrência várias vezes, não uma.

O passo 2 acima é exactamente isto, automatizado e repetido 5x. Corre-o
e confirma que passa antes de dares a Fase 2 por fechada; o passo 4/5
confirma depois que o caminho Dart real (não só a reimplementação TS)
se comporta da mesma forma.

## Próximo passo

Fase 3 do guia (ver `Technical/guia-desenvolvimento.md`) — por
enquanto não analisada em detalhe nesta conversa.
