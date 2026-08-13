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

1. ~~`createStaff.ts` usa email real para login, não nº gerado —
   ainda não confirmaste se está correto.~~ **Confirmado pelo Carlos
   (Fase 3):** staff usa mesmo só o email, decisão fechada. Não é um
   erro por corrigir — a assunção estava certa.
2. **Sem `package-lock.json` commitado em `firebase/functions/`,** o job
   `functions` da CI (`.github/workflows/ci.yml`) vai falhar logo no
   passo de cache do `setup-node` — esse passo exige que o lockfile
   exista. `cd firebase/functions && npm install` gera-o; **tens de
   commitar o `package-lock.json` gerado** para a CI passar a funcionar.
   O mesmo não se aplica a `firebase/scripts` e `firebase/tests` — esses
   jobs não usam cache do `setup-node`.
3. ~~Build+lint das Cloud Functions — não confirmado nesta
   conversa.~~ **Atualização (Fase 3):** confirmado, e revelou um bug
   real que estava aqui desde o início — `createMember.ts`/
   `createStaff.ts` usavam uma API do `firebase-admin` que não existe
   na versão instalada (`^14.2.0`). Ver "Oitavo problema" na secção da
   Fase 3 para o diagnóstico e a correção.

### Passos para verificar a Fase 1 localmente

Comandos em PowerShell — sem `&&`/`\` de continuação de linha (isso é
sintaxe bash); cada passo é uma sequência de linhas separadas.

```powershell
# 1. Instalar as novas dependências das Cloud Functions (zod)
cd firebase/functions
npm install
cd ../..

# 2. Instalar dependências do seed script e dos testes de isolamento
cd firebase/scripts
npm install
cd ../tests
npm install
cd ../..

# 3. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 4. 🔴 Correr o teste crítico de isolamento entre tenants
firebase emulators:exec --project=demo-gym-saas-dev --only firestore "npm --prefix firebase/tests test"
# Todos os testes têm de passar. Se algum "assertFails" passar a
# "assertSucceeds", há uma fuga de isolamento — não avances sem
# perceber porquê.

# 5. Cloud Functions: build + lint
cd firebase/functions
npm run build
npm run lint
cd ../..

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
cd firebase/scripts
npm run seed
cd ../..

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

```powershell
# 1. Confirmar que tudo continua a compilar/passar (inclui os novos
#    testes unitários/widget da Fase 2)
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 2. 🔴 Correr os testes de Security Rules — isolamento (Fase 1) +
#    concorrência na última vaga (Fase 2), ambos em firebase/tests
cd firebase/tests
npm install
cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore "npm --prefix firebase/tests test"
# O teste de concorrência corre o cenário de capacidade 1 CINCO vezes
# seguidas — se overbooking fosse possível por race condition, é
# provável que aparecesse nalguma das repetições. Confirma que os dois
# "it()" de booking-concurrency.test.ts passam, não só os de isolamento.

# 3. Seed (occurrence de teste amanhã às 18:00, capacidade 2)
#    — com o emulador completo a correr (firebase emulators:start
#    --project=demo-gym-saas-dev):
cd firebase/scripts
npm run seed
cd ../..

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

O passo 2 acima é exactamente isto, automatizado e repetido 5x — **e
confirmado**, tal como o resto do critério: isolamento (8/8), booking/
cancelamento/re-booking na app real contra o emulador em Chrome, tudo
verificado por ti, não só por mim.

### Resumo dos 7 bugs reais apanhados a fechar esta fase

Fica aqui só a lista, para referência rápida — o raciocínio completo de
cada um está nas secções acima:

1. `BookTrainingScreen` lia o utilizador atual com `ref.read()` dentro
   do handler do botão, não `ref.watch()` no `build()` — marcação
   ignorada em silêncio nalguns testes.
2. `MyBookingsScreen` não atualizava sozinha depois de cancelar no
   teste (limitação do `fake_cloud_firestore` com `collectionGroup`,
   não da app) — resolvido com `ref.invalidate(...)` depois de
   mutações.
3. `tenant-isolation.test.ts` e `booking-concurrency.test.ts`
   partilhavam o mesmo `projectId`, e o vitest corre-os em paralelo —
   `clearFirestore()` de um apagava os dados do outro a meio.
4. Erro transitório do motor de Rules do **emulador** sob transações
   verdadeiramente simultâneas (`evaluation error`, não `false`) —
   mitigado com retry limitado no teste, não é um bug do código real.
5. Faltava uma regra de Rules dedicada (`{path=**}`) para autorizar a
   query `collectionGroup('bookings')` — sem ela, caía sempre no
   bloqueio genérico do fim do ficheiro.
6. A regra de `update` de bookings só permitia `booked → cancelled`,
   nunca o inverso — impossível voltar a marcar depois de cancelar.
7. Exceções de domínio lançadas de dentro do callback de
   `runTransaction()` perdiam o tipo ao atravessar o interop JS do
   Flutter Web — a UI caía sempre na mensagem de erro genérica, mesmo
   nos casos "normais". Resolvido devolvendo um resultado do callback
   e lançando a exceção certa só depois, em Dart puro.

## Fase 3 — Planos, serviços e subscriptions

**Objetivo:** um membro só consegue marcar-se num serviço se tiver uma
subscription ativa que lhe dê acesso a esse serviço; um Gestor consegue
criar Planos, definir que Services cada Plano inclui (com a respetiva
regra de utilização), e atribuir um Plano a um membro.

### O que foi acrescentado

- **Domínio**: `UsageRule` (unlimited/limited com `limit`+`period`),
  `Plan`, `PlanService` (a relação Plan↔Service, com a `UsageRule`
  específica dessa combinação — Domain Model v1 §12/13), `Subscription`
  (com `activeServiceIds` denormalizado, `agreedPrice` separado do
  `currentPrice` do Plan, e `grantsAccessTo(serviceId)`), e duas
  exceções: `NotEligibleForServiceException` (bloqueia o booking) e
  `SubscriptionServiceConflictException` (bloqueia criar uma
  subscription a conflitar com outra já ativa) (`lib/domain/entities/`).
- **Repositories + infra**: `PlanRepository`/`SubscriptionRepository`/
  `MemberRepository` (`lib/repositories/`) e as implementações Firebase
  (`lib/infrastructure/firebase/`). `MemberRepository` é novo nesta
  fase — não existia nenhum repositório de listagem de membros antes,
  precisava dele para o picker do ecrã de atribuição.
- **Decisão de arquitetura — `createSubscription` como Cloud Function,
  ao contrário de `createBooking`/`cancelBooking` (Fase 2, que são
  transação client-side)**: a regra "um membro não pode ter duas
  subscriptions ativas que dão acesso ao mesmo serviço" (Domain Model
  v1 §15) precisa de examinar TODAS as subscriptions ativas existentes
  do membro — um número variável de documentos, não uma comparação
  dentro de UM documento como o contador de vagas da Fase 2. Não há
  forma direta de exprimir "nenhum documento nesta subcoleção
  interseta X" em Security Rules sem repetir a mesma lógica em `get()`s
  dentro da própria regra — frágil e caro. Uma Cloud Function com Admin
  SDK faz essa validação em código normal (`firebase/functions/src/
  createSubscription.ts`, mesmo padrão de `createMember`/`createStaff`
  da Fase 1): confirma que o membro e o Plan existem e estão ativos,
  lê os `PlanService` ativados desse Plan, cruza com
  `activeServiceIds` de todas as subscriptions ativas já existentes do
  membro, e só se não houver interseção escreve a nova subscription —
  com `activeServiceIds` calculado a partir dos `PlanService`
  ativados, para a leitura de elegibilidade não precisar de nenhum
  `join` depois.
- **Elegibilidade no booking (UC06/07/08/09)**:
  `BookSessionUseCase` (`lib/application/use_cases/
  book_session_use_case.dart`) passou a receber também o
  `SubscriptionRepository`, e chama `isEligibleForService(memberId,
  serviceId)` ANTES de sequer tentar a transação de booking da Fase 2
  — lança `NotEligibleForServiceException` sem tocar no Firestore de
  bookings se o membro não tiver acesso. `isEligibleForService` é uma
  query direta (`memberId == X && status == 'active' &&
  activeServiceIds array-contains serviceId`, `limit(1)`) — daí os dois
  índices compostos novos em `firestore.indexes.json`.
  `BookTrainingScreen` ganhou um `on NotEligibleForServiceException
  catch` com mensagem própria, distinta de "sem vagas"/"já marcado".
- **Security Rules** (`firestore.rules`): nova função `isManager(tenantId)`
  (`belongsToTenant(tenantId) && 'manager' in
  request.auth.token.roles` — mesmo formato de custom claims que
  `requireManager()` usa nas Cloud Functions). `plans` e
  `plans/{id}/services`: leitura ampla dentro do tenant, escrita só
  Manager (ao contrário de `subscriptions`, isto é escrita direta do
  cliente via `FirebasePlanRepository`, não passa por Cloud Function —
  não há nenhuma invariante cross-documento a validar aqui, por isso
  uma regra de role simples chega). `subscriptions`: leitura ampla
  dentro do tenant (a query de elegibilidade e o Manager precisam de a
  poder ler), `allow write: if false` sempre — mesmo um Manager
  autenticado não pode escrever diretamente; a única via é a Cloud
  Function, que corre com Admin SDK e ignora Rules.
- **Ecrãs de Gestor** (`lib/presentation/screens/`):
  `ManagePlansScreen` (lista de Planos + diálogo de criação
  nome/descrição/preço/moeda) → `PlanDetailScreen` (dados do Plano +
  um `SwitchListTile` por Service do tenant, ativar pede logo a
  `UsageRule` num diálogo — ilimitado ou limitado com quantidade e
  período). `AssignSubscriptionScreen` (picker de membro + picker de
  Plano, preço acordado pré-preenchido com o `currentPrice` do Plano
  mas editável, chama `createSubscription` e mostra a mensagem
  específica de `SubscriptionServiceConflictException` em caso de
  conflito). `ManagerScreen` é o hub com as duas entradas.
  `HomeScreen` passou a `ConsumerStatefulWidget` e só mostra o ícone de
  acesso a `ManagerScreen` na AppBar quando `AppUser.isManager` — só
  UI, a fonte de verdade da autorização continua a ser as Security
  Rules/Cloud Function do lado do servidor, não este `if`.
- **Seed script**: `seedPlanAndSubscription` cria um Plan "Standard
  (teste)" com o Service semeado na Fase 2 ativado (`UsageRule`
  ilimitada), e uma subscription ativa da Rita a esse Plan — sem isto,
  o booking manual em Chrome ficaria sempre bloqueado pela verificação
  de elegibilidade nova. Idempotente (salta se a subscription de teste
  já existir).
- **🔴 Testes de Security Rules**
  (`firebase/tests/plans-subscriptions-rules.test.ts`, ficheiro novo,
  `projectId` próprio pelo mesmo motivo dos outros dois — ver Fase 2):
  confirma que um membro lê mas não escreve `plans`/`plans.services`,
  que um Manager do próprio tenant escreve mas um Manager doutro
  tenant não, e que **ninguém** — nem um membro, nem um Manager
  autenticado — consegue escrever ou apagar diretamente uma
  `subscription`, só ler.
- **Testes unitários novos**: `test/domain/usage_rule_test.dart`
  (`describe()` para os 3 períodos, `UsagePeriod.fromValue`,
  igualdade via `Equatable`) e `test/domain/subscription_test.dart`
  (`grantsAccessTo` para os 4 estados possíveis,
  `SubscriptionServiceConflictException.toString()`) — cobrem só a
  lógica pura de domínio, sem precisar de Firebase.
  `book_session_use_case_test.dart` e `book_training_screen_test.dart`
  foram reescritos para injetar uma subscription repository fake
  (unit) / mock do `FirebaseFunctions` (widget) — ver secção seguinte
  sobre o que ficou e o que não ficou confirmado.

### Ainda em aberto / não verificado nesta sandbox

1. ~~Nada disto correu.~~ **Resolvido:** confirmaste `flutter test` a
   passar (depois de dois bugs reais meus — ver "Nono" e "Décimo"
   problema abaixo, e um erro de import em `manage_services_screen.dart`).
2. **Widget tests parcialmente acrescentados.**
   `manage_plans_screen_test.dart` (lista vazia, criar plano com
   sucesso, criar sem nome fica bloqueado pela validação — confirma
   inclusive que nada é escrito no Firestore quando a validação falha)
   e `plan_detail_screen_test.dart` (service por incluir aparece
   desligado, ligar o switch com "Ilimitado" grava
   `enabled:true`+`usage.type:unlimited`, ligar com "Limitado" grava
   `limit`/`period`) — ambos só dependem de Firestore
   (`fake_cloud_firestore`), por isso escrevi-os com confiança alta.
   **`AssignSubscriptionScreen` e `ManagerScreen` continuam sem teste
   de widget** — `AssignSubscriptionScreen` chama `createSubscription`
   através de `FirebaseFunctions.httpsCallable(...).call(...)`, e
   mockar essa cadeia com `mocktail` (`HttpsCallable`/
   `HttpsCallableResult` são tipos do pacote `cloud_functions`, cuja
   forma exata — generics, comportamento por omissão — não tenho como
   confirmar sem correr Flutter) é um risco real de escrever um teste
   que "passa" mas não verifica o que diz verificar. Prefiro não
   escrever isso às cegas; fica para quando puderes correr/rever tu.
   `ManagerScreen` é só navegação (2-3 `ListTile`→`Navigator.push`)
   sem lógica própria — baixo risco de bug, por isso também baixa
   prioridade de teste automatizado.
3. **Discrepância no critério "Done" do guia** (secção abaixo): o
   texto do guia menciona um "picker de atribuição manual" que só deve
   mostrar alunos elegíveis — isso é o picker de atribuição de sessões
   (UC08-A/17/19), que ainda não existe na app (é ecrã de gestão de
   sessões/séries, não construído em nenhuma fase até agora). A lista
   de histórias da própria Fase 3 no guia só pede o ecrã de atribuir
   Plano a membro (`AssignSubscriptionScreen`), que está feito. Não
   sei se isto é um erro de wording no guia ou se o critério "Done"
   pressupõe algo que devia ter sido pedido explicitamente como
   história e não foi — continua sinalizado, deliberadamente não
   implementado (é trabalho de gestão de sessões, Fase 5+, fora do
   scope desta fase).
4. ~~Preço acordado (`agreedPrice`) não é validado contra nada.~~
   **Resolvido:** validador do formulário em
   `AssignSubscriptionScreen` agora rejeita negativos, alinhado com o
   schema zod da Cloud Function (`agreedPrice: z.number().nonnegative()`
   — zero continua válido, ex.: uma promoção).

### Oitavo problema: `admin.firestore()`/`admin.auth()` não existem no `firebase-admin` instalado

Ao correres `npm run build` em `firebase/functions` pela primeira vez
nesta conversa, deu 12 erros de TypeScript em `createMember.ts`,
`createStaff.ts` e `createSubscription.ts` — todos do tipo
`Property 'firestore'/'auth' does not exist on type 'typeof import
(".../firebase-admin/lib/index")'`.

Não é um erro de configuração local nem transitório: confirmei lendo
`node_modules/firebase-admin/lib/index.d.ts` diretamente (tenho acesso
a Node/npm no meu sandbox, ao contrário do Flutter) — a versão
instalada é `firebase-admin@14.2.0`, e o módulo raiz `firebase-admin`
nessa versão só exporta `initializeApp`/`getApp`/`getApps`/`deleteApp`
e afins (App lifecycle). A API antiga em estilo namespace
(`admin.firestore()`, `admin.auth()`, `admin.firestore.FieldValue`,
`admin.firestore.FieldPath`) que `createMember.ts`/`createStaff.ts`
usavam desde a Fase 1 **nunca chegou a existir nesta versão** — não é
uma remoção recente, é assim desde sempre no v14. `lib/memberNumber.ts`
e `firebase/scripts/seed.mjs` já usavam a forma modular correta
(`import { getFirestore } from 'firebase-admin/firestore'`), por isso
nunca deram este erro — só os três ficheiros que ainda tinham o
`import * as admin from 'firebase-admin'` antigo.

Isto explica também o item "Build+lint das Cloud Functions — não
confirmado nesta conversa" que ficou em aberto na Fase 1: nunca tinha
mesmo sido corrido até agora, e estava partido desde o primeiro commit
de `createMember.ts`/`createStaff.ts`.

Corrigido nos três ficheiros e em `index.ts` (que só usava
`admin.initializeApp()`, também modernizado por consistência, embora
esse em concreto já compilasse): troquei para imports modulares —
`getFirestore`/`FieldValue`/`FieldPath` de `'firebase-admin/firestore'`,
`getAuth` de `'firebase-admin/auth'`, `initializeApp` de
`'firebase-admin/app'`. **Corri `npx tsc` e `npx eslint --ext .ts src`
a sério no meu sandbox depois da correção — ambos passam sem erros
nem avisos.** Isto é diferente do resto desta fase (que só pude
confirmar por leitura cuidadosa do código, não por execução real) —
aqui tenho Node disponível, por isso esta parte está genuinamente
verificada, não só revista.

### Nono problema: não havia forma de o Gestor entrar na app

Ao testares os ecrãs de Gestor novos, o login com
`leo@nxtperformancestudio.pt` (o email real do Leo, criado pelo seed
como Gestor) falhou com "Número de sócio ou password inválidos.". Não
é bug de credenciais nem de Rules: era um gap conhecido e já
documentado desde a Fase 1 — o comentário no topo de
`login_screen.dart` dizia literalmente "staff faz login com o email
real... um segundo ecrã de login para staff fica para quando for
pedido". Até agora nunca tinha sido pedido, porque nenhum ecrã exigia
que um Gestor autenticado na APP (não só via Cloud Function) existisse
— a Fase 3 é a primeira a introduzir ecrãs só-Gestor.

`FirebaseAuthRepository.signInWithMemberNumber` convertia sempre o
texto introduzido num email sintético
(`buildSyntheticEmail(tenantId, memberNumber)`), mesmo quando esse
texto já era um email real — por isso `leo@nxtperformancestudio.pt`
virava algo como
`member-leo@nxtperformancestudio.pt@nxt_performance_studio.gymsaas.internal`,
que não corresponde a nenhuma conta.

Corrigido sem criar um segundo ecrã: o mesmo campo agora aceita as
duas coisas — um identificador com `'@'` é usado tal como está (email
real de staff); sem `'@'`, continua a ser um nº de sócio, convertido
no email sintético de sempre (não há ambiguidade possível, nenhum nº
de sócio pode conter `'@'`). Alterado em
`firebase_auth_repository.dart` (a lógica), `auth_repository.dart`
(doc do contrato) e `login_screen.dart` (label do campo passou a "Nº
de sócio (ou email, se és staff)", teclado deixou de estar restrito a
números). `test/presentation/login_screen_test.dart` tinha uma
asserção que dependia do texto exato da mensagem de validação
("Introduz o teu nº de sócio") — atualizada para o novo texto
("Introduz o teu nº de sócio ou email"); os outros dois testes desse
ficheiro não mudam de comportamento. **Não escrevi um teste novo para
a deteção do `'@'` em si** (a lógica que decide entre email real e
email sintético): isso vive dentro de `FirebaseAuthRepository`, que
fala com `FirebaseAuth` a sério — teria de usar `firebase_auth_mocks`
(já é dev dependency, mas nunca usada neste projeto) e não tenho forma
de confirmar a API exata desse pacote sem correr Flutter, por isso
prefiro não adivinhar um teste que pareça verificar isto mas possa
estar errado. Fica como verificação manual: confirma que entrar com
`leo@nxtperformancestudio.pt` funciona agora.

(Pequeno ajuste a seguir a feedback: o label do campo simplificou de
"Nº de sócio (ou email, se és staff)" para só "Nº de sócio ou email" —
mais curto, mesma informação. `auth_gate_test.dart` tinha uma asserção
com o texto exato do label, também atualizada.)

### Décimo problema: nunca havia forma de CRIAR um Service, só associá-lo a um Plan

Ao testares, reportaste "não sei onde está o botão para criar planos
ou serviços" e, depois de encontrares `ManagePlansScreen`, "consigo
criar planos mas não devia ser também possível criar serviços?". Tens
razão — isto era um erro meu de leitura do âmbito da fase, não um bug
de execução. O guia pede explicitamente "Ecrã Gestor: criar/editar
Plans **e Services** (UC26)"; eu só construí a segunda metade de
"Services" (a relação Plan↔Service — `PlanDetailScreen`, o switch +
`UsageRule`), e assumi, incorretamente, que os Services em si (o
catálogo do ginásio — "Aula de Grupo", "Pilates", etc.) já estavam
todos resolvidos desde a Fase 2. Não estavam: a Fase 2 só criou UM
Service, à mão, pelo seed script, e nunca existiu nenhum ecrã para
criar outro. `firestore.rules` ainda tinha `services` com
`allow write: if false`, com um comentário meu literalmente a dizer
"ainda sem ecrã de gestão (Fase 3)" — ou seja, já sabia que faltava
isto e não fechei o ciclo.

Isto explica também, ao mesmo tempo, o erro persistente "Este plano
ainda não tem nenhum serviço associado" ao atribuir o "Standard
(teste)": não cheguei a confirmar a causa exata (pedi para verificares
na UI do emulador e não chegaste a responder), mas com este ecrã novo
já dá para veres e corrigires diretamente — abre o Plano, confirma se
o switch de "Aula de Grupo" está ligado, e ativa-o se não estiver.

Acrescentado:
- `ServiceRepository`: `watchServices()` (todos os Services, ativos e
  inativos — `getActiveServices()` da Fase 2 mantém-se, é o que o
  booking usa), `createService({name})`, `setServiceActive(...)`.
  Implementado em `FirebaseServiceRepository`.
- `firestore.rules`: `services` passou de `allow write: if false` para
  `allow write: if isManager(tenantId)` — mesmo padrão de `plans`.
- `ManageServicesScreen` (ecrã novo): lista todos os Services com um
  `SwitchListTile` (ativo/inativo), FAB "+" para criar um novo (só
  nome — `active: true` por omissão). Erros de escrita mostrados num
  SnackBar, mesmo padrão do nono problema/correção anterior.
- `ManagerScreen`: terceiro cartão "Serviços", antes de "Planos".
- `PlanDetailScreen`: a lista de Services elegíveis para associar a um
  Plano deixou de ser um `FutureProvider` isolado
  (`getActiveServices()`, uma leitura única) e passou a observar o
  novo `servicesProvider` (`StreamProvider`, filtrado para ativos no
  próprio ecrã) — sem isto, criar um Service em `ManageServicesScreen`
  não apareceria em `PlanDetailScreen` sem um `ref.invalidate()`
  manual que não havia como disparar entre dois ecrãs diferentes.
- **🔴 Testes de Security Rules**
  (`plans-subscriptions-rules.test.ts`): novo bloco `describe` para
  `services` — membro lê mas não escreve, Manager do tenant cria e
  desativa, Manager de outro tenant não consegue.

### Passos para verificar a Fase 3 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 2. 🔴 Correr os testes de Security Rules — isolamento (Fase 1) +
#    concorrência (Fase 2) + plans/subscriptions (Fase 3)
cd firebase/tests
npm install
cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore "npm --prefix firebase/tests test"

# 3. Cloud Functions: build + lint (createSubscription é código novo;
#    createMember/createStaff tinham um bug de imports do firebase-admin
#    v14 nunca antes detetado — ver "Oitavo problema" acima)
cd firebase/functions
npm run build
npm run lint
cd ../..

# 4. Seed — com o emulador completo a correr
#    (firebase emulators:start --project=demo-gym-saas-dev):
cd firebase/scripts
npm run seed
cd ../..
# Confirma no output que aparece "plan_test_standard" e
# "subscription_test_rita".

# 5. Testar como Gestor (Leo / leo@nxtperformancestudio.pt / DevPass123!,
#    entra no mesmo campo "Nº de sócio ou email")
flutter run -t lib/main_development.dart
# Deve aparecer o ícone de "Gestão" na AppBar (só para o Leo, não para
# a Rita). Em "Gestão → Serviços", confirma que "Aula de Grupo" (do
# seed) aparece ativo, e cria um Service novo (ex.: "Pilates"). Em
# "Gestão → Planos", cria um Plano novo, ativa um Service com uma
# UsageRule limitada (ex.: 2x/semana), confirma que fica guardado ao
# voltar ao ecrã. Atribui esse Plano a um membro sem subscription e
# confirma que aparece sucesso; tenta atribuir OUTRO plano que dê
# acesso ao MESMO service a esse membro e confirma que aparece a
# mensagem de conflito. Se atribuir "Standard (teste)" (do seed) ainda
# der "este plano ainda não tem nenhum serviço associado", abre esse
# Plano em "Gestão → Planos" e confirma/ativa o switch de "Aula de
# Grupo" à mão — ver "Décimo problema" acima.

# 6. Testar como membro sem plano — bloqueio de booking
# Cria (via UI do Gestor ou Cloud Function createMember direta) um
# membro que NÃO tenha nenhuma subscription, faz login com ele, e
# tenta marcar "Aula de Grupo". Deve aparecer a mensagem específica de
# "não tens um plano ativo", sem sequer tentar a transação de booking.

# 7. Testar como a Rita (já tem subscription do seed) — confirma que
#    marcar continua a funcionar normalmente (regressão da Fase 2).
```

### Critério "Done" da Fase 3

> um aluno sem o serviço contratado é bloqueado ao tentar marcar-se; o
> picker de atribuição manual só mostra alunos elegíveis.

A primeira metade está feita e coberta (passo 6 acima +
`NotEligibleForServiceException` + teste unitário de
`BookSessionUseCase`). A segunda metade — ver ponto 3 de "Ainda em
aberto" acima — refere-se a um picker de sessões que não faz parte da
lista de histórias desta fase nem existe ainda na app; sinalizada, não
implementada às escondidas nem ignorada em silêncio.

## Próximo passo

Fase 4 do guia (`Technical/guia-desenvolvimento.md`) — ainda por
consultar em detalhe.
