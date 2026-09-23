# Gym SaaS

Implementação incremental do `Technical/guia-desenvolvimento.md`. Cada fase
tem o seu objetivo e critério "Done" — não avançar para a fase seguinte
sem o anterior estar confirmado (isto é especialmente crítico nas fases
marcadas 🔴).

## Fase 0 — Fundação do projeto ✅ concluída e verificada

Camadas Flutter (`presentation/domain/application/repositories/infrastructure`),
Riverpod, três ambientes (development/staging/production), Firebase
Emulator Suite, CI (lint+test), Crashlytics, e um "hello world" (desde
então removido — ver "Restos da fase de arranque") que
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
# o ecrã "Início" do Aluno. Confirma também que a MESMA combinação de nº
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
   ~~`AssignSubscriptionScreen` continua sem teste de widget~~
   **Resolvido (fora do plano de fases, depois da Fase 4):**
   `assign_subscription_screen_test.dart` — o receio original era
   mockar `FirebaseFunctions.httpsCallable(...).call(...)` diretamente
   com `mocktail` (risco real de um teste que "passa" sem verificar
   nada, ver texto original abaixo). A Fase 4 provou um padrão melhor
   entretanto (`book_training_screen_test.dart`,
   `my_bookings_screen_test.dart`): um fake que implementa
   `SubscriptionRepository` inteiro (mantém as subscriptions em
   memória, nunca toca em `cloud_functions`) injetado via
   `subscriptionRepositoryProvider.overrideWithValue(...)`. Cobre
   atribuição com sucesso (membro fica selecionado, preço limpa,
   secção "Planos ativos" atualiza) e o caso de conflito
   (`SubscriptionServiceConflictException` mostrada inline).
   `ManagerScreen` é só navegação (2-3 `ListTile`→`Navigator.push`)
   sem lógica própria — baixo risco de bug, por isso continua sem
   teste automatizado dedicado.
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

### Extensão pedida: ver os planos de cada membro (fora do guia)

Depois de testares a Fase 3, pediste para conseguir ver os planos de
cada membro e evitar duplicados — o segundo já estava coberto
(`createSubscription` recusa por serviço em conflito, Domain Model v1
§15), mas não havia forma de VER. Acrescentado:

- `memberSubscriptionsProvider` (`plan_providers.dart`, `.family` por
  `memberId`), sobre `watchMemberSubscriptions()` que já existia desde
  a Fase 3.
- `AssignSubscriptionScreen`: mostra logo, ao escolher o membro, um
  cartão com os planos ativos que já tem — antes de tentares submeter.
  Aceita também `initialMember` opcional.
- `ManageMembersScreen` (novo, "Gestão → Membros") + `MemberDetailScreen`
  (novo): lista de membros → detalhe com TODAS as subscriptions
  (ativas e histórico, com estado, preço, serviços, datas) + botão
  "Atribuir novo plano".
- Sem alterações a `firestore.rules`: leitura de `members`/`plans`/
  `services`/`subscriptions` já era ampla dentro do tenant.
- **Não corri nada disto** — balanços de chavetas confirmados por
  script, não compilação real nem widget tests novos para estes dois
  ecrãs. Confirma com `flutter test`/`flutter analyze` e testa em
  Chrome: Gestão → Membros → escolhe a Rita → deve aparecer a
  subscription do seed.

### Extensão pedida: desativar Plano / desativar Membro (fora do guia)

Perguntaste sobre eliminar Plans/Services/Membros. Resposta curta:
**desativar, não eliminar** — é o mesmo padrão já usado em todo o
domínio (bookings e subscriptions nunca são apagados, só mudam de
`status`; Plans e Services já tinham `active`). Eliminar partiria
histórico (subscriptions/bookings que ainda apontam para esse
id). Acrescentado:

- `Plan.copyWith({active})` (novo método no domínio) + `SwitchListTile`
  "Plano ativo" no topo de `PlanDetailScreen`, usando o
  `updatePlan()` que já existia. Resolve o Plan atual pelo
  `plansProvider` ao vivo (não pelo valor imutável recebido no
  construtor), para o switch refletir o estado real mesmo depois de
  navegares para trás e para a frente.
- `MemberRepository.setMemberActive()` (novo, escreve `status` —
  mesmo campo já lido em `_fromDoc`) + `SwitchListTile` "Membro ativo"
  em `MemberDetailScreen`, mesmo raciocínio de resolver o membro atual
  ao vivo.
- **Não mexe no Firebase Auth nem em `firestore.rules`** — um membro
  "inativo" continua tecnicamente a conseguir fazer login; isto é só
  marcação de negócio. Bloquear login/marcação de um membro inativo a
  sério (Rules) fica para quando for pedido — não implementei isso às
  escondidas.
- `AssignSubscriptionScreen`/`ManagePlansScreen` **não filtram** planos
  inativos do dropdown/lista — continuam a aparecer, só marcados
  "· inativo". Impedir escolher um Plano inativo no picker é um passo
  a mais que não pediste explicitamente; fica sinalizado, não feito.
- **Não corri nada disto** — mesma ressalva de sempre, confirma com
  `flutter analyze`/`flutter test`.

### Extensão pedida: gaps encontrados a comparar com os mockups (fora do guia)

Pediste para analisar `Functional/nxt-studio-screens.html` (os
mockups) contra o que já estava construído, e depois "faz todos" os
gaps que encontrasse. Encontrei três:

**1. Ecrã "Criar utilizador" (UC22) — em falta desde a Fase 1.**
`createMember`/`createStaff` (Cloud Functions) existiam desde a Fase 1,
mas nenhuma UI os chamava — não havia forma de criar um Aluno ou Staff
a partir da app. Acrescentado:

- `CreateUserScreen` (novo): `SegmentedButton` Aluno/Staff, nome,
  email+papéis (Instrutor/Gestor) só para Staff. Ao contrário do
  mockup ("Modalidade associada" com checkboxes Hyrox/PT/Pilates),
  `createStaff.ts` não tem campo de modalidade no schema — só `roles`;
  segui o que o backend aceita, não o mockup à letra.
- Diálogo bloqueante (`barrierDismissible: false`) no fim, mostrando
  nº de sócio ou email + password temporária em `SelectableText` — é a
  ÚNICA vez que a password aparece (mockup: "credenciais comunicadas
  fora da app"). Fechar o diálogo é a única saída.
- FAB "+" ligado a partir de `ManageMembersScreen` e `ManageStaffScreen`
  (ver ponto 2).

**2. Gestão de Staff — não existia repository nem ecrã nenhum.**
Só havia `MemberRepository` (Alunos); Instrutores/Gestores não tinham
nenhuma forma de serem listados, vistos ou desativados pela app.
Acrescentado, seguindo exatamente o padrão já usado para Members/Plans:

- `StaffSummary` (domínio), `StaffRepository`/`FirebaseStaffRepository`
  (lê `tenants/{tenantId}/staff`, mapeia `roles` via `Role.fromClaim`,
  `active` a partir de `status`).
- `ManageStaffScreen` (novo, "Gestão → Staff"): lista com papéis e
  estado, FAB "+" → `CreateUserScreen`.
- `StaffDetailScreen` (novo): email, papéis, `SwitchListTile` "Staff
  ativo" (mesmo raciocínio de desativar-não-eliminar da secção
  anterior). Nota explícita quando inativo: desativar aqui não cancela
  automaticamente sessões futuras desse instrutor (UC24) — isso é
  gestão de sessões, ainda não construída (Fase 5+).
- `ManagerScreen`: novo card "Staff".

**3. `AssignSubscriptionScreen` — UX diferente do mockup, mas sem
hardcodar categorias.** O mockup (UC26) mostra atribuir vários
serviços/níveis a um membro num único fluxo agrupado por categoria
(sala nível único, aulas de grupo múltiplas, PT único). Não hardcodei
essas categorias — violaria o Domain Model v1 §10 ("nunca um enum
fixo na app": Plans são configuráveis por tenant, não uma lista fixa
de categorias). Em vez disso:

- Depois de atribuir um plano com sucesso, o ecrã já não faz `pop` —
  fica no mesmo membro, limpa só o campo do plano e do preço (com uma
  `key` nova no dropdown, porque `DropdownButtonFormField.initialValue`
  só é lido na primeira construção — mudar a variável sozinha não
  limpa o valor mostrado), e a secção "Planos ativos deste membro"
  atualiza-se sozinha (é um `StreamProvider`). O Gestor pode assim
  atribuir vários planos seguidos ao mesmo membro sem sair do ecrã.
  Sair é sempre via botão de voltar da AppBar.

**Não corri nada disto** — mesma ressalva de sempre: balanços de
chavetas/parênteses confirmados por script em todos os 96 ficheiros
`.dart` de `lib/`/`test/`, não compilação real. Não escrevi widget
tests novos para `CreateUserScreen`/`ManageStaffScreen`/
`StaffDetailScreen`/`AssignSubscriptionScreen` pela mesma razão já
documentada nas extensões anteriores: mockar a cadeia `HttpsCallable`
do `cloud_functions` via `mocktail` não dá para verificar sem correr
Flutter a sério — prefiro documentar isto do que escrever um teste que
posso não ter a certeza que está correto. Confirma com
`flutter analyze`/`flutter test` e testa em Chrome: Gestão → Membros →
"+" → cria um Aluno → confirma que aparece o diálogo com nº de sócio;
Gestão → Staff → "+" → cria um Staff → confirma login com esse email;
Gestão → Membros → escolhe alguém → "Atribuir novo plano" → atribui um
plano → confirma que o ecrã fica no mesmo membro e o plano some do
dropdown mas aparece na secção "Planos ativos".

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

## Fase 4 — Usage tracking e limite semanal

**Objetivo do guia:** "limite semanal (Standard 1x / Plus 2x / Premium
3x) validado corretamente, com semana segunda-domingo."

### Decisão de arquitetura (perguntada ao Carlos antes de codificar)

A Fase 3 já tinha fechado `createSubscription` como Cloud Function
(Admin SDK) em vez de transação client-side, por a validação precisar
de percorrer um número variável de documentos. A Fase 4 tinha o mesmo
dilema para `createBooking`/`cancelBooking` — e mais dois pontos sem
resposta na documentação (`Firestore Data Model v1` §71, "o que ainda
não está decidido"): onde vive a "antecedência mínima para cancelar", e
o que acontece ao cancelar FORA dessa janela. Perguntei antes de
implementar; respostas do Carlos:

1. **`createBooking`/`cancelBooking` passam a Cloud Function** (Admin
   SDK), não continuam como transação client-side da Fase 2. Motivo:
   `Firestore Data Model v1` §52 pede explicitamente autoridade no
   backend para limite semanal e antecedência mínima.
2. **Antecedência mínima: um valor único por tenant**
   (`tenants/{id}/config/bookingPolicy.minCancellationNoticeHours`),
   não por Plan nem por Service.
3. **Cancelar fora da janela: cancela na mesma (liberta a vaga), mas
   NÃO devolve a utilização semanal** — funciona como penalização por
   cancelar tarde.

### O que foi acrescentado

- **Domain:** `Usage` (`domain/entities/usage.dart`) — read model
  derivado, sem `limit` guardado (evita ficar desatualizado se o
  Gestor mudar a `UsageRule` depois). `Booking` ganhou `serviceId`/
  `period` (nullable — `null` só em bookings de seed anteriores a esta
  fase). Nova `UsageLimitReachedException`.
- **`core/utils/iso_week.dart`** (+ equivalente TS em
  `firebase/functions/src/lib/isoWeek.ts`, que É a versão que decide de
  facto) — `isoWeekKey`/`isoWeekRange`, semana segunda 00:00 a domingo
  23:59, formato `YYYY-Www`. Limitação documentada: cálculo em UTC, não
  no timezone do tenant (não há biblioteca de timezone nas
  dependências) — perto da fronteira segunda/domingo à meia-noite pode
  desviar por causa do horário de verão.
- **Cloud Functions novas** (`firebase/functions/src/`):
  `createBooking.ts` (substitui a transação client-side da Fase 2:
  valida elegibilidade, limite semanal via `usage/{memberId}_
  {serviceId}_{period}`, capacidade, concorrência na última vaga —
  tudo o que já existia mais o limite novo), `cancelBooking.ts`
  (cancela sempre, devolve `usage` só dentro da janela configurada),
  `recalculateUsage.ts` (Manager-only, recalcula `usage` a partir dos
  `Booking`s reais — Firestore Data Model v1 §32/D13: usage nunca é a
  fonte de verdade).
- **`TenantRepository`** ganhou `getMinCancellationNoticeHours`/
  `setMinCancellationNoticeHours` + `TenantSettingsScreen` (novo,
  "Gestão → Definições") para o Gestor configurar isto — sem UI não
  havia forma nenhuma de definir o valor.
- **`firestore.rules`:** nova coleção `usage` (leitura ampla no tenant,
  escrita sempre `false`). `sessionOccurrences`/`bookings` passam de
  "o próprio membro pode escrever `activeBookingCount`/o seu booking
  dentro de condições exatas" (Fase 2) para **escrita sempre `false`
  para o cliente** — fecha, de vez, a lacuna que já estava documentada
  (e aceite) no código antigo: "um cliente malicioso podia, em teoria,
  enviar só o incremento do contador sem criar o booking". `config/
  {configId}` passa de escrita ampla (Fase 1) para só Manager.
- **`lib/infrastructure/firebase/firebase_booking_repository.dart`**
  reescrito: já não faz `runTransaction` nenhuma, só chama
  `createBooking`/`cancelBooking` via `cloud_functions` e traduz
  `FirebaseFunctionsException` (código + `details.reason`) para as
  exceções de domínio — mesmo padrão de
  `firebase_subscription_repository.dart` (Fase 3).
- **`UsageRepository`** (novo, só leitura) + `book_training_screen.dart`
  ganhou uma barra "Esta semana: X/Y sessões de \<serviço\>" (story 7),
  visível só quando a `UsageRule` aplicável é `limited`.
- **Seed script:** o plano "Standard (teste)" passa de `unlimited` para
  `limited` (1x/semana) em "Aula de Grupo", e há uma segunda
  `sessionOccurrence` na mesma semana — sem isto não dava para testar o
  bloqueio à mão com só uma sessão disponível.

### Ainda em aberto / não verificado nesta sandbox

1. **Testes de negócio das Cloud Functions não escritos.** O ficheiro
   antigo `test/repositories/firebase_booking_repository_test.dart`
   testava a transação client-side diretamente contra
   `FakeFirebaseFirestore`; essa lógica mudou de sítio (agora vive em
   `createBooking.ts`/`cancelBooking.ts`), e testá-la exigiria o
   Firebase Functions Emulator (não montado neste projeto — só o
   Firestore Emulator tem testes de Rules, em `firebase/tests`). Fica
   sinalizado como lacuna real, não escondida. Os testes de ECRÃ
   (`book_training_screen_test.dart`/`my_bookings_screen_test.dart`)
   continuam a cobrir a reação da UI a sucesso/erro, através de um fake
   de `BookingRepository` que simula no `FakeFirebaseFirestore` o que a
   Cloud Function faria — não a lógica de negócio da função em si.
2. **`firebase/tests/usage-rules.test.ts` (novo) não corri** — nem
   Java (logo, nem o Firestore Emulator) nem uma instalação de
   `node_modules` compatível com este SO (`esbuild`/`rollup`
   instalados para outra plataforma) estavam disponíveis na sandbox
   onde este código foi escrito. Mesma ressalva de sempre: confirma com
   `firebase emulators:exec ... "npm --prefix firebase/tests test"`.
3. ~~`recalculateUsage` não tem nenhum botão na UI~~ **Resolvido
   (task #63, fora do plano de fases):** `MemberDetailScreen` mostra
   agora "Recalcular utilização" em cada plano ativo do membro — chama
   `UsageRepository.recalculateUsage` (novo método,
   `firebase_usage_repository.dart`, via
   `httpsCallable('recalculateUsage')`) para cada serviço a que a
   subscription dá acesso (picker quando há mais do que um serviço) e
   mostra o resultado (`período: usadas sessão(ões)`) num diálogo, ou
   uma mensagem própria quando não há nada para recalcular. Coberto por
   `member_detail_screen_test.dart` com o mesmo padrão de fake
   repository (nunca mocka `cloud_functions` diretamente) — caso de
   sucesso e caso "nada a recalcular".
4. **Isolamento entre tenants na collectionGroup de `recalculateUsage`**
   segue o mesmo raciocínio já aceite em `watchMyBookings` (um uid só
   pertence a um tenant) — não repetido com um teste de isolamento
   dedicado; `usage-rules.test.ts` cobre as Rules, não a Cloud Function.

### Passos para verificar a Fase 4 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 2. Cloud Functions: build + lint (createBooking/cancelBooking/
#    recalculateUsage são código novo desta fase)
cd firebase/functions
npm run build
npm run lint
cd ../..

# 3. 🔴 Security Rules — isolamento + concorrência + plans/subscriptions
#    + usage/bookings-fechados (Fase 4)
cd firebase/tests
npm install
cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore "npm --prefix firebase/tests test"

# 4. Seed (com o emulador completo a correr:
#    firebase emulators:start --project=demo-gym-saas-dev) — se já
#    tinhas semeado antes da Fase 4, corre outra vez: atualiza o plano
#    "Standard (teste)" para 1x/semana e acrescenta a segunda sessão.
cd firebase/scripts
npm run seed
cd ../..

# 5. Testar o limite semanal como a Rita
flutter run -t lib/main_development.dart
# Login: nº "000001" / password "MemberPass123!". Em "Marcar", deve
# aparecer já a barra "Esta semana: 0/1 sessões de Aula de Grupo" por
# cima das duas sessões. Marca a PRIMEIRA — sucesso, a barra passa a
# "1/1". Tenta marcar a SEGUNDA — bloqueado com "Já atingiste o limite
# semanal deste serviço (1/1)".

# 6. Testar a devolução de utilização ao cancelar
# Em "Minhas marcações", cancela a marcação. Sem nenhuma antecedência
# mínima configurada (default 0h = sem restrição), a barra em "Marcar"
# deve voltar a "0/1" e a segunda sessão volta a ficar marcável.

# 7. Testar a antecedência mínima
# Login como Leo (Gestor) → "Gestão → Definições" → mete um valor alto
# (ex.: 999999) em "Antecedência mínima (horas)" → Guardar. Login outra
# vez como a Rita, marca e depois tenta cancelar: o cancelamento deve
# continuar a funcionar (a vaga liberta-se), mas a barra de utilização
# NÃO deve voltar a descer — a marcação continua a contar para o
# limite semanal.
```

### Critério "Done" da Fase 4

> um aluno Plus é bloqueado à 3ª tentativa de marcação na mesma semana,
> e o contador reseta corretamente na segunda-feira seguinte.

A primeira metade está feita e coberta pelo passo 5 acima (adaptado ao
seed: 1x/semana em vez de 2x, mesmo mecanismo). A segunda metade (reset
à segunda-feira) é uma consequência direta de `isoWeekKey`/
`isoWeekRange` gerarem uma chave nova a cada semana ISO — não precisa
de nenhum job/cron a "resetar" nada, o documento antigo simplesmente
deixa de ser lido (fica como histórico). Não simulei a passagem de uma
semana inteira num teste automatizado (exigiria mockar `DateTime.now()`
tanto no Dart como no TS); fica sinalizado, não verificado ponta a
ponta.

### Extensão pedida: aviso antes de cancelar (fora do guia)

Depois de testares a Fase 4 (limite semanal a funcionar), reparaste que
cancelar uma marcação não avisava nada sobre a utilização — cancelava
em silêncio, sem dizer se ia ou não devolver a vaga ao limite semanal.
Acrescentado a `my_bookings_screen.dart`:

- **Diálogo de confirmação antes de cancelar**, com texto diferente
  consoante o caso: serviço sem limite ("A vaga fica livre para outro
  membro"), dentro da janela de antecedência ("... e a utilização desta
  semana é devolvida"), ou fora da janela (aviso mais forte, botão a
  vermelho: "esta marcação continua a contar para o teu limite
  semanal — a utilização NÃO é devolvida"). É uma PREVISÃO calculada no
  cliente (`occurrenceProvider` + `minCancellationNoticeHoursProvider` +
  `applicableUsageRuleProvider`) — a autoridade continua a ser
  `cancelBooking.ts`.
- **`cancelBooking.ts` passa a devolver `usageRefunded: boolean`** (era
  só `{cancelled: true}`), para a mensagem final (SnackBar, depois do
  cancelamento) refletir o que REALMENTE aconteceu, não a previsão do
  diálogo. `BookingRepository.cancelBooking`/`CancelBookingUseCase`
  propagam esse valor (`Future<bool>` em vez de `Future<void>`).
- Novo `occurrenceProvider` (`.family`, `booking_providers.dart`) —
  busca uma única `SessionOccurrence` por id; não existia nenhuma forma
  de "Minhas marcações" saber a que horas é a sessão de uma marcação.

**Não corri nada disto** — mesma ressalva de sempre. Testes
atualizados: `my_bookings_screen_test.dart` agora confirma o diálogo
antes de assumir que cancelar funciona; `cancel_booking_use_case_test.dart`
ganhou um teste para o valor de retorno novo. Não escrevi um teste de
widget para o caminho "fora da janela" (aviso a vermelho) — exigiria
seed de subscription+plan+usage limited dentro do
`FakeFirebaseFirestore` do teste só para chegar lá, e a lógica em si
(qual mensagem aparece, `withinWindow`) é simples o suficiente para
rever a olho; fica sinalizado, não escondido.

## Fase 5 — Sessões recorrentes (séries)

**Objetivo do guia:** "aulas/PT 'todas as semanas a esta hora', com
exceções pontuais sem quebrar a série."

### Decisões de arquitetura (perguntadas ao Carlos antes de codificar)

O guia lista "modelo híbrido: atribuição manual + vagas abertas na
mesma ocorrência" como story da fase, mas o UC19 dá um exemplo concreto
(Leo pré-atribui 5 alunas fixas a um "PT de grupo" recorrente) que
deixava em aberto uma decisão de arquitetura real: essas alunas ficam
marcadas automaticamente em CADA semana gerada, ou só na ocorrência que
já existir no momento? Perguntei antes de implementar; respostas do
Carlos:

1. **Auto-atribuição em cada semana gerada.** A série guarda
   `preAssignedMemberIds`; sempre que a Cloud Function materializa uma
   ocorrência nova a partir dela, esses membros são marcados
   automaticamente, com a mesma validação de elegibilidade/limite/
   capacidade de um booking normal (`source: manager`). Implica
   partilhar a lógica de validação entre `createBooking.ts` e a função
   de geração — ver refactor abaixo.
2. **Só o Gestor gere isto por agora**, dentro de "Gestão" (mesmo
   padrão de Planos/Serviços/Staff/Membros). Uma área própria para o
   Instrutor fica marcada, deliberadamente não construída — é
   literalmente o que a Fase 6 do guia já lista ("Operações do dia a
   dia — Instrutor/Gestor").

`Modality` (Domain Model v1 §8-9) continua fora de âmbito — nenhuma
story da Fase 5 pede isto, e não existe nenhuma implementação dela na
app; sinalizado, não esquecido.

### O que foi acrescentado

- **Domínio**: `SessionSeries` (`lib/domain/entities/session_series.dart`)
  — `dayOfWeek` (convenção `DateTime.weekday`, segunda=1…domingo=7,
  igual à já usada em `iso_week.dart`), `startTime` ("HH:mm"),
  `durationMinutes`, `capacity`, `startDate`, `preAssignedMemberIds`,
  `status`. `capacityLabel` calcula Individual/Duo/Trio/Grupo(N) a
  partir de `capacity` — nunca um enum persistido (UC19). `SessionOccurrence`
  ganhou `seriesId`/`instructorId` (nullable, `null` em ocorrências
  ad-hoc ou anteriores a esta fase — mesmo padrão de
  `Booking.serviceId`/`period` desde a Fase 4).
- **Refactor em `firebase/functions/src/` (comportamento inalterado
  para o caminho self-service):** a lógica de elegibilidade e a
  transação de booking saíram de `createBooking.ts` para
  `lib/bookingLogic.ts` (`resolveEligibility`/`runBookingTransaction`,
  parametrizado por `source`). Motivo: a mesma regra de negócio
  (capacidade, duplicação, limite semanal) passou a ser reutilizada
  por mais dois caminhos — duplicá-la arriscaria divergir.
  `createBooking.ts` ficou mais curto, chamando isto com `source:
  'self'`.
- **`generateRecurringOccurrences.ts`** (novo): materializa as
  próximas **8 semanas** de cada série `active` (`collectionGroup`
  quando corre para todos os tenants), com id determinístico
  `{seriesId}_{YYYY-MM-DD}` (idempotente — correr duas vezes nunca
  duplica), e auto-atribui `preAssignedMemberIds` a cada ocorrência
  nova via `runBookingTransaction` (`source: manager`) — a falha de UM
  membro (sem plano, sem vaga) não bloqueia os outros nem a criação da
  ocorrência. `export const generateRecurringOccurrences = onSchedule(
  'every day 03:00', ...)` para produção; `generateRecurringOccurrencesNow`
  (callable, `requireManager`) é o caminho principal para testar isto
  localmente — o Functions Emulator não dispara `onSchedule` por
  temporizador — e também ferramenta operacional, mesmo padrão de
  `recalculateUsage` (Fase 4).
- **`assignMembersToOccurrence.ts`** (novo, `requireManager`): atribui
  manualmente um ou mais membros a UMA ocorrência concreta (mesma
  validação partilhada, `source: manager`), devolvendo um resumo por
  membro (não falha o pedido inteiro por causa de um só). Fecha a
  lacuna sinalizada desde a Fase 3 ("picker de atribuição manual
  UC08-A... Fase 5+").
- **`firestore.rules`**: `sessionOccurrences` deixa de ser `allow
  write: if false` sempre (Fase 4) — Manager volta a poder
  criar/editar uma ocorrência (ad-hoc ou ajuste pontual de uma gerada
  por série), mas `create` exige `activeBookingCount == 0` e `update`
  exige que esse campo não mude nessa escrita — `bookings` continua
  **sempre** `allow write: if false`, mesmo para Manager; só as Cloud
  Functions (Admin SDK) escrevem aí. Nova coleção `sessionSeries`:
  leitura ampla no tenant, escrita só Manager (mesmo padrão de
  `plans`/`services` — escrita direta do cliente, sem invariante
  cross-documento a proteger aqui).
- **Índices novos** (`firestore.indexes.json`): `sessionOccurrences`
  (`seriesId`+`startAt`, para "ajustar uma semana da série");
  `sessionSeries.status` com `fieldOverride` `COLLECTION_GROUP` (a
  função agendada varre todos os tenants); `subscriptions`
  (`status`+`activeServiceIds` array-contains, sem `memberId` — para
  listar TODOS os membros elegíveis a um serviço, não só verificar um).
- **Repositórios Dart**: `SessionSeriesRepository`/
  `FirebaseSessionSeriesRepository` (`watchSeries`, `createSeries`,
  `updateSeries`, `cancelSeries` — `WriteBatch` que marca a série E
  todas as suas ocorrências futuras `cancelled` na mesma escrita
  atómica, ocorrências passadas intocadas; `generateNow`).
  `SessionOccurrenceRepository` ganhou `createOccurrence` (ad-hoc, "só
  esta data"), `updateOccurrence`, `cancelOccurrence`,
  `watchOccurrencesForSeries`, `assignMembers` (chama
  `assignMembersToOccurrence`). `SubscriptionRepository` ganhou
  `watchEligibleMemberIds(serviceId)` — todos os membros com uma
  subscription ativa que dá acesso a um serviço (não só "este membro é
  elegível?" como já existia).
- **Ecrãs**: `ManageSeriesScreen` ("Gestão → Aulas/Horários", novo card
  em `ManagerScreen`) — lista de séries. `CreateSeriesScreen` — toggle
  "Só esta data"/"Semanal, fixa", serviço, instrutor opcional
  (`staffProvider` filtrado a `Role.instructor`), dia da semana ou
  data, hora, duração, capacidade (chips de preset
  Individual/Duo/Trio/Grupo que só pré-preenchem o número, nunca um
  enum), e picker opcional de pré-atribuição (`eligibleMembersProvider`,
  bloqueado a não exceder a capacidade). `SeriesDetailScreen`
  ("ajustar uma semana da série") — resumo, botões "Gerar agora"/
  "Cancelar série" (com confirmação), e por ocorrência: editar (só
  essa semana, texto explícito a dizer isso), cancelar só essa, ou
  adicionar membro.
- **Seed script**: `seedRecurringSeries` — série "Hyrox — Segundas
  18:00" (capacidade 6, Rita pré-atribuída), sem ocorrências ainda
  (Gestão → Aulas/Horários → "Gerar agora" materializa-as).

### Verificado desta vez — pela primeira vez com ferramentas reais disponíveis

Ao contrário de todas as fases anteriores (que terminavam sempre com
"não corri nada disto — sem acesso a Flutter/Node/Java nesta sandbox"),
desta vez tive `flutter`, `node`/`npm`, `java` e o `firebase` CLI
disponíveis. Corri, a sério, não só revi:

- `dart format` nos ficheiros desta fase, `flutter analyze
  --fatal-infos` (0 avisos) e **`flutter test` — 65/65 testes a
  passar**, incluindo os 12 novos desta fase (`session_series_test.dart`,
  `manage_series_screen_test.dart`).
- `npm run build` + `npm run lint` em `firebase/functions` — 0 erros,
  0 avisos, incluindo o refactor de `createBooking.ts`.
- 🔴 `firebase emulators:exec --only firestore,functions,auth "npm
  --prefix firebase/tests test"` — **53/53 testes de Security
  Rules/Functions a passar**, incluindo os 14 novos de
  `session-series-rules.test.ts` (`sessionSeries` Manager-only,
  `sessionOccurrences` create/update sem poder tocar
  `activeBookingCount`, `bookings` continua fechado mesmo a Manager) e
  `booking-concurrency.test.ts` reescrito (ver "Décimo terceiro
  problema" abaixo).

Três problemas reais apanhados ao correr isto de verdade — fica aqui o
registo, como nas fases anteriores:

**Décimo segundo problema — `sessionOccurrenceRepositoryProvider`
partiu um teste da Fase 4.** Adicionar `FirebaseFunctions` ao
construtor de `FirebaseSessionOccurrenceRepository` (necessário para o
novo `assignMembers`) fez `my_bookings_screen_test.dart` falhar — esse
teste nunca tinha precisado de mockar `functionsProvider` porque
`occurrenceProvider` (usado desde a Fase 4 para saber a que horas é
uma sessão) só tocava no Firestore. Sem o mock, `functionsProvider`
resolve para `FirebaseFunctions.instance` real, que não tem nenhuma
app Firebase inicializada neste teste. Corrigido acrescentando o mesmo
mock nunca invocado já usado em `book_training_screen_test.dart`.
Confirmei que nenhum outro ficheiro de teste tinha o mesmo problema
(`grep` por `occurrenceProvider`/`sessionOccurrenceRepositoryProvider`
sem `functionsProvider`).

**Décimo terceiro problema — `booking-concurrency.test.ts` (Fase 2)
estava partido desde a Fase 4, ninguém tinha reparado — corrigido
nesta fase, a pedido do Carlos.** Ao correr os testes de Rules pela
primeira vez de facto, os 2 testes deste ficheiro falhavam sempre com
`PERMISSION_DENIED`. Não era nada desta fase — o ficheiro simulava a
marcação como transação **client-side** direta contra o Firestore (era
assim que funcionava até à Fase 2), mas a Fase 4 fechou
`sessionOccurrences`/`bookings` para escrita de qualquer cliente (só
Cloud Functions escrevem, Admin SDK). Confirmei com `git stash` que
isto já falhava antes de qualquer alteração desta fase — não era uma
regressão minha, era uma lacuna de verificação da própria Fase 4 (que
também nunca tinha corrido isto). Consequência séria: a proteção
contra overbooking — a garantia mais crítica do guia inteiro — não
tinha NENHUM teste automatizado a passar desde a Fase 4.

Reescrito para chamar `createBooking` a sério, através do Functions
Emulator, em vez de reimplementar a transação em paralelo:
autenticado como dois membros distintos via `signInWithCustomToken`
(as claims `tenantId`/`roles` embutidas no custom token propagam-se
para o ID token — técnica documentada da Firebase para testes, evita
ter de criar utilizadores reais no Auth Emulator só para isto), chama
`httpsCallable(functions, 'createBooking')` a sério, com Admin SDK só
para semear os dados de teste (bypassa Rules diretamente, sem
`@firebase/rules-unit-testing`). **Duas armadilhas descobertas ao
fazer isto, não assumidas:**

1. `createBooking` exige elegibilidade (Fase 3) antes de chegar à
   transação de capacidade — sem seed de uma `subscription` ativa por
   membro, as duas tentativas eram sempre rejeitadas por "não
   elegível", nunca testando concorrência nenhuma.
2. **Uma Cloud Function a correr no emulador está SEMPRE ligada ao
   projeto passado em `--project`** (aqui, `demo-gym-saas-dev`) — não
   a nenhum `projectId` que o ficheiro de teste escolha. A primeira
   tentativa usou um `projectId` próprio (mesmo padrão dos outros 4
   ficheiros deste diretório) e `createBooking` respondia sempre
   `not-found`: a função lia/escrevia sob `demo-gym-saas-dev`, o teste
   semeava sob um projeto completamente separado dentro do mesmo
   emulador. Corrigido usando `demo-gym-saas-dev` como `PROJECT_ID`
   deste ficheiro (único dos 5 que precisa disto) — o isolamento fica
   só ao nível do `tenantId` (`tenant_booking_fn_test`, nunca usado
   pelo seed script nem pelos outros ficheiros de teste), não do
   projeto.

Depois destas duas correções, os 2 testes passam de forma repetível —
o output confirma, em cada uma das 5 repetições da primeira story,
exatamente 1 marcação aceite e a outra rejeitada com
`resource-exhausted`/"Já não há vagas", a garantia real a ser
provada, agora contra a transação que corre em produção
(`lib/bookingLogic.ts#runBookingTransaction`), não uma reimplementação
paralela dela. **Precisa de mais um passo antes de correr** (ver passo
2 abaixo): o Functions Emulator carrega `firebase/functions/lib/
index.js`, por isso `npm run build` tem de correr ANTES do emulador
arrancar — sem isto, a função nem chega a ficar registada.

**O que continua por verificar manualmente** (não tenho como correr
`flutter run` + clicar na app a partir daqui): todo o fluxo em Chrome —
criar série, "Gerar agora", confirmar ocorrências + auto-atribuição no
emulador, editar/cancelar uma ocorrência isolada, cancelar a série. Os
passos abaixo cobrem exatamente isto.

### Passos para verificar a Fase 5 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 2. Cloud Functions: build + lint (bookingLogic.ts, generateRecurringOccurrences.ts,
#    assignMembersToOccurrence.ts são código novo/refatorado desta fase)
cd firebase/functions
npm run build
npm run lint
cd ../..

# 3. 🔴 Security Rules + concorrência real via Cloud Function —
#    isolamento + plans/subscriptions + usage/bookings-fechados +
#    sessionSeries (Fase 5) + booking-concurrency (reescrito nesta
#    fase). PRECISA de firestore,functions,auth (não só firestore como
#    nas fases anteriores) — booking-concurrency.test.ts chama
#    createBooking a sério através do Functions Emulator. O passo 2
#    acima (`npm run build`) já deixou `firebase/functions/lib/`
#    pronto, que é o que o Functions Emulator carrega.
cd firebase/tests
npm install
cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth "npm --prefix firebase/tests test"
# Espera 53/53.

# 4. Seed (com o emulador completo a correr:
#    firebase emulators:start --project=demo-gym-saas-dev)
cd firebase/scripts
npm run seed
cd ../..
# Confirma no output que aparece "sessionSeries/series_test_hyrox_mon".

# 5. Testar como o Leo (Gestor)
flutter run -t lib/main_development.dart
# Login "leo@nxtperformancestudio.pt" / "DevPass123!". Gestão → Aulas/
# Horários → deve aparecer "Hyrox" (Segunda · 18:00 · Grupo (6)). Abre-a,
# confirma "Ainda não há ocorrências geradas", carrega "Gerar agora".

# 6. Confirmar a geração + auto-atribuição na UI do emulador
# (localhost:4000/firestore) — tenants/nxt_performance_studio/
# sessionOccurrences deve ter várias novas segundas-feiras futuras
# (até 8 semanas), cada uma com seriesId preenchido e
# activeBookingCount == 1 (a Rita). Confirma também que existe o
# booking dela em sessionOccurrences/{id}/bookings/{uid da Rita},
# source: "manager".

# 7. Confirmar do lado da Rita
# Login "000001" / "MemberPass123!" → "Marcações" deve já mostrar as
# sessões de Hyrox das próximas segundas, sem ela ter marcado nada.

# 8. Editar/cancelar uma ocorrência isolada sem afetar as outras
# Como o Leo, na série → escolhe uma ocorrência → "Editar esta
# ocorrência" (muda a hora ou capacidade) → confirma que só essa
# ocorrência muda (as outras segundas-feiras continuam iguais). Depois,
# noutra ocorrência, "Cancelar só esta" → confirma que desaparece de
# "Marcar treino" mas as restantes continuam disponíveis.

# 9. Cancelar a série inteira
# "Cancelar série" (com confirmação) → confirma na UI do emulador que
# TODAS as ocorrências futuras passam a status "cancelled", mas
# qualquer ocorrência já passada (se houver) fica intocada. "Gerar
# agora" deixa de fazer nada (série já não está ativa).

# 10. Criar uma sessão "só esta data" com pré-atribuição
# Gestão → Aulas/Horários → "+" → "Só esta data" → escolhe serviço,
# data/hora, capacidade, e pré-atribui a Rita no picker → "Criar".
# Confirma que a sessão aparece já com a Rita marcada (sem passar por
# "Gerar agora" — isto é atribuição imediata, não recorrente).
```

### Critério "Done" da Fase 5

> consegues criar uma série semanal, ver as próximas 4-8 semanas
> geradas automaticamente, editar só uma sem afetar as outras, e
> cancelar a série sem apagar ocorrências passadas.

Os passos 5-9 acima cobrem exatamente isto — horizonte de 8 semanas
(dentro do intervalo pedido), edição isolada confirmada por não afetar
as restantes, cancelamento de série confirmado por só afetar futuras.
**Continua por confirmar manualmente por ti** (ver "O que continua por
verificar" acima) — o mecanismo está implementado e os testes
automatizados (Dart + Rules) passam, mas ninguém clicou ainda na app a
sério para esta fase.

### Extensão pedida: gerar automaticamente ao criar a série (fora do guia)

Depois de testares o fluxo, perguntaste se fazia sentido o Gestor ter
de carregar num botão "Gerar agora" separado logo a seguir a criar uma
série — não fazia. `CreateSeriesScreen` passou a chamar `generateNow()`
automaticamente a seguir a `createSeries()` ter sucesso, para as
próximas ocorrências já aparecerem sem passo extra. O cron diário
(`generateRecurringOccurrences.ts`) continua necessário a seguir a
isto — só resolve o momento da criação, não o horizonte de 8 semanas a
continuar a avançar com o tempo. O botão "Gerar agora" em
`SeriesDetailScreen` mantém-se como ferramenta de apoio (ex.: se esta
chamada falhar, ou se o cron falhar nalgum dia) — falha aqui não desfaz
a série, só mostra uma mensagem a dizer para usares o botão manual.

### Extensão pedida: auditoria dos documentos funcionais (fora do guia)

Pediste para verificar se havia algum ponto da documentação funcional
(mockups em `Functional/nxt-studio-screens.html`, decisões fechadas em
`Functional/use-cases-update.md`) referente a esta fase ou às
anteriores que já devesse ter sido implementado. Cruzei os 40+ ecrãs
do mockup (cada um com a sua referência UC) e todas as decisões
fechadas contra as 11 fases do `guia-desenvolvimento.md` e o código
atual. A esmagadora maioria do que falta está corretamente arrumada em
fases futuras (Fase 6 em diante). Encontrei 4 pontos que existem nos
documentos funcionais mas nunca tinham sido atribuídos a NENHUMA fase
do guia técnico — não é "ainda não chegou a vez", caíram na fenda
entre os dois documentos. Dois foram implementados agora (ver secções
seguintes); dois ficaram documentados no próprio
`guia-desenvolvimento.md` (Fase 6), com a razão de não terem sido
feitos agora:

1. **UC01-A — recuperar password self-service**: precisa de enviar SMS/
   email de facto (nenhuma fase monta essa infraestrutura ainda) —
   ficou como story nova da Fase 6, com nota explícita.
2. **UC02 — perfil do aluno**: implementado agora, versão sem foto (ver
   abaixo).
3. **UC25 — visão global do Gestor**: implementado agora, versão sem
   "por modalidade" (ver abaixo).
4. **`Modality`** (Domain Model v1 §8-9): nunca foi modelada em
   nenhuma fase, apesar de ser pré-requisito do UC20 ("calendário do
   instrutor... por modalidade", já pedido explicitamente na Fase 6) e
   da decisão fechada do UC12/22 ("instrutor pode ter várias
   modalidades"). Ficou como primeira story nova da Fase 6, com nota
   explícita a dizer que o calendário não fica completo sem isto.

### Extensão pedida: UC02 — Perfil do Aluno (fora do guia)

Versão sem foto de perfil — precisaria de integrar Firebase Storage
(upload de imagem, `storage.rules`, picker), infraestrutura ainda não
tocada em nenhuma fase; sinalizado, não escondido. O que ficou:

- `MemberSummary` ganhou `phone`/`email` (contacto real, distinto do
  email SINTÉTICO usado só para login — esse nunca aparece aqui).
  `MemberRepository` ganhou `watchMember(uid)` e `updateOwnContact(...)`.
- **Lacuna de segurança real, apanhada ao construir isto — não só de
  UI**: `firestore.rules` tinha `members/{memberId}: allow read, write:
  if belongsToTenant(tenantId)` desde a Fase 1 — qualquer membro
  autenticado do tenant podia escrever no documento de QUALQUER OUTRO
  membro, incluindo `memberNumber`/`status`. Nunca explorado por
  nenhum ecrã existente, mas era uma autorização real a menos, não só
  uma omissão de UI. Corrigido: escrita ampla continua só Manager; o
  próprio membro só pode atualizar `phone`/`email` (+`updatedAt`) no
  SEU PRÓPRIO documento — `request.resource.data.diff(resource.data)
  .affectedKeys().hasOnly([...])` garante que nenhum outro campo muda
  nessa via, mesmo que o cliente tente.
- `MyProfileScreen` (novo): nome/nº de sócio em leitura, telefone/email
  editáveis. Acessível por um ícone novo na AppBar de `HomeScreen`, só
  quando `AppUser.isMember` (staff que não seja também membro, como o
  Leo, não tem `members/{uid}` — o ícone fica escondido para não levar
  a um beco sem saída).
- Testes: `my_profile_screen_test.dart` (mostra dados, guarda
  contacto, estado de erro sem documento) + 5 testes novos de Security
  Rules em `session-series-rules.test.ts` (próprio consegue,
  memberNumber/status bloqueados, outro membro bloqueado, Manager
  continua livre, Manager de outro tenant bloqueado).

### Extensão pedida: UC25 — Visão global do Gestor (fora do guia)

Versão mínima, sem "aulas/horários de todas as modalidades" do
mockup — depende de `Modality`, que não existe (ver acima). Agrega o
que já dá para agregar sem essa peça:

- `SessionOccurrenceRepository` ganhou
  `watchOccurrencesStartingBetween(from, to)` — ao contrário de
  `watchUpcomingOccurrences`, não filtra por `serviceId` (percorre
  todos os serviços do tenant).
- `GestorDashboardScreen` (novo, "Gestão → Visão global", primeiro
  card do hub): membros ativos, séries ativas, sessões agendadas nos
  próximos 7 dias, ocupação média nesse período.
- Teste: `gestor_dashboard_screen_test.dart` — confirma os 4 números
  com dados semeados propositadamente distintos (inclui uma ocorrência
  cancelada dentro da janela e uma fora da janela, para confirmar que
  nenhuma das duas entra na contagem/ocupação).

### Bug reportado: "dá para ver o horário/vagas mas não que treino é"

Reportaste que, em "Marcar treino", conseguias ver hora e vagas mas
não havia forma de saber a que serviço/aula cada sessão pertencia. Não
era só uma UI incompleta — eram dois bugs reais, um deles bastante
sério, ambos existentes desde fases anteriores e só agora visíveis a
sério por causa da Fase 5 (várias séries, potencialmente em serviços
diferentes, a coexistirem):

1. **`BookTrainingScreen` só mostrava ocorrências de UM serviço.**
   `primaryServiceProvider` ("o primeiro serviço ativo") era um hack
   deliberado da Fase 2, para não hardcodar um id de serviço quando só
   existia um. Ninguém o corrigiu quando a Fase 3 trouxe múltiplos
   serviços — funcionava por coincidência enquanto só havia sessões de
   um serviço de cada vez. Com a Fase 5 a permitir séries em serviços
   diferentes, isto passou a esconder sessões REAIS do aluno, em
   silêncio, sem nenhum aviso — o aluno nunca saberia que essas sessões
   existiam. Corrigido: `SessionOccurrenceRepository` ganhou
   `watchUpcomingOccurrencesAllServices()` (sem filtro de serviço);
   `primaryServiceProvider`/`upcomingOccurrencesProvider(serviceId)`
   ficaram sem consumidores e foram removidos.
2. **Nenhum cartão mostrava o nome do serviço.** Cada cartão em
   "Marcar treino" tinha só hora + vagas; a barra "X/Y sessões esta
   semana" (Fase 4) era única, fixa no topo, presumindo sempre o mesmo
   serviço. Corrigido: cada cartão mostra agora o nome do serviço (e
   do instrutor, quando definido); a barra de utilização deixou de ser
   global e passou a ser uma linha por cartão, com o serviço DESSA
   sessão.
3. **"Minhas marcações" nunca mostrou nada disto — nem sequer a
   hora.** Desde a Fase 2 ("fica para a próxima iteração") passando
   pela Fase 4 ("mostra sim, mas só o suficiente para calcular o aviso
   de cancelamento" — ou seja, os dados já eram lidos internamente,
   nunca mostrados), o ecrã mostrava literalmente só "Marcação
   #abc123" + a data em que a marcação tinha sido FEITA. Corrigido:
   cada cartão mostra agora o nome do serviço e a data/hora da SESSÃO
   (lida via `occurrenceProvider`, que já existia desde a Fase 4 —
   só nunca tinha chegado a aparecer no ecrã).

Testes atualizados/novos: `book_training_screen_test.dart` ganhou um
teste dedicado (duas séries, dois serviços diferentes, confirma que
AMBOS aparecem — a prova direta da correção do bug #1) e passou a
confirmar o nome do serviço no cartão; `my_bookings_screen_test.dart`
passou a semear um `services/service_1` e a confirmar o nome no
cartão, em vez de "Marcação #".

**Verificado**: `flutter analyze` limpo, **70/70 testes Dart** a
passar.

## Fase 6 — Operações do dia a dia (Instrutor/Gestor)

**Objetivo do guia:** dar ao Instrutor e ao Gestor as ferramentas do
dia a dia sobre uma sessão concreta — quem apareceu, ajustar vagas,
cancelar, remarcar, avisar os inscritos — e a primeira área da app
própria do Instrutor (até aqui só o Gestor tinha ecrãs de gestão,
decisão explícita da Fase 5).

### Decisão de arquitetura (perguntada ao Carlos antes de codificar)

O guia lista 9 stories, duas delas (notificações push, recuperação de
password) a precisar de infraestrutura nova (FCM, fornecedor SMS/
email) que eu não consigo configurar por ti. Perguntei se querias
deixá-las de fora desta fase ou avançar mesmo assim, com a ressalva
explícita de que ficariam incompletas sem essa configuração externa —
escolheste avançar com as 9. O que isso significa na prática, ponto a
ponto:

- **Notificações push**: o código fica todo implementado (token
  registration, Cloud Function, UI de envio), mas só entrega
  notificações de facto depois de configurares uma VAPID key (Web
  push) e/ou certificado APNs (iOS) na Firebase Console — um passo que
  não é feito por código, o mesmo tipo de passo manual já documentado
  desde a Fase 0 ("criar o Firebase Project"). Sem essa configuração,
  `getToken()` falha em silêncio (capturado, não propaga erro nenhum
  para o utilizador) e a app continua a funcionar normalmente, só sem
  entregar pushes.
- **Recuperação de password**: só é genuinamente self-service para
  **staff** (email real — `sendPasswordResetEmail` do Firebase Auth
  funciona de graça). Para **membros** (identificados por nº de sócio,
  email sintético nunca entregável), a app mostra uma mensagem
  explícita a dizer para contactar o Gestor — não finjo um mecanismo
  que não existe. Fica documentado que a parte de membros precisa de
  um fornecedor de SMS/email a decidir antes de ser implementada.

### O que foi acrescentado

- **`Modality`** (Domain Model v1 §8-9, pré-requisito acrescentado ao
  guia ao fechar a Fase 5): `lib/domain/entities/modality.dart` (`id`,
  `name`, `active`, `serviceIds` — lista de ids no próprio documento,
  Firestore Data Model v1 §12). `ModalityRepository`/
  `FirebaseModalityRepository`, mesmo padrão CRUD simples de
  `ServiceRepository`. `ManageModalitiesScreen` (novo card em
  "Gestão"). `StaffSummary` ganhou `modalityIds`; `CreateUserScreen`/
  `StaffDetailScreen` ganharam o picker (checkboxes) para instrutores.
  `SessionSeries`/`SessionOccurrence` ganharam `modalityId` opcional
  (copiado da série para a ocorrência na geração, mesmo padrão de
  `instructorId`); `CreateSeriesScreen` ganhou o dropdown, filtrado às
  modalidades ativas do serviço escolhido. `firestore.rules`:
  `modalities` — leitura ampla no tenant, escrita Manager (mesmo
  padrão de `services`/`plans`).
- **Roster de uma ocorrência — peça partilhada por presença/reduzir
  vagas/remarcar.** Até esta fase, nenhum ecrã mostrava os NOMES de
  quem estava inscrito numa sessão (só a contagem "X/Y").
  `BookingRepository` ganhou `watchBookingsForOccurrence`.
  `OccurrenceDetailScreen` (novo): cartão com serviço/modalidade/
  instrutor/hora/vagas + lista de inscritos, e é o ecrã onde vivem
  todas as ações desta fase — acessível a partir de
  `SeriesDetailScreen` e do calendário. `ManageSeriesScreen` passou a
  mostrar também "Sessões avulsas" (ocorrências `seriesId == null`,
  que até aqui, uma vez criadas, nunca mais apareciam em lado nenhum
  da Gestão).
- **Presença/no-show (UC10-A)**: `Attendance` (`memberId`, `status`
  attended/no_show, `recordedBy`, `recordedAt`) — documento isolado em
  `sessionOccurrences/{id}/attendance/{memberId}`, separado do
  `Booking` de propósito (Domain Model v1 §29). Escrita direta do
  cliente (sem invariante cross-documento, não precisa de Cloud
  Function) — Manager OU Instrutor; nova função `isInstructor(tenantId)`
  em `firestore.rules`. `OccurrenceDetailScreen`: toggle Presente/
  Faltou por inscrito.
- **Reduzir vagas (UC18 atualizado) + cancelamento pelo estúdio
  (UC18/UC10)**: ambos cross-documento (booking + contador + usage),
  por isso Cloud Function. `lib/bookingLogic.ts` ganhou o par
  `prepareRelease`/`applyRelease` (desenho em duas fases — Firestore
  exige que TODAS as leituras de uma transação aconteçam antes de
  qualquer escrita, o que impedia libertar vários membros num único
  loop transacional sem isto). `removeMembersFromOccurrence.ts` (novo)
  e `cancelOccurrenceForStudio.ts` (novo, substitui a escrita direta
  da Fase 5 — a limitação que a própria Fase 5 já tinha assinalado
  como "isso é Fase 6") partilham essa lógica; usage é SEMPRE
  devolvida (estúdio-iniciado, ao contrário de `cancelBooking.ts` que
  respeita a janela de antecedência mínima). `firestore.rules`:
  `sessionOccurrences.update` passou a exigir também que `status` não
  mude nessa escrita — cancelar já não pode saltar a cascata mesmo por
  um Manager. `OccurrenceDetailScreen`: "Reduzir vagas" (força escolher
  exatamente `atuais − novo limite` de quem sai) e "Cancelar sessão"
  (com aviso do nº de inscritos afetados).
- **Desativação de instrutor com cascata (UC24)**:
  `deactivateInstructor.ts` (novo) — marca `staff.status = inactive`,
  cancela todas as `sessionSeries` desse instrutor, e para cada
  ocorrência futura ainda agendada aplica a mesma cascata de
  `cancelOccurrenceForStudio` (uma transação por ocorrência — reutiliza
  `prepareRelease`/`applyRelease`). Novo índice composto
  `sessionOccurrences(instructorId, startAt)`. `StaffDetailScreen`: ao
  desligar um instrutor, mostra um diálogo de confirmação explicando a
  cascata e, no fim, um resumo (quantas séries/ocorrências/bookings
  foram afetados) — nunca finge que "desativar" é uma escrita simples
  quando na verdade cancela sessões de outras pessoas.
- **Remarcar aluno (UC10-B)**: `rescheduleBooking.ts` (novo) — cancela
  a marcação na ocorrência de origem (sempre com sucesso se existir) e
  tenta marcar no destino. **Não é atómico entre origem e destino**
  (são documentos/subcoleções diferentes) — se o destino falhar (sem
  vaga, sem elegibilidade), a função devolve um erro com `reason`
  prefixado `from-cancelled-*` para a UI mostrar isto com clareza, em
  vez de sugerir que nada aconteceu; `RescheduleFailedException`
  distingue esse caso de "não tinha marcação na origem" (erro comum/
  esperado). `OccurrenceDetailScreen`: botão "Remarcar" por inscrito,
  picker das próximas ocorrências do MESMO serviço.
- **Notificações push (UC21) + infraestrutura FCM**: `MemberRepository`/
  `StaffRepository` ganharam `registerFcmToken` (`arrayUnion`, nunca
  substitui tokens antigos — um dispositivo pode reinstalar a app).
  `fcmTokenRegistrationProvider` (novo) — chamado uma vez por sessão de
  login a partir de `HomeScreen`, pede permissão + regista o token,
  com falha SEMPRE silenciosa (ver decisão acima).
  `firestore.rules`: `fcmTokens` juntou-se à lista restrita de campos
  que o próprio membro pode escrever no seu documento (Fase 5, UC02);
  `staff` já tinha escrita ampla, sem alteração necessária.
  `sendNotification.ts` (novo) — alvo `memberId` único OU
  `occurrenceId` (todos os inscritos ativos dessa sessão; não existe
  nenhum conceito de "alunos do instrutor" independente de uma sessão
  concreta no Domain Model, por isso o alvo "todos os alunos" do
  mockup simplifica para isto — sinalizado). `SendNotificationScreen`
  (novo), acessível a partir de `OccurrenceDetailScreen` (todos os
  inscritos) e de `ManagerScreen` (um membro específico).
  `FirebaseMessaging.onMessage` em `HomeScreen` mostra um SnackBar em
  primeiro plano (sem `flutter_local_notifications`, fora de âmbito —
  mensagens em segundo plano/terminado já aparecem via o SO, sem
  código extra).
- **Calendário do instrutor (UC20)**: `InstructorCalendarScreen`
  (novo) — próximas 2 semanas, agrupadas por dia, cada sessão com
  serviço/modalidade/hora/vagas; toca → `OccurrenceDetailScreen` (o
  mesmo ecrã de gestão — os mockups mostram estas ações também na
  secção "Instrutor", não é um ecrã à parte). Ícone novo em `HomeScreen`
  (visível a um instrutor puro, filtrado à própria agenda) e card novo
  em `ManagerScreen` (sem filtro — "a visão do gestor" dos mockups é a
  mesma janela, todas as sessões).
- **Recuperação de password para staff (UC01-A)**: `AuthRepository`
  ganhou `sendPasswordResetEmail`. `LoginScreen`: link "Esqueci-me da
  password" — se o identificador introduzido contém `@` (mesma deteção
  já usada para login de staff desde a Fase 3), chama o Firebase Auth
  diretamente; sem `@` (nº de sócio), mostra o aviso "contacta o Gestor"
  descrito acima.

### Verificado

- `dart format` nos ficheiros desta fase, `flutter analyze
  --fatal-infos` (0 avisos) e **`flutter test` — 83/83 testes a
  passar**, incluindo os 13 novos desta fase (`modality_test.dart`,
  `attendance_test.dart`, `manage_modalities_screen_test.dart`,
  `occurrence_detail_screen_test.dart` — presença + reduzir vagas,
  fakes de repositório contra `FakeFirebaseFirestore`, nunca mock
  direto de `cloud_functions`, mesmo padrão de sempre).
- `npm run build` + `npm run lint` em `firebase/functions` — 0 erros,
  0 avisos, incluindo as 6 Cloud Functions novas desta fase
  (`removeMembersFromOccurrence`, `cancelOccurrenceForStudio`,
  `deactivateInstructor`, `rescheduleBooking`, `sendNotification`).
- 🔴 `firebase emulators:exec --only firestore,functions,auth "npm
  --prefix firebase/tests test"` — **73/73 testes de Security
  Rules/Functions a passar**, incluindo os 15 novos de
  `operations-rules.test.ts` (`modalities` Manager-only, `attendance`
  Manager/Instrutor nunca membro, `sessionOccurrences.status` bloqueado
  a escrita direta mesmo para Manager, `members.fcmTokens` na mesma
  regra restrita do próprio membro). Um teste da Fase 5
  (`session-series-rules.test.ts`, "Manager consegue cancelar só esta
  ocorrência") tinha ficado a assumir o comportamento ANTIGO — corrigido
  para refletir o bloqueio novo desta fase, com nota a apontar para
  `operations-rules.test.ts`.

**O que continua por confirmar manualmente** (sem como correr `flutter
run` + clicar na app a partir daqui): todo o fluxo em Chrome — ver os
passos abaixo. Em particular, notificações push e recuperação de
password de membro só têm como ser confirmadas depois das decisões de
infraestrutura pendentes (ver acima).

### Passos para verificar a Fase 6 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
# Espera 83/83.

# 2. Cloud Functions: build + lint
cd firebase/functions
npm run build
npm run lint
cd ../..

# 3. 🔴 Security Rules + Functions (precisa de firestore,functions,auth
#    — booking-concurrency.test.ts, da Fase 5, continua a chamar
#    createBooking a sério através do Functions Emulator)
firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth "npm --prefix firebase/tests test"
# Espera 73/73.

# 4. Com o emulador completo a correr (firebase emulators:start
#    --project=demo-gym-saas-dev) e o seed já feito (Fase 5):
flutter run -t lib/main_development.dart

# 5. Modalidades — como o Leo (Gestor)
# Gestão → Modalidades → "+" → cria "Pilates" → abre-a, ativa o
# serviço "Hyrox" → volta a "Aulas/Horários" → cria uma série nova →
# confirma que o dropdown de modalidade aparece e lista "Pilates".

# 6. Presença — abre uma sessão (a partir de "Aulas/Horários" ou do
# calendário) com inscritos → marca Presente num, Faltou noutro →
# confirma no emulador (localhost:4000/firestore) que
# sessionOccurrences/{id}/attendance/{uid} tem o status certo.

# 7. Reduzir vagas — na mesma sessão, "Reduzir vagas" → baixa a
# capacidade → escolhe exatamente quem sai → confirma que a
# capacidade e a contagem batem certo, e que o(s) membro(s) removido(s)
# recupera(m) a utilização semanal (Marcações dele(s) já não mostra
# essa sessão).

# 8. Cancelar sessão pelo estúdio — outra sessão com inscritos →
# "Cancelar sessão" → confirma que TODOS os inscritos recuperam a
# utilização semanal e a sessão desaparece de "Marcar treino".

# 9. Desativar um instrutor com sessões futuras — Gestão → Staff →
# escolhe um instrutor com séries/sessões futuras → desliga "Staff
# ativo" → confirma o diálogo de aviso e o resumo final → confirma que
# essas séries/sessões desaparecem.

# 10. Remarcar um aluno — numa sessão com inscritos, "Remarcar" num
# membro → escolhe outra sessão do mesmo serviço → confirma que ele
# sai da origem e aparece no destino.

# 11. Notificar — a partir de uma sessão, "Notificar inscritos" (envia
# a todos os ativos) e, a partir de Gestão → "Notificar um membro"
# (um só) → confirma que não crasha mesmo sem VAPID key configurada
# (mensagem "0 dispositivo(s)" é esperada sem essa configuração).

# 12. Calendário do instrutor — login como um Instrutor puro (sem
# Role.manager) → ícone novo na AppBar → confirma que só mostra as
# suas próprias sessões nas próximas 2 semanas. Como o Leo (Manager),
# Gestão → "Calendário" → confirma que mostra TODAS as sessões.

# 13. Recuperação de password — LoginScreen → "Esqueci-me da
# password" com "leo@nxtperformancestudio.pt" → confirma no emulador
# de Auth (localhost:4000/auth) que o email foi enviado. Com um nº de
# sócio → confirma a mensagem "contacta o Gestor", sem tentar enviar
# nada.
```

### Critério "Done" da Fase 6

> um Instrutor consegue ver a sua agenda, marcar presença, e o Gestor
> consegue reduzir vagas/cancelar uma sessão sem overbooking nem
> perder o histórico.

Os passos 6-9 e 12 acima cobrem exatamente isto — presença registada
por sessão, reduzir vagas/cancelar sempre com devolução de utilização
(nunca overbooking, `activeBookingCount` continua exclusivo das Cloud
Functions), agenda do instrutor a mostrar só as suas sessões. Remarcar
(UC10-B) e notificar (UC21) vão além do critério mínimo, também
cobertos (passos 10-11). **Continua por confirmar manualmente por ti**
— o mecanismo está implementado e os testes automatizados (Dart +
Cloud Functions + Rules) passam, mas ninguém clicou ainda na app a
sério para esta fase.

## Extensão pedida: dados pessoais em falta (fora do guia)

Reportaste que "Criar utilizador" pedia poucos dados (só nome para o
Aluno; nome+email para o Staff), que o Staff devia ter os mesmos dados
pessoais do Aluno, e que devia ser possível editar tudo isso depois de
criado, não só o que já era editável. Antes de mexer, confirmei
contigo duas decisões:

1. **Que campos acrescentar** — confirmaste todos os sugeridos:
   telefone, email, data de nascimento, morada, NIF, contacto de
   emergência. Nenhum destes está em nenhum mockup/use case atual (o
   mockup "Criar utilizador" só tem um único campo "Contacto"); ficam
   documentados aqui como decisão tua, não como algo já pedido nos
   documentos funcionais.
2. **Email do staff, ao editar** — confirmaste que deve sincronizar
   com o login (Firebase Auth), não ficar um campo solto.

### O que foi acrescentado

- **Domínio**: `MemberSummary` ganhou `birthDate`/`address`/`nif`/
  `emergencyContact` (todos opcionais, `''`/`null` por omissão —
  `phone`/`email` já existiam desde a Fase 5, UC02). `StaffSummary`
  ganhou os mesmos cinco campos (incluindo `phone`, que não existia
  para staff de todo).
- **`createMember.ts`/`createStaff.ts`**: schemas zod ganharam estes
  campos, todos opcionais — o Gestor pode não os ter à mão no momento
  da criação, e continua a poder preenchê-los depois. `birthDate`
  viaja como string ISO, guardado como `Timestamp`.
- **`updateStaffProfile.ts`** (Cloud Function nova, `requireManager`):
  única forma de editar dados de staff depois de criado. Ao contrário
  do membro (ver abaixo), o `email` do staff É o login real (decisão
  fechada da Fase 3) — por isso isto precisa de Admin SDK: se o email
  mudar, `auth.updateUser(uid, {email})` sincroniza a credencial de
  login junto com o Firestore, para nunca divergirem (editar só o
  Firestore deixaria o staff a tentar entrar com um email que já não
  bate certo). Trata `auth/email-already-exists` com uma mensagem
  clara em vez de deixar rebentar um erro genérico.
- **`MemberRepository.updateMemberProfile`** (novo): escrita direta do
  cliente — `firestore.rules` já dava ao Manager escrita ampla em
  `members/{id}` desde a Fase 1, e o email do membro nunca é o login
  (é sempre sintético), por isso não há nada no Firebase Auth para
  sincronizar aqui. Nenhuma alteração a `firestore.rules` foi
  necessária.
- **`PersonalDataFields`** (`lib/presentation/widgets/`, novo) —
  primeiro widget verdadeiramente partilhado da app: telefone, data de
  nascimento (com `showDatePicker`), morada, NIF e contacto de
  emergência apareciam de forma idêntica em três sítios (criar,
  editar Aluno, editar Staff) sem nenhuma lógica de negócio a variar
  entre eles — justifica a pequena abstração, ao contrário do resto da
  app, onde formulários parecidos ficam deliberadamente duplicados.
  Nome/email ficam FORA deste widget de propósito (semântica diferente
  em cada ecrã).
- **`CreateUserScreen`**: Aluno ganhou um campo de email de contacto
  (não existia nenhum) + `PersonalDataFields`; Staff ganhou
  `PersonalDataFields` (o email de login já existia).
- **`MemberDetailScreen`/`StaffDetailScreen`**: novo cartão "Dados
  pessoais", sempre editável (mesmo espírito de `MyProfileScreen` —
  campos + botão "Guardar", sem modo de edição à parte). O do Staff
  mostra um aviso a dizer que mudar o email muda o login.
- **Bug real apanhado a testar isto, não só uma lacuna de UI**:
  `CreateUserScreen._submit()` só desligava o spinner do botão no
  `finally`, DEPOIS do diálogo de credenciais (bloqueante) ter sido
  fechado — o `CircularProgressIndicator` indeterminado ficava a
  animar por baixo do diálogo enquanto este estava aberto. Invisível
  ao utilizador (o diálogo tapa o botão), mas foi o que apanhou isto:
  um `flutter test` a sério nunca estabilizava (`pumpAndSettle`
  timeout) depois de criar uma conta. Corrigido: o spinner desliga
  assim que a chamada de rede termina, antes de mostrar o diálogo —
  mesmo padrão já usado em `member_detail_screen.dart#_recalculate`
  desde a Fase 3.

### Verificado

- `dart format`, `flutter analyze --fatal-infos` (0 avisos), **`flutter
  test` — 94/94 testes a passar**, incluindo os 9 novos
  (`member_summary_test.dart`, `staff_summary_test.dart`,
  `create_user_screen_test.dart`, mais testes novos em
  `member_detail_screen_test.dart`/`staff_detail_screen_test.dart`).
- `npm run build` + `npm run lint` em `firebase/functions` — 0 erros,
  0 avisos, incluindo `updateStaffProfile.ts`.
- `firebase emulators:exec --only firestore,functions,auth "npm
  --prefix firebase/tests test"` — **73/73** (sem alterações a
  `firestore.rules` nesta extensão, por isso sem testes de Rules
  novos — `updateMemberProfile` usa a mesma regra de sempre para
  Manager, `updateStaffProfile` é Cloud Function, Admin SDK, fora do
  alcance das Rules).

**Por confirmar manualmente**: criar um Aluno/Staff com os novos
campos preenchidos; editar os dados de um membro e de um staff já
existentes a partir do respetivo ecrã de detalhe; confirmar que mudar
o email de um staff realmente muda o email de login (tentar entrar com
o email novo depois).

## Fase 7 — Treino livre

**Objetivo do guia:** grelha semanal configurável pelo Gestor para o
"Treino sem acompanhamento", com visibilidade diferente por papel —
sugestão automática a partir da semana anterior, revista/publicada
pelo Gestor, e só então visível ao Aluno.

### Decisões de arquitetura

Mockups (`Functional/nxt-studio-screens.html`) e use cases
(`Functional/use-cases-update.md`, UC09/UC17-A/UC10-A fechados) já
tinham isto bem definido — não precisei de perguntar nada de aberto
antes de codificar, só documentar as decisões que já estavam
fechadas:

1. **Modelo de dados**: `freeTrainingSchedules/{weekId}` (estado
   `draft`/`suggested`/`published`, Firestore Data Model v1 §39) +
   subcoleção `slots/` (§40) — cada slot reutiliza o MESMO mecanismo
   de capacidade/transação de `sessionOccurrences` (`lib/bookingLogic.ts`,
   Fase 2/4/5), só o caminho muda. "Treino sem acompanhamento" é um
   `Service` normal (Domain Model v1 §30) — nada de especial a criar
   em Gestão → Serviços.
2. **Visibilidade por papel** (UC09/UC17 fechado — o "Done" crítico
   desta fase): Aluno só vê a CONTAGEM de vagas, nunca nomes;
   Instrutor e Gestor veem nomes. Aplicado a sério nas Security Rules
   (`firestore.rules`), não só escondido na UI — um Aluno não consegue
   sequer `list` a subcoleção de bookings de um slot, só `get` a
   própria (ver testes novos abaixo).
3. **Presença** (UC10-A fechado): Manager-only para treino livre — ao
   contrário de `sessionOccurrences/attendance` (Fase 6, Manager OU
   Instrutor), aqui o Instrutor é sempre só leitura ("recurso
   partilhado", sem instrutor "dono").
4. **Sugestão automática** (UC17-A fechado): "nunca aplicada sozinha" —
   uma semana sem grelha nasce `draft` (vazia, sem semana anterior
   para copiar) ou `suggested` (copiada da semana anterior); só depois
   de "Aprovar e publicar" é que o Aluno a vê.

### O que foi acrescentado

- **Domínio**: `FreeTrainingSchedule` (`weekId`, `weekStart`, `status`,
  `createdBy`, `publishedAt`) e `FreeTrainingSlot` (`id`, `weekId`,
  `serviceId`, `startAt`, `endAt`, `capacity`, `activeBookingCount` —
  sem `status` próprio, ao contrário de `SessionOccurrence`: esta fase
  não pede cancelar um bloco isolado). Reutiliza `Booking`/`Attendance`
  tal como estão (Firestore Data Model v1 §40: "os bookings utilizam o
  mesmo conceito geral de booking") — só o caminho muda
  (`freeTrainingSchedules/{weekId}/slots/{slotId}/...`), por isso não
  há entidades `FreeTrainingBooking` nenhumas. `isoWeek.dart`/`isoWeek.ts`
  ganharam `weekIdForDate` (`YYYY-MM-DD` da segunda-feira da semana).
- **Cloud Functions novas**: `suggestFreeTrainingSchedule` (idempotente
  por `weekId` determinístico, mesmo padrão de
  `generateRecurringOccurrences`) + `publishFreeTrainingSchedule`
  (valida ≥1 slot, `status → published`) controlam o estado da semana.
  `bookFreeTrainingSlot`/`cancelFreeTrainingBooking`/
  `assignMembersToFreeTrainingSlot` reutilizam `resolveEligibility`/
  `runBookingTransaction`/`prepareRelease`/`applyRelease` de
  `lib/bookingLogic.ts` — mesma validação de elegibilidade/capacidade/
  limite semanal de sempre, sem nenhuma lógica de negócio duplicada.
  `cancelFreeTrainingBooking` não reutiliza `cancelBooking.ts` (a
  janela de antecedência mínima já não usava `bookingLogic.ts` desde a
  Fase 6) — duplicado deliberadamente em vez de refatorar código já
  testado sem necessidade.
- **`firestore.rules`**: `freeTrainingSchedules` — só Manager lê
  rascunho/sugestão, qualquer membro do tenant lê uma semana
  `published`; escrita sempre `false` (Cloud Functions). `slots` —
  mesma visibilidade da semana-mãe (via `get()` explícito ao
  documento pai — Rules não herdam a condição do `match` pai
  automaticamente); Manager escreve diretamente para montar a grelha
  (mesmo padrão de `sessionOccurrences` ad-hoc), `activeBookingCount`
  exclusivo das Cloud Functions, `delete` sempre `false`. `bookings` —
  um Aluno só consegue `get` a PRÓPRIA marcação, nunca `list` nem `get`
  a de outro membro; Instrutor/Gestor listam todas. `attendance` —
  Manager-only (não `isInstructor`, ao contrário de
  `sessionOccurrences/attendance`).
- **`FreeTrainingRepository`/`FirebaseFreeTrainingRepository`** (novo):
  `watchSchedule`/`watchSlots`/`watchSlotBookings`/`getMyBooking`
  (`get`, não `list` — é o único caminho que a Rule permite a um
  Aluno)/`watchSlotAttendance`/`suggestSchedule`/`publishSchedule`/
  `createSlot`/`updateSlotCapacity`/`bookSlot`/`cancelSlotBooking`/
  `assignMembers`/`recordAttendance`. Reutiliza as mesmas exceções de
  `BookingRepository` (`BookingCapacityExceededException`,
  `AlreadyBookedException`, etc.) — mesmo mecanismo por baixo, não faz
  sentido duplicar os tipos de erro.
- **`FreeTrainingScreen`** (novo, 3º separador em `HomeScreen`,
  "Livre") — navegação semana a semana, lista de horários da semana
  `published` agrupada por dia, "HH:MM–HH:MM · N vaga(s)
  restante(s)" + Reservar/Cancelar (nunca mostra quem mais está
  inscrito — nem pede essa informação ao repository).
- **`ManageFreeTrainingScreen`** (novo, "Gestão → Treino livre") —
  gerar a sugestão da semana (escolhe o serviço), banner de estado
  (rascunho/sugestão por aprovar/publicada), lista de blocos por dia,
  "Adicionar bloco de horário" (dias da semana em chips + hora +
  capacidade + serviço → cria um slot concreto por dia selecionado —
  o "bloco" do mockup é só conveniência de autoria, por baixo são
  sempre slots individuais), "Aprovar e publicar semana".
- **`FreeTrainingSlotDetailScreen`** (novo) — roster COM nomes
  (Manager/Instrutor), presença (Manager-only), atribuir membros
  manualmente (Manager-only, `eligibleMembersProvider` já existia
  desde a Fase 5).
- **`InstructorCalendarScreen`** (Fase 6, estendido) — passou a
  mesclar também os slots de treino livre publicados (semana atual +
  seguinte) numa secção "Treino livre" por dia, mesmo espírito do
  mockup "Semana — visão do gestor" (UC20 atualizado: "recurso
  partilhado, visível a qualquer instrutor"). Só semanas `published`
  entram aqui, mesma restrição que a Security Rule já aplica —
  rascunho/sugestão ficam exclusivos de `ManageFreeTrainingScreen`.
  Lacuna aceite e sinalizada no código: a janela de 2 semanas pode, em
  teoria, tocar numa 3ª semana ISO parcial quando "hoje" não é
  segunda-feira; cobrimos sempre a semana atual e a seguinte.

### Verificado

- `dart format`, `flutter analyze --fatal-infos` (0 avisos), **`flutter
  test` — 107/107 testes a passar**, incluindo os 13 novos desta fase
  (`free_training_schedule_test.dart`, `free_training_slot_test.dart`,
  `free_training_screen_test.dart` — prova direta de que o ecrã do
  Aluno só mostra contagem, nunca nomes —,
  `manage_free_training_screen_test.dart`). `auth_gate_test.dart`
  precisou de `initializeDateFormatting('pt_PT')` (o novo 3º tab de
  `HomeScreen` formata uma data logo no primeiro build, mesmo sem
  estar selecionado — `IndexedStack` constrói todos os tabs).
- `npm run build` + `npm run lint` em `firebase/functions` — 0 erros,
  0 avisos, incluindo as 5 Cloud Functions novas.
- 🔴 `firebase emulators:exec --only firestore,functions,auth "npm
  --prefix firebase/tests test"` — **97/97 testes de Security
  Rules/Functions a passar**, incluindo os 24 novos de
  `free-training-rules.test.ts` — a prova real do "Done" crítico desta
  fase: um Aluno consegue ler a própria marcação mas falha a ler a de
  outro membro (`get`) e falha a listar a subcoleção inteira (`list`);
  Instrutor/Gestor conseguem ambos; um Instrutor falha a registar
  presença (só Manager); ninguém escreve `freeTrainingSchedules`
  diretamente, nem apaga um `slot`, mesmo sendo Manager.

Um bug real apanhado ao testar a sério (não só uma lacuna de
cobertura): `_FakeFreeTrainingRepository` nos testes de widgets usava
`Stream.value(...)` para simular `watchSchedule`/`watchSlots` — isso
só emite o valor capturado no momento em que o provider é observado
pela primeira vez, nunca reflete mutações seguintes (gerar sugestão,
adicionar bloco, publicar). Corrigido com `StreamController.broadcast`
— mesma armadilha que um `FakeFirebaseFirestore` real não tem (o seu
`snapshots()` já é reativo por natureza), só apanhada aqui por não
haver Firestore nenhum a testar (o repository de treino livre é
maioritariamente Cloud Functions).

**Por confirmar manualmente**: gerar a sugestão de uma semana nova (com
e sem semana anterior para copiar), adicionar/ajustar blocos, publicar
e confirmar que só aí o Aluno passa a ver os horários; reservar e
cancelar como Aluno (confirmar que a utilização semanal seguinte
respeita `minCancellationNoticeHours` tal como as aulas); atribuir
manualmente um membro como Gestor; registar presença; confirmar em
Chrome (não só nos testes) que um Aluno nunca vê nomes em lado nenhum
do fluxo de treino livre.

### Passos para verificar a Fase 7 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Confirmar que tudo continua a compilar/passar
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
# Espera 107/107.

# 2. Cloud Functions: build + lint
cd firebase/functions
npm run build
npm run lint
cd ../..

# 3. 🔴 Security Rules + Functions
firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth "npm --prefix firebase/tests test"
# Espera 97/97.

# 4. Com o emulador completo a correr e o seed já feito:
flutter run -t lib/main_development.dart

# 5. Como o Leo (Gestor) — criar e publicar uma semana
# Gestão → Treino livre → escolhe o serviço "Treino sem
# acompanhamento" (cria-o primeiro em Gestão → Serviços, se ainda não
# existir) → "Gerar grelha desta semana" → "Adicionar bloco de
# horário" (ex.: Segunda a Sexta, 06:00–08:00, capacidade 10) →
# confirma que aparecem os slots dessa semana → "Aprovar e publicar
# semana".

# 6. Como a Rita (Aluno)
# Tab "Livre" → confirma que os horários da semana publicada aparecem
# com contagem de vagas ("N vaga(s) restante(s)"), NUNCA nomes →
# "Reservar" → confirma que passa a "Cancelar" → "Cancelar" → volta a
# "Reservar".

# 7. Confirmar a visibilidade por papel na UI do emulador
# (localhost:4000/firestore) — tenants/nxt_performance_studio/
# freeTrainingSchedules/{weekId}/slots/{slotId}/bookings deve ter o
# booking da Rita; volta à app como o Leo → Gestão → Treino livre →
# toca num slot → confirma que vês o NOME da Rita na lista de
# inscritos (Gestor/Instrutor veem; Aluno nunca vê isto em lado
# nenhum).

# 8. Presença e atribuição manual
# No mesmo ecrã de detalhe do slot, marca presença da Rita → confirma
# que só aparece esse botão para o Leo (Gestor), não apareceria para
# um Instrutor. "Atribuir" → escolhe outro membro elegível → confirma
# que fica inscrito sem ele próprio ter reservado.

# 9. Calendário mesclado
# Gestão → Calendário (ou "As minhas aulas" como Instrutor) → confirma
# que a semana com o treino livre publicado mostra também a secção
# "Treino livre" por dia, com nomes.
```

### Critério "Done" da Fase 7

> um Aluno nunca consegue, por rules nem por UI, ver o nome de outro
> aluno inscrito no treino livre — mas o Gestor consegue.

Os 24 testes de `free-training-rules.test.ts` provam exatamente isto
do lado do servidor (não só a UI): um Aluno falha `get`/`list` sobre a
marcação de outro membro, Instrutor/Gestor conseguem ambos. O passo 7
acima confirma o mesmo comportamento a sério, em Chrome.
**Continua por confirmar manualmente por ti** (ver "O que continua por
verificar" acima) — o mecanismo está implementado e os testes
automatizados (Dart + Cloud Functions + Rules) passam, mas ninguém
clicou ainda na app a sério para esta fase.

## Fase 8 — Avaliações e histórico de treino

**Objetivo do guia:** dados históricos do aluno, nunca sobrescritos —
avaliações físicas, evolução de carga por exercício, plano de treino
montado a partir de uma biblioteca partilhada.

### Decisões de arquitetura

Os documentos técnicos (`Domain Model v1` §33-34, `Firestore Data
Model v1` §43-44) descrevem a FORMA das coleções mas não enumeram
campos nem resolvem tudo como caminhos Firestore literais — três
decisões fechadas por mim ao codificar, documentadas aqui:

1. **Os "17 campos" da avaliação** (UC04/UC14) só existem enumerados
   no mockup (`Functional/nxt-studio-screens.html`), não nos
   documentos técnicos. Contagem: idade + 9 campos de composição
   corporal (peso, altura, IMC, %massa gorda, massa muscular, gordura
   visceral, metabolismo basal, %água, idade metabólica) + 3 de saúde
   (pressão arterial, perímetro cintura, perímetro abdominal) + 5
   físicos (força MS/MI/core, flexibilidade, resistência) = 18 campos
   mostrados, mas o IMC é `Auto` no mockup (sempre calculado de
   peso/altura, nunca um input) — por isso "17 campos definidos" bate
   certo com 18 mostrados menos 1 calculado.
2. **Caminho do histórico de carga**: o guia escreve
   `members/{id}/training/loadHistory/` — isto não resolve como um
   caminho Firestore válido (segmentos ímpares, sem um documento fixo
   intermédio claro). Modelado como subcoleção direta
   `members/{id}/loadHistory/{recordId}`, mesmo padrão "flat" já usado
   em todo o resto da app.
3. **Plano de treino**: nenhum documento técnico modela isto (só
   assessments/loadHistory têm secção própria), apesar do guia pedir
   explicitamente o ecrã. Modelado como
   `members/{id}/planEntries/{entryId}` — cada entrada referencia um
   exercício da biblioteca partilhada + a prescrição específica deste
   membro (séries/reps/carga).

### O que foi acrescentado

- **Domínio**: `Assessment` (17 campos + `imc` calculado como getter,
  nunca persistido) — `updatedAt`/`updatedBy` só preenchidos numa
  edição (UC04/UC14 fechado: "o Instrutor pode corrigir uma já
  registada"). `LoadHistoryEntry` (append-only). `Exercise`
  (nome/descrição/grupo muscular/`videoPath` opcional — o caminho no
  Storage, nunca a URL de download, que pode expirar). `TrainingPlanEntry`
  (séries/reps/`currentLoad` — sempre o valor mais recente, nunca a
  fonte de verdade do histórico).
- **Repositórios** (`AssessmentRepository`, `LoadHistoryRepository`,
  `ExerciseRepository`, `TrainingPlanRepository`) — escrita direta do
  cliente (Instrutor/Gestor), sem Cloud Function: nenhuma invariante
  cross-documento a proteger, mesmo raciocínio já usado para
  `AttendanceRepository` desde a Fase 6. Exceção:
  `TrainingPlanRepository.updateLoad`/`addEntry` usam um `WriteBatch`
  para gravar a entrada do plano E o novo registo de histórico juntos
  — nunca um sem o outro, para os dois nunca divergirem.
- **Storage — primeira vez a sério nesta app** (Platform Foundation
  §19, já antecipava isto: "será implementado quando existir upload
  real"). `storage.rules` deixou de ser deny-all: vídeo de exercício
  em `tenants/{tenantId}/exercises/{exerciseId}/video`, leitura ampla
  no tenant (o Aluno precisa de ver o vídeo do seu plano), escrita
  Instrutor/Gestor, só `contentType` `video/*` até 100MB — "formato ou
  tamanho inválido é rejeitado" (mockup) aplicado a sério no servidor,
  não só na UI. `StorageRepository`/`FirebaseStorageRepository` (novo)
  — abstração pedida explicitamente pela Platform Foundation §19,
  mesmo princípio de `AuthRepository`. Dependências novas:
  `file_picker` (devolve bytes, não `dart:io File` — único jeito de
  funcionar sem ramificação por plataforma em Flutter Web) e
  `video_player` (oficial do Flutter). Emulador de Storage ligado no
  bootstrap (linha já preparada desde a Fase 0, só comentada).
- **`firestore.rules`**: `assessments`/`loadHistory`/`planEntries`
  (nested em `members/{memberId}`) — o próprio membro só LÊ o seu
  (nunca escreve), Instrutor/Gestor leem e escrevem. `loadHistory` é
  o único caso da app com `allow create` mas `update`/`delete` sempre
  `false`, mesmo para Manager — "nunca sobrescrever o histórico"
  (UC16 fechado) garantido a sério, não só por convenção do cliente.
  `exercises` — leitura ampla, escrita Instrutor OU Gestor (não
  Manager-only como `services`/`plans`/`modalities`: a biblioteca é
  ferramenta do dia a dia do Instrutor, não decisão de negócio).
- **Ecrãs Instrutor**: `InstructorStudentsScreen` ("Alunos", novo
  ponto de entrada — reutiliza `membersProvider`, já existia desde a
  Fase 3) → `StudentTrainingScreen` ("Ficha do aluno": plano + contagem
  de avaliações + "Nova avaliação" em destaque) →
  `AssessmentFormScreen` (criar/editar, mesmo formulário para os dois,
  17 campos com validação obrigatória + pré-visualização do IMC) /
  `TrainingPlanEditorScreen` (adicionar da biblioteca via
  `AddPlanEntryScreen`, atualizar carga, remover). `ExerciseLibraryScreen`
  + `ExerciseFormScreen` (criar/editar + upload de vídeo).
- **Ecrãs Aluno** (ícones novos na AppBar de `HomeScreen`, visíveis só
  quando `isMember`): `MyTrainingPlanScreen` ("O meu plano" — toca num
  exercício → vídeo demonstrativo ou evolução de carga, exatamente as
  duas ações do mockup). `LoadEvolutionScreen` (carga atual + delta
  desde o primeiro registo + histórico completo, mais recente
  primeiro). `AssessmentListScreen`/`AssessmentDetailScreen`
  reutilizados tal como estão do lado do Instrutor — só o botão
  "Editar" no detalhe fica escondido para um Aluno.

### Verificado

- `dart format`, `flutter analyze --fatal-infos` (0 avisos), **`flutter
  test` — 127/127 testes a passar**, incluindo os 20 novos desta fase
  (4 ficheiros de domínio + `assessment_form_screen_test.dart` —
  prova que campos obrigatórios em falta bloqueiam a gravação e que o
  IMC é calculado corretamente — + `training_plan_editor_screen_test.dart`
  — prova que "Atualizar carga" chama sempre `updateLoad`, nunca um
  `update` de campo isolado).
- `npm run build` + `npm run lint` em `firebase/functions` — 0 erros
  (sem alterações nesta fase — tudo escrita direta do cliente, sem
  Cloud Function nova).
- 🔴 `firebase emulators:exec --only firestore,functions,auth,storage
  "npm --prefix firebase/tests test"` — **123/123 testes de Security
  Rules/Functions a passar**, incluindo os 19 novos de
  `training-rules.test.ts` (assessments/loadHistory/planEntries só o
  próprio membro lê, `loadHistory` nunca aceita `update`/`delete` nem
  para Manager, `exercises` aceita escrita de Instrutor) e os **7
  primeiros testes de Storage Rules desta app**
  (`storage-rules.test.ts` — leitura ampla no tenant, escrita
  Instrutor/Gestor, `contentType` errado rejeitado, isolamento entre
  tenants).

**Por confirmar manualmente**: criar uma avaliação completa e depois
editá-la; criar um exercício na biblioteca e carregar um vídeo mp4 a
sério (confirmar que reproduz no ecrã do Aluno); montar um plano para
um aluno e atualizar a carga de um exercício várias vezes, confirmando
que o histórico completo aparece em "Evolução da carga"; confirmar que
um Aluno nunca consegue editar nada disto, só ver o seu próprio.

### Passos para verificar a Fase 8 localmente

Comandos em PowerShell — sem `&&`; cada passo em linhas separadas.

```powershell
# 1. Instalar as dependências novas (file_picker, video_player) e
#    confirmar que tudo continua a compilar/passar
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
# Espera 127/127.

# 2. Cloud Functions: build + lint (sem alterações nesta fase, só para
#    confirmar que nada regrediu)
cd firebase/functions
npm run build
npm run lint
cd ../..

# 3. 🔴 Security Rules (Firestore + Storage) + Functions
firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth,storage "npm --prefix firebase/tests test"
# Espera 123/123.

# 4. Com o emulador completo a correr e o seed já feito:
flutter run -t lib/main_development.dart

# 5. Como o Leo (Instrutor/Gestor) — biblioteca + plano
# Gestão → Biblioteca de exercícios → "+" → cria "Agachamento com
# barra" (Pernas) → guarda → reabre o exercício → "Carregar vídeo
# demonstrativo (mp4)" → escolhe um ficheiro .mp4 pequeno → confirma
# "Vídeo carregado." e o pill muda para "Com vídeo".

# 6. Avaliação da Rita
# Gestão → Alunos → Rita Ferreira → "Nova avaliação" → tenta guardar
# vazio (confirma "Obrigatório" nos campos) → preenche os 17 campos →
# confirma que o IMC aparece calculado (não editável) → guarda →
# confirma que aparece em "Avaliações (1)" → abre-a → "Editar" → muda
# o peso → guarda → confirma que mostra "Editada em ..." no detalhe.

# 7. Plano de treino da Rita
# Na ficha da Rita → "Plano de treino" → "+" → procura "Agachamento" →
# define séries/reps/carga inicial → "Adicionar ao plano" → confirma
# que aparece na lista → menu (⋮) → "Atualizar carga" → novo valor →
# "Guardar".

# 8. Confirmar do lado da Rita (login "000001")
# Ícone "O meu plano" → confirma o exercício com séries/reps/carga
# atual → toca-lhe → "Ver vídeo demonstrativo" (se tiveres carregado
# um no passo 5) → volta → "Ver evolução da carga" → confirma que
# aparecem os DOIS registos (o inicial + a atualização do passo 7),
# mais recente primeiro, com o delta calculado. Ícone "As minhas
# avaliações" → confirma que vês a avaliação criada no passo 6, SEM
# nenhum botão "Editar".
```

### Critério "Done" da Fase 8

> atualizar uma carga nunca apaga a anterior, e o aluno consegue ver a
> evolução completa.

O passo 7-8 acima cobre exatamente isto — cada atualização de carga
cria um `LoadHistoryEntry` novo (`firestore.rules` bloqueia `update`/
`delete` mesmo para Manager, testado a sério em
`training-rules.test.ts`), e "Evolução da carga" mostra a lista
completa, não só o valor atual. **Continua por confirmar manualmente
por ti** — o mecanismo está implementado e os testes automatizados
(Dart + Rules, incluindo Storage pela primeira vez) passam, mas
ninguém clicou ainda na app a sério para esta fase, em particular o
upload de vídeo real (só testado via bytes sintéticos no emulador).

## Auditoria funcional Fase 0-8 (mockups + use cases) — lote de correções

Pedido teu depois de fechar a Fase 8: *"verifica se até esta fase está
tudo implementado que deveria estar a nível funcional, vê os mockups e
os use cases"*. Comparei `Functional/nxt-studio-screens.html` e
`Functional/use-cases-update.md` contra o código, excluindo o que já
estava assinalado como limitação conhecida nas secções anteriores
deste README. Resultado: **7 lacunas reais** + 2 pontos ambíguos, todos
corrigidos neste lote.

### 1. UC08-A "Sessão extra" existia no modelo, mas nunca era `true`

`Booking.isExtra` estava no domínio desde a Fase 2 e o mockup "Detalhe
da aula" mostra um botão "+ Sessão extra" — mas
`lib/bookingLogic.ts#runBookingTransaction` tinha `const isExtra =
false` hardcoded, com um comentário a admitir que estava por
implementar. Ou seja: a exceção do UC08 ("por omissão, atribuir =
contar"; a única exceção é a sessão extra explícita) nunca era
possível.

- `runBookingTransaction` ganhou `isExtra` como parâmetro real.
  `assignMembersToOccurrence.ts` ganhou-o no schema zod e passa-o
  adiante; os restantes caminhos (self-service, geração de séries)
  continuam a passar `false` por omissão.
- **`isExtra` isenta do LIMITE SEMANAL do plano, nunca da capacidade
  da sala** — são restrições diferentes e independentes. O
  `activeCount >= capacity` continua a aplicar-se sempre. O "2/2
  sessões" do mockup é o limite do plano, não a lotação.
- `assignMembersToOccurrence` passou de `requireManager` para
  `requireManagerOrInstructor`: passa a servir dois botões num ecrã
  onde presença/reduzir vagas/cancelar/remarcar já eram Manager OU
  Instrutor desde a Fase 6 — não fazia sentido só esta ação ser mais
  restrita que as vizinhas na mesma tela.

### 2. Antecedência mínima para MARCAR não existia (UC06/07/08/09 fechado)

Havia `minCancellationNoticeHours` (Fase 4, para *cancelar*), mas o use
case fechado pede explicitamente o lado oposto — *"não pode marcar-se,
por exemplo, 5 minutos antes da aula começar, e esse valor deve ser
configurável pelo Gestor"*. Não existia nada.

- Campo irmão `minBookingNoticeMinutes` no mesmo documento
  `tenants/{t}/config/bookingPolicy`, validado no servidor em
  `createBooking.ts` **e** `bookFreeTrainingSlot.ts`.
- Só se aplica ao caminho **self-service**. Atribuição manual por
  Instrutor/Gestor nunca passa por esta validação — mesmo espírito do
  UC08-A: o estúdio pode sempre decidir.
- Nova `TooCloseToStartException` (Dart) para a UI mostrar a mensagem
  exata em vez de um erro genérico; `TenantSettingsScreen` ganhou o
  segundo campo, a par do de cancelamento.

### 3. Blocos de treino livre não se podiam editar nem remover

`updateSlotCapacity` existia no repository desde a Fase 7 mas **nunca
foi ligado a nenhum ecrã** (código morto), e não havia forma nenhuma
de apagar um bloco criado por engano — `firestore.rules` tinha `allow
delete: if false` para `slots`.

- `updateSlotCapacity` → `updateSlot` (ganhou `startAt`/`endAt`: não
  fazia sentido só a capacidade ser editável) + `deleteSlot` novo,
  ambos ligados a um menu (⋮) em `ManageFreeTrainingScreen`.
- Security Rules: `delete` passa a ser permitido **só antes de a
  semana ser publicada** e **só com `activeBookingCount == 0`**.
  Depois de publicada continua `false` mesmo para o Gestor — alunos
  podem já ter marcado; nesse caso reduz-se a capacidade, não se
  apaga. Coberto por 4 testes novos em `free-training-rules.test.ts`.

### 4. Texto desatualizado no diálogo de cancelar ocorrência

`SeriesDetailScreen` ainda dizia *"Cancelar aqui NÃO cancela nem
notifica essas marcações automaticamente (isso é Fase 6)"* — mentira
desde a Fase 6, quando `cancelOccurrenceForStudio` passou a cascatar o
cancelamento e a devolver a utilização. Corrigido para descrever o que
realmente acontece.

### 5. Calendário não tinha a navegação do mockup

O mockup "Semana — visão do gestor" mostra navegação semana a semana +
tabs Seg-Dom. `InstructorCalendarScreen` mostrava uma lista contínua
de "próximas 2 semanas", sem forma de recuar nem de saltar para um dia.

- Provider novo `occurrencesForWeekProvider` (família por semana ISO)
  substitui `upcomingTwoWeeksOccurrencesProvider` (janela fixa a
  partir de "agora", que não permitia navegar para trás).
- Setas de semana + `ChoiceChip` Seg-Dom; a secção "Treino livre"
  passou a ser do dia selecionado.
- **Simplificação sinalizada:** o mockup mostra nomes na
  pré-visualização ("9/12 · Rita, Miguel, Tiago..."). Isso exigiria
  carregar os bookings de CADA sessão da semana só para a
  pré-visualização (N+1 queries); mantive só a contagem — tocar na
  sessão abre `OccurrenceDetailScreen`, que já mostra os nomes.

### 6. Ocorrências ad-hoc não tinham "Editar aula" nem "Adicionar membro"

Estas ações existiam, mas só no menu (⋮) da lista de
`SeriesDetailScreen` — ou seja, **só para ocorrências geradas por uma
série**. Uma sessão "só esta data" só era alcançável via
`OccurrenceDetailScreen`, que não as tinha. `OccurrenceDetailScreen`
ganhou "Editar aula", "Adicionar membro" e "+ Sessão extra" (o gatilho
de UI do ponto 1), fechando a lacuna para ambos os tipos.

### 7. Aviso de conflito de horário — e porque NÃO é "sala"

O mockup diz *"Conflito de horário com outra aula da mesma sala é
sinalizado antes de guardar"*. Procurei `Room`/`Sala` em todos os
documentos técnicos (Domain Model v1, Firestore Data Model v1,
Platform Foundation): **não existe em lado nenhum**. Inventar a
entidade agora seria fabricar dados que ninguém decidiu.

Implementei o proxy real e defensável: aviso quando **o mesmo
instrutor** já tem outra sessão sobreposta (série recorrente no mesmo
dia da semana, ou ocorrência já materializada no mesmo dia concreto).
Nunca bloqueia — só avisa; a decisão é do Gestor. **Sinalizado, não
escondido:** se quiseres a versão "sala" a sério, é preciso primeiro
decidir a entidade `Room` e associá-la a séries/ocorrências.

### Ambíguo #1 — exclusividade de nível de sala (UC26 atualizado)

O UC26 fechado diz que "Sem acompanhamento" e Standard/Plus/Premium
**não são produtos independentes, são níveis do mesmo produto** — e o
mockup mostra-os como *radio buttons* ("escolha uma opção"), enquanto
Aulas de grupo e PT continuam checkboxes livremente combináveis. O
código só impedia duas subscriptions ativas para o **mesmo
`serviceId`** (Fase 3), o que nunca apanhava "Sem acompanhamento" +
"Standard" (serviços diferentes).

- `Service` ganhou `exclusiveGroup` (identificador livre, `null` na
  maioria). Serviços com o **mesmo** grupo passam a ser mutuamente
  exclusivos.
- `createSubscription.ts` valida agora conflito por serviço **ou** por
  grupo. Coberto por 3 testes novos que chamam a Cloud Function a
  sério no emulador (`subscription-exclusive-group.test.ts`),
  incluindo o caso negativo (serviço sem grupo continua combinável).
- `ManageServicesScreen` passou a permitir editar um serviço (nome +
  grupo), não só criar/ativar.

### Ambíguo #2 — home dedicada ao Instrutor puro

O mockup tem um ecrã "Início — Dashboard do instrutor". Um Instrutor
puro (sem `Role.manager` e sem `Role.member`) caía no `HomeScreen` do
Aluno: via "Marcar treino"/"Treino livre"/"Minhas marcações" — que não
se lhe aplicam, não tem plano nem marcações — com as ferramentas reais
escondidas atrás de ícones na AppBar.

`InstructorHomeScreen` novo: duas estatísticas ("Sessões hoje" só as
dele, "Alunos ativos") + atalhos para Alunos / Biblioteca de
exercícios / As minhas aulas / Enviar notificação. Um instrutor que
**também** é membro continua a ver os separadores de Aluno (para esse
lado da conta são reais).

Duas notas honestas: "Nova avaliação" não é atalho de topo porque criar
uma avaliação exige escolher o aluno primeiro (passa por "Alunos"); e
"Alunos ativos" conta todos os alunos ativos do tenant, não só os da
modalidade do instrutor — o âmbito por modalidade (UC28) nunca foi
modelado como restrição real, é a mesma lacuna já assinalada na Fase 8,
não uma nova.

### Verificação

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
cd firebase/functions
npm run build
npm run lint
cd ../..
firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth,storage "npm --prefix firebase/tests test"
```

Estado atual: `flutter analyze --fatal-infos` limpo, **141 testes Dart**
a passar, `npm run build`/`lint` limpos, **131 testes** no emulador
(10 ficheiros) a passar — incluindo os 9 testes novos deste lote
(2 antecedência mínima, 4 delete de slots, 3 exclusividade de grupo).
Corri a suite do emulador duas vezes seguidas para confirmar que não
ficou nada instável.

Dois problemas de fiabilidade de testes apanhados e corrigidos pelo
caminho (ambos meus, introduzidos neste lote):

- `subscription-exclusive-group.test.ts` rebentava por *timeout* de 5s
  na primeira invocação — o arranque do runtime do Functions Emulator
  soma-se ao tempo da função (~250ms), e este ficheiro corre em
  paralelo com o de concorrência, que satura o emulador. Passou a ter
  timeouts explícitos de 15s, tal como `booking-concurrency.test.ts`
  já tinha pelo mesmo motivo.
- `create_series_screen_test.dart` dependia da hora do dia: o caminho
  "só esta data" compara contra ocorrências FUTURAS, por isso semear
  "hoje às 18:00" passava de manhã e falhava a partir das 18:00 (foi
  exatamente assim que reparei). Passou a substituir o provider em vez
  de semear no Firestore — isola a lógica de sobreposição, que é o que
  o teste quer mesmo verificar. `instructor_home_screen_test.dart`
  tinha uma variante do mesmo problema (a "sessão noutro dia" caía em
  cima de hoje sempre que a suite corresse a uma segunda-feira).

⚠️ Nota sobre `dart format`: correr `--set-exit-if-changed .` na raiz
falha em ~18 ficheiros que **não** foram tocados neste lote (drift
pré-existente, ficheiros intocados no git face à versão atual do
formatter). Formatei só os ficheiros deste lote — reformatar o resto
seria uma alteração à parte, não a escondo mas também não a misturo
aqui.

### O que fica por confirmar

**Nada disto foi clicado manualmente por ti ainda.** Tentei validar no
browser (emulador + `flutter run -d web-server`) mas o painel de
browser desta sessão não conseguiu compor frames, por isso não há
verificação visual real — compensei com testes de widget que exercitam
a lógica nova a sério (tabs por dia, filtro por instrutor, aviso de
conflito nos dois modos, dashboard do instrutor, editar serviço com
grupo). O manual continua por fazer:

- "+ Sessão extra" numa sessão cheia para o limite semanal do aluno —
  confirmar que entra e que NÃO consome utilização.
- Configurar "antecedência mínima para marcar" em Gestão → Definições
  e tentar marcar dentro da janela como aluno.
- Remover um bloco de treino livre antes de publicar; confirmar que
  depois de publicada a opção fica desativada.
- Criar duas séries sobrepostas para o mesmo instrutor e ver o aviso.
- Atribuir "Sem acompanhamento" e depois "Standard" ao mesmo aluno —
  deve ser rejeitado com os nomes em conflito.
- Entrar como um instrutor puro e confirmar o dashboard.

## 2ª passagem: auditoria funcional final + varredura de performance/bugs

Pedido teu a seguir ao lote acima: *"faz uma última avaliação dos
requisitos funcionais e mockups até esta fase"* + *"varre todo o código
à procura de problemas de performance, bugs, etc."*. Reli os UCs
fechados linha a linha e varri o código. Encontrei **2 lacunas
funcionais** e **5 problemas de código** — três deles bugs reais de
correção, não só de performance.

### Funcional #1 — notificações automáticas nunca existiram (UC11/UC18/UC24)

Havia envio de push, mas **só manual** (um humano escreve título+corpo
em "Notificar inscritos"). Os UCs fechados pedem envio **automático**
quando é o estúdio a mexer na marcação de alguém:

- UC18 — *"os alunos removidos são notificados (UC11)"*;
- UC10/UC18 — cancelamento de aula pelo estúdio;
- UC24 — desativar instrutor: *"alunos notificados e sessões devolvidas"*.

Nada disto notificava ninguém. Extraí `lib/notifications.ts`
(partilhado com o envio manual, que ficou a usá-lo) e liguei-o a
`removeMembersFromOccurrence`, `cancelOccurrenceForStudio` e
`deactivateInstructor`.

Três decisões que vale a pena registar: o envio **nunca lança** — uma
notificação que falha (sem VAPID key, token expirado) não pode desfazer
um cancelamento que já aconteceu; corre **fora** da transação; e em
`deactivateInstructor` é **uma notificação por aluno**, não uma por
ocorrência cancelada (um aluno com 8 sessões desse instrutor receberia
8 pushes idênticos).

O texto da notificação diz o dia mas **não a hora**, de propósito: o
runtime das Functions não sabe o fuso do dispositivo e não há
biblioteca de timezone no projeto — imprimir a hora em UTC daria uma
notificação com a hora errada metade do ano (`Europe/Lisbon` é UTC+1 no
verão). Escrevi-a primeiro com hora, dei por isso a rever, e tirei-a.

### Funcional #2 — nomes dos inscritos no calendário (UC20)

O UC20 pede *"nº de inscritos **e lista de nomes** por slot"* e o
mockup mostra "9/12 · Rita, Miguel, Tiago...". No lote anterior deixei
só a contagem e assinalei como simplificação — por causa das N+1
queries de carregar os inscritos de duas semanas inteiras.

Revi essa decisão: **as tabs por dia que eu próprio adicionei tornaram
o argumento inválido**. O ecrã mostra agora um só dia (3-8 sessões),
por isso o nº de listeners é pequeno e limitado pelo próprio layout.
Implementado, com os 3 primeiros nomes + "+N" como no mockup, e sem
abrir listener nenhum para sessões canceladas ou vazias.

### Bug #1 🔴 — cancelar uma sessão extra roubava uma utilização

O mais sério. Uma sessão EXTRA (UC08-A) nunca incrementa `usage` — é
esse o objetivo. Mas **todos** os caminhos de cancelamento
(`cancelBooking.ts`, `prepareRelease`, `cancelFreeTrainingBooking.ts`)
decrementavam `usage` a partir do `serviceId`/`period` do booking **sem
olhar ao `isExtra`**.

Efeito prático: marcar 1 sessão normal (1/2 usadas) + 1 extra (continua
1/2) e cancelar a extra deixava o membro a **0/2** — ganhava uma sessão
que nunca tinha gasto. Enquanto `isExtra` foi sempre `false` (até ao
lote anterior) este caminho não podia estar errado; tornar a flag
funcional expôs o bug.

### Bug #2 🔴 — remarcar uma sessão extra convertia-a em normal

`rescheduleBooking.ts` liberta a origem e cria uma marcação nova no
destino — mas criava-a sempre com `isExtra: false`. Uma sessão extra
remarcada pelo estúdio passava a consumir o limite semanal: o membro
**perdia** uma sessão do plano só por ter sido mudado de horário.
`ReleasePlan` passou a expor `isExtra` para a flag viajar da origem
para o destino.

Os dois bugs estão cobertos por `extra-session-usage.test.ts` (4 testes
contra as Cloud Functions reais no emulador). **Confirmei que os testes
falham sem a correção** — reverti os `!isExtra` de propósito, corri, vi
2 testes a falhar, e restaurei. Um teste de regressão que passa nas
duas versões não vale nada.

### Bug #3 — query de marcações descarregava o histórico todo

`watchMyBookings` fazia uma `collectionGroup` por `memberId` **sem
filtrar `status` e sem limite**: um membro com dois anos de app
descarregava centenas de bookings cancelados para mostrar as 2-3
marcações ativas que tem — e o ecrã filtrava em Dart. Passou a filtrar
`status == 'booked'` no servidor (índice novo:
`bookings(memberId, status)` em COLLECTION_GROUP; o índice de 4 campos
que já existia não serve, tem `serviceId` pelo meio).

### Bug #4 — "próximas ocorrências" sem teto nenhum

`watchUpcomingOccurrences`/`watchUpcomingOccurrencesAllServices` tinham
`startAt >= now` **sem fronteira superior nem limite**, e alimentam o
ecrã principal do Aluno. O cron diário empurra o horizonte de 8 semanas
todos os dias, por isso o conjunto cresce com o nº de séries e nunca
encolhe — e qualquer marcação de qualquer pessoa no tenant faz o
snapshot inteiro voltar a chegar. Adicionado `.limit(200)`; como o
`orderBy('startAt')` é ascendente, corta pelas mais distantes e as
próximas — as únicas marcáveis na prática — ficam sempre.

### O que verifiquei e estava bem

Para não dar a ideia de que só encontrei problemas: `recalculateUsage`
já filtrava `isExtra == false` corretamente (foi o único caminho de
usage que estava certo desde o início); o picker de atribuição manual
já filtra elegíveis server-side como o UC08-A exige; `Assessment` já
guarda `updatedBy`/`updatedAt` (UC04/UC14); e os `context.mounted` a
seguir a `await` estão todos no sítio. Os loops sequenciais nas Cloud
Functions são exigidos pelo Firestore (leituras antes de escritas numa
transação), não são descuido.

### Verificação

Estado final: `flutter analyze --fatal-infos` limpo, **142 testes
Dart**, `npm run build`/`lint` limpos, **135 testes** no emulador
(11 ficheiros). As mesmas ressalvas do lote anterior mantêm-se: sem
validação manual no browser, e o `dart format` na raiz continua a
acusar ficheiros pré-existentes que não toquei.

⚠️ **Índice novo por implantar:** `firestore.indexes.json` ganhou
`bookings(memberId, status)`. No emulador funciona sem mais nada, mas
em produção é preciso `firebase deploy --only firestore:indexes` —
sem isso, "Minhas marcações" passa a dar erro de índice em falta.

## 3ª passagem: revisão geral do código (bugs, clean code, performance)

Pedido teu: *"avaliação extensiva geral do código à procura de bugs,
problemas de clean code, performance"*. Revi por camadas — 27 Cloud
Functions, Security Rules, domínio/repositórios/providers, e os 44
ecrãs. Seis correções, duas delas de segurança.

### 🔴 Segurança #1 — qualquer aluno podia escrever no documento de staff

`staff/{id}` tinha `allow read, write: if belongsToTenant` desde a
Fase 1. Ou seja, qualquer **aluno** autenticado do tenant podia
desativar um instrutor (`status: inactive` — negação de serviço na
prática, o calendário e os ecrãs filtram por isso), alterar-lhe
nome/email/dados pessoais, ou criar um `staff/{o-próprio-uid}`.

Não era escalada de privilégios — os roles vêm dos custom claims do
token, nunca deste documento — mas era escrita indevida a sério. É
exatamente a lacuna que `members` fechou na Fase 5 e que aqui ficou por
fechar com o argumento *"só o Gestor mexe em staff hoje"*: verdade na
UI, nunca imposta pelo servidor.

Escrita passou a Manager, com uma exceção estreita para o próprio staff
registar o seu token FCM (UC21) — e um teste que confirma que um
instrutor **não** se consegue promover a manager por essa via. Leitura
mantém-se ampla porque o ecrã de marcação do Aluno mostra o nome do
instrutor; isso implica que os dados pessoais do staff continuam
legíveis por qualquer membro, o que fica **assinalado**: as Rules não
filtram por campo, fechá-lo exigiria mover os dados pessoais para uma
subcoleção — mudança de modelo, não de regra.

### 🔴 Segurança #2 — qualquer aluno podia escrever no documento do tenant

Mesma raiz: `tenants/{id}` com escrita ampla. Um aluno podia renomear o
ginásio ou pôr o tenant a `suspended`. Nenhum ecrã de cliente escreve
aqui (o seed usa Admin SDK), por isso apertar para Manager não parte
nada.

### 🟠 Bug — utilizador Auth órfão quando a criação falha a meio

`createMember`/`createStaff` fazem `auth.createUser` e só depois
escrevem o documento no Firestore. Se as claims ou a escrita falhassem,
ficava uma conta no Firebase Auth **sem** `members/{uid}`/`staff/{uid}`
e sem `tenantId` nas claims: a pessoa conseguia autenticar-se (a
password temporária foi mesmo criada) e entrava num estado que nenhum
ecrã trata — e o Gestor não a via na lista para a corrigir, porque a
lista lê o Firestore. Ambas passaram a desfazer a conta no `catch`.

### 🟠 Bug — datas malformadas rebentavam com erro cru

`Timestamp.fromDate(new Date(input))` com o input validado só como
`z.string()`: uma data inválida dava `RangeError` e o cliente recebia
`INTERNAL`, sem pista do campo errado. Novo `lib/parseDate.ts` devolve
`invalid-argument` com o nome do campo, como o resto das funções.

Em `updateStaffProfile` isto era pior do que parecia: a ordem era
`auth.updateUser` (que muda a **credencial de login**) e só depois o
Firestore. Uma data má rebentava **depois** de o email de login já ter
mudado — o staff deixava de conseguir entrar com o email antigo, e o
Gestor continuava a ver o email antigo no ecrã, sem sinal nenhum de que
estavam dessincronizados. Agora valida antes de tocar no Auth.

### 🟠 Performance — 21 providers `.family` sem `autoDispose`

O achado com mais impacto. Em Riverpod, um `.family` sem `autoDispose`
cria uma instância **por argumento** e mantém-na viva o resto da
sessão, com o listener Firestore aberto. Na prática:

- abrir 30 sessões ao longo de um turno → 30 listeners permanentes em
  `bookings`/`attendance`/ocorrência;
- um instrutor a percorrer 40 alunos → 40+ listeners de
  avaliações/planos/histórico de carga;
- navegar 20 semanas no calendário → 20 listeners de intervalos de
  ocorrências.

Fuga de memória **e** custo real de Firestore (cada listener fatura
leituras a cada alteração). Os 20 providers de âmbito de ecrã passaram
a `autoDispose`; a exceção deliberada é o registo de token FCM, que tem
de sobreviver à navegação.

### 🟡 Clean code — diálogos duplicados (duplicação minha)

`_EditOccurrenceDialog` e `_AssignMemberDialog` existiam quase
byte-a-byte iguais em `series_detail_screen.dart` **e**
`occurrence_detail_screen.dart` — porque no lote anterior acrescentei
as ações ao segundo ecrã **copiando** as do primeiro em vez de as
extrair. Duas cópias da mesma regra ("nunca selecionar mais do que as
vagas disponíveis") divergem na primeira alteração que só apanhe uma
delas. Extraídos para `lib/presentation/widgets/occurrence_dialogs.dart`
(−345 linhas), com o subtítulo "altera só esta semana" como parâmetro,
por ser a única diferença real entre os dois usos. Também removi um
parâmetro (`servicesById`) que era passado a cada tile de inscrito e
nunca lido.

### O que verifiquei e estava bem

As 27 Cloud Functions têm todas guarda de autorização, incluindo a
variante callable do gerador de séries. `nextMemberNumber` é
transacional a sério (sem race na geração do nº de sócio). Os loops
sequenciais nas transações são exigidos pelo Firestore, não descuido.
As listas grandes usam `ListView.builder`/`separated`; as que usam
`Column` são limitadas pela capacidade da sessão. Os `catch (_)` que
existem são os dois deliberados e documentados.

### Verificação

Estado final: `flutter analyze --fatal-infos` limpo, **142 testes
Dart**, `npm run build`/`lint` limpos, **142 testes** no emulador
(11 ficheiros) — 7 deles novos, a cobrir as duas regras de segurança
apertadas. Mantêm-se as ressalvas de sempre: sem validação manual no
browser, e o `dart format` na raiz continua a acusar ficheiros
pré-existentes que não toquei.

⚠️ **Continua por implantar** o índice `bookings(memberId, status)` do
lote anterior (`firebase deploy --only firestore:indexes`). As Rules
apertadas nesta passagem também precisam de
`firebase deploy --only firestore:rules` para valerem em produção.

## Fase 9 — Pagamentos (registo, não processamento)

**Objetivo:** histórico mensal de mensalidades, sem gateway (Domain
Model v1 §36, D17 — "apenas registo no MVP"); e o próprio UC01 (fechado)
a bloquear o login quando a mensalidade está em atraso.

### O que foi construído

- **Domínio** — `PaymentRecord` (`memberId`, `year`, `month`, `status`,
  `amount?`, `subscriptionId?`, `changedAt`, `changedBy`) e
  `PaymentStatus` — TRÊS estados, não um booleano: `paid`/`overdue`/
  `paidLate` (o mockup distingue "pago a tempo" de "pago com atraso";
  só `overdue` bloqueia o login). `paymentPeriodKey(DateTime)` e
  `paymentMonthLabel(month, year)` são helpers partilhados
  (`"2026-08"`/`"Agosto 2026"`), cálculo em UTC — mesma limitação já
  assinalada em `core/utils/iso_week.dart`.
- **`PaymentRepository`/`FirebasePaymentRepository`** —
  `tenants/{t}/members/{memberId}/paymentRecords/{YYYY-MM}`. Ao
  contrário de `loadHistory` (Fase 8, imutável por decisão explícita do
  UC16), aqui a correção de um mês já registado é esperada (Domain
  Model v1 §46: "append/update CONTROLADO") — o mesmo documento é
  atualizado, não duplicado.
- **Denormalização deliberada** — `MemberSummary` ganhou
  `currentPaymentStatus`/`currentPaymentPeriod`, escritos por
  `setPaymentStatus` no MESMO `WriteBatch` que o registo do mês, mas
  SÓ quando esse mês é o mês atual (corrigir Junho em Agosto nunca pode
  fazer `members/{id}` "esquecer" que Agosto está pago). Mesmo padrão
  já usado para `TrainingPlanEntry.currentLoad`/`loadHistory` na Fase
  8. Sem isto, tanto a lista "Mensalidades — mês atual" (todos os
  membros) como o bloqueio de login (UC01, disparado em TODA sessão
  aberta por um Aluno) exigiriam uma query extra à subcoleção — aqui
  ficam de borla, reaproveitando `membersProvider`/`memberProfileProvider`
  já existentes.
- **`MemberSummary.currentMonthStatus(now)`/`isOverdueFor(now)`** —
  "ausência de registo NUNCA bloqueia, só uma marcação EXPLÍCITA de
  atraso" (decisão fechada): um `currentPaymentPeriod` de um mês
  ANTERIOR ao atual conta como "sem registo este mês", nunca como "em
  atraso esquecido". As três leituras do estado do mês atual (lista do
  Gestor, `MyProfileScreen`, gate de login) passam todas por este único
  método — nunca podem divergir sobre o que conta como "mês atual".
- **Security Rules** — `paymentRecords`: leitura só ao PRÓPRIO membro
  e ao Manager (ao contrário de assessments/loadHistory/planEntries, o
  Instrutor NÃO lê — o mockup coloca "pagamentos" explicitamente na
  secção exclusiva do Gestor); escrita Manager-only, incluindo `update`
  (correção de mês já registado). Índice novo:
  `paymentRecords(year DESC, month DESC)`, `COLLECTION` scope.
- **`ManagePaymentsScreen`** (Gestor, "Mensalidades — mês atual") —
  reaproveita `membersProvider` sem NENHUM listener novo (a
  denormalização acima é o que torna isto possível); um pill por
  membro (✓ Pago / ⚠ Em atraso / ⚠ Pago com atraso / "Sem registo" —
  cinzento, nunca vermelho, para não confundir "por marcar" com
  "atrasado"); tocar abre um diálogo com 3 opções + valor opcional.
- **`PaymentHistoryScreen`** (Gestor) — "um registo por mês, nunca só o
  estado atual" (mockup); cada linha do histórico é tocável para
  corrigir esse mês especificamente, reaproveitando o mesmo diálogo
  (`showPaymentStatusDialog`, partilhado entre os dois ecrãs).
- **Bloqueio de login (UC01 fechado)** — `AuthGate` ganhou um terceiro
  gate, depois do de password temporária: `isBlockedForOverduePaymentProvider`
  lê `memberProfileProvider` (já existente) e, se `isOverdueFor(now)`,
  mostra `AccountBlockedScreen` em vez de `HomeScreen` — mesma cópia do
  mockup ("Login — exceções"): *"Conta inativa — Mensalidade em atraso.
  Contacta o estúdio para reativar o acesso."*, com um botão "Sair"
  (sem auto-resolução — a decisão é sempre do Gestor).

  **Decisão pragmática, sinalizada:** o bloqueio só se aplica a contas
  PURAMENTE de Aluno (`roles == {member}`). Um Instrutor/Gestor que
  também seja membro (Domain Model v1 §6 admite isto) nunca fica
  bloqueado por causa da própria mensalidade — o risco operacional de
  um Gestor ficar sem acesso à própria gestão do ginásio seria pior do
  que aplicar a regra também a ele. O mockup não cobre este caso
  (só mostra o ecrã de bloqueio a partir do login de Aluno).
- **`MyProfileScreen`** ganhou uma linha "Mensalidade: {estado}" —
  equivalente real ao card "Mensalidade: Em dia" do mockup do "Início"
  (`HomeScreen`, Fase 2, é uma navegação por separadores sem card de
  topo — reconstruir esse layout ficaria fora do âmbito de uma fase
  sobre pagamentos; sinalizado). Só o mês atual — o histórico completo
  continua exclusivo do Gestor.

### Testes

**165 testes Dart** (12 novos): `payment_record_test.dart` (enum,
helpers, Equatable), `member_summary_test.dart` estendido
(`currentMonthStatus`/`isOverdueFor`, incluindo o caso "mês anterior
não bloqueia"), `firebase_payment_repository_test.dart` (o
`WriteBatch` fica coerente — mês atual denormaliza, mês passado NÃO
mexe no denormalizado), `manage_payments_screen_test.dart`,
`my_profile_screen_test.dart` estendido, `auth_gate_test.dart`
estendido (bloqueia quando `overdue`, não bloqueia quando não).

**148 testes no emulador** (6 novos, `operations-rules.test.ts`):
próprio membro lê o seu histórico / não lê o de outro; Instrutor NÃO
lê (Manager-only, ao contrário dos outros dados históricos da Fase 8);
Manager lê e escreve (incluindo `update`); membro não consegue
marcar-se a si próprio como pago; isolamento entre tenants.

### Verificação

`flutter analyze --fatal-infos` limpo, 165 testes Dart, `npm run
build`/`lint` limpos, 148 testes no emulador (11 ficheiros).

⚠️ **Índice novo por implantar:** `paymentRecords(year DESC, month
DESC)` — `firebase deploy --only firestore:indexes`. Sem isto,
`PaymentHistoryScreen` dá erro de índice em falta em produção (o
emulador não exige índices pré-implantados, por isso os testes
passam sem isto).

⚠️ **Fora de âmbito, sinalizado:** processamento de pagamentos em si
(gateway) — D17 do Domain Model já deixa isso explicitamente fora do
MVP. `subscriptionId` existe no modelo (Firestore Data Model v1 §46)
mas nunca é usado pela UI: um membro pode ter várias subscriptions
ativas em simultâneo e o mockup mostra sempre UM pill por membro por
mês, nunca um por subscription — a decisão de "a que subscription
pertence a mensalidade" continua por tomar, tal como o próprio
documento técnico já assinalava.

## Fase 10 — Identidade visual e paridade com os mockups

**Porque existe esta fase.** Ao testar a app a sério depois da Fase 9,
a conclusão foi que o passo seguinte do guia (lançamento) não fazia
sentido: a UI não se parecia com os mockups, havia muita coisa difícil
de perceber, e a criação de utilizadores "parecia estar em falta".
Auditei os mockups (`Functional/nxt-studio-screens.html`) contra a app
ecrã a ecrã e escrevi o resultado como uma fase nova no guia
(`Technical/guia-desenvolvimento.md`, Fase 10, sub-fases 10.1 a 10.5);
a antiga Fase 10 (lançamento) passou a Fase 11.

O diagnóstico não era "vários ecrãs mal feitos": era a falta de uma
base. O tema da app era **uma linha** (`ThemeData(colorSchemeSeed:
Colors.indigo)`) em modo claro, enquanto o mockup é escuro com paleta e
tipografia próprias. Sem tokens e componentes partilhados, qualquer
melhoria por ecrã seria trabalho perdido.

### 10.1 — Design system

- `lib/core/theme/app_colors.dart` — os tokens do `:root` do mockup,
  com os mesmos nomes (`void_`, `panel`, `panel2`, `red`, `redDeep`,
  `bone`, `mute`, `dim`, `ok`, `warn`) para se poder comparar com o CSS
  sem tradução mental. `statusFill()` dá o fundo a 10% que o CSS usa em
  pills e banners — nunca a cor cheia, ilegível em texto pequeno.
- `lib/core/theme/app_theme.dart` — `AppTheme.dark`, com um
  `ColorScheme.dark` **explícito** e não `fromSeed` (uma seed
  redistribui as cores por conta própria e deixa de ser a paleta do
  mockup). Tipografia via `google_fonts`: Oswald itálico para display
  (`AppTheme.display()`), Inter para corpo.
- `lib/presentation/widgets/design_system.dart` — os componentes
  repetidos do mockup: `Pill`, `PanelCard`, `IconBox`, `Avatar`,
  `SlashDivider`, `ScreenHeader`, `PillTabs`, `StatNumber`, `UsageBar`,
  `AppBanner`, `FieldBlock`, `SectionLabel`, `EmptyState`. 16 testes —
  do que pode regredir sem ninguém dar por isso (as iniciais do avatar,
  a fração da barra, o mapeamento estado→cor), não da aparência.

### 10.2 — Estrutura e navegação

Esta parte não é pintura: mexe em navegação.

- **"Início" do Aluno** (`MemberHomeScreen`), que não existia: card de
  estado da conta (nº de sócio, planos ativos, pill da mensalidade),
  "Próxima marcação" e a grelha 2×2 de atalhos.
- **Shell por papel** (`HomeScreen`): três shells em vez de um só com
  ícones condicionais na `AppBar`. Um Gestor via "Marcar treino",
  "Treino livre" e "Minhas marcações" — coisas que não faz — e a Gestão
  estava atrás de um ícone sem rótulo no canto. Agora: Gestor →
  `Visão global · Gestão` (+ `Treino` **só** se também tiver conta de
  membro); Instrutor puro → dashboard sem barra inferior; Aluno →
  `Início · Marcar · Livre · Marcações`. Quem acumula papéis vê o shell
  do papel mais abrangente, e as funções do outro continuam alcançáveis
  a partir dele.
- **Gestão reorganizada** (`ManagerScreen`): de 14 cards chapados para
  cinco grupos com rótulo e uma linha de explicação — Pessoas, Oferta
  (Planos → Serviços → Modalidades, a ordem em que se pensa neles),
  Agenda, Dinheiro, Conteúdos e definições. Cada entrada ganhou um
  subtítulo que diz o que se faz lá dentro. "Atribuir um plano a um
  membro" passou a botão de ação no fim do grupo Oferta em vez de mais
  um card de navegação: é um verbo no meio de substantivos.
- **"Utilizadores" numa lista só** (`ManageUsersScreen`): alunos e
  staff juntos, ordenados por nome, com avatar de iniciais, subtítulo
  de papel/nº/modalidade e pill de estado, separadores
  Todos/Alunos/Staff, procura por nome ou nº de sócio, e UM "+".
  Confirmou-se a suspeita: a criação de utilizadores nunca esteve em
  falta — `CreateUserScreen` está completa desde a Fase 6, mas estava
  enterrada atrás de dois FABs em ecrãs diferentes.
- **Separadores por modalidade em "Marcar treino"**, como no mockup.
- **Estados vazios explicativos** (`EmptyState`): ~20 listas diziam só
  "Ainda não existe nenhum X". Passaram a dizer o que o ecrã é, porque
  está vazio e qual é o próximo passo, com o botão de criar quando faz
  sentido. Onde um ecrã depende de outro, o pré-requisito aparece dito
  à cabeça (um plano sem serviços não dá acesso a nada; uma aula tem de
  ser de um serviço) em vez de se descobrir mais tarde.

### Decisões e desvios (deliberados, não omissões)

- **Barra inferior mantida no Aluno, com "Início" à frente.** O mockup
  não usa barra inferior em ecrã nenhum — a classe `.bottom-nav` existe
  no CSS mas nunca é usada; a navegação é toda por dashboard. Mantive os
  separadores: dá o dashboard sem um refactor de navegação arriscado, e
  "Marcar"/"Livre"/"Marcações" continuam a um toque em vez de dois. Os
  atalhos do dashboard que correspondem a separadores trocam de tab em
  vez de empilhar um ecrã (senão ficava um "voltar" para um sítio de
  onde nunca se saiu). Efeito secundário útil: a `AppBar` do Aluno
  chegou a ter SEIS ícones sem rótulo; "O meu plano" e "As minhas
  avaliações" saíram de lá e passaram a cards nomeados.
- **Separadores de modalidade construídos a partir das modalidades que
  TÊM sessões futuras.** Um separador que abre vazio é pior do que não
  existir, e um ginásio que não usa modalidades não vê separadores
  nenhuns. O estado guarda o ID e não o índice: a lista muda quando uma
  sessão é marcada ou cancelada, e um índice passaria a apontar para
  outra modalidade sem ninguém tocar em nada.
- **"Livre" continua separador de nível de cima**, não uma modalidade.
  É outra coleção (`freeTrainingSlots`), com regras e ecrã próprios —
  juntá-los fingiria uma unidade que o modelo de dados não tem.
- **`ManageMembersScreen`/`ManageStaffScreen` não foram apagados.**
  Continuam no código e navegáveis; a Gestão é que passa pela lista
  unificada.
- **Foto de perfil continua fora de âmbito** (exigia Storage +
  picker), como já estava sinalizado desde a Fase 5.

### Testes acrescentados em 10.1/10.2

16 do design system (incluindo 3 do `EmptyState`), 8 do
`MemberHomeScreen`, 4 do `ManageUsersScreen`, 2 dos separadores de
modalidade e 2 do shell do Gestor (que um Gestor abre em "Visão global"
e **não** vê separadores de marcação — a regra que foi pedida
explicitamente).

Duas armadilhas encontradas ao escrever estes testes, que vale a pena
não repetir: um teste do `AuthGate` passou a verde pela razão errada
(procurava o texto "Marcar treino", que passou a existir como card do
dashboard e não só como título da `AppBar`); e os taps em
`find.byIcon(Icons.add)` tornaram-se ambíguos quando o `EmptyState`
ganhou um botão de criar com o mesmo ícone do FAB — passaram a
`find.byType(FloatingActionButton)`.

Uma terceira apareceu em 10.5: os testes do picker agrupado falhavam a
tocar em opções que existiam. Um `tap()` num alvo fora do viewport de
teste (800x600) não falha — simplesmente não acerta em nada, e o teste
passa a depender de posição em vez de comportamento. Resolvido a
aumentar a superfície (`tester.view.physicalSize`), como já se fazia em
`create_series_screen_test.dart`.

### 10.5 — Gestor: "Atribuir serviço/plano" (a peça com substância)

Este era o único item da Fase 10 que mexia num fluxo de negócio e não só
na apresentação. O mockup mostra a atribuição orientada a **serviços**,
agrupada: "Nível de treino de sala" em seleção única (Sem
acompanhamento / Standard / Plus / Premium), "Aulas de grupo" em seleção
múltipla, "PT de Pilates" única. A app eram dois dropdowns — membro +
UM plano — e dar a alguém "sala Plus + Aula Hyrox + PT Pilates" eram
três voltas ao mesmo formulário, com a exclusividade a aparecer só como
erro depois de submeter.

`AssignSubscriptionScreen` foi reescrito para esse formato. O que
importa é de onde vem o agrupamento: **deriva** do
`Service.exclusiveGroup` dos serviços que cada plano dá
(`planExclusiveGroupsProvider`), nunca de uma lista fixa de categorias
no código — Domain Model v1 §10 é explícito em que "Standard"/"Plus"/
"Premium" são nomes que cada tenant escolhe.

Três decisões que vale a pena ter escritas:

- **Um plano cujos serviços caiam em dois grupos exclusivos diferentes
  conta como avulso.** Não pode ser a opção única de nenhum dos dois — a
  alternativa era escolher um grupo à sorte.
- **Um grupo que o membro já ocupa aparece bloqueado**, a dizer qual é o
  plano atual e que para trocar tem de se cancelar primeiro. A Cloud
  Function recusaria qualquer outro nível do mesmo grupo; mostrar botões
  que só levam a um erro garantido é pior do que explicar.
- **Não é atómico.** São N chamadas a `createSubscription`, uma por
  plano, e não há transação que as cubra. Se a terceira falhar, as duas
  primeiras ficaram feitas — a mensagem final diz o que passou **e** o
  que falhou, e a seleção do que falhou fica marcada para se corrigir sem
  remarcar tudo. Mesmo princípio já usado em `rescheduleBooking`. Há um
  teste dedicado a este caso.

### 10.3 / 10.4 — re-skin do Aluno e do Instrutor

Aluno, completo menos o detalhe das avaliações: login (marca + claim em
Oswald, erro genérico antes do botão, rodapé "Só o estúdio pode criar o
teu acesso"), conta inativa, "O meu plano" (▶ + carga em vermelho
itálico à direita + linha de ajuda), "Marcar" (vagas em `Pill`,
`UsageBar` a sério, banner do UC08-A), "Minhas marcações" e Perfil.

Instrutor, parcial: dashboard (avatar, `StatNumber`, atalhos com
`IconBox`) e os separadores de dia do calendário em `PillTabs`.

Quatro correções que saíram deste re-skin e não eram cosméticas:

- **O nome do estúdio no login** vinha do `tenantId` — um ID, não um
  nome ("NXT_PERFORMANCE_STUDIO"), e transbordava a linha. Passou a
  `TenantAppConfig.displayName`, config de build. Não pode vir do
  documento `tenants/{id}`: as Rules exigem sessão para o ler, e este é
  precisamente o ecrã de antes da sessão.
- **O erro de cancelamento de uma marcação** era a segunda linha do
  subtítulo, no mesmo cinzento do resto do texto — lia-se como
  informação normal. Passou a banner.
- **O estado da mensalidade no perfil** usava `Colors.green`/
  `Colors.orange`, cores fora da paleta. Passou a `Pill`.
- **Os separadores de dia do calendário** eram sete `ChoiceChip`
  esticados por `Expanded`: num ecrã de telefone cortavam o texto.

Nos subtítulos do dashboard do Instrutor tirei os códigos de use case
("UC13/14/16"): dizem algo a quem escreveu os documentos, nada a quem
usa a app.

### Verificação

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

Estado: `dart format` limpo, `flutter analyze --fatal-infos` sem
problemas, **196 testes a passar** (eram 201 antes de remover os 7
testes da sonda de diagnóstico da Fase 0 — ver "Correções depois de
testar a app a sério") e **150 contra o Emulator Suite**.

### Ainda em aberto nesta fase

- **Avaliações do Aluno (detalhe dos 17 campos)** continuam em
  `ListTile`s em vez de `FieldBlock`.
- **Os ecrãs de formulário do Instrutor/Gestor** ("Ficha do aluno",
  "Editor de plano", "Nova avaliação", "Criar aula", "Detalhe da aula",
  "Reduzir vagas", "Enviar notificação") continuam em `Card`/`ListTile`
  Material. Funcionam e já estão no tema escuro, mas não usam os
  componentes partilhados.

## Correções depois de testar a app a sério (Fase 10)

Quatro coisas encontradas a usar a app como Aluno e como Gestor.

### 1. "Treino livre" dava permission-denied a um Aluno

O ecrã mostrava `[cloud_firestore/permission-denied] Null value error
for 'get'` sempre que a semana ainda não tinha grelha nenhuma. A causa
estava nas Security Rules, não na app:

```
allow read: if isManager(tenantId)
  || (belongsToTenant(tenantId) && resource.data.status == 'published');
```

`resource.data` num documento que **não existe** é um erro de
avaliação, não um `false` — e o cliente recebe `permission-denied`. O
mesmo padrão estava no `get()` à semana-mãe usado pela regra dos slots.
Corrigido com `resource == null` explícito na semana e uma função
`freeTrainingWeekPublished()` que faz `exists()` antes do `get()`.

Duas notas honestas sobre esta correção:

- O `exists()` custa **uma leitura extra** quando o documento existe. É
  o preço de a regra poder dar `false` em vez de rebentar; tentei
  primeiro comparar o resultado do `get()` com `null` e não funciona —
  a expressão inteira falha na mesma.
- Escrevi um segundo teste a assumir que um Aluno devia conseguir
  listar os slots de uma semana inexistente e receber lista vazia.
  Estava errado: os slots de uma semana não publicada são fechados de
  propósito (UC17-A, "nenhum aluno pode ver uma grelha em estado
  sugerido"), e a app nunca os lista sem confirmar antes, no documento
  da semana, que está publicada. O teste passou a afirmar o contrário —
  que a listagem é recusada.

Verificado: **150 testes contra o Emulator Suite**, todos a passar.

### 2. "Marcar" aparecia em sessões já marcadas

O cartão de uma sessão que o próprio membro já tinha marcado continuava
a oferecer o botão, e a única resposta a premi-lo era o
`AlreadyBookedException` vindo da Cloud Function — depois do toque.
Agora o cartão mostra o pill "Marcado" e uma linha a dizer onde se
cancela ("Marcações"), sem repetir a ação de cancelar em dois ecrãs.

O fake de `BookingRepository` nos testes tinha `watchMyBookings` a
devolver `Stream.empty()` — bastava enquanto nenhum ecrã testado olhava
para as marcações do próprio membro. Deixou de bastar: com um stream
vazio, este teste passaria por a funcionalidade não existir.

### 3. Restos da fase de arranque

O botão de diagnóstico (o ícone de insecto na `AppBar`) existia para
provar o critério "Done" da Fase 0 — "a app liga ao emulador e
lê/escreve um documento de teste" — e ficou num sítio visível a
utilizadores reais durante nove fases. Saiu, e com ele toda a sonda:
`HelloWorldScreen`, `PingResult`, `PingRepository`,
`FirebasePingRepository`, `PingFirestoreUseCase`, os providers, os
testes e o `emulator_smoke_test.dart` (a dependência `integration_test`
existia só para ele).

O achado sério foi nas Rules:

```
match /_diagnostics/{docId} {
  allow read, write: if true;
}
```

Uma coleção aberta a **qualquer pessoa**, autenticada ou não, em
produção. Removida.

Também estava por fazer o óbvio: a app chamava-se `gym_saas` no
launcher do Android, no iOS ("Gym Saas"), no separador do browser e no
`manifest.json`, e a descrição web era "A new Flutter project.".
`gym_saas` continua a ser o nome do *package* Dart — mudá-lo obrigava a
reescrever todos os imports sem ganho nenhum.

### 4. Ícone e marca

`assets/branding/app_icon.png` (o quadrado 1024×1024) alimenta os
ícones de Android/iOS/Web via `flutter_launcher_icons`; regerar com
`dart run flutter_launcher_icons` sempre que o ficheiro mudar. O fundo
do ícone adaptativo é o preto do tema e não branco: no Android o ícone
é recortado em círculo, e um fundo branco daria um anel claro à volta
de um logótipo desenhado para fundo escuro.

`assets/branding/logo_wordmark.png` é o mesmo logótipo recortado à
mancha do lettering e com o fundo a transparente, para assentar em
qualquer painel do tema. Aparece no login, via
`TenantAppConfig.logoAsset` — config de build, pela mesma razão do
`displayName`: o ecrã de login é anterior à sessão, e sem sessão não há
leitura autorizada de nada do tenant. Se o asset faltar numa build, o
ecrã cai no nome em texto em vez de mostrar uma imagem partida.

### Sobre a faixa vermelha "Running in emulator mode"

Não é código nosso e não vai para produção: é o aviso que o SDK web do
Firebase Auth injeta sozinho quando está ligado ao emulador.
Desaparece assim que a app apontar para um projeto real.

## Varredura geral antes de produção

Uma passagem por todo o código à procura de **classes** de problema, não
de casos isolados — cada achado abaixo aparecia em vários sítios ao
mesmo tempo, que é o sinal de que falta uma peça partilhada.

### Exceções cruas no ecrã (49 sítios)

`Text('Erro: $error')` era o tratamento de erro em praticamente todos os
ecrãs. Foi assim que o bug do treino livre chegou ao utilizador: como
`[cloud_firestore/permission-denied] ... Null value error for 'get' @
L393`. Isso é informação para quem escreve o código.

O novo `ErrorState` diz o que aconteceu em português, oferece "Tentar
outra vez" onde há como (invalidando o provider), e guarda o `toString()`
da exceção atrás de "Detalhe técnico" — continua a chegar a um print de
ecrã de suporte, sem ser a primeira coisa que se lê. Tem uma variante
`compact` de uma linha para erros dentro de formulários.

O `AuthGate` levou tratamento à parte: é o primeiro ecrã depois do
arranque e **não tem nada por trás**. Uma falha a ler o perfil deixava a
app num ecrã sem uma única ação possível a não ser fechá-la; agora tem
sempre "Sair" além do "Tentar outra vez".

### O mesmo estado com aspetos diferentes

`PaymentStatus` estava traduzido para etiqueta+cor em três ecrãs, e as
três versões já tinham divergido — "✓ Pago" em dois, "Em dia" no
terceiro, dois deles ainda em `Colors.green`/`Colors.orange`, fora da
paleta. O mesmo para `SubscriptionStatus`.

Passou a haver um sítio só (`status_pills.dart`). As etiquetas perderam
os símbolos `✓`/`⚠`: o pill já carrega a cor, e o símbolo era o que
sobrava de quando não havia design system.

Com isto ficam **zero** cores Material hardcoded na camada de
apresentação — todas as que restam são tokens de `AppColors`.

### Restos da fase de arranque (continuação)

O `healthCheck` era a única Cloud Function do projeto **sem guard
nenhum**: um `onCall` público que devolvia o `GCLOUD_PROJECT` a quem o
chamasse. Existia para provar que a base de Functions compilava; hoje há
19 funções reais a prová-lo e nenhum cliente o chamava. Removido.

Confirmado por varredura que **todas** as restantes funções chamáveis
têm `requireManager` / `requireManagerOrInstructor` /
`requireAuthenticated`.

### Queries sem limite

27 streams em tempo real sem `limit()`. A maioria é legítima — membros,
staff, planos, serviços e modalidades são limitados pelo tamanho do
negócio, e cortá-los esconderia pessoas silenciosamente, o que é pior do
que uma lista lenta.

Limitei só onde a coleção cresce **sem fim** e a ordenação torna os N
mais recentes a resposta certa:

| Coleção | Limite | Porquê |
|---|---|---|
| `loadHistory` | 200 | cresce a cada treino registado; o gráfico mostra os recentes |
| `assessments` | 100 | ordenado da mais recente para a mais antiga |
| `paymentRecords` | 36 | um por mês — três anos de histórico |

Caso à parte, `SeriesDetailScreen`: listava **todas** as ocorrências de
uma série por ordem crescente. Uma série semanal gera 52 por ano, por
isso ao fim de um ano o Gestor abria a ficha e via primeiro dezenas de
aulas passadas — sobre as quais não há nada a fazer — com as próximas no
fundo. Passou a mostrar de hoje em diante (o índice `(seriesId, startAt)`
já existia, não custou nada).

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**202 testes Flutter** · **150 testes contra o Emulator Suite** ·
`npm run build` e `npm run lint` das Functions a passar · build web de
produção a compilar.

## Fase 11 — RGPD, App Check e limites

O que faltava para isto poder receber pessoas reais. Está tudo o que não
depende de existir um projeto Firebase; o resto está em
[LANCAMENTO.md](LANCAMENTO.md).

### RGPD — porque é que isto foi o item mais sério

A app guarda pressão arterial, percentagem de massa gorda, gordura
visceral e metabolismo basal. Isso é categoria especial no artigo 9.º do
RGPD, com regras mais apertadas do que dados normais. Não existia uma
única linha sobre consentimento em nenhum sítio do código.

**Consentimento (artigos 7.º e 9.º).** Dois registos separados, e a
separação é o ponto:

- Aceitação do aviso de privacidade — cobre o tratamento necessário à
  relação com o ginásio, cuja base legal é o contrato, não o
  consentimento.
- Autorização **explícita e opcional** para dados de saúde.

O artigo 7.º, n.º 4 diz que o consentimento não é livre se for condição
de um serviço que dele não depende. Marcar aulas não depende de
autorizar avaliações físicas — por isso o interruptor começa desligado,
"Continuar" funciona com ele desligado, e quem recusa usa a app inteira
menos as avaliações.

A garantia é do **servidor**, não da UI: as Security Rules recusam
escrever uma avaliação sem consentimento, e o teste que o prova usa um
Instrutor autenticado a escrever diretamente ao Firestore, com a UI fora
do caminho. Esconder um botão não é proteção.

O registo passa por Cloud Function e não por escrita direta porque o
artigo 7.º, n.º 1 exige poder **demonstrar** o consentimento — um campo
com um timestamp escolhido pelo cliente não demonstra nada. Fica também
um `consentLog` append-only: a prova que interessa é "consentiu em X,
retirou em Y", não o valor de hoje.

**Exportação (artigos 15.º/20.º).** `exportMemberData` devolve perfil,
consentimentos, avaliações, cargas, plano, marcações, presenças,
mensalidades, subscrições e utilização. O próprio membro exporta-se a si;
um Gestor exporta qualquer membro do tenant, porque é ele quem responde
ao pedido. Os `fcmTokens` saem da exportação — são identificadores de
dispositivo, sem valor para o titular e sensíveis se copiados.

**Apagamento (artigo 17.º), e a parte que não é óbvia.** Os registos de
pagamento **não** são apagados: o artigo 17.º, n.º 3, alínea b) excetua o
que é preciso para cumprir uma obrigação legal, e a contabilidade
portuguesa tem retenção obrigatória de 10 anos (artigo 123.º do CIRC).
Apagá-los a pedido do titular seria trocar uma infração por outra. São
**anonimizados** — fica o valor e o período, sai tudo o que liga o
registo a uma pessoa — e a função devolve essa contagem à parte, para o
Gestor poder dizer ao titular exatamente o que ficou.

É Manager-only e exige repetir o número de sócio. O artigo 12.º, n.º 6
permite exigir prova de identidade antes de apagar, e um botão "apagar a
minha conta" dentro da app não a verifica melhor do que uma sessão
aberta — que pode ser um telemóvel deixado desbloqueado.

**Um bug encontrado ao escrever isto:** os documentos de presença
guardavam o `memberId` só no id do documento. O apagamento usa um
collection group query, que não consegue filtrar por id sem o caminho
completo — as presenças teriam sobrevivido a um pedido de apagamento.
Passou a ser também campo, com índice próprio.

### App Check

`firebase_app_check` estava no `pubspec.yaml` desde a Fase 0 e nunca
tinha sido inicializado. Via-se nos logs do emulador:
`{"verifications":{"app":"MISSING","auth":"VALID"}}`.

A `apiKey` do Firebase é pública — vai no bundle web, extrai-se de um
APK. Sem App Check, qualquer pessoa chama `createBooking` ou
`createMember` por HTTP direto. As Rules e os guards continuam a decidir
*quem* pode fazer o quê; o que faltava era impedir um script de martelar
as funções.

Falha **aberta** de propósito: um dispositivo que não consiga atestar
entra na app à mesma. Trocar um risco de abuso por uma app que não abre
seria mau negócio — e o enforcement do lado do servidor liga-se depois,
com dados de monitorização à frente (ver LANCAMENTO.md §3).

### Rate limiting

11 funções sensíveis, com limites escolhidos por operação: 30/min para
marcar e cancelar, 20 em 5 min para criar membros (cobre inscrever uma
turma inteira, trava a criação em massa), 5 em 5 min para exportar e
apagar.

Janela deslizante grosseira, um documento por (uid, operação). Não é
exato nos limites e não faz mal: a diferença entre 10 e 11 chamadas por
minuto não interessa a ninguém, a diferença entre 10 e 10 000 interessa.
Falha **aberta**, como o App Check — recusar operações legítimas por
causa da infraestrutura do próprio limitador seria pior do que o abuso
que evita.

### Uma lição repetida nas Security Rules

O bug do treino livre voltou noutra forma: escrevi
`hasHealthDataConsent` com `get(...)` e um `!= null`, e a regra rebentava
em vez de recusar quando o membro não tinha campo `consent`. Em Rules,
`get()` a documento inexistente é um **erro de avaliação**, não um
`false` — e aceder a um campo ausente também. A forma correta é
`exists()` primeiro e `'campo' in data` antes de o ler. Apanhado pela
suite, não à vista.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**209 testes Flutter** · **160 contra o Emulator Suite** (10 novos só de
RGPD) · Functions a compilar e a passar lint.

## Poderes do Gestor — deixar de precisar de um developer

Pedido depois de testar: *"tudo o que ele puder fazer que não tenha que
vir chatear um dev"*. Fui à procura do que obrigava a mexer no Firebase
à mão e encontrei três coisas — uma delas era pior do que uma
inconveniência.

### Repor a password de um utilizador

O pedido mais banal ao balcão de um ginásio, e não tinha resposta
nenhuma dentro da app. Para **staff** ainda havia o "esqueci-me da
password" no login (email real). Para **alunos** não havia nada: eles
autenticam-se com um email sintético construído a partir do nº de
sócio, que não existe em lado nenhum e ao qual não se pode enviar um
link de recuperação.

`resetUserPassword` gera uma temporária e marca `passwordTemporaria`,
tal como a criação da conta faz — a pessoa entra com ela e a app obriga
a trocá-la (UC22). O Gestor entrega-a em mão, que é a verificação de
identidade que faz sentido quando a pessoa está à frente dele.

Revoga também os refresh tokens: se a razão da reposição for uma conta
comprometida, deixar a sessão antiga viva tornaria a reposição inútil.

Não deixa o Gestor repor a **própria** password por esta via — para isso
existe a troca normal, e um Gestor que se tranque a si mesmo com uma
password que não anotou fica sem forma de entrar.

### Cancelar, pausar e reativar uma subscrição — o beco sem saída

Este era o problema a sério. Dava para **atribuir** um plano e nunca
para lhe mexer:

- Um aluno que saísse do ginásio ficava com plano ativo para sempre, a
  contar como elegível para marcar.
- Pior: `createSubscription` recusa um plano que colida no mesmo
  `exclusiveGroup`, e o ecrã de atribuição — escrito por mim na mesma
  fase — dizia *"para trocar de nível, cancela primeiro o plano
  atual"*. **Uma instrução impossível de cumprir.** Trocar um aluno de
  Standard para Plus exigia um developer.

`updateSubscriptionStatus` fecha isto. **Não cascateia para as marcações
já feitas**, e é deliberado: o membro tinha o direito quando marcou, e
apagar-lhe uma aula da semana que vem porque mudou de plano seria uma
surpresa desagradável. Reativar limpa o `endedAt` — sem isso ficava
"ativa mas terminada em X", um estado contraditório que qualquer
relatório leria mal.

### Promover e despromover staff

Os papéis eram decididos na criação e nunca mais mudavam. Um instrutor
que passasse a sócio-gerente exigia mexer nas custom claims à mão.

`updateStaffRoles` escreve nos **dois** sítios, e ambos são precisos: as
claims (que é o que as Security Rules e os guards leem — a autoridade
real) e o documento de staff (que é o que a UI lista). Escrever só no
documento daria um Gestor que a app mostra e o servidor recusa.

A trava que interessa: **um Gestor não se despromove a si próprio**.
Sem ela, o único Gestor de um ginásio consegue trancar-se fora e fica a
precisar exatamente do developer que isto existe para dispensar.

### Conta de instrutor no seed

Não existia nenhuma. O shell do Instrutor — calendário, alunos,
biblioteca, presenças — só se conseguia ver entrando como Gestor, que
mostra outra coisa. O seed passou a criar a Ana Marques e a atribuir-lhe
as sessões geradas, senão o calendário dela abria vazio.

O membro de dev passou também a nascer com consentimento RGPD dado —
sem isso, cada arranque parava no ecrã de consentimento antes de se
conseguir testar o resto. Para ver esse ecrã, cria um membro novo pela
app.

### Um bug de infraestrutura de testes, pelo caminho

`gdpr.test.ts` e `manager-powers.test.ts` passavam sozinhos e falhavam
na suite completa. Parecia contaminação entre ficheiros; era **timeout**
— o vitest dá 5 segundos por omissão, e uma Cloud Function em arranque
a frio com 13 ficheiros em paralelo passa disso. Os ficheiros mais
antigos contornavam-no com um timeout por teste (`}, 30_000)`);
`firebase/tests/vitest.config.ts` trata agora o problema de uma vez.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**209 testes Flutter** · **173 contra o Emulator Suite** (13 novos só de
poderes do Gestor, todos a testar as recusas e não o caminho feliz) ·
Functions a compilar e a passar lint.

## Só o que o plano dá

Pedido depois de testar: *"os alunos só deveriam conseguir marcar os
serviços a que têm direito — os que não têm nem deveriam aparecer no
ecrã"*.

Estava metade feito e a metade errada. A validação existia (a Cloud
Function recusa uma marcação sem plano que dê acesso, desde a Fase 3),
mas a UI mostrava o horário **inteiro** do ginásio. O aluno só descobria
ao tocar em "Marcar" e receber um erro.

Isso é mau de duas formas: obriga a tentar para saber, e mostra como
oferta aquilo que é, na verdade, uma venda por fazer.

`myEligibleServiceIdsProvider` filtra "Marcar treino" e "Treino livre"
pelos serviços a que as subscrições ativas dão acesso. Deriva da
**mesma** fonte que o servidor consulta (`status == active` +
`activeServiceIds`), de propósito: se a UI filtrasse por outro critério,
haveria sempre um caso em que mostra o que a função recusa, ou esconde o
que ela aceitaria.

Três decisões que valem a pena registar:

- **Enquanto a elegibilidade carrega, não se filtra.** Esconder o
  horário todo por um instante e vê-lo aparecer a seguir é pior do que
  mostrá-lo um instante a mais. A proteção real continua a ser do
  servidor — isto só evita mostrar portas fechadas.
- **Três estados vazios diferentes**, porque são três problemas
  diferentes: "não tens plano nenhum com acesso a aulas" (fala com o
  estúdio), "tens plano mas não há aulas dele nos próximos dias"
  (espera), e "não há horário publicado" (o ginásio ainda não o pôs).
  Um único "sem sessões" mandava o aluno adivinhar qual dos três era.
- **Os separadores por modalidade** passaram a ser construídos sobre a
  lista já filtrada — senão restava um separador "Pilates" que abria
  vazio.

### Uma fuga de dados encontrada pelo caminho

Ligar este filtro fez o cliente do Aluno passar a ler subscrições, e aí
vi a regra que lá estava desde a Fase 3:

```
match /tenants/{tenantId}/subscriptions/{subscriptionId} {
  allow read: if belongsToTenant(tenantId);
}
```

**Qualquer aluno lia as subscrições de todos os outros** — incluindo o
`agreedPrice`, o preço que cada pessoa negociou com o ginásio. Passou a
ser leitura da própria, com Gestor e Instrutor a manterem a visão ampla
(o Instrutor precisa dela para pré-atribuir membros a uma sessão).

Numa query de lista, a regra é avaliada por documento devolvido: uma
query filtrada por `memberId == uid` devolve só os próprios e passa; uma
sem esse filtro falha no primeiro documento alheio. Não foi preciso
inspecionar a query — quatro testes cobrem os dois lados.

### Um teste que mudou de significado

`bloqueia a marcação com mensagem própria quando o membro não é
elegível` verificava que tocar em "Marcar" devolvia a mensagem certa. O
ecrã já não chega lá — a sessão nem aparece, que é uma garantia mais
forte. O teste passou a afirmar isso, e a mensagem de erro continua
coberta em `book_session_use_case_test.dart`, que é onde pertence: a
Cloud Function continua a ser a única validação que conta, e o plano
pode ser cancelado com o ecrã aberto.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**214 testes Flutter** · **177 contra o Emulator Suite**.

## Pesquisa e filtros nas listas de gestão

Pedido depois de testar. Feito como peça partilhada e não ecrã a ecrã:
seis listas precisavam do mesmo, e copiar a caixa de pesquisa seis vezes
garantia seis comportamentos diferentes.

### Ignorar acentos não é polimento

`searchNormalize` tira acentos e passa a minúsculas antes de comparar.
Em português isto decide se a funcionalidade serve: quem procura escreve
"joao" à pressa, quem se inscreveu escreveu "João". Uma pesquisa que
falhasse aí seria pior do que não ter pesquisa nenhuma — daria a
impressão de que a pessoa não está inscrita.

Sem pacote externo: o alfabeto português cabe num mapa, e o `intl` (já
presente) não remove diacríticos.

### Onde ficou, e porquê cada filtro

| Ecrã | Pesquisa | Filtros |
|---|---|---|
| Membros | nome ou nº de sócio | Ativos / Inativos |
| Staff | nome ou email | Instrutores / Gestores |
| Mensalidades | nome ou nº de sócio | Em atraso / Sem registo / Pagas / Com atraso |
| Biblioteca de exercícios | nome, descrição, grupo | grupo muscular (construído do que existe) |
| Alunos (Instrutor) | nome ou nº | — |
| Atribuir plano | nome ou nº, em folha própria | — |

Nome **ou** número em toda a parte, de propósito: quem procura não deve
ter de decidir antes qual dos dois vai escrever.

**Cada chip traz a sua contagem.** "Em atraso (3)" responde à pergunta
que levou a pessoa ao ecrã antes de ela tocar em nada, e evita o filtro
que abre vazio. Nas mensalidades, a contagem só inclui membros ativos —
um inativo não deve mensalidade deste mês, e mantê-lo na lista fazia o
número mentir.

**Nenhuma lista abre já filtrada.** O primeiro chip é sempre "Todos":
uma lista que abre filtrada esconde coisas sem ninguém ter pedido.

Os grupos musculares da biblioteca são construídos a partir dos
exercícios que existem, não de uma lista fixa — `Exercise.muscleGroup` é
texto livre, e um enum ficaria desatualizado no dia seguinte.

### O dropdown de membros

Em "Atribuir plano", escolher a pessoa era um `DropdownButtonFormField`.
Funciona com dez nomes; com trezentos é uma lista por onde se rola à
procura, sem forma de escrever o que se sabe. Passou a ser uma folha com
pesquisa, que mostra só membros **ativos** — atribuir um plano a quem
saiu do ginásio é quase sempre engano.

### "Nada encontrado" ≠ "ainda não há nada"

Cada lista filtrada tem estado vazio próprio, distinto do estado vazio
da lista. Mandar "criar o primeiro membro" a quem escreveu um nome que
não existe seria enganador — há membros, só nenhum corresponde. O texto
diz qual foi a pesquisa que falhou.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**231 testes Flutter** (17 novos: normalização de pesquisa e o
comportamento da lista de membros) · **177 contra o Emulator Suite**.

## Varredura de boas práticas

Pedido: varrer a app à procura de pontos de melhoria segundo o que as
grandes empresas fazem. Fui procurar **classes** de problema com greps
concretos em vez de aplicar uma checklist genérica. Seis achados, todos
corrigidos.

### 1. Itens de lista com estado, sem `key` — um bug a sério

Três widgets de lista com estado interno (`_OccurrenceTile`,
`_BookingTile`, `_SubscriptionTile`) eram construídos sem `key`. O
Flutter emparelha elementos por **posição**: quando a lista muda — uma
sessão é marcada e sai da lista, o stream reordena — o estado fica
agarrado ao índice.

Efeito prático: tocar em "Marcar" na terceira sessão e ver o spinner
aparecer noutra, porque entretanto a lista mudou por baixo. É a regra
"itens de lista com estado levam sempre key", e faltava nos três sítios
onde importava.

### 2. Cache offline do Firestore — estava desligado

Uma linha, e é das poucas coisas de infraestrutura que se ganham assim.
Num ginásio (cave, betão, wifi partilhado) a ligação cai a toda a hora;
com cache, o que já foi lido continua a aparecer e as escritas diretas
ficam em fila.

O que **não** resolve, e é bom não confundir: as Cloud Functions
(marcar, cancelar, criar contas) precisam mesmo de rede — não há como
pôr em fila uma transação que valida capacidade contra o estado do
servidor. Essas continuam a falhar, agora dizendo porquê.

### 3. Erros de rede sem tradução

O `ErrorState` mostrava sempre a mesma frase genérica e escondia o
código atrás de "Detalhe técnico". Melhor do que despejar a exceção, mas
a pessoa continuava sem saber se o problema era dela, da rede, ou da
app — e a resposta muda conforme o caso.

`describeFirebaseError` traduz o que é **acionável**: sem rede
(espera-se), rate limit (espera-se um minuto), sem permissões (fala com
o estúdio), sessão expirada (entra outra vez). Sem ligação o ecrã diz
"Sem ligação" e não "Algo correu mal" — não correu nada mal, e dizer o
contrário manda a pessoa procurar um problema que não existe.

Erros que não sabemos traduzir continuam a cair na frase genérica, de
propósito: inventar uma explicação para um erro que não percebemos é
pior do que admitir que não sabemos.

### 4. Perda de dados ao sair de um formulário

21 ecrãs com campos de texto, **zero** avisos. Preencher a ficha de um
membro novo — nome, contactos, data de nascimento, NIF, morada, contacto
de emergência — tocar sem querer no "voltar" (ou fazer o gesto de voltar
no Android, fácil de acionar por engano) e perder tudo sem uma palavra.

`UnsavedChangesGuard` aplicado aos dois formulários mais longos: criar
utilizador e avaliação física. Duas subtilezas:

- **Lê `hasChanges` no momento de sair, não no build.** Um
  `canPop: !hasChanges()` avaliaria durante a construção do widget e
  ficaria desatualizado no instante do gesto. Há um teste só para isto.
- **A avaliação também EDITA**, por isso "tem alterações" compara com
  uma fotografia dos valores iniciais, tirada no `initState`. Comparar
  com "está preenchido" perguntaria sempre ao editar — e um diálogo que
  aparece sempre é ruído, que ensina a carregar em "sair" sem ler.

### 5. Acessibilidade do `Avatar`

Um leitor de ecrã lia **"RF"**. As iniciais são uma abreviatura visual;
para quem ouve, o que interessa é o nome. Agora anuncia "Rita Ferreira"
e exclui o texto decorativo da árvore semântica.

Ao mesmo tempo: com o texto do sistema a 200%, as iniciais transbordavam
o círculo (que tem tamanho fixo). `FittedBox` encolhe-as para caber, que
é o correto para decoração — ao contrário de conteúdo, que deve crescer.

### 6. Um `IconButton` sem tooltip

Dos 19 da app, 18 já tinham. O que faltava era o "adicionar exercício ao
plano" — sem tooltip, um leitor de ecrã anuncia só "botão".

### O que NÃO fiz, e porquê

- **Localização (l10n).** As strings estão em português no código. Para
  um estúdio português com clientes portugueses, extrair tudo para
  ficheiros ARB é trabalho grande sem retorno nenhum hoje. Passa a fazer
  sentido no dia em que houver um cliente que não fale português.
- **Router declarativo.** A navegação é `Navigator.push` desde a Fase 0,
  sem URLs partilháveis na web nem deep links. Está documentado desde
  então; continua a ser a decisão certa para o tamanho atual, e mudá-lo
  agora tocaria em todos os ecrãs.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**244 testes Flutter** (13 novos) · **177 contra o Emulator Suite**.

## Varredura final

Cinco achados. Dois deles são o tipo de coisa que só se descobre a olhar
para a infraestrutura, e ambos eram **sensíveis ao tempo** — mais baratos
de corrigir agora do que depois do primeiro deploy.

### 1. As Cloud Functions ficavam no Iowa

Por omissão, as Cloud Functions v2 nascem em `us-central1`. O Firestore
vai ficar em `europe-west1` (decisão de RGPD e latência, ver
LANCAMENTO.md). Sem alinhar as duas coisas:

- uma marcação feita num telemóvel em Lisboa viaja até ao Iowa;
- a função atravessa o Atlântico **outra vez a cada leitura e escrita**
  da transação, e uma transação de booking faz várias;
- paga-se tráfego entre regiões por cima disso.

O que torna isto urgente: **uma função implantada não muda de região**.
Migrar obriga a apagar e recriar, com indisponibilidade. Antes do
primeiro deploy custa uma linha.

Ao mesmo tempo, `maxInstances: 10`. No plano Blaze não há teto por
omissão — um ciclo infinito num cliente escala até onde a conta aguentar.
Dez instâncias servem folgadamente um estúdio e transformam um bug caro
num bug lento, que é o lado certo para errar.

O emulador provou o acoplamento na hora: com o cliente ainda a pedir
`us-central1`, **22 testes falharam** com `not-found`. É exatamente a
falha que o comentário no código descreve — e a razão de a região viver
numa constante partilhada (`kFunctionsRegion`) em vez de escrita duas
vezes.

### 2. A CI corria os testes errados

```yaml
firebase emulators:exec --project=demo-gym-saas-dev --only firestore
```

Só o emulador do Firestore. Os cinco ficheiros que chamam Cloud
Functions a sério — concorrência na última vaga, sessões extra, grupos
exclusivos, RGPD, poderes do Gestor — precisam de `functions`, `auth` e
`storage`. E o passo nem sequer compilava as funções antes, pelo que o
emulador arrancaria sem elas.

Ou seja: **os testes de maior valor da suite não estavam a ser corridos
em CI nenhuma**. Uma CI verde que não prova o que parece provar é pior
do que não ter CI, porque dá confiança.

Também faltava `predeploy` no `firebase.json`: sem ele,
`firebase deploy --only functions` publica o JavaScript que estiver em
`functions/lib`, que pode ser de uma compilação de há dias. É o clássico
"mas eu corrigi isso" — corrigido no source, não no que foi publicado.

### 3. Erros que o utilizador vê eram invisíveis em produção

O Crashlytics estava ligado só a erros **não apanhados**. Esta app quase
não tem crashes: apanha tudo e mostra um `ErrorState`. Se amanhã 30% das
marcações falharem por um índice em falta ou uma regra mal publicada,
ninguém fica a saber — os utilizadores veem uma mensagem simpática,
desistem, e a consola diz que está tudo bem.

`reportHandledError` regista-os como não-fatais. Fica no `initState` do
`ErrorState` e não espalhado por cada `catch`: **todo** o erro que o
utilizador chega a ver passa por ali, e o `initState` garante uma
ocorrência por erro em vez de uma por rebuild.

Nunca deixa a telemetria partir o ecrã que está a reportar o erro —
seria trocar uma mensagem por um crash.

### 4 e 5. O que verifiquei e estava bem

Vale a pena dizer o que a varredura **não** encontrou, para não parecer
que ficou por olhar:

- Controllers sem `dispose` — nenhum.
- Erros engolidos em silêncio (`catch (_) {}`) — nenhum.
- N+1 de providers dentro de itens de lista — os três casos encontrados
  são `.family` partilhados ou instâncias únicas, com cache do Riverpod
  a resolver.
- `applicationId` e `bundleId` — já são os reais, não `com.example`.
- Limites de upload no Storage — 100 MB e só `video/*`.
- Idempotência da função agendada de geração de ocorrências — já lá
  estava, com verificação de existência antes de escrever.

### Sobre "tão bom como a Netflix"

Boa parte do que faz a Netflix ser a Netflix não se aplica a um estúdio
com trezentos sócios: CDN global, testes A/B contínuos, personalização
por ML, dezenas de equipas. O que **se** aplica são as práticas de
engenharia — e essas estão feitas: isolamento entre tenants testado,
transações com concorrência testada a sério, regras de segurança
verificadas contra o servidor e não assumidas, RGPD aplicado no
servidor, telemetria de erros reais, CI que corre o que interessa, e
região e custos definidos antes do primeiro deploy.

O que falta não é código: é o que está em [LANCAMENTO.md](LANCAMENTO.md).

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**246 testes Flutter** · **177 contra o Emulator Suite** · Functions a
compilar e a passar lint · build web de produção a compilar.

## Dossier legal (RGPD) — e a fuga que ele encontrou

Nove documentos em [`legal/`](legal/README.md), redigidos a partir do
que o código **de facto** faz, campo a campo, para revisão por advogado:
política de privacidade, registo de tratamentos (artigo 30.º),
consentimento para dados de saúde, procedimento de resposta a pedidos de
titulares, plano de violação de dados, política de conservação,
avaliação sobre AIPD e EPD, subcontratantes, e declarações para a App
Store e o Google Play.

Tudo o que é decisão jurídica está marcado **[ADVOGADO]**; tudo o que é
dado da empresa, **[PREENCHER]**.

### O melhor que saiu disto não foi o texto

A escrever a secção "quem tem acesso" da política, ia escrever a frase
óbvia:

> Nenhum outro aluno vê os teus dados.

Fui verificar antes de a escrever. **Era falsa.**

```
match /tenants/{tenantId}/members/{memberId} {
  allow read: if belongsToTenant(tenantId);
}
```

Qualquer aluno autenticado lia o documento de **qualquer outro membro**
do ginásio: nome, telefone, email, NIF, morada, data de nascimento,
contacto de emergência. E a mesma regra nas marcações de cada aula
deixava listar quem estava inscrito em quê.

O treino livre já fazia isto bem desde a Fase 7 — o UC09/UC17 é
explícito, *"Aluno vê só contagem; Gestor e Instrutor veem nomes"* — e
as aulas normais tinham ficado para trás. O isolamento entre ginásios
estava certo e testado; o isolamento **entre alunos do mesmo ginásio**
não existia.

Corrigido: um aluno lê o seu próprio perfil e as suas próprias
marcações, mais nada. Nenhum ecrã de Aluno precisava do resto — os treze
que usam a lista de membros são todos de Gestor ou de Instrutor.

Cinco testes novos fixam-no, e um teste antigo mudou de significado: "um
membro consegue ler dados do próprio tenant" lia o documento de OUTRO
membro para provar acesso ao tenant. Passava por causa da regra
demasiado larga — ou seja, **provava o isolamento entre ginásios e
escondia a falta de privacidade entre alunos**. Agora lê o seu, que é o
que sempre quis dizer.

É a segunda vez nesta fase que redigir documentação encontra um bug que
a revisão de código não encontrou. A primeira foi a das subscrições, com
o preço acordado de cada pessoa à vista de toda a gente.

### O que fica sinalizado nos documentos

Não são coisas que eu possa resolver:

- **Cópias de segurança por ativar** — enquanto não estiverem, uma
  eliminação errada não tem volta, e isso é material para o artigo 32.º.
- **Sem eliminação automática por prazo** — a política de conservação
  depende hoje de uma revisão manual anual.
- **Diagnóstico de erros na web** pode exigir consentimento prévio pelo
  regime ePrivacy.
- **Menores de idade** não estão tratados: o ecrã de consentimento
  assume um titular maior.
- **A Google exige um caminho web para pedir eliminação de conta** — a
  app faz a verificação presencialmente, e falta a página que o explica.

### Estado

`dart format` limpo · `flutter analyze --fatal-infos` sem problemas ·
**246 testes Flutter** · **182 contra o Emulator Suite** (5 novos de
privacidade entre alunos).

## O Instrutor cria as suas aulas

Pedido depois de testar: *"o instrutor não consegue marcar aulas? Cada
instrutor deveria ter um serviço e modalidade associada e conseguir
criar aulas para essa modalidade/serviço."*

Estava certo. Séries e ocorrências eram **Manager-only** desde a Fase 5,
o que obrigava o Gestor a montar o horário de toda a gente — num estúdio
onde cada instrutor sabe as suas horas melhor do que ninguém.

### Modalidades descreviam; serviços autorizam

O staff já tinha `modalityIds` desde a Fase 6, mas eram **informativas**:
diziam "a Ana dá Pilates" e mais nada. Faltava a peça que decide.

`StaffSummary.serviceIds` é essa peça. Vazio por omissão, e de
propósito: um instrutor recém-criado não deve poder pôr aulas no horário
antes de alguém decidir quais. O Gestor atribui-os na ficha de staff.

### A autorização vive no servidor

```
function instructorOwnsSession(tenantId, data) {
  let staffPath = .../staff/$(request.auth.uid);
  return isInstructor(tenantId)
    && data.get('instructorId', '') == request.auth.uid
    && exists(staffPath)
    && data.get('serviceId', '') in get(staffPath).data.get('serviceIds', []);
}
```

Duas condições, e as duas importam:

1. **A aula tem de ser dele.** Sem isto, um instrutor punha aulas no
   horário em nome de um colega — que depois apareciam no calendário
   dessa pessoa.
2. **O serviço tem de estar na lista dele.** Sem isto, quem dá Pilates
   criava aulas de Hyrox.

Na alteração, a regra avalia **a série que já lá está e a que fica**. Só
com as duas é que este caso é apanhado: uma instrutora a pegar na série
de um colega e a reatribuí-la a si própria produz um estado final
perfeitamente válido *para ela* — o que a trava é ela não ter direito ao
estado inicial. Há um teste dedicado a isso.

O `delete` fica com o Gestor: apagar uma série com ocorrências geradas e
alunos inscritos tem consequências em cadeia.

Custa um `get()` por escrita. Criar ou ajustar uma aula é raro, e a
alternativa — confiar no cliente — não é alternativa nenhuma.

### Na aplicação

O atalho **"Criar aula"** aparece no dashboard do Instrutor, e o ecrã
abre-se constrangido: o seletor de serviço mostra só os dele, e o campo
de instrutor deixa de ser escolha — passa a dizer o nome dele.

**O atalho só aparece se ele tiver serviços atribuídos.** Sem eles o
servidor recusa a criação, e um atalho que leva a uma recusa é pior do
que atalho nenhum. Se abrir o ecrã por outra via, encontra um estado
vazio a explicar que tem de pedir os serviços ao Gestor.

### Estado

**246 testes Flutter** · **195 contra o Emulator Suite** (13 novos, quase
todos a testar recusas: serviço alheio, instrutor alheio, apropriação de
série, instrutor sem serviços, e a criação com marcações já feitas).

A conta de instrutor do seed (`ana@nxtperformancestudio.pt`) já nasce com
o serviço "Aula de Grupo" associado, para o atalho aparecer sem
configuração manual.

## Treino livre, biblioteca e plano de treino

Três coisas apanhadas a usar a app.

### O treino livre pedia o serviço vezes sem conta

Pedia-o ao criar a grelha da semana **e outra vez em cada bloco**. Mas o
treino livre é sempre o mesmo serviço — o que ele precisa de um serviço
para quê: é o que liga cada bloco ao plano do aluno e ao limite semanal.

Passou a ser uma definição do estúdio, escolhida **uma vez** em Gestão ›
Definições. Os dois seletores desapareceram. Sem ela configurada, o ecrã
diz onde se escolhe em vez de perguntar a cada passo.

**Um bug meu, apanhado por um teste:** ao tirar o seletor, fui buscar o
serviço com `ref.read` num `FutureProvider` que, depois de existir
grelha, ninguém neste ecrã observa — devolvia "a carregar", ou seja
`null`, e o bloco não era criado **em silêncio**. Passou a `.future`, que
resolve independentemente de quem observa, e a dizer o que falta quando
falta.

### O vídeo do exercício só se podia carregar depois de o criar

Criar um exercício com vídeo era: preencher, gravar, voltar a abrir,
carregar. A app dizia *"Guarda o exercício antes de carregar o vídeo"* —
que é a app a explicar uma limitação sua em vez de a resolver.

Agora escolhe-se o ficheiro a qualquer momento; fica em memória e sobe ao
gravar, com o exercício já criado.

Sobre o **"nem funciona"**: não consegui reproduzir sem correr a app, e
digo-o em vez de fingir que corrigi. O que encontrei e mudei, e que
plausivelmente o explica:

- O seletor filtrava por extensão **`.mp4` apenas**. Um vídeo gravado num
  telemóvel é `.mov` — não aparecia sequer na janela de escolha, o que se
  lê exatamente como "não funciona". Passou a aceitar qualquer vídeo.
- O `contentType` era sempre `video/mp4`, mesmo quando o ficheiro não
  era. Passou a derivar da extensão.
- Se o problema for outro, o erro agora aparece num banner destacado com
  a mensagem do servidor — e o `ErrorState` reporta-o ao Crashlytics.

### O plano de treino não tinha treinos

O pedido: *"podemos ter vários treinos associados a uma só pessoa, como
costas ou peito, no entanto apenas permite adicionar exercícios."*

Exato. O plano era uma lista corrida de exercícios. Um aluno que treina
três vezes por semana via os exercícios dos três dias todos misturados,
e nem ele nem o instrutor sabiam o que fazer em que dia.

Passou a ter a estrutura que qualquer instrutor usa e que as apps da área
implementam — **plano → treinos → exercícios ordenados**:

- **Treinos** com nome livre ("Treino A — Costas e Bíceps"), ordenados
  pela sequência da semana, com notas gerais.
- **Exercícios ordenados dentro de cada treino**, reordenáveis por
  arrasto. A sequência não é decorativa: agachamento antes de extensão de
  pernas é uma decisão de treino.
- **Descanso entre séries** e **nota por exercício** ("cadência 3-1-1",
  "se doer o ombro, para").

Três decisões que valem a pena:

**A prescrição passou a ser texto.** `reps` era um inteiro, e isso não
chega para o que um instrutor escreve: "8-12", "45s", "até à falha". O
próprio comentário do domínio dava a prancha como exemplo — e o modelo
não a conseguia representar. O histórico de cargas mantém repetições em
número: aí é o que foi mesmo feito, e isso é sempre contável.

**Registar carga deixou de sobrescrever a prescrição.** O código antigo
escrevia as repetições do dia por cima das do plano. As da entrada são o
que o instrutor prescreveu; as do histórico são o que o aluno fez hoje.
São coisas diferentes e agora vivem separadas.

**Apagar um treino não apaga os exercícios.** Ficam num grupo "sem treino
atribuído" para o instrutor os mover. Apagá-los em cascata perderia a
prescrição e deixaria o histórico de cargas sem contexto — e é também
onde aparecem as entradas criadas antes de existirem treinos.

### Estado

**251 testes Flutter** · **195 contra o Emulator Suite** · analyze e
format limpos.

Precisas de voltar a semear: o seed passou a criar o serviço "Treino
Livre" e a configurá-lo, e a dar serviços à instrutora.

## Testar os três papéis ao mesmo tempo

O Firebase Auth na web guarda a sessão em IndexedDB, e o IndexedDB é
isolado por **origem** (esquema + host + porta). `localhost:5100` e
`localhost:5200` são origens diferentes para o browser — logo, sessões
diferentes. Três separadores da mesma janela, cada um com o seu
utilizador, sem andar a saltar entre perfis do Chrome.

```powershell
.\scripts\testar-3-contas.ps1
```

Compila, serve nas portas 5100/5200/5300 e abre os três separadores.
`-SkipBuild` salta a compilação quando o `build/web` já está atualizado.

| Porta | Papel | Credenciais |
|---|---|---|
| 5100 | Gestor | `leo@nxtperformancestudio.pt` / `DevPass123!` |
| 5200 | Instrutor | `ana@nxtperformancestudio.pt` / `InstructorPass123!` |
| 5300 | Aluna | `000001` / `MemberPass123!` |

Staff entra com email, alunos com o nº de sócio — no mesmo campo.

Serve o build estático, por isso **não tem hot reload**: para ver
alterações ao código é preciso voltar a compilar. Para desenvolver
continua a usar-se `flutter run`.

Precisa dos emuladores a correr e semeados.

## Quando a app "está toda bugada"

Aconteceu, e a causa não estava no código: arranques e paragens
repetidos do Emulator Suite deixaram um processo **zombie** a segurar as
portas 5001 e 8080. O hub e a UI não respondiam, e o emulador devolvia
**404 em todas as Cloud Functions**. Do lado da app isso aparece como
`[firebase_functions/internal] internal` e nada funciona: marcar,
cancelar, gerar grelhas.

Passou a haver forma de distinguir isso de um bug a sério, em segundos:

```bash
npm --prefix firebase/tests test -- smoke
```

`smoke-fluxo-completo.test.ts` corre o percurso de uma pessoa sobre os
dados semeados — gerar e publicar a grelha de treino livre, marcar uma
aula, cancelá-la, e confirmar que a subscrição da aluna dá acesso aos
serviços do plano. Se isto passa, o servidor está bom e o problema é
outro; se falha, a mensagem diz onde.

É idempotente de propósito: limpa a marcação e a utilização semanal da
execução anterior antes de começar. Sem isso falhava à segunda vez com
"já tens uma marcação" e "atingiste o limite semanal" — o teste a
tropeçar em si próprio, não a app.

**Se as portas ficarem presas**, o remédio é matar quem as segura e
levantar um único emulador:

```powershell
Get-NetTCPConnection -LocalPort 5001,8080,9099,9199 -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

Depois `firebase emulators:start` e voltar a semear. **Os dados do
emulador não sobrevivem** a isto — é memória, não disco.

## Registo de treino: sessões, séries e histórico

Pedido: *"tanto o gestor, como o treinador, como o próprio aluno deveriam
conseguir iniciar treinos, marcar quantas repetições o aluno fez e ter
acesso a um histórico. Isto é um ginásio com acompanhamento."*

Faltava mesmo, e era o buraco maior que restava. Havia a **prescrição**
(o plano) e um **histórico de cargas solto** por exercício — mas não
havia o **treino**: a ida ao ginásio, com as séries que se fizeram, na
ordem em que se fizeram.

### Como as apps da área resolvem isto

Hevy, Strong, Trainerize e TrueCoach convergem no mesmo modelo, e adotei-o:

1. **Sessão** — escolhe-se um treino do plano e abre-se um registo ao vivo.
2. **Uma linha por série**: `kg × reps` + confirmar, com os campos já
   preenchidos pela prescrição.
3. **O que se fez da última vez**, em cinzento, ao lado. É a peça que faz
   a progressão acontecer: ninguém se lembra do peso da semana passada, e
   sem essa referência o registo vira burocracia em vez de ferramenta.
4. **Terminar** fecha a sessão com duração e volume total.
5. **Histórico** por sessão e por exercício.

A diferença entre as apps de auto-registo e as de acompanhamento é
**quem regista**. Aqui são os três, e é o mesmo componente para todos —
o que muda é o `performedBy` que fica no registo, não haver dois
caminhos na app.

### Duas Rules que impediam isto

**O aluno não podia escrever o seu próprio histórico de cargas.** Era
Instrutor/Gestor apenas. Num ginásio, o aluno registar o seu treino é o
caso normal, não a exceção.

**Estava atrás do consentimento de dados de saúde.** Separei os dois
conceitos, e é a decisão com mais peso desta fase:

- **Avaliações físicas** (composição corporal, pressão arterial) —
  continuam a exigir consentimento explícito do artigo 9.º.
- **Registo de treino** (séries, repetições, cargas) — passou à base
  contratual. É o registo do serviço prestado.

Manter o gate tornava o registo de treino indisponível a quem recusasse
avaliações — e o acompanhamento é o núcleo do serviço, não um extra.
Está sinalizado [ADVOGADO] em `legal/01` secção 5, com um tratamento
próprio no registo do artigo 30.º.

### Decisões de modelo

**As séries vivem num array no documento da sessão**, não numa
subcoleção: uma sessão lê-se e escreve-se como uma unidade, e a
alternativa custaria uma leitura por série sempre que o ecrã abrisse.

**O `loadHistory` continua a ser escrito** em paralelo. É o que alimenta
o gráfico de evolução — uma pergunta ("quanto levantava há três meses")
que as sessões sozinhas não respondem, porque as séries estão dentro de
um array e não são consultáveis.

**O nome do treino é copiado para a sessão.** Um treino pode ser
renomeado ou apagado; um registo que muda de nome retroativamente não é
um registo.

**Uma sessão terminada não se apaga** — nem pelo Gestor. Descartar só
vale para uma em curso, aberta por engano. Apagar histórico passa pelo
apagamento RGPD, que é deliberado e auditável.

### Um teste que mudou de significado

`um membro NÃO consegue criar um registo de carga` (Fase 8) afirmava o
contrário do que agora é correto. Não o apaguei: reescrevi-o para o que
a secção protege de facto — um aluno escreve no SEU histórico e não no
de outro — e deixei o porquê da mudança em comentário.

### Estado

**256 testes Flutter** · **221 contra o Emulator Suite** (12 novos de
sessões de treino, quase todos sobre fronteiras: aluno no treino de
outro, apagar histórico, sobrescrever registos).

## O que ainda faltava a um ginásio com acompanhamento

Perguntaste se existia mais alguma funcionalidade primordial em falta.
Encontrei quatro coisas, uma delas um bug com dinheiro em cima, e
escolheste fazer as quatro.

### 1. Planos expirados continuavam a dar acesso

`endDate` era guardado ao criar a subscrição, mostrado na ficha do
aluno... e ignorado por toda a lógica de autorização, que olhava só
para `status == 'active'`. Um plano terminado em março deixava marcar
aulas em agosto, e a ficha dizia "Ativo" com a data de fim já passada.
Isto não é um detalhe de UI: é receita que o estúdio deixa de cobrar
sem dar por isso.

A correção está em `resolveEligibility`
(`firebase/functions/src/lib/bookingLogic.ts`) e no equivalente do
lado do cliente (`Subscription.grantsAccessAt`), deliberadamente com a
mesma regra dos dois lados — se divergissem, a app mostrava serviços
que o servidor recusa.

Havia ainda um `limit(1)` na query de subscrições que tornava o bug
pior: com dois planos a dar acesso ao mesmo serviço, bastava o
primeiro devolvido estar expirado para o acesso ser negado, mesmo
havendo outro válido. Passou a procurar um válido entre todos.

**Política, decidida e escrita:** vale até ao **fim do dia** do
`endDate`. Quem tem plano "até 31 de março" treina no dia 31. Sem
tolerância depois disso — uma janela de cortesia seria uma decisão de
negócio tua, não minha, e fica fácil de acrescentar num sítio só.

### 2. Lista de espera

A app impõe capacidade por desenho, portanto aulas cheias são o normal
e não a exceção. Sem fila, um cancelamento deixava **um lugar vazio
que ninguém sabia que existia**: quem estava interessado tinha de
andar a abrir a app a ver se tinha vagado, e na maior parte das vezes
não voltava a abrir.

Agora, numa sessão cheia, o botão desativado "Sem vagas" dá lugar a
"Entrar em lista de espera". Quando alguém cancela, o primeiro da fila
**fica com o lugar automaticamente** e é notificado.

**Promoção automática e não convite com prazo.** Algumas apps avisam e
dão X minutos para confirmar. Isso exige um temporizador por cada lugar
vago e deixa o lugar em suspenso enquanto ninguém responde — num
estúdio pequeno, aulas a começar com lugares reservados para quem não
viu a notificação. A troca é justa porque cancelar é barato: quem for
promovido e já não puder vir cancela, e dentro da janela de
antecedência recupera a utilização semanal. A notificação diz-lhe
exatamente isso.

A promoção percorre a fila em vez de levar só o primeiro: quem perdeu
a elegibilidade entretanto (plano acabou, foi cancelado) sai da fila em
silêncio e passa-se ao seguinte — senão bloqueava a fila para sempre.

**A posição é escrita pelo servidor em cada entrada**, e recalculada a
cada entrada, saída e promoção. Não é o cliente a contar: as Rules não
deixam um aluno **listar** a fila, só ler a entrada dele. Quem mais
está à espera é informação dos outros.

### 3. Lembrete antes da aula

A falta sem aviso é o custo real de um estúdio com capacidade
limitada: o lugar ficou ocupado, ninguém o pôde usar, e a aula correu
com menos gente do que a lista dizia. Quase nunca é má-fé — é alguém
que marcou na segunda-feira e se esqueceu na quinta.

Uma função agendada (de hora a hora) avisa quem tem marcação, com a
antecedência que definires nas Definições (12 horas por omissão, "0"
desliga). O corpo da mensagem pede explicitamente o cancelamento a
quem já não puder vir — o objetivo não é só recordar, é **provocar o
cancelamento atempado**, que devolve a utilização semanal e liberta o
lugar para o primeiro da lista de espera. As duas funcionalidades
desta fase encaixam uma na outra de propósito.

`reminderSentAt` na ocorrência garante um único aviso por sessão,
mesmo com a função a correr de hora a hora. Marca-se mesmo quando não
há ninguém inscrito, senão a sessão era relida a cada hora até começar.

A mensagem diz "daqui a cerca de N horas" e nunca uma hora absoluta —
o runtime das Functions não sabe o fuso do aluno e imprimir a hora em
UTC dava uma notificação errada metade do ano (a mesma limitação já
assinalada na Fase 6, aqui contornada em vez de ignorada).

### 4. Painel de retenção

Num ginásio de proximidade, quem desiste não cancela: deixa de
aparecer, continua a pagar dois ou três meses, e só depois cancela.
Nessa altura já não há conversa possível. O sinal existia nos dados
desde a Fase 6 — presenças e faltas — mas não havia nenhum ecrã que o
lesse: só se via aula a aula, uma de cada vez.

Gestão › Dinheiro › **Retenção**: ocupação e taxa de faltas dos
últimos 30 dias, e a lista de quem não aparece há 2 semanas / 3
semanas / 1 mês / 2 meses. A lista ocupa o resto do ecrã e cada linha
abre a ficha do aluno, porque é a única das três coisas que se traduz
numa ação hoje: ligar a estas pessoas.

Decisões que separam um número útil de um número enganador, todas com
teste:

* **Só quem tem plano ativo** entra na lista de risco. Quem já não tem
  plano não está em risco de sair — já saiu; contá-lo inflacionava o
  número e enterrava quem ainda dá para recuperar.
* **Ocupação é sobre lugares, não sobre sessões.** Uma aula de 10 com
  2 pessoas e outra de 2 com 2 não são "50% e 100%, média 75%": são 4
  lugares ocupados em 12, 33%.
* **Sessões futuras e canceladas não contam.** Uma aula de amanhã com
  duas marcações não é uma aula com 20% de ocupação.
* **Sem presenças registadas, a taxa de faltas é "—" e não "0%".** 0%
  diria que está tudo bem; a verdade é que ninguém registou nada — e o
  ecrã diz isso, incluindo no estado vazio da lista de risco.
* **"Sem presença nos últimos N dias", nunca "nunca veio".** Só se
  procura até ao início do período; afirmar mais do que isso seria
  mentira.

Fica no servidor (`getRetentionOverview`) e não no cliente porque
agregar isto obriga a ler as presenças de todas as sessões do mês, e
essas vivem em subcoleções que o cliente nem sequer pode percorrer de
uma vez — as Rules não abrem `attendance` a collection group queries,
de propósito.

### Estado

**256 testes Flutter** · **263 contra o Emulator Suite** (+42 nesta
ronda: 4 do bug dos planos expirados, 12 da lista de espera incluindo
as Rules da fila, 8 dos lembretes, 13 da retenção, 5 das regras de
leitura da fila).

**Índice novo por implantar:** `sessionOccurrences (status, startAt)`,
usado pelos lembretes. Junta-se aos que já estavam à espera de
`firebase deploy --only firestore:indexes`.

## Quatro coisas estranhas no treino

Reportadas a testar, e todas com a mesma raiz: a Fase 11 acrescentou
treinos e registo ao vivo, mas os ecrãs que já existiam não foram
revistos à luz dos dados novos que passaram a receber.

### 1. O aluno não via a que treino pertencia cada exercício

O editor do instrutor ganhou "Treino A — Costas" / "Treino B — Peito".
O ecrã do aluno continuou a ser a lista corrida que era antes de os
treinos existirem: dezoito exercícios seguidos, sem dizer quais eram os
de hoje. A informação estava na base de dados e não chegava a quem
precisa dela para treinar.

"O meu plano" passou a ser uma secção por treino, com o nome, as
instruções que o instrutor escreveu (que até aqui só ele próprio via),
os exercícios pela ordem prescrita, e **um botão para começar aquele
treino** — sem voltar a perguntar qual, porque a pergunta já foi
respondida ao ler o cabeçalho.

Exercícios sem treino atribuído continuam visíveis, num grupo próprio.
Esconder o que o instrutor prescreveu seria pior do que os mostrar
desarrumados.

### 2. Uma série registada não se podia corrigir

Só havia "anular a última". Enganar-se na segunda de quatro séries
obrigava a apagar as outras duas e a registá-las de cabeça — e o erro
mais caro (60 kg escritos como 6) ficava também no histórico de cargas,
onde não havia forma nenhuma de lhe tocar.

Agora toca-se na série confirmada e corrige-se ali, ou apaga-se. A
parte que interessa é o que acontece por baixo: **cada série passou a
guardar o id do registo de carga que criou** (`SetLog.loadHistoryId`).
Sem essa ligação era impossível saber qual dos registos do exercício
correspondia à série errada — e por isso é que, até aqui, "anular"
deixava deliberadamente um registo órfão no gráfico.

Isso obrigou a abrir uma fresta nas Security Rules, e o desenho da
fresta é a decisão importante:

* `update` continua bloqueado para toda a gente. "Nunca sobrescrever o
  histórico" (UC16) mantém-se.
* `delete` passou a ser permitido **apenas** em registos que vieram de
  uma série (`sessionId` presente). Corrigir é apagar o errado e criar
  o certo.
* Os registos que o Instrutor cria ao mudar a carga prescrita **não
  têm `sessionId`** e continuam imutáveis. A progressão que o UC16
  protege é essa; um engano de dedo registado há dois minutos não é
  progressão, é lixo que fica no gráfico para sempre.

**Limite assumido:** corrigir é durante a sessão. Depois de terminada,
o treino é histórico e a app não oferece edição — as Rules até a
permitiriam, mas não há ecrã para isso, e dizê-lo aqui é melhor do que
deixar alguém à procura.

### 3. A evolução da carga mostrava todas as séries

Com o registo ao vivo, cada exercício escreve um registo por série:
quatro séries num dia davam quatro linhas iguais, e três treinos por
semana davam doze linhas por semana — para responder sempre à mesma
pergunta, "estou a subir?".

Passou a ser **uma linha por dia de treino, com a melhor série desse
dia**: a carga mais alta, e as repetições que saíram nela. Empate na
carga resolve-se pelas repetições (60 × 10 é melhor série do que 60 ×
8). Cada linha traz o ganho em relação ao treino anterior, e o número
de séries do dia como contexto do que ficou de fora.

Por cima, um gráfico da progressão — desenhado à mão com um
`CustomPainter`, sem biblioteca nova: uma linha e alguns pontos não
pagam uma dependência, e um pacote de gráficos traz temas próprios que
teriam de ser dobrados ao design da app.

### 4. Históricos sem filtragem nem agrupamento

Três ecrãs que eram listas corridas e cresciam para sempre:

* **Treinos feitos** — agrupado por mês, com filtro por treino e um
  resumo no topo (quantos treinos, volume total, há quantos dias foi o
  último). O mês é a régua com que se pensa em treino ("em julho fui
  doze vezes"); o filtro responde à outra pergunta frequente, "quando
  foi a última vez que fiz pernas?".
* **Avaliações** — agrupadas por ano, e cada linha traz a diferença de
  peso para a avaliação anterior. Antes era preciso abrir duas fichas e
  subtrair de cabeça. A diferença é mostrada sem cor de "bom/mau": quem
  treina para ganhar massa quer o sinal contrário de quem treina para
  perder peso, e não cabe à app decidir qual é qual.
* **Mensalidades** — agrupadas por ano, com o estado do ano no
  cabeçalho ("Em dia", "2 em atraso"). A pergunta que se faz a um
  histórico de mensalidades é sobre o ano, não sobre a lista toda.

### Estado

**266 testes Flutter** (+10: cinco do plano agrupado por treino, cinco
da evolução por dia) · **268 contra o Emulator Suite** (+5, todos sobre
a fresta nova nas Rules — incluindo a prova de que os registos sem
`sessionId` continuam intocáveis).

## Varredura de bugs e de UX

Passagem por todos os 51 ecrãs, todos os repositórios e todas as Cloud
Functions, à procura do que estava errado e do que estava só
desconfortável. O que se segue é o que encontrei e corrigi, dos bugs
para os detalhes.

### Um campo em falta explicava quatro bugs

A marcação não guardava **quando é que a sessão acontece**. Só isso, e
daí saíam quatro comportamentos errados:

1. **"As minhas marcações" ordenava pela data em que a marcação foi
   FEITA.** Marcar hoje uma aula do mês que vem punha-a antes da de
   amanhã, marcada na semana passada.
2. **As sessões passadas nunca saíam da lista**, com um botão
   "Cancelar" que já não fazia sentido nenhum (e que o servidor
   recusaria).
3. **As marcações de treino livre apareciam partidas.** A app lê as
   marcações todas com uma collection group query, e o treino livre
   vive noutro caminho (`freeTrainingSchedules/{semana}/slots/{slot}/
   bookings`). O ecrã tratava tudo como aula: o cartão dizia "Sessão já
   não disponível" e o "Cancelar" chamava a Cloud Function das aulas —
   falhava **sempre**, e não havia forma de tirar o cartão de lá.
4. **O ecrã inicial dizia "não tens nenhuma sessão futura marcada"** a
   quem tinha treino livre marcado para o dia seguinte: procurava a
   próxima sessão resolvendo uma ocorrência por marcação, e as de
   treino livre resolviam para `null`.

A correção é `startAt` copiado para a marcação no momento em que ela é
criada (`bookingLogic.ts`), mais o tipo de marcação derivado do
caminho. Com isso, "as minhas marcações" ordena, separa próximas de
"já realizadas", identifica o treino livre e cancela-o pela função
certa — e o ecrã inicial deixou de fazer **uma leitura extra por
marcação** só para saber qual é a próxima.

### "Membro ativo: não" era uma etiqueta

Desativar um aluno na ficha dele não impedia nada: a autorização olhava
só para as subscrições, e a subscrição de quem sai raramente é
cancelada no mesmo instante. O interruptor existia, dizia "Inativo", e
a pessoa continuava a marcar aulas.

Passou a ser verificado em `resolveEligibility` — o sítio por onde
passam **todos** os caminhos (marcar, treino livre, atribuição manual,
geração automática, promoção da lista de espera), em vez de em cada um
deles. Ausência do campo conta como ativo, para não trancar dados
antigos. Do lado do aluno, a conta inativa passou a dizê-lo numa faixa
no ecrã inicial: sem isso ele via os botões todos e recebia uma recusa
que parecia um bug da app.

### Treino livre: três coisas no mesmo cartão

* **Sem estado de ocupado.** O botão ficava ativo durante a chamada ao
  servidor; dois toques seguidos disparavam duas reservas.
* **Blocos já passados ofereciam "Reservar".** Na sexta, o bloco de
  segunda às 8h continuava a convidar; o servidor recusava, e a recusa
  chegava como erro genérico.
* **Erros em cru.** `'$e'` num SnackBar dá exatamente aquele
  `[firebase_functions/internal] internal` que já tinhas apanhado. Usa
  agora a mesma tradução do resto da app (`describeFirebaseError`), tal
  como o "esqueci-me da password" no login.

### Sessões canceladas na lista do aluno

Uma aula cancelada pelo estúdio continuava a aparecer em "Marcar", com
as vagas todas livres e um botão desativado sem explicação. Quem tinha
marcação nela já foi notificado; para os outros era só ruído — deixou
de aparecer.

### Ordenação e agrupamento

* **Marcar treino** — agrupado por dia, com "Hoje" e "Amanhã" em vez da
  data. O cartão deixou de repetir a data (o cabeçalho já a dá) e
  mostra só a hora. Uma lista corrida de quarenta aulas obrigava a ler
  a data de cada cartão para saber se era hoje ou daqui a duas semanas.
* **Aulas / Horários** (Gestor) — ganhou procura (serviço, instrutor,
  dia) e filtro por serviço; as séries passaram a estar ordenadas por
  dia da semana e hora, que é como um horário se lê. As canceladas
  saíram do meio das ativas para uma secção própria no fim: uma série
  cancelada não é horário, é histórico que se pode querer reativar.
* **Listas de pessoas** — `watchMembers`/`watchStaff` devolviam os
  documentos pela ordem do Firestore, que para ids automáticos é ordem
  nenhuma. Passaram a vir por nome, com os acentos normalizados para
  "Álvaro" não cair no fim do alfabeto. Ordenado no cliente e não com
  `orderBy('name')` de propósito: um `orderBy` **exclui** documentos
  sem o campo, e um registo antigo sem nome desapareceria da gestão em
  vez de aparecer por arrumar.
* **Notificar um membro** — a escolha era um `DropdownButtonFormField`
  com todos os alunos lá dentro. Passou a usar o mesmo seletor com
  procura que já existia para atribuir planos.

### "Ocupação média" que não era ocupação

O painel do Gestor mostrava "Ocupação média" calculada sobre sessões
que **ainda não aconteceram**: uma aula de sexta ainda por encher punha
o número em 20% numa semana que acabou cheia. Passou a chamar-se
**"Lotação prevista"**, que é o que é. A ocupação realizada vive no
painel de Retenção e é calculada só sobre sessões já dadas — os dois
números coexistem agora sem se contradizerem.

Os cartões desse painel também mostravam um spinner eterno quando a
leitura falhava (o estado de erro estava mapeado para o mesmo `null` do
estado de carregamento). Passaram a mostrar que falharam.

### Marcar presenças era um toque por pessoa

Numa aula de vinte, vinte toques — todos os dias. Ninguém faz isso mais
do que uma semana, e sem presenças registadas o painel de retenção
mostra toda a gente "em risco" e a taxa de faltas a "—". Ou seja: a
funcionalidade que mede a retenção dependia de um gesto que ninguém
repetiria.

"Marcar todos como presentes" resolve-o num toque, e **não sobrescreve
quem já foi marcado**: o caso normal é "vieram todos menos aquele
dois" — marcam-se as faltas e o botão trata do resto, dizendo quantos
faltam ("Marcar os restantes 3 como presentes").

### Custo

`getRetentionOverview` é a função mais cara do projeto — percorre as
sessões do mês e lê as presenças de cada uma. Não tinha limite de
chamadas: um ecrã com um bug de refrescamento custava leituras a sério.
Ganhou o mesmo rate limiting das funções de marcação.

### O que ficou por fazer, e porquê

* **Lista de espera no treino livre.** As aulas têm; os blocos de
  treino livre cheios continuam a mostrar "Sem vagas". A promoção
  automática está escrita contra `sessionOccurrences` e estendê-la aos
  slots é uma mudança de fundo, não um retoque — fica sinalizada em vez
  de meio-feita.
* **Corrigir séries de um treino já terminado.** Corrige-se durante a
  sessão; depois de terminada não há ecrã para isso (as Rules até o
  permitiriam).
* **`watchMembers` continua sem limite.** Para um estúdio (centenas de
  alunos) é uma leitura completa aceitável e simplifica muita coisa;
  para milhares seria preciso paginar, e aí a procura teria de passar a
  ser feita no servidor.

### Estado

**272 testes Flutter** (+6: quatro sobre os tipos de marcação e a
ordenação em "as minhas marcações", dois sobre a marcação de presenças
em bloco) · **270 contra o Emulator Suite** (+2 sobre a conta
desativada — deixa de poder marcar, e reativar devolve o acesso — mais
a prova de que a marcação guarda mesmo a data da sessão, que é a peça
de que dependem quatro das correções acima).

## Onde está o dinheiro (e o que passou a custar menos)

Antes de mexer em nada, contei o que a app pede ao Firebase numa
utilização normal. A ordem das contas não é a que se espera.

**O Firestore não é o problema.** Uma sessão de um aluno (abrir a app,
ver o horário, ver o plano) custava ~250 leituras. Com 200 alunos a
abrir a app 20 vezes por mês são ~1M de leituras/mês — dentro do
plafond gratuito diário (50 000 leituras/dia) na maior parte dos dias,
e a poucos cêntimos se o ultrapassar.

**O tráfego dos vídeos é o problema.** Cada aluno que abre um exercício
descarrega o ficheiro inteiro. Um vídeo de 40 MB, visto uma vez por 150
alunos, são 6 GB — por exercício. Uma biblioteca de 40 exercícios vista
uma vez por toda a gente são 240 GB, e o tráfego de saída do Storage é
a rubrica mais cara do Firebase. Isto podia ser **duas ordens de
grandeza** acima de tudo o resto junto.

### O que mudou

**1. Vídeos com cache (a correção que mais poupa).** Os vídeos subiam
sem `Cache-Control`, por isso o browser voltava a descarregar o
ficheiro inteiro em cada visualização. Passaram a subir com 30 dias de
cache — a segunda vez que o mesmo aluno vê o mesmo exercício deixa de
custar tráfego. É seguro apesar de o caminho ser sempre o mesmo:
substituir o vídeo gera um token de download novo, logo um URL novo,
que a cache antiga não serve.

Ao escolher o ficheiro, o instrutor passa a ver um aviso acima de 25 MB
a dizer o que isso significa para quem o vai ver. Aviso, não bloqueio:
quem quiser mesmo carregar um vídeo grande, carrega.

**2. O horário deixou de vir todo.** "Marcar treino" lia as sessões de
TODOS os serviços do ginásio e filtrava em memória pelos serviços do
plano do aluno. Passou a pedir ao servidor só os serviços a que ele tem
direito (`whereIn`, que usa o índice `serviceId+startAt` que já
existia). Um aluno só com aulas de grupo deixou de descarregar Pilates
e PT para os deitar fora.

E o caso extremo: um aluno **sem plano nenhum** lia o horário completo
para lhe dizerem que não tinha acesso a nada. Agora não se faz query
nenhuma — conjunto de serviços vazio, zero leituras.

**3. O treino livre deixou de perguntar bloco a bloco.** "Já reservei
este horário?" era uma leitura por bloco: vinte blocos numa semana,
vinte leituras de cada vez que o separador abria. As marcações de
treino livre já vinham todas na mesma consulta que serve "as minhas
marcações" — desde que a marcação passou a saber a que semana e a que
slot pertence, isto deriva-se sem uma única leitura extra.

**4. O ecrã inicial deixou de resolver uma ocorrência por marcação**
(corrigido na varredura anterior, mas conta aqui: era uma leitura por
marcação ativa, em cada abertura da app, só para saber qual era a
próxima).

**5. Cache no alojamento web.** O `firebase.json` não tinha secção de
hosting nenhuma. Ficou configurada com os cabeçalhos certos: o
CanvasKit (a maior fatia do que o browser descarrega, e que só muda com
a versão do Flutter) com um ano de cache imutável; o `main.dart.js` com
`must-revalidate` — que devolve `304 Não modificado` e **zero bytes**
quando a app não mudou, sem nunca arriscar servir uma versão velha; e
o `index.html` e o service worker sem cache, que são eles que decidem
que versão se usa.

**6. Rate limiting na função mais cara.** `getRetentionOverview` — a
única que percorre um mês de sessões — não tinha limite de chamadas. Um
ecrã com um bug de refrescamento custava leituras a sério; agora tem o
mesmo teto das funções de marcação.

Resultado: a sessão de um aluno passou de ~250 para ~140 leituras, e os
casos que liam o horário todo para mostrar um estado vazio passaram a
zero. O tráfego de vídeo repetido passou a zero.

### O que NÃO fiz, e porquê

Isto é tão importante como a lista de cima. Três otimizações que
pareciam boas e não pagam a complexidade que trazem:

* **Contadores de presença desnormalizados** (um trigger a manter
  `attendedCount`/`lastAttendanceAt`) para o painel de retenção deixar
  de percorrer as presenças sessão a sessão. Poupa ~3 000 leituras por
  mês — **menos de um cêntimo** — e traz um trigger que pode ficar
  dessincronizado com a verdade. O painel é do Gestor, abre-se meia
  dúzia de vezes por dia e já tem rate limiting. Fica como nota: se um
  dia forem várias centenas de sessões por mês, é este o passo
  seguinte.
* **Juntar as três leituras do documento de configuração numa só.** São
  duas leituras a mais por abertura das Definições, num ecrã que só o
  Gestor abre. Trocar clareza por isso não se justifica.
* **Ler só os exercícios do plano do aluno** em vez da biblioteca toda.
  Faria sentido com uma biblioteca de centenas; com a cache offline
  ligada (Fase 8), a segunda abertura da app já só paga os documentos
  que mudaram.

### O que continua a ser teu

* **Orçamento com alertas** no Google Cloud Billing (já está no
  `LANCAMENTO.md`) — é a rede de segurança que nenhuma otimização
  substitui.
* **Não ligues `minInstances`** nas Cloud Functions. Tira o arranque a
  frio e passa a custar dinheiro 24h por dia, mesmo sem ninguém a usar
  a app. `maxInstances: 10` já está definido, e é o que interessa:
  transforma um bug caro num bug lento.
* **Vídeos curtos.** É a única decisão do dia a dia com impacto real na
  fatura: 40 exercícios a 5 MB são 200 MB de biblioteca; a 50 MB são 2
  GB, e cada visualização multiplica isso pelo número de alunos.

### Estado

**278 testes Flutter** (+6: quatro sobre a query filtrada por serviço —
incluindo a prova de que um aluno sem plano não gera query nenhuma — e
dois sobre o estado do botão de treino livre agora que ele deixou de
custar uma leitura por bloco) · **270 contra o Emulator Suite**.

Nenhum dos comportamentos mudou para quem usa a app: as mesmas sessões,
as mesmas reservas, os mesmos avisos. O que mudou foi quanto se pede ao
servidor para os mostrar.

## Última ronda

Seis coisas, e três delas eram bugs a sério — do tipo que só se descobre
a ler o código com tempo, porque nenhuma delas rebenta: dão a resposta
errada em silêncio.

### 1. As aulas apareciam uma hora depois no verão

O maior. Uma série guarda `startTime: "19:00"` — a hora a que a aula
começa, escrita por quem a criou a olhar para o relógio da parede. A
geração das ocorrências fazia `setUTCHours(19)`, ou seja tratava essas
19:00 como **UTC**.

Em Portugal isso está certo no inverno e errado no verão: do último
domingo de março ao último de outubro Lisboa é UTC+1, e a mesma aula
passava a aparecer **às 20:00** na app — para o aluno, para o instrutor,
para toda a gente, sete meses por ano. As sessões avulsas não tinham o
problema (nascem de um seletor de data/hora, já com o instante certo),
o que tornava tudo mais confuso ainda: no horário, as aulas da série
apareciam uma hora depois das outras.

A cópia da semana de treino livre tinha a mesma doença por outra via:
somava `7 × 24h` em milissegundos, o que na semana da mudança da hora
muda o bloco das 18:00 para as 17:00.

Corrigido sem dependência nova — o Node traz os dados de fusos horários
completos e o `Intl` sabe responder a "que horas eram em Lisboa neste
instante?"; com isso mede-se o desvio e faz-se a conversão
(`lib/timeZone.ts`, 9 testes só sobre as semanas em que o relógio muda,
nos dois sentidos). O fuso vem do documento do estúdio, e não está
escrito à força em lado nenhum.

### 2. Remarcar um aluno podia deixá-lo sem nada

`rescheduleBooking` cancelava na origem e só depois descobria que o
destino estava cheio, cancelado, inexistente, ou fora do plano do
aluno. O instrutor carregava num botão para mudar alguém de hora e o
aluno **saía do horário** — com uma mensagem a explicar-lhe que agora
tinha de o marcar à mão.

Agora tudo o que se consegue saber de antemão é verificado antes de
tocar em nada. A janela que sobra é uma corrida real e estreita (alguém
ocupar a última vaga do destino nos milissegundos entre a validação e a
marcação), e essa continua a ser reportada como tal.

A ordem contrária — marcar no destino primeiro, largar a origem depois —
eliminaria a corrida por completo, mas parte quem tem limite semanal: o
aluno passaria a ocupar duas utilizações ao mesmo tempo e uma
remarcação neutra seria recusada por limite atingido. Fica escrito no
código, para não ser "melhorado" mais tarde.

### 3. Qualquer aluno lia o NIF e a morada dos instrutores

O documento de `staff` é legível por todo o ginásio de propósito — é
dele que sai o nome do instrutor no cartão de uma aula. Só que lá
dentro estavam também **telefone, data de nascimento, morada, NIF e
contacto de emergência**.

É exatamente a mesma fuga que foi encontrada e fechada em `members` na
Fase 11 (foi escrever a política de privacidade que a revelou); o staff
tinha ficado para trás. E o registo de tratamentos já dizia, na altura,
que o destinatário destes dados era "o gestor do estúdio" — o documento
estava certo e o código é que não.

Os dados pessoais passaram para `staff/{uid}/private/profile`, que só o
próprio e o Gestor leem, com escrita sempre pelas Cloud Functions. O
documento público fica com o mínimo para a app funcionar: nome, email
(é a identidade de login e o contacto profissional), papéis, serviços,
modalidades e estado.

### 4. A lista de espera só olhava para os cancelamentos

Abrir mais vagas numa aula cheia não puxava ninguém da fila. E é o caso
mais comum de todos: a aula enche, ficam três pessoas à espera, o
instrutor decide que "cabem mais dois" e edita a lotação de 8 para 10 —
e os dois lugares novos ficavam vazios com três pessoas a olhar para
eles.

Passou a haver um trigger sobre o documento da sessão (e não uma
função chamada pela app: editar a sessão é uma escrita direta do
cliente, e há mais do que um caminho até lá — incluindo uma correção
feita à mão na consola). Tirar alguém de uma sessão pelo ecrã de gestão
também passou a puxar a fila.

### 5. Escritas que ficavam à espera para sempre

Com a cache offline ligada, o `Future` de uma escrita no Firestore **só
completa quando o servidor confirma**. A cache local atualiza-se logo —
mas o `await` fica pendurado. Num ginásio, onde a ligação cai a toda a
hora e o instrutor está a marcar presenças com o telemóvel na mão, isso
é um botão que roda para sempre: nem erro, nem sucesso. A pessoa toca
outra vez, e outra.

`writeOrQueue` espera pela confirmação, mas não para sempre: passado o
tempo limite devolve o controlo à UI e diz a verdade — *"guardado no
telemóvel; assim que houver ligação, sobe sozinho"*. A escrita não é
cancelada, só se deixa de a esperar. Um erro que aconteça **enquanto
ainda se espera** continua a subir (se as Rules recusam à frente da
pessoa, ela tem de saber); só o que chega depois de termos desistido é
que é engolido — nessa altura já ninguém está à escuta, e deixá-lo
solto rebentava num sítio sem relação nenhuma com o que se estava a
fazer.

### 6. Funções que podiam morrer a meio

As que percorrem um número de documentos que cresce com o ginásio —
desativar um instrutor, sincronizar um plano, apagar os dados de um
aluno, gerar o horário — corriam com o tempo-limite por omissão de 60
segundos. Num estúdio grande, uma delas podia parar a meio: metade das
sessões canceladas, metade não, e nada a dizer que ficou assim. Levam
agora tempo-limite explícito, uma a uma. As de marcação continuam com o
teto normal, de propósito: uma marcação que demore 60 segundos é um
bug, não um caso a acomodar.

### Estado

**285 testes Flutter** · **294 contra o Emulator Suite** (+24 nesta
ronda: 9 sobre as semanas em que o relógio muda, 6 sobre remarcações que
não podem perder a marcação de origem, 6 sobre os dados pessoais do
staff, 3 sobre a fila de espera quando se abrem vagas), mais 5 testes
Flutter sobre as escritas offline.

Cada um destes testes falha na versão anterior do código — foi assim que
confirmei que os bugs eram reais e não interpretações minhas do que o
código parecia fazer.

**Nota para o ambiente de testes:** as ocorrências geradas antes desta
ronda ficaram com a hora antiga (UTC). Não há dados de produção, mas o
emulador tem — apagar e voltar a gerar o horário é o mais simples.

## Estatísticas do aluno, e treinar com a turma

Duas peças para quem acompanha — e as duas saíram de olhar para o que
as apps da área fazem, não de inventar.

### Estatísticas por aluno

O Instrutor tinha o histórico (treino a treino) e as avaliações (uma a
uma), mas nenhum sítio onde ver a pessoa toda: se está a aparecer, se
está a subir, se treina sempre a mesma coisa. É isso que se olha antes
de falar com alguém, e era o que faltava.

Ficha do aluno › **Estatísticas**. A ordem das secções é a decisão
principal, e é a mesma a que o Hevy, o Strong, o Trainerize e o
TrueCoach chegaram:

1. **Consistência** — treinos por semana, nas últimas 12 semanas, mais
   a sequência de semanas seguidas. É o número que melhor prevê se
   alguém ainda é sócio daqui a seis meses, e o único que se traduz
   numa conversa hoje. As semanas vazias aparecem no gráfico: sem elas,
   três treinos em três meses desenhavam a mesma linha que três treinos
   numa semana.
2. **Equilíbrio** — séries por grupo muscular (dos últimos 30 dias). É
   onde se vê quem faz peito três vezes por semana e pernas nunca.
3. **Força** — por exercício, a melhor série e a **estimativa de 1RM**
   (Epley, `carga × (1 + reps/30)`), com a variação desde o primeiro
   registo. Toca e abre a evolução da carga, dia a dia, que já existia.
4. **Composição corporal** — peso, massa gorda, massa muscular e IMC,
   com a variação desde a primeira avaliação.

Três decisões que separam um número útil de um número bonito:

* **Acima de 12 repetições não se estima 1RM.** A fórmula afasta-se
  depressa da realidade — uma série de 20 daria um valor que a pessoa
  nunca levantaria. Aparece "—" em vez de um número falso.
* **Sem carga não há 1RM.** Uma prancha ou uma corrida entram nas
  contagens, mas não em força.
* **A variação de peso não tem cor de "bom" ou "mau".** Ganhar peso é o
  objetivo de quem treina para massa e o contrário de quem treina para
  emagrecer; a app mostra a direção, quem interpreta é o instrutor.

E uma que é sobre honestidade: quando não há treinos registados, o ecrã
diz que as estatísticas saem do que fica registado em cada treino — não
acusa o aluno de não treinar. Pode treinar e ninguém registar.

O cálculo é uma função pura (`computeMemberStats`), com 16 testes que
fixam cada uma destas regras. E não custa uma leitura a mais: usa as
mesmas duas queries que a ficha do aluno já fazia.

### Treinar com a turma

Registar o treino de dez pessoas abrindo a ficha de cada uma, uma a
uma, é impossível de fazer com o telemóvel na mão enquanto se dá a
aula. O resultado prático era não se registar nada — e sem registos, as
estatísticas acima e o painel de retenção ficam a olhar para o vazio.

O modelo é o que os softwares de box e estúdio usam para exatamente
esta situação (Wodify, SugarWOD, PushPress, e o "group training" do
Trainerize): **parte-se da AULA, não do aluno**. Na sessão, o botão
"Treinar com a turma" abre um ecrã com:

* a turma inteira numa tira horizontal, cada um com o seu estado ("por
  iniciar", "4 séries");
* **"Iniciar treino para a turma"** — abre a sessão de toda a gente de
  uma vez, e salta quem já estava a treinar (alguém que chegou mais
  cedo e começou pelo telemóvel; abrir-lhe uma segunda sessão seria não
  saber a qual pertence a próxima série);
* o registo do aluno selecionado por baixo, com a **prescrição dele à
  frente** — trocar de pessoa é um toque, sem sair do ecrã;
* **"Terminar todos"** no fim, que fecha o que tem séries e descarta o
  que ficou vazio (um treino sem uma única série no histórico é ruído).

Por baixo continuam a ser sessões individuais, uma por aluno, com o
nome da aula. É deliberado: o histórico, as estatísticas e a evolução
da carga de cada um continuam a funcionar exatamente como antes, sem
nenhum conceito novo de "sessão partilhada" para tratar em todo o lado.

O registo de uma série passou a ser um widget partilhado
(`ExerciseLogger`): é a mesma peça no treino individual e no de turma —
o que muda é de quem é a sessão.

### Um bug apanhado a construir isto

O botão "Iniciar treino para a turma" não fazia nada à primeira. A
causa é conhecida nesta base de código e está documentada desde a Fase
2: um `StreamProvider` só arranca quando alguém olha para ele, e ler
`currentAppUserProvider` com `valueOrNull` dentro do handler de um
toque apanha-o ainda em carregamento — o utilizador fica `null` e a
função sai em silêncio. O mesmo estava a acontecer no registo de
presenças (que só funcionava porque outro ecrã tinha inicializado o
provider antes). Os dois passaram a esperar por ele (`await ...
.future`) em vez de torcer para que já lá esteja.

### Estado

**311 testes Flutter** (+26: 16 sobre as regras das métricas, 4 sobre o
ecrã de estatísticas, 6 sobre o treino de turma) · **294 contra o
Emulator Suite** (sem alterações no servidor nesta ronda).

## "Erro interno" quando faltava preencher um campo

Reportado a testar: criar uma conta sem preencher tudo dava
`firebase internal`. Confirmei contra o emulador antes de mexer em
nada, e eram **duas** causas diferentes — mais uma terceira, do lado da
app, que fazia com que qualquer falha do servidor aparecesse assim.

### 1. Metade das funções lançava o erro de validação em cru

Dez Cloud Functions faziam `schema.parse(...)`. Quando a validação
falha, isso lança um erro da biblioteca — e uma exceção que não é
`HttpsError` chega ao cliente como **`internal` / `INTERNAL`**. Ou
seja: o Gestor esquecia-se do nome e a app dizia-lhe "erro interno",
que não diz o que fazer e sugere que a app se partiu.

As outras dezoito usavam `safeParse` e devolviam `error.message` — que
é o JSON do erro da biblioteca. O ecrã mostrava um bloco
`[{"code":"too_small","path":["name"]...}]`.

Passou a haver um sítio só (`lib/validation.ts#parseInput`) que traduz
qualquer falha de validação para uma frase em português a dizer **que
campo falta**: "Falta preencher: nome." / "Escolhe pelo menos um:
papéis (Instrutor/Gestor)." / "O email não tem um formato válido." Os
`details` levam os nomes dos campos, para a app poder marcá-los no
formulário quando isso fizer falta.

### 2. Email repetido nem chegava à validação

Criar um instrutor com um email que já existe não é um erro de
validação: é o Firebase Auth a recusar. Esse erro não estava a ser
apanhado por ninguém — outra vez `internal`. Agora dá
`already-exists` com "Já existe uma conta com este email. Usa outro, ou
procura a pessoa na lista de utilizadores." O mesmo para email
malformado, conta inexistente e demasiadas tentativas.

### 3. A app mostrava a exceção em bruto — em 67 sítios

Este é o problema de fundo, e era transversal: quase todos os ecrãs
faziam `Text('Não foi possível X: $e')`. A app pedia desculpa e a
seguir despejava `[firebase_functions/internal] INTERNAL` no ecrã.

Há agora uma função única (`userFacingError`) com uma ordem
deliberada:

1. **o que o Firebase diz, traduzido** — é onde estão os casos
   acionáveis (sem rede, sem permissão, campo em falta, email
   repetido);
2. **a mensagem do próprio erro, quando foi escrita para uma pessoa** —
   é o caso das exceções de domínio desta app, que existem
   precisamente para explicar o que aconteceu em português;
3. **a frase de quem chamou**, que descreve a ação que falhou.

O detalhe técnico não se perde: continua atrás de "Detalhe técnico" no
`ErrorState` e continua a ir para o Crashlytics. O que muda é o que a
pessoa lê primeiro.

### Os campos obrigatórios não se viam

A outra metade da pergunta. Havia validação, mas o único sinal de que
um campo era preciso aparecia **depois** de carregar em gravar — e num
formulário onde a maioria dos campos é opcional (criar utilizador tem
nove campos, dois obrigatórios), isso é descobrir a regra por
tentativa e erro.

Convenção adotada: asterisco no rótulo (`requiredLabel`) e uma linha a
explicá-lo uma vez por formulário (`RequiredFieldsHint`). Aplicada onde
o formulário MISTURA obrigatórios e opcionais — criar utilizador, criar
série, atribuir plano, criar exercício. Onde tudo é obrigatório (as
duas passwords, o login) o asterisco não acrescenta nada e não foi
posto.

O email de staff ganhou também um `helperText` a dizer o que ele é
("É por aqui que esta pessoa entra na app") — era o campo com mais
potencial de engano, porque o aluno tem um email de contacto que NÃO
serve para entrar.

### Um teste que só falhava à segunda vez

A suite do emulador passava e, corrida outra vez a seguir, falhava com
"Demasiados pedidos em pouco tempo". Não era contaminação entre testes:
os contadores do rate limiter vivem no Firestore e **sobrevivem entre
corridas** no emulador. Um `globalSetup` limpa-os antes de cada corrida
— nenhum destes testes anda a provar o limitador (esse tem os seus), e
um teste que falha à segunda vez é um teste em que ninguém confia.

Confirmado com duas corridas completas seguidas, ambas limpas.

### Estado

**313 testes Flutter** (+2: as regras da tradução de erros, incluindo
que um bloco de JSON e um `INTERNAL` NUNCA vão para o ecrã) ·
**301 contra o Emulator Suite** (+7 sobre exatamente o que foi
reportado: campo em falta, sem papéis, data malformada, email
repetido — todos a exigir código certo E mensagem legível).

Cada um destes testes falha na versão anterior do código.

## Última ronda, véspera de produção

Nesta não acrescentei nada à app. Fui procurar o que só se parte **em
produção** — as coisas que passam no emulador e falham no dia seguinte.
Encontrei três, e todas seriam visíveis logo na primeira hora.

### 1. Dois índices em falta (o emulador não os exige)

O Firestore precisa de índices compostos para queries com filtro +
ordenação. **O emulador não os exige; a produção exige.** É a categoria
de erro mais traiçoeira que há: a suite passa inteira, e em produção o
ecrã devolve "The query requires an index".

Faltavam dois, e nos dois piores sítios possíveis:

* `loadHistory (exerciseId, recordedAt DESC)` — a evolução da carga,
  que é o ecrã para onde toda a gente vai ver se está a progredir.
* `workoutSessions (finishedAt, startedAt DESC)` — a pergunta "tens um
  treino a decorrer?". Esta corre no **ecrã inicial de qualquer aluno**
  e em qualquer sítio com o botão de iniciar treino: sem o índice, a
  app abria partida para toda a gente.

Fiz a auditoria a todas as queries do projeto (cliente e servidor)
contra o `firestore.indexes.json`. As outras dezasseis estavam
cobertas. As duas novas já lá estão, e o checklist ganhou um passo para
confirmar na consola que ficaram **construídos** antes de abrir a app a
alguém — construir demora minutos e, enquanto não termina, a query
falha na mesma.

### 2. `flutter build web` publicava a app de DESENVOLVIMENTO

O comando sem `-t` compila `lib/main.dart`, que aponta para o ambiente
de development. Com a secção de hosting que ficou configurada na ronda
anterior, o deploy publicaria uma app com aspeto perfeitamente normal a
escrever na base de dados errada — e ninguém daria por isso.

Três coisas mudaram:

* o checklist passou a ter o comando certo, em destaque
  (`flutter build web --release -t lib/main_production.dart`), e o
  equivalente para Android e iOS;
* tudo o que **não** é produção mostra agora uma fita laranja no canto
  com o nome do ambiente. Se aparecer "DEVELOPMENT" no site do estúdio,
  foi publicada a build errada — passa a ver-se em vez de se descobrir
  pelos dados;
* a CI passou a compilar a build de produção. Se o caminho de produção
  partir, sabe-se no momento, não no dia do deploy.

### 3. Não havia forma de entrar no projeto novo

O checklist dizia "cria o primeiro Gestor com o script de seed apontado
ao projeto real, ou na consola". As duas coisas estão erradas: o seed
está preso ao projeto do emulador, e **a consola do Firebase não sabe
atribuir custom claims** — sem `tenantId` e `roles` no token, a conta
autentica-se e fica num estado que nenhum ecrã trata.

Ou seja: seguindo o checklist à letra, amanhã de manhã ninguém
conseguia entrar na app acabada de publicar.

Há agora um script para isso
(`firebase/scripts/create-first-manager.mjs`), que cria o documento do
tenant (com o fuso horário, de que a geração de aulas depende), a conta
de Auth, as claims e o documento de staff. Sem `--yes` diz o que ia
fazer e não faz nada — a rede contra correr no projeto errado. Testado
contra o emulador, incluindo correr duas vezes seguidas.

### Reportado a testar em produção (24/08/2026)

**A lista de alunos vinha ordenada por nome.** O número de sócio é a
identidade que o estúdio usa ao balcão — é por ele que se procura
alguém — e a ordem alfabética escondia-a. Passou a ordenar por número
(`compareMembersByNumber`, em `firebase_member_repository.dart`),
comparando-o como número e não como texto: sem isso, "1000" vinha antes
de "999" assim que o estúdio passasse dos três dígitos. Quem não tem
número vai para o fim, por nome, em vez de se misturar.

O separador **"Todos"** mantém a lista fundida e alfabética — era uma
decisão deliberada da Fase 10 (um Gestor que procura alguém não sabe de
cor se é aluno ou instrutor) e não havia motivo para a desfazer. A
ordem por número manda no separador "Alunos", onde só há alunos.

**O aviso de conflito de horário aparecia sempre.** O relato foi "diz
que o instrutor já tem aulas àquela hora, e não tem". Tinha: os dados
de produção mostravam uma série às segundas às 18:00 para esse
instrutor — e o formulário de criação **abre precisamente em
segunda-feira às 18:00**. O aviso disparava mal se escolhesse o
instrutor, a comparar com um horário que ninguém tinha indicado ainda.

Não era um falso positivo, era um aviso no momento errado — o que dá no
mesmo, porque um aviso que aparece sempre deixa de ser lido. Duas
mudanças:

* O aviso só aparece depois de o horário ser **uma escolha** (dia,
  data, hora, duração ou o próprio "só esta data / semanal" — qualquer
  um conta).
* Ao gravar, o conflito é **reavaliado e passa a pedir confirmação**
  em vez de criar em silêncio. Isto responde à segunda metade do
  relato, "e depois cria": o aviso podia nunca ter sido visto — horário
  nos valores por omissão, ou fora do ecrã — e a aula sobreposta nascia
  sem ninguém decidir nada.

A deteção passou a viver numa função pura (`findScheduleConflict`)
usada pelos dois caminhos; duplicá-la era a forma mais certa de os dois
deixarem de concordar. Na confirmação, as listas são lidas com
`.future` e não com `valueOrNull`: enquanto o aviso está escondido
ninguém as observa, e `valueOrNull` devolvia `null` — a verificação
diria "sem conflito" exatamente quando era mais precisa.

### Todos os ecrãs, em todos os telemóveis

Os 859 testes de widget deste projeto corriam todos no ecrã por omissão
do `flutter_test`: **800×600, sem recortes, texto à escala 1.0**. Não é
nenhum telemóvel. É mais largo do que qualquer iPhone e mais baixo do
que todos — exatamente o tamanho em que um `Row` demasiado cheio cabe e
uma `Column` demasiado alta não estoura.

`test/presentation/layout_matrix_test.dart` põe **os 56 ecrãs da app em
9 tamanhos** (522 casos, 20 segundos) e deixa o framework acusar: um
`RenderFlex overflowed` é um `FlutterError`, e um `FlutterError` faz o
teste falhar sozinho. Não foi preciso escrever asserções de layout — só
faltava pôr os ecrãs onde isso acontece.

Isto não é estética. O Flutter desenha as barras amarelas e pretas por
cima do conteúdo, e **o que ficou de fora deixa de ser tocável**. Um
botão "Confirmar" empurrado para lá da margem é uma funcionalidade que
não existe naquele telefone.

#### Os nove tamanhos, e porque são estes

`test/support/device_matrix.dart`. A lista é curta de propósito — cada
entrada multiplica-se por todos os ecrãs, e uma matriz lenta é uma
matriz que se deixa de correr. Cada uma está lá por representar um canto
diferente do espaço:

| | Porquê |
|---|---|
| iPhone SE · 375×667 | o mais estreito que a App Store ainda aceita |
| Android pequeno · 360×640 | mais estreito do que qualquer iPhone atual |
| iPhone 15 · 393×852 | entalhe + gestos: 93 pontos desaparecem antes do conteúdo |
| Pixel 7 · 412×915 | Android moderno, furo na câmara e barra de gestos |
| **iPhone deitado · 852×393** | a app **não** tranca a orientação |
| iPad · 744×1133 | é submetida como universal |
| **Android · texto 1.3×** | o "Enorme" do Android |
| **iPhone SE · texto 2.0×** | acessibilidade a sério no iOS |
| **iPhone SE · teclado aberto** | 291 dos 667 pontos desaparecem |

Os quatro a negrito são os que encontraram quase tudo, e são os quatro
que nunca se testam à mão: ninguém roda o telemóvel, ninguém muda o
tamanho de letra, e no emulador escreve-se com o teclado do computador —
o teclado do telefone nunca chega a aparecer.

A orientação não foi uma escolha minha: o `Info.plist` declara landscape
nas duas direções e o Android não declara `screenOrientation` nenhum.
A app anuncia que roda, portanto tem de rodar — e quem faz a revisão na
App Store roda o telefone.

#### A armadilha que este teste tem de evitar

**Um ecrã de erro cabe sempre.** Se o fixture não servir, o provider
falha, o ecrã mostra três linhas de [ErrorState], e o teste passa a
verde sem ter medido nada — a pior espécie de teste, porque dá confiança
em vez de a medir.

Cada caso verifica por isso duas coisas além do estouro: que não há
`ErrorState` no ecrã, e que há texto desenhado. Apanhou-me logo três
vezes — `RetentionScreen` precisava de uma Cloud Function que o fixture
não tinha, e `ManagerScreen` e `MemberHomeScreen` são **corpos de
separador**, que rebentam com "No Material widget found" se forem postos
como `home:` sem o `Scaffold` do `HomeScreen` à volta. Sem estas
asserções teria contado 24 falsos verdes.

O fixture também é deliberadamente **comprido**: "Maria Madalena
Gonçalves", "Treino Funcional em Grupo", "07:00 – 13:00, 16:00 – 21:30".
Um fixture de "Ana" e "Plano A" cabe em qualquer ecrã e não prova nada.

#### 51 falhas, e o que estava por trás

Do primeiro arranque saíram 51 falhas em 328 casos. Dezanove eram do meu
andaime; **32 eram reais**. Por ordem de gravidade:

**🔴 A vitrina estourava em todos os tamanhos, incluindo iPad.** A linha
do horário era um `Row` com `spaceBetween` e dois `Text` sem
constrangimento nenhum. Com um horário real de um estúdio com pausa de
almoço — "Segunda a sexta" ao lado de "07:00 – 13:00, 16:00 – 21:30" —
passava 226 px num iPhone SE e 141 num iPad. É o **primeiro ecrã que
qualquer pessoa vê**, incluindo a revisão da App Store, e só não se via
ainda porque a informação pública em produção está por preencher.

**🔴 Todos os dropdowns da app.** `isExpanded` não era usado em lado
nenhum, e sem ele o `DropdownButton` põe o item selecionado num `Row`
que não constrange — um nome como "Bernardo Albuquerque Teixeira"
passava 595 px a 2.0×. São 8 dropdowns em 5 ficheiros; a matriz só
apanhou um ecrã porque só lá o fixture pôs nomes reais. Corrigidos
todos.

**🔴 O ecrã da password temporária, com o teclado aberto.** É um
formulário de password: o teclado está sempre aberto enquanto alguém o
usa, e tira 291 dos 667 pontos de um iPhone SE. Faltavam 52 px, e o que
ficava de fora era o botão de confirmar. **É o primeiro ecrã de qualquer
sócio novo** — estar preso ali é estar preso fora da app.

**🔴 O navegador de período, escrito à mão quatro vezes.** Dois
`IconButton` de 96 px fixos e um `Text` sem constrangimento. A 1.3×
faltavam 54 px e a 2.0× faltavam 207 — e o que saía do ecrã eram **as
setas de mudar de semana**, deixando o ecrã preso num período só sem
nada a indicar que havia mais. Estava em `FreeTrainingScreen`,
`InstructorCalendarScreen` e `ManageFreeTrainingScreen`; extraí
`PeriodNavigator`, e a matriz apontou-me logo a **quarta cópia**, por
meses, em `ManagePaymentsScreen`. É o argumento inteiro para extrair: a
quinta vai nascer certa.

**🟠 Cartões de atalho com razão de aspeto fixa.** O `GridView.count` do
início do Aluno usava `childAspectRatio: 1.9` — uma razão fixa deriva a
**altura da largura**, e a altura de que aqueles cartões precisam vem do
tamanho de letra, que é do utilizador. Estourava já com texto normal num
iPhone SE. Passou a duas linhas de dois com altura natural.

**🟠 Estados vazios e ecrãs de informação sem rolamento.** As categorias
de exercícios (o botão "Criar uma de raiz" fora do ecrã: o ecrã que
existe para resolver o vazio não tinha como o resolver) e a conta
bloqueada (a explicação de como desbloquear, cortada).

**🟠 Linhas que não podiam caber, e passaram a adaptar-se.** "Pago com
atraso" ao lado de um nome a 2.0× não cabe em telemóvel nenhum —
espremer não resolve. Acima de ~1.3× o estado desce para baixo do nº de
sócio. O mesmo para a barra do treino de turma (as ações descem para uma
fila que desliza) e para a ficha do instrutor (o avatar e a
identificação deixam de partilhar a linha).

#### Cobrir os 15 ecrãs que faltavam encontrou mais três

A primeira versão da matriz cobria 41 dos 56 ecrãs — os que faltavam
precisavam de entidades que o fixture não construía. Construí-as, e a
matriz respondeu logo:

**🔴 O detalhe da avaliação física estourava em TODOS os telemóveis**,
incluindo um Pixel 7, já com o tamanho de letra normal. É o mesmo
`Row(spaceBetween)` com dois `Text` livres da vitrina, agora com
etiquetas como "Perímetro abdominal". Depois de corrigido, procurei a
forma em toda a app: havia uma terceira ocorrência em
`MemberStatsScreen` que a matriz aprova hoje — dois textos curtos a
10 px — mas que vem de um formatador de datas. Ficou constrangida
também; custa duas linhas e fecha a porta.

Aqui os dois lados cedem de formas diferentes, e a diferença importa: a
etiqueta quebra em linhas, e o valor **quebra mas nunca é cortado**. Um
peso com o fim truncado não é informação incompleta — é outro número, e
num ecrã de avaliação física isso lê-se e acredita-se.

**🟠 A ficha do instrutor, a 2.0×.** O botão de foto é um `Wrap`, mas
dentro de uma `Column` sem largura recebe espaço infinito e por isso
nunca chega a quebrar.

**E o `HomeScreen` deixou de estar de fora.** Estava excluído porque
chamava `FirebaseMessaging.onMessage` no `initState` sem guarda, e isso
rebenta sem Firebase inicializado. Não era só um problema de teste: o
FCM pode não existir onde a app corre — um Android sem Google Play
Services, um browser com notificações bloqueadas, ou (hoje) a web sem
VAPID key. Sem a guarda, o que morria era a **casca da app** — a barra
de separadores, tudo — por causa de uma funcionalidade acessória. O
registo do token já falhava em silêncio de propósito; este era o único
sítio que não. Entra agora na matriz uma vez por perfil, porque a barra
é diferente em cada um e é ela que come altura ao conteúdo.

#### O que isto NÃO prova

* **Não é um teste visual.** Mede se o layout cabe, não se está bonito.
  Um ecrã pode caber e estar horrível, e a matriz dá verde.
* **Corre no computador, não no telefone.** As métricas de tipo de letra
  do iOS (SF Pro) e do Android (Roboto) não são iguais às da máquina de
  testes. Uma linha que cabe por 2 px aqui pode cortar no dispositivo.
* **Cobre os 56 ecrãs, mas um ecrã tem mais do que um estado.** A
  matriz vê cada um numa configuração — a do fixture. Um diálogo aberto,
  uma lista vazia, um erro de validação por baixo de um campo: nada
  disso é medido, e qualquer um deles muda a altura.
* **Nada disto substitui abrir a app num telemóvel.** Substitui é ter de
  abrir 56 ecrãs em 9 telemóveis para descobrir o que um teste encontra
  em 20 segundos.

```bash
flutter test test/presentation/layout_matrix_test.dart
```

### Botões que não diziam nada, e avisos a mais

Reportado assim: *"não aparece nada a indicar que está em loading quando
tocamos num botão, o que até permite tocar no botão mais que uma vez e
pode criar problemas"*. Mais o aspeto: *"é estranho as mensagens de
confirmação aparecerem como pop-ups de texto"*.

#### A primeira medição estava errada

Contei 23 ficheiros sem proteção. Procurava `_busy|_submitting|_saving`
e o `send_notification_screen` usa `_sending`. Refiz: os botões
principais — marcar aula, login, atribuir plano — **já estavam
protegidos**, e a maioria do resto passa por diálogos, que fecham ao
primeiro toque.

Mas ficou um que prova o ponto por inteiro. `start_workout_button`
chamava `startSession` sem guarda nenhuma: **dois toques criavam dois
treinos** para a mesma pessoa, e o segundo ficava aberto para sempre
porque o ecrã só mostra um. E "Terminar" no treino ativo fazia dois
`pop`, levando o ecrã de baixo com ele.

#### A guarda vive num sítio só

A guarda são três linhas — um `bool`, um `setState` à entrada e outro no
`finally`. Escrevê-la vinte vezes dá vinte oportunidades de esquecer o
`finally`, e esquecê-lo deixa o botão **morto para sempre**, com o ecrã
a parecer bloqueado sem dizer porquê. Há um teste só para esse caso.

`AsyncActionButton` também fecha a janela entre o toque e o `setState`:
um toque duplo rápido cabe num fotograma, por isso há uma segunda guarda
dentro do próprio handler.

#### A queixa dos pop-ups levou a uma resposta melhor do que mudar o CSS

Contei **134 SnackBars: 87 erros, 47 confirmações.**

Ia dar-lhes melhor aspeto. Mas a resposta não é embelezar o pop-up — é
**não o mostrar**. Uma confirmação só é precisa quando o resultado *não
se vê*; anunciar "Guardado" por cima de um ecrã que já mostra o que foi
guardado é ruído, e ruído ensina a ignorar os avisos que importam.

Por isso a confirmação foi para **dentro do botão**: a ação acaba, o
ícone vira um visto durante um segundo e meio, e desaparece. Fica onde o
dedo tocou.

Os que ficam deixaram de parecer uma faixa do sistema colada por cima da
app: flutuam, com cantos e o mesmo contorno dos cartões.

#### E uma correção: exagerei no diagnóstico

Disse "59 confirmações, muitas redundantes". Ao lê-las uma a uma, a
maioria carrega informação que **não** está no ecrã — contagens ("3 de 5
atribuídos"), avisos ("a pessoa vê a mudança no próximo login"), estados
invisíveis ("a foto aparece dentro de instantes"). Redundantes a sério
eram poucas, e essas saíram.

O que encontrei de pior foi outra coisa: **validação mostrada como
pop-up**. Dizia o que estava mal e desaparecia em quatro segundos —
enquanto a pessoa ainda olhava para o formulário. As de formulário
passaram para debaixo do campo errado, e somem quando ela começa a
corrigir. "Nome e email válido são obrigatórios" virou um erro em cada
campo, porque uma frase para dois campos obriga a adivinhar qual deles
é.

#### O que fica por fazer

42 confirmações continuam lá, e a maior parte com razão. Restam umas
sete "ação recusada" em diálogos e seletores — onde um toast é
defensável, por não haver campo a que prender a mensagem. Não as mexi
sem evidência de que estão erradas.

### Separadores que eram verbos

Na mesma conversa: *"será que faz sentido mudar o botão de marcar para
aulas? Porque há um botão para treino livre que também é uma marcação"*.

O aluno via **Início · Marcar · Livre · Marcações**. Três problemas de
uma vez:

* **"Marcar" não dizia o quê** — e o treino livre também é marcar.
* **"Marcar" ficava a três letras de "Marcações"** — fazer e consultar,
  com nomes quase iguais, a dois separadores de distância.
* Pior nos títulos: o ecrã chamava-se **"Marcar TREINO"** e era o das
  aulas, ao lado de **"TREINO livre"**. A mesma palavra para as duas
  coisas que era preciso distinguir.

Uma barra de navegação é um conjunto de **lugares**, não de ações.
Passou a **Início · Aulas · Treino livre · Marcações**: cada separador
diz o que lá está, e marcar é o que se faz nos dois primeiros.

Os ícones também estavam trocados — o haltere, símbolo de treinar
sozinho, estava nas aulas de grupo, e uma figura de meditação no treino
livre.

O atalho no ecrã inicial passou a dizer "Aulas" também: leva ao mesmo
sítio, e antes um dizia "Marcar treino" e o outro "Marcar".

### A janela de marcação, e o que o aluno ainda pode marcar

Duas queixas, a mesma raiz: o aluno não sabia o que estava a olhar.

#### Dois meses de horário para uma decisão sobre esta semana

As séries geram ocorrências com **8 semanas** de antecedência, para o
estúdio poder planear. O aluno via-as todas — o ecrã trazia duas semanas
de início e tinha um rodapé "ver mais" que abria as oito.

Não é só ruído. Marcar com dois meses de antecedência **ocupa uma vaga
que mais ninguém pode usar**, para uma aula de que quem marcou já não se
vai lembrar. Um horizonte curto é o que mantém as vagas a circular.

`bookingHorizonDays` vive em `config/bookingPolicy`, ao lado de
`minBookingNoticeMinutes` — são as duas pontas da mesma janela: não
marcar demasiado em cima da hora, nem demasiado longe. Editável em
Gestão › Definições. `0` = sem limite, que é o valor por omissão, para
não mudar o comportamento de um estúdio que já use a app sem saber desta
definição.

Aplica-se às **aulas e ao treino livre**, e é validado nas **duas
pontas**: o ecrã esconde o que está fora do horizonte, e o servidor
recusa na mesma. Esconder não é impedir — um pedido direto à função
continuava a passar, e é por isso que o teste está do lado do servidor.

Detalhes que só aparecem a fazer: o rodapé "ver mais semanas" desaparece
quando há horizonte (levaria a uma lista que não cresce), e a seta de
semana seguinte do treino livre desliga-se quando a semana a seguir já
não tem nada marcável.

#### "Quantas aulas ainda posso marcar?"

O limite semanal existia e era respeitado, mas só se via **dentro do
cartão de cada aula**, em letra pequena, e só nas aulas daquele serviço.
Para saber quantas sessões lhe sobravam, o aluno tinha de rolar até
encontrar uma aula do serviço certo.

E se o plano tivesse dois serviços com limites diferentes — o caso normal
num pacote — não havia sítio nenhum onde os dois números aparecessem
juntos.

`WeeklyAllowance` põe-nos no topo do ecrã de marcar, antes do horário.
Três decisões:

* **Diz o que SOBRA, não o que foi gasto.** "Restam 2" responde à
  pergunta; "1/3 usadas" obriga a fazer a conta, e a conta é feita com o
  telemóvel na mão à porta do ginásio.
* **Só os serviços com limite.** Uma linha a dizer "ilimitado" por cada
  serviço sem limite empurra para baixo a única que tem informação.
* **O cartão inteiro desaparece** quando não há limite nenhum. Um
  "Esta semana" vazio lê-se como um erro de carregamento.

Só a semana corrente, de propósito: um resumo que tentasse cobrir as
seguintes teria de escolher qual mostrar, e a resposta certa muda
conforme a aula em que se está a pensar — que é o que a linha dentro de
cada cartão já resolve.

### Um plano por membro, e a regra que faltava

Reportado assim: *"eu atribuí um plano treino livre e ele passou para
outro ecrã onde tinha que atribuir planos avulsos… não percebo o que é
isto sequer"*. Disse duas vezes que não havia navegação nenhuma. **Estava
errado das duas.**

#### O que acontecia mesmo

O ecrã não fechava depois de guardar. E como o grupo exclusivo passava a
estar ocupado, a secção que a pessoa tinha acabado de usar **colapsava**
numa linha cinzenta — restando a secção seguinte, "Planos avulsos", com
um botão *Guardar* por baixo. A parte usada desaparecia e outra
tomava-lhe o lugar. Em tudo o que importa, **era** outro ecrã.

#### Três camadas de mecanismo à superfície

`Service.exclusiveGroup` era uma etiqueta de **texto livre** que o Gestor
tinha de escrever igual em dois serviços para os declarar alternativas.
A ajuda do campo dizia: *"Serviços com o MESMO grupo tornam-se mutuamente
exclusivos (UC26) — um membro nunca pode ter subscriptions ativas a dois
deles"*. `UC26` é um documento de requisitos; `subscriptions` é uma
coleção da base de dados. Escrever `Acompanhamento` num e
`acompanhamento` noutro fazia-os não se ligarem, em silêncio.

O grupo de um **plano** derivava dos serviços que ele embrulhava. Por
isso "Hyrox Team" aparecia numa escolha única de acompanhamento — porque
incluía "Treino livre" lá dentro. Nada no ecrã dizia isso.

E "avulso" era um **falso amigo**: a app usa "sessão avulsa" noutro ecrã
com o sentido normal (uma aula pontual fora da série semanal). Quem
acabou de ver o primeiro lê o segundo como o conceito irmão.

#### A decisão: um plano ativo por membro

Não foi mudar o nome às coisas — foi tirar a pergunta.

Sem dois planos ao mesmo tempo, **as duas regras de conflito deixam de
ter objeto**: não há dois planos a dar o mesmo serviço, nem a dar
serviços alternativos. E some um problema que ninguém tinha visto:
`resolveEligibility` resolvia o limite semanal apanhando a **primeira**
subscrição que desse aquele serviço (`.find()`), por isso dois planos com
limites diferentes davam o limite que a base de dados calhasse devolver
primeiro. Com um plano só não há nada para escolher.

Atribuir um plano a quem já tem um **substitui** o anterior, numa escrita
atómica, e devolve o nome do que saiu para o ecrã o poder dizer. Recusar
obrigaria a dois passos para o que é um só gesto: mudar de plano.

O ecrã passou a ser o que sempre quis ser — uma lista de planos, escolhe
um, com o atual assinalado e o botão a dizer "Mudar de plano". E fecha
quando o trabalho acaba.

#### E a regra que nunca tinha sido escrita

Procurei em toda a app: **não havia verificação nenhuma de horários
sobrepostos**. Um aluno podia marcar duas aulas exatamente à mesma hora.

A app impedia o que não devia e não impedia o que devia.

`lib/overlap.ts` recusa marcar o que se cruze com outra marcação do
próprio — aulas e treino livre, pelo mesmo caminho. Não assume durações:
lê a sessão de cada candidata (que é o documento-pai da marcação) para
saber quando acaba. A janela de busca alarga 6 horas para trás, senão
marcar às 10h00 não via a aula das 09h30 que só acaba às 10h30. As
fronteiras são exclusivas — duas aulas seguidas, uma a acabar e outra a
começar à mesma hora, continuam a poder ser marcadas.

É a única regra de combinação que a app impõe, e a única que não precisa
de explicação nenhuma: ninguém está em dois sítios ao mesmo tempo.

#### O seed acompanhou

Os planos deixaram de ser peças para combinar e passaram a **pacotes
completos** — quem quer sala e aulas compra o plano que traz as duas.
É assim que um ginásio vende de qualquer forma: três ou quatro pacotes,
não combinações arbitrárias. A lista cobre de propósito um plano sem
limites, um com limite semanal, um com dois limites diferentes e um
ilimitado, para se ver o efeito de cada um sem inventar dados.

### A chamada: de "está algures" a "está à frente"

A presença já existia e funcionava. O que não existia era forma de
**ver** — nem de lá chegar sem saber o caminho.

#### Três problemas, e o pior era o mais simples

**"Sessões hoje: 2" era um número morto.** O cartão que diz que há
trabalho não levava ao trabalho. Marcar a chamada da aula de hoje eram
três toques — "As minhas aulas" → escolher o dia → escolher a aula — e
a ação mais frequente que um instrutor faz nesta app estava mais longe
do que "Biblioteca de exercícios". O painel do Gestor era pior: quatro
toques, por Aulas/Horários → série → ocorrência.

**Não dava para saber se uma aula já tinha sido marcada sem a abrir.** O
cartão de cada aula mostrava "8/12 inscritos" — isso é lotação, não
presença. Um instrutor que deu quatro aulas e se esqueceu de uma tinha
de abrir as quatro para descobrir qual.

**Lá dentro, "por marcar" era invisível.** Dois `IconButton` no fim da
linha, um visto e uma cruz, sempre os dois visíveis e ambos cinzentos
enquanto não houvesse registo. Numa turma de doze eram vinte e quatro
ícones pequenos para ler, e "por marcar" era indistinguível de "marcado"
à distância a que se olha para um telemóvel enquanto se dá aula.

#### O que mudou

**As aulas de hoje passaram a ser o primeiro ecrã** — do Instrutor (as
dele) e do Gestor (as do estúdio), pelo mesmo widget, `TodayClasses`.
Cada uma com o estado da chamada e um toque para a fazer.

A janela é a **semana ISO**, não "daqui para a frente", e a diferença é
o ponto todo: as aulas que precisam de chamada são precisamente as que
**já aconteceram**. Com `upcomingWeekOccurrencesProvider` — que começa em
`DateTime.now()` — a aula das 9h desaparecia da lista às 9h01, no minuto
exato em que passava a interessar. Há um teste só para isso.

**O crachá diz o estado sem abrir a aula:** "3 por marcar" ou "Chamada
feita". Não aparece antes de a aula começar — nessa altura ter toda a
gente por marcar é o estado normal, e um aviso aceso desde a manhã para
a aula da noite ensina a ignorar os avisos.

**A linha do inscrito passou o estado para a cabeça.** Os estados formam
uma coluna que se lê de uma vez — ○ ✓ ✓ ○ ✓ — e é isso que torna "falta
alguém?" respondível sem ler nomes. **Tocar na linha marca presença**,
porque é o que acontece nove em cada dez vezes; tocar outra vez limpa o
registo, para que um toque errado se desfaça pelo mesmo gesto que o
causou. A falta, que é a exceção, está no menu.

Limpar exigiu um `clearAttendance` novo no repositório, e a distinção
importa: uma falta é uma **afirmação** sobre o aluno e entra nas contas
de retenção; "por marcar" é a ausência de afirmação. Sem isto, desfazer
um engano obrigava a trocá-lo por outro — marcar falta a alguém que
veio. As Rules não mudaram: `allow write` já cobria `delete`.

**Os números apareceram.** O ecrã da aula já tinha o botão certo
("marcar os restantes como presentes") e uma frase quando não havia
restantes. Não tinha a contagem — quantos vieram, quantos faltaram,
quantos faltam ver. E a contagem fica mesmo com a chamada completa: "12
presentes, 1 falta" é o registo do que aconteceu, não um aviso que se
apaga quando o trabalho acaba.

#### Cor não é informação

O estado vai **escrito** no subtítulo de cada linha, não só na cor do
ícone. Verde e vermelho são exatamente os dois tons que uma pessoa
daltónica não separa, e são exatamente os dois que este ecrã usaria.
Há um teste que o fixa.

#### O que isto custa

Uma leitura da subcoleção `attendance` por aula mostrada. É por isso que
o crachá só aparece depois de a aula começar e que a lista é só de hoje:
o calendário mostra um dia de cada vez e o painel mostra as de hoje, por
isso são poucas aulas em ambos os casos. Uma lista semanal com crachás
em todas seria vinte leituras para desenhar vinte etiquetas.

### Testes de carga — um ginásio cheio, e o cronómetro ligado

Tudo o que tinha sido medido até aqui foi medido com o seed de
desenvolvimento: meia dúzia de membros, duas aulas, uma série. Nesse
tamanho tudo é rápido, e a pergunta que interessa ficava por responder.

`firebase/scripts/load-test.mjs` constrói o estúdio que o NXT vai ser —
**100 sócios, 20 séries semanais, 8 semanas de história** (160 aulas
passadas, 1528 marcações, 1528 presenças) — e cronometra o que dói. Corre
só contra o emulador, e recusa-se a correr contra outra coisa.

#### O que aguentou sem se notar

| | |
|---|---|
| Cron diário (gerar 8 semanas de 20 séries) | **655 ms** — 160 aulas |
| Painel de retenção sobre 160 aulas e 1528 presenças | **252 ms** |
| Lembretes, uma passagem | **41 ms** |
| Lista de membros (Gestor) | **26 ms** |
| Contagem de membros ativos (`count()`) | **10 ms** |
| Aulas das próximas 2 semanas (Aluno) | **12 ms** |
| As minhas marcações (Aluno) | **10 ms** |

O painel de retenção é o caso mais interessante: a docstring chama-lhe "a
função mais cara do projeto" e, à escala real deste estúdio, resolve-se
em **um quarto de segundo**. A preocupação era legítima e a dimensão
não é a que se temia — fica medido, para não se voltar a otimizar às
cegas.

#### 🔴 O que não aguentou: muita gente a marcar a MESMA aula

Trinta marcações simultâneas numa aula de doze lugares: **306 segundos**
e só oito aceites. Quatro lugares vazios e quatro pessoas recusadas sem
ser por falta de vaga.

Antes de concluir seja o que for, era preciso separar o que é a app do
que é o emulador. A mesma contenção, medida **diretamente no Firestore**
sem passar pelas funções:

| Em simultâneo | Firestore só | Pelo emulador de funções |
|---|---|---|
| 5 | 3,6 s — todas ✓ | 7,2 s — 5 aceites ✓ |
| 10 | 7,7 s — todas ✓ | **306 s** — 8 aceites |
| 30 | 19,4 s — **28 de 30** | **306 s** — 8 aceites |

O tecto de 306 segundos, **idêntico** para 10 e para 30, não é carga: é
um limite a ser atingido. O emulador de funções serializa invocações e
tem um teto de concorrência. Isso é ferramenta, não produto, e não vale
como aviso sobre produção.

O que **é** real é a coluna do meio. Marcações da mesma aula disputam o
mesmo documento — é lá que vive o `activeBookingCount` — e com trinta em
simultâneo duas falharam por **esgotarem as tentativas da transação**,
não por falta de vaga.

E a perda é **intermitente**: repeti a medição e à segunda passaram as
trinta. É isso que a torna traiçoeira — não aparece num teste, aparece na
manhã em que o estúdio abre as marcações às 9h00 e toda a gente toca ao
mesmo tempo. Ao aluno diz "não foi possível marcar" numa aula com
lugares, e ele não tenta outra vez.

#### Quantas tentativas, medido em vez de escolhido

A primeira correção foi `maxAttempts: 15` — um número escolhido por ser
grande. `firebase/scripts/contention-probe.mjs` existe para não deixar
esse número por justificar: replica a transação da marcação **direto no
Firestore**, varia só o `maxAttempts`, e repete cada valor várias vezes,
porque a perda é intermitente e uma ronda só não decide nada.

Só conta como perda quem foi recusado por **esgotar tentativas**. Quem
chega depois de a aula encher é recusado por **capacidade**, que é a
resposta certa e imediata — misturar as duas era medir o sucesso do
teste, não o da app.

Trinta em simultâneo, doze lugares, três rondas cada:

| `maxAttempts` | Rondas limpas | Tempo | Pior ronda |
|---|---|---|---|
| 5 (por omissão) | 2 de 3 | 12,8–20,8 s | **3 aceites, 27 perdidos** |
| 10 | 3 de 3 | **7,6–12,5 s** | — |
| 15 | 3 de 3 | 12,3–18,4 s | — |

Duas coisas que eu não sabia antes de medir. A primeira: o valor por
omissão não falha "às vezes uma ou duas" — na ronda em que falha, colapsa
e deixa **nove lugares vazios**. A segunda: quinze tentativas é *pior* do
que dez. Mais tentativas significa mais transações a disputar o mesmo
documento ao mesmo tempo, e a disputa alimenta-se a si própria.

Ficou em **`maxAttempts: 10`**, na marcação e no cancelamento — nove
rondas seguidas sem perder ninguém, e o mais rápido dos três.

#### E uma conclusão minha que estava errada

Na mesma ronda havia um teste a expirar aos 60 s na suite completa
(`extra-session-usage.test.ts`) e passando sozinho em 1,4 s. Baixei o
`maxAttempts`, a suite ficou verde, e escrevi que era isso. **Não era.**
Falhou outra vez na corrida seguinte.

O que me levou ao erro foi a plausibilidade: mais tentativas seguram
transações mais tempo, o emulador serializa, a história fechava. E uma
corrida verde a seguir a uma mudança é a evidência mais fácil de aceitar
que existe — pela mesma razão que é a mais fraca.

A causa verdadeira era outra e independente: 32 ficheiros de teste
lançados em paralelo contra **um** emulador de funções, que serializa
invocações. Está medida e corrigida em
`firebase/tests/vitest.config.ts` — a suite passou a correr com 4
workers em vez de 16, ficou estável em seis corridas seguidas, e ainda
por cima mais rápida.

Fica escrito porque o quase-erro é maior do que o erro: com uma corrida
verde eu tinha dado o problema por resolvido e publicado com ele lá
dentro.

O custo é latência para quem calha ficar no fim da fila, e é limitado por
desenho: o número de transações a disputar de facto o documento nunca
passa muito da lotação.

O custo é latência para quem calha ficar no fim da fila, e é um custo
limitado por desenho: quem chega depois de a aula encher é recusado por
**capacidade**, o que é uma resposta imediata e não uma repetição. O
número de transações a disputar de facto o documento nunca passa muito da
lotação.

Isto não resolve contenção infinita — nada resolve, num contador exato
dentro de um documento. Resolve a ordem de grandeza deste estúdio, que é
a que interessa.

#### E quando mesmo assim falhar, o que o aluno lê

Dez tentativas reduzem a contenção; não a abolem. Num contador exato
dentro de um documento nada abole — por isso interessa o que acontece na
vez em que falha.

Falhava com a mensagem genérica de erro do Firebase: *"Ocorreu um erro.
Tenta novamente."* Diz a coisa errada duas vezes. Primeiro porque parece
uma avaria da app, quando na verdade a aula **tem lugar** e a marcação
só não conseguiu passar à frente dos outros. Depois porque não diz o
único facto que faria a pessoa tentar outra vez.

`isContentionError()` distingue as duas causas — `ABORTED` (10) e
`DEADLINE_EXCEEDED` (4), por código numérico, por código em texto e, em
último recurso, pela mensagem, porque o SDK não é consistente em qual
deles traz. `createBooking` converte-as num `aborted` com texto próprio:

> Está muita gente a marcar esta aula ao mesmo tempo. Tenta outra vez —
> ainda pode haver lugar.

"Ainda pode haver lugar" é a parte que interessa: é a diferença entre
alguém tentar outra vez e alguém fechar a app. E é uma afirmação
verdadeira — se não houvesse, a recusa teria vindo por capacidade.

Coberto por `contention.test.ts` (5 testes), que fixa sobretudo o que
**não** deve ser tratado como contenção: uma aula cheia e uma recusa de
elegibilidade têm de continuar a dizer o que são.

#### E uma asserção minha que estava errada

O teste de carga marcava como incoerente qualquer corrida em que o número
de aceites não fosse igual à lotação. Com cinco pessoas a disputar doze
lugares, cinco aceites é o resultado **correto** — e o teste chamava-lhe
falha. Passou a comparar com o menor entre quem tentou e quantos lugares
há.

Vale a pena o registo: um teste de carga que grita a toda a hora é um
teste que se aprende a ignorar, e foi por sorte que dei com este antes de
o usar para decidir alguma coisa.

#### Os números são do emulador

Corre num processo só, é mais lento em latência do que a produção e **não
modela a rede**. Servem para comparar operações entre si e apanhar o que
cresce mal — não para prever o tempo que um telemóvel vai sentir.

Para responder à pergunta seguinte sem reescrever nada:

```bash
node firebase/scripts/load-test.mjs --membros=500 --series=40 --concorrentes=20
```

E para voltar a pôr em causa o `maxAttempts` — com o emulador do
Firestore a correr, sem precisar de seed nenhum:

```bash
node firebase/scripts/contention-probe.mjs 30 5,10,15 3
```

### Varredura de funcionalidades, e a app a correr

Duas varreduras seguidas: uma à lógica de negócio, outra a usar a app a
sério contra o emulador, com os três perfis.

#### 🔴 Mudar a hora de uma aula partia o limite semanal do plano

Editar uma aula era uma escrita direta do cliente que só tocava no
documento da aula. Parecia inofensivo — é um documento e uma data.

Mas cada marcação guarda uma **cópia** da `startAt` e o `period`, a
semana ISO em que foi contada, e o limite do plano vive num documento
`usage/{membro}_{serviço}_{semana}`. Mover uma aula de uma semana para
outra deixava a utilização contada na semana antiga **e a semana de
destino outra vez livre**.

O custo não era um número errado num ecrã. Com um plano de 1x por
semana, o aluno passava a ter **duas aulas** na semana para onde a aula
foi movida — o limite deixava de existir, e tudo continuava a parecer
certo.

Passou por `updateOccurrenceSchedule`, que numa transação atualiza a
aula, a data copiada em cada marcação ativa e move a utilização entre
semanas. **E as Rules deixaram de aceitar a mudança de `startAt` por
escrita direta**, mesmo do Gestor — sem isso o caminho partido
continuava a existir ao lado do novo, que é como estes bugs voltam.

Não recusa quem fique acima do limite na semana nova: é o estúdio a
mudar o horário, não o membro a marcar. Recusar deixaria o Gestor sem
forma de corrigir uma hora errada porque um aluno tem a semana cheia.

#### 🔴 Séries de treino que desapareciam

`logSet` acrescenta ao array com `arrayUnion`; `updateSet`, `deleteSet` e
`undoLastSet` liam o array inteiro, mudavam-no em memória e
reescreviam-no. Misturar as duas coisas é uma corrida: uma série
registada entre a LEITURA e a ESCRITA de um "desfazer" desaparecia,
porque a reescrita punha lá uma versão anterior a ela existir. Nada
falhava, nada avisava.

Parecia improvável enquanto só o aluno registava do seu telemóvel. A
aula de grupo mudou isso — o instrutor regista as séries de toda a gente
do dispositivo dele, e o aluno pode estar a registar no seu. Dois
escritores no mesmo array.

As três passaram a correr dentro de uma transação. Varri o resto da
camada de infraestrutura à procura do mesmo padrão: não há mais nenhum.

#### 🔴 Três bugs que só a app a correr revelou

**O login não funcionava.** `ReCaptchaV3Provider('debug')` não é um modo
de debug — passa a string "debug" ao reCAPTCHA como chave de site. Dava
dezenas de erros por minuto, o SDK do Auth tropeçava neles, e o login
falhava. Proteção nenhuma, e a estorvar. Deixou de se ativar App Check
sem chave real: ativá-lo com uma chave inventada dá a ilusão de proteção
e o custo de a não ter.

**Autenticar com sucesso deixava a pessoa no formulário de login.** Desde
que a app abre na vitrina, o login é *empilhado* por cima do gate — o
gate trocava o ecrã por baixo e ninguém tirava o login de cima. Ficava
com o aspeto exato de um login que falhou. Bug meu, da mesma semana.

**A app mentia sobre o limite semanal.** Marquei a aula de amanhã, e a
aula da semana seguinte passou a mostrar "1/1 sessões — já usaste as
sessões desta semana" com um botão "Marcar" ativo ao lado. Toquei:
marcou. O servidor estava certo; a interface é que lia sempre
`DateTime.now()` em vez da semana da aula. É o pior lado para errar — é
o que faz as pessoas **não** marcarem.

#### 🟠 Quando a app não consegue ler, finge que o estúdio está vazio

A cache local do Firestore ficou corrompida a meio dos testes
(`refusing to open IndexedDB database`) e o instrutor viu o seu próprio
ecrã inicial com um "?" no lugar do nome, "0 sessões hoje" e "0 alunos
ativos". Tudo plausível, tudo falso, e sem um único sinal de que algo
tinha corrido mal.

A causa está em 54 sítios, em 22 ficheiros, escritos assim:

```dart
final membros = ref.watch(membersProvider).valueOrNull ?? const [];
```

Cada um trata **três coisas diferentes como a mesma**: "ainda não
carregou", "falhou a carregar" e "está mesmo vazio".

Corrigir os 54 significaria 54 formas diferentes de mostrar o mesmo erro,
e o 55.º a ser escrito nascia outra vez errado. O Riverpod já sabe quando
um provider falha: um `ProviderObserver` ouve isso num sítio só
(`DataHealthObserver`) e um aviso discreto no fundo do ecrã diz o que se
passa — sem tapar nada, porque quem está offline com a cache quente
continua a poder usar o que tem.

Espera quatro segundos antes de aparecer: um aviso que pisca a cada
hesitação da rede ensina as pessoas a ignorá-lo. E quem o dispensa não
volta a ser incomodado pela mesma falha — só pela seguinte.

Isto não substitui o tratamento de erro de cada ecrã. É a rede por baixo,
para garantir que um erro nunca passa em silêncio onde ninguém se lembrou
de o tratar.

#### 🟡 Coerência, encontrada a usar

O aviso "Falta preencher" da Informação pública ficava **vermelho por
causa de um campo que já nem listava** — desalinhou quando a política de
privacidade passou a viver dentro da app. E o campo continuava a dizer
"Obrigatória" quando já não é.

Na vitrina, "Sábado" e "Domingo" apareciam **sem horas nenhumas**: o
ecrã de gestão sugere os dias da semana pré-preenchidos, por isso quem
fecha ao fim de semana guardava linhas só com o dia. Um dia seguido de
nada lê-se como um erro. Passou a contar só a linha que tem horas.

#### Duas vezes estive quase a reportar um bug que não existe

**"O Enter não submete o login."** Fui verificar antes de escrever:
`onFieldSubmitted: (_) => _submit()` já lá estava. O que falhou foi a
escrita não ter chegado ao campo.

**"O instrutor vê '?' em vez do nome."** Vi isso no ecrã. Mas os dados no
emulador estavam certos — era a cache corrompida. Virou o achado do
`DataHealthObserver`, que é o problema verdadeiro.

A causa das duas: a janela do browser estava minimizada, e nessas
condições o Flutter web não desenha nem processa input. Vale a pena
ficar escrito, porque quem tentar repetir estes testes vai tropeçar no
mesmo.

#### O que não está coberto por testes, e porquê

A corrida das séries de treino **não tem teste**. As ferramentas não
chegam lá: os testes contra o Emulator Suite são em TypeScript e não
chamam código Dart, e o `fake_cloud_firestore` dos testes de widget não
modela conflitos de transação. A correção é claramente certa —
ler-mudar-escrever dentro de uma transação — mas fica dito que é
raciocínio, não prova.

O mesmo para a contagem semanal do ecrã de marcar: tentei prendê-la com
um teste de widget e naquele fixture a linha nem chega a ser desenhada.
Deixei o buraco escrito no ficheiro em vez de um teste que não testa o
que diz.

#### E dos perfis, o que ficou por percorrer

Cobri o Gestor (visão global, gestão, informação pública) e o Aluno
(início, marcar, limite semanal). Do Instrutor vi só o ecrã inicial, e
com dados que não eram de confiança. Ficaram por percorrer: treino livre,
plano de treino, avaliações, calendário do instrutor e a aula de grupo.

### 🔴 O bug que fazia as fotos "não aparecerem" — e os vídeos também

Reportado como "a foto do ícone, mesmo depois de a carregar, não
aparece". O que se via era o avatar com iniciais, como se o envio não
tivesse acontecido.

Tinha acontecido, e tudo o resto estava certo. Fui verificar contra
produção antes de mexer em código:

* o ficheiro estava no Storage — `avatar.jpg`, 5774 bytes, reduzido;
* o original tinha sido apagado, como a função faz;
* o documento do membro tinha `photoPath`, `photoUrl` e `photoUpdatedAt`;
* e o URL respondia **HTTP 200, `image/jpeg`, 5774 bytes**.

Tudo a funcionar, e na app nada. A diferença estava num cabeçalho que não
vinha na resposta:

```
$ curl -I -H "Origin: https://gym-sas.web.app" <url>
HTTP/1.1 200 OK
Content-Type: image/jpeg
Cache-Control: public, max-age=31536000
                          ← e nada de Access-Control-Allow-Origin
```

**O Flutter web não usa um `<img>`.** Busca os bytes para os descodificar
ele próprio, e isso é um pedido sujeito a CORS. Sem
`Access-Control-Allow-Origin`, o browser bloqueia-o, o `errorBuilder` do
`PersonAvatar` dispara — e o `errorBuilder` desenha exatamente as
iniciais. O caso de falha era visualmente idêntico ao caso de "esta
pessoa não tem foto", e é por isso que isto se aguentou sem ninguém
perceber porquê.

Um bucket do Firebase Storage nasce **sem** configuração de CORS, e
nunca ninguém lhe pôs uma. Ou seja: nenhum conteúdo servido do Storage
alguma vez funcionou na web. Não eram só os avatares — os **vídeos de
demonstração dos exercícios** estavam partidos pela mesma razão desde
que existem, e ninguém tinha ligado as duas coisas.

Corrigido com `firebase/scripts/set-storage-cors.mjs`. O `origin` é `*`, e
vale a pena dizer porquê em vez de parecer desleixo: aqui o CORS não é
uma barreira de acesso. Estes URLs já são buscáveis por qualquer servidor
— o segredo é o token que vai no endereço, não a origem do pedido. O CORS
só limita o que o JavaScript de outro site pode ler no browser, e esse
site consegue a mesma imagem através do seu próprio servidor. Restringir
às origens de produção dava a mesma segurança (nenhuma) e partia o
desenvolvimento local, onde o servidor do Flutter muda de porta a cada
arranque.

Nenhum teste podia ter apanhado isto: contra o emulador não há CORS
nenhum, e o widget test não faz rede. É uma daquelas coisas que só se vê
a olhar para os cabeçalhos de uma resposta real.

### A foto de perfil passou a ser do estúdio

Pedido depois: o aluno não deve poder mudar a própria foto.

A razão é boa e mudou como isto se pensa. A foto não é personalização de
perfil — é a cara que o instrutor vê na tira da turma para reconhecer
quem tem à frente, a meio de uma aula. Um aluno a trocá-la por um desenho
qualquer não está a enfeitar o perfil dele, está a estragar a ferramenta
de outra pessoa.

Saiu o botão de "O meu perfil", e as Security Rules acompanharam: a
escrita em `avatars/` passou a exigir Gestor, nem sequer o próprio. Sem
isso, tirar o botão só escondia a permissão — quem chamasse a API
diretamente continuava a poder.

Isso abriu um buraco que o pedido não previa: **sem o botão do perfil,
um instrutor ou gestor deixava de poder ter foto de todo**, porque não
havia outro sítio onde alguém lha pusesse. A ficha de staff ganhou o
mesmo bloco que a ficha de aluno já tinha.

### Duas coisas menores, encontradas à volta

**Um aviso de "alterações por gravar" que era mentira.** O ecrã novo de
Informação pública usava uma flag ligada pelo `onChanged` do `Form` — e o
próprio carregamento dos valores dispara esse `onChanged`, tal como se
alguém estivesse a escrever. Abrir o ecrã e sair sem tocar em nada
perguntava se se queriam perder alterações que não existiam. O docstring
do `UnsavedChangesGuard` até avisa contra isto ("pode ser uma função que
compara o estado atual com o inicial — não é preciso manter uma flag");
ignorei-o e paguei. Passou a comparar com o formulário tal como ficou
depois de carregado — incluindo as sugestões de horário que o próprio
ecrã escreve, que também não são alterações do utilizador. Há dois testes
a prender os dois lados.

**Um comentário que descrevia o que não acontecia.** O
`AvatarUploadButton` dizia que ficava em "a preparar…" até o documento da
pessoa ganhar o `photoPath`. Nunca fez isso — espera pelo envio e mais
nada. Um comentário que descreve o que se queria ter feito é pior do que
nenhum, porque quem o lê deixa de ir ver.

### O que a varredura NÃO encontrou

Fui à procura de incoerências nos dados de produção, que é onde costuma
estar a sensação de que há mais coisa partida por baixo. Não havia:

| | |
|---|---|
| Subscrições a apontar para planos ou membros inexistentes | 0 |
| Aulas e séries a apontar para serviços inexistentes | 0 |
| Entradas de plano de treino a apontar para exercícios apagados | 0 (de 33) |
| Aulas com o contador de marcações desalinhado do real | 0 (de 41) |
| Membros sem número de sócio | 0 (de 51) |

### Preparar a submissão às lojas

Chegaram cinco avisos sobre o que a App Store costuma recusar. Fui
verificar cada um contra o código em vez de os aceitar de cor — duas
estavam certas, uma estava certa mas não se aplica, numa delas estamos na
exceção, e o enquadramento da primeira estava inflacionado. E faltavam
quatro coisas que ninguém tinha mencionado, uma das quais recusa o upload
antes de um humano abrir a app.

#### O que era verdade e o que não era

**"Só o ecrã de login é o perfil clássico de rejeição por 4.2"** — meia
verdade, guideline errada. A 4.2 é *Minimum Functionality*: apps que são
pouco mais do que um site embrulhado. A que morde apps atrás de login é a
**5.1.1(v)**, e diz que se a app não tiver funcionalidades significativas
ligadas à conta, deve deixar usar sem login. Esta tem — marcações, planos
de treino, avaliações. O risco real é mais banal: o reviewer não
consegue entrar, ou entra e vê ecrãs vazios.

**Conta demo nas review notes** — verdade, e o item mais importante da
lista.

**Sign in with Apple** — regra verdadeira, não se aplica. Procurei:
não há `google_sign_in`, Facebook, `OAuthProvider` nem `signInWithPopup`.
Só número de sócio/email e password contra o Firebase Auth. A obrigação
da 4.8 só nasce com login social de terceiros.

**Eliminação de conta** — a 5.1.1(v) exige-a a apps que **suportam
criação de conta**. Esta não suporta: só o estúdio cria acessos. Ficamos
na exceção, e por decisão de produto fica assim — o aluno exporta os
dados pela app e o apagamento pede-se ao estúdio, que confirma a
identidade. Está explicado no ecrã "Os meus dados" e vai nas review
notes.

**Dizer nas notas que o registo é feito pelo ginásio** — verdade, e o
ecrã de login já o diz a quem lá chega.

#### O que faltava, e ninguém tinha visto

**O `Info.plist` não tinha uma única descrição de uso.** Estava
exatamente como o Flutter o gerou, e a app abre o seletor de fotos em
dois sítios (foto de perfil, vídeo de exercício). Fui ao código do
`file_picker` instalado: usa `PHPickerViewController` quando pode, mas
tem um caminho alternativo com `UIImagePickerController` — e é a presença
dessa API no binário que dispara o `ITMS-90683 — Missing Purpose String
in Info.plist`, **no upload**, antes de qualquer pessoa ver a app.

Uma chave só, e não mais: o plugin abre a biblioteca de fotos
(`DKImagePickerControllerSourceTypePhoto`) e nunca a câmara nem o
microfone. Declarar permissões que não se usam é convidar perguntas na
revisão.

**O ecrã de arranque do iOS era branco puro.** `LaunchScreen.storyboard`
com `red="1" green="1" blue="1"` numa app que só tem modo escuro — o
mesmo flash branco que tínhamos acabado de corrigir na web, em todos os
arranques no iPhone. Passou a `#0B0B0C`.

**Não existia política de privacidade em lado nenhum** — nem documento,
nem URL. O `ConsentScreen` geria um `kPrivacyPolicyVersion` mas não
mostrava política nenhuma. Isto não é um risco, é um bloqueio: o App
Store Connect não deixa submeter sem o URL. E é mais sério aqui do que
numa app qualquer, porque esta trata dados de saúde — categoria especial
do artigo 9.º, que exige consentimento **informado**, e informado quer
dizer poder ler o documento antes de aceitar.

A política passou a viver **dentro da app** (`PrivacyPolicyScreen`), em
código e versionada — pela mesma razão que o resumo do ecrã de
consentimento: é a versão mostrada que o registo de consentimento
identifica, e um texto que muda no servidor sem mudar a versão tornaria
esse registo inútil como prova. Antes, a ligação dependia de alguém ter
publicado o documento noutro sítio e colado o endereço; até lá, o ecrã
de consentimento pedia aceitação de um documento que não existia em lado
nenhum.

Está em quatro sítios: consentimento (para se ler antes de aceitar),
login (é onde quem revê a app a procura), "Os meus dados" e a vitrina. O
campo de URL continua a existir, agora opcional, para a ficha da loja —
que exige um endereço público — e para o dia em que houver uma versão
revista alojada.

⚠️ O texto foi escrito a partir do que o código faz, e cada afirmação é
verificável nas Rules, nas Functions ou nos ecrãs. Isso torna-o exato,
não suficiente: **falta a revisão jurídica**. Quando ela existir,
substitui-se o texto **e sobe-se o `kPrivacyPolicyVersion`**, senão
ninguém volta a ser perguntado sobre um documento que mudou.

#### A vitrina

Em vez de um formulário de password à entrada, a app abre agora num ecrã
com a marca, o que o estúdio faz, morada, contactos, horário e o mapa de
aulas. O login fica a um toque, em "Já sou membro — entrar".

Não custa nada a quem já é membro: a sessão do Firebase sobrevive a
fechar a app, por isso isto só aparece no primeiro arranque e depois de
sair.

Isso obrigou ao primeiro caminho desta base de dados que se lê **sem
sessão**: `tenants/{t}/public/`. Abrir leitura sem autenticação num
projeto multi-tenant é a mudança mais fácil de fazer mal, por isso vale a
pena ser explícito:

* lá dentro está o que já estaria num cartaz na montra — morada,
  contactos, horário, e o mapa de aulas com modalidade, dia, hora,
  duração e lotação total. Sem nomes, sem instrutores, sem lugares
  ocupados, sem ids que sirvam para pedir outra coisa;
* **não se escreve diretamente**, nem sendo Gestor. Um documento público
  com escrita direta do cliente é um convite a pôr lá o que não devia;
* e há sete testes de regras que provam que ele **não abriu mais nada** —
  sem sessão, o documento do tenant, os membros e até o catálogo de
  serviços continuam fechados.

Os dois documentos que lá vivem chegam por caminhos diferentes, e a
diferença é a questão:

* **`public/schedule`** é *derivado*. Sai das séries ativas e é reescrito
  pelo mesmo cron diário que gera as ocorrências. Ninguém o mantém, e por
  isso não desatualiza — um horário público errado manda pessoas ao
  ginásio à hora errada.
* **`public/info`** é *escrito pelo Gestor*, pela Cloud Function
  `updateStudioInfo`.

O ecrã cala-se sobre o que não sabe: um campo vazio não aparece, e um
mapa de aulas que não é reescrito há mais de uma semana também não. O
cron corre todos os dias; sete dias de silêncio significam que alguma
coisa parou.

#### Onde a morada do estúdio devia viver (e a correção a meio)

A primeira versão disto pôs a morada, os contactos, o horário e o URL da
política na **configuração da build**, com uma marca `POR PREENCHER` e um
teste que falhava a build de produção enquanto lá estivesse.

O argumento era que estes dados aparecem antes de haver sessão, e sem
sessão não há leitura autorizada de nada do tenant. Era verdade — e tinha
deixado de ser um impedimento **no mesmo trabalho**, no momento em que a
vitrina passou a ler de um caminho público para o mapa de aulas. Se o
horário das aulas pode vir de lá, a morada também pode.

E na config era pior por uma razão que não se vê no código: mudar o
número de telefone do ginásio obrigava a um developer, uma build nova e
uma revisão da App Store. É exatamente o problema que o resto da app foi
resolvendo fase a fase — tudo o que é negócio pertence a quem gere o
negócio.

Passou para **Gestão › Informação pública**. Com ele desapareceu a marca
`POR PREENCHER` e o teste que a guardava; o guarda passou a ser um aviso
no próprio ecrã, que lista o que falta e fica **vermelho** quando o que
falta é a política de privacidade — a única coisa ali sem a qual não há
submissão possível.

A troca de guarda tem um custo honesto: um teste falha no CI, um aviso na
app só falha a quem o abre. Ganha-se não precisar de um developer para
mudar uma morada, e deixa de haver uma build vermelha por preencher que
toda a gente aprende a ignorar.

Pormenores que a implementação obrigou a decidir:

* **A escrita passa por uma Cloud Function** e valida o que lá se põe —
  não por segurança, mas para o Gestor não publicar um botão partido: um
  "URL" sem esquema abre uma página em branco no telemóvel e ninguém
  saberia porquê.
* **Campos vazios são válidos** e querem dizer "não mostrar". Bloquear o
  Gestor de guardar a morada enquanto não tiver o horário todo seria pior
  do que deixá-lo fazer uma coisa de cada vez.
* **Linhas de horário totalmente em branco não são guardadas.** O ecrã
  oferece quatro linhas e o Gestor deixa em branco as que não usa; isso
  não é dado.

#### A conta para a revisão

Já havia o `create-test-users.mjs`, e não servia: as contas que ele cria
estão **vazias**. Um reviewer que entre e veja "sem marcações, sem plano
de treino, sem avaliações" fica exatamente onde estava. E havia um risco
concreto — essas contas têm `isTestAccount: true` e são apagadas em bloco
pelo `--delete`. Apagar a conta de demonstração a meio de uma revisão é
rejeição garantida, e é o tipo de coisa que se faz sem pensar.

O `seed-review-account.mjs` cria um aluno com o estúdio já andado: plano
contratado (escolhe o que dá acesso a mais serviços), três aulas
marcadas, plano de treino com três treinos, uma avaliação física e a
mensalidade do mês paga. Marca-o com `isReviewAccount: true` e **não**
com `isTestAccount`, por isso o `--delete` das contas de teste não lhe
toca. No fim imprime o que copiar para as review notes.

#### Ainda por fazer

* ⚠️ **Preencher Gestão › Informação pública** — morada, contactos,
  horário e sobretudo a política de privacidade. O ecrã diz o que falta e
  fica vermelho enquanto a política não estiver lá.
* **App Privacy labels** no App Store Connect: declarar recolha de dados
  de saúde e fitness, contactos e identificadores. Declarar a menos é
  motivo de rejeição.
* **Notificações push** pedem permissão logo a seguir ao login, sem
  contexto, e ainda não entregam nada (falta a chave APNs). Não bloqueia
  a revisão; vale a pena rever a altura do pedido.
* A **versão** está em `0.1.0`, que a um reviewer lê como beta.

### O tempo que o utilizador sente

A varredura anterior foi atrás de leituras e de euros. Esta foi atrás de
outra coisa: o tempo entre tocar no link e conseguir fazer alguma coisa.
São problemas diferentes e moram em sítios diferentes.

#### O ecrã ficava branco durante o arranque todo

O `<body>` do `index.html` tinha exatamente uma linha: o script do
Flutter. Mais nada. Entre tocar no link e a app pintar o primeiro pixel,
o utilizador via **branco** — e nesse intervalo o browser tem de
descarregar vários megabytes, compilar o motor gráfico, arrancar o
Flutter e inicializar sete SDKs do Firebase.

Em localhost isso são milissegundos, que é por isso que nunca ninguém
deu por nada. Num telemóvel com dados móveis são segundos, e segundos de
ecrã branco não se leem como "está a carregar" — leem-se como "não
funciona".

Há agora um ecrã de arranque: fundo `#0B0B0C` (a mesma cor da app, para
não haver o salto de branco para preto), o nome do estúdio e uma barra
indeterminada. É tudo CSS embutido no `index.html`, de propósito:
qualquer ficheiro externo — uma folha de estilos, o logótipo — seria
mais um pedido de rede a acontecer precisamente no momento que isto
existe para tapar.

Para o tirar foi preciso um `web/flutter_bootstrap.js` próprio: o que o
Flutter gera limita-se a chamar o carregador e não dá gancho nenhum para
saber quando a app está viva.

Duas coisas correram mal a fazer isto, e as duas ficaram registadas no
código:

* **O comentário que se auto-sabotou.** Escrevi os nomes dos
  placeholders (`{{...}}`) dentro de um comentário a explicá-los — e o
  `flutter build` substitui-os *também aí*. Injetou o carregador do motor
  inteiro a meio de um `//`, e o ficheiro deixou de ser JavaScript
  válido. O `node --check` passou a fazer parte da verificação.
* **`requestAnimationFrame` não dispara num separador em segundo
  plano.** A remoção dependia dele, e o ecrã de arranque ficava preso por
  cima de uma app já a funcionar até alguém voltar ao separador. Apanhei
  isto a testar com o painel do browser escondido.

O segundo caso mudou o desenho: a remoção vive agora no `index.html`,
com um prazo de segurança de 20 segundos. Um ecrã de arranque que não sai
é **pior** do que não ter nenhum — fica por cima de uma app que está a
funcionar e ninguém consegue tocar em nada. Ao fim de 20 segundos sai de
qualquer maneira, mesmo que nada lho peça.

#### A app passou a ser compilada para WebAssembly

Medido, com as duas builds lado a lado e comprimidas:

| | gzip |
|---|---|
| `main.dart.js` + CanvasKit | **3,90 MB** |
| `main.dart.wasm` + skwasm | **2,77 MB** |

Menos 1,1 MB, e o motor gráfico passa de 6,8 para 3,4 MB por
descomprimir. Além dos bytes, o browser deixa de ter de interpretar 4 MB
de JavaScript antes de correr o primeiro `main()`.

O `--wasm` gera as **duas** builds e o carregador escolhe: quem tiver um
browser sem WasmGC recebe exatamente o que recebia antes. Confirmei numa
build real que o `buildConfig` traz as duas entradas, e confirmei num
browser que a versão wasm carrega o `main.dart.wasm` e o `skwasm`, **não**
toca no `main.dart.js`, renderiza o login e aceita texto nos campos.

Isto obrigou a uma correção nos cabeçalhos de cache que teria passado
despercebida: o `firebase.json` dava regra ao `/main.dart.js` mas o
`main.dart.wasm` e o `main.dart.mjs` não existiam quando aquilo foi
escrito. Ficariam com o valor por omissão do Firebase Hosting e a app
servia uma versão velha durante uma hora depois de cada deploy.

#### Entre autenticar e ver a app eram três idas ao servidor, em fila

O `AuthGate` encadeava três verificações — password temporária,
consentimento, mensalidade — cada uma dentro do `.when(data:)` da
anterior, cada uma com o seu ecrã de espera de página inteira.

**Nenhuma usava o resultado da outra.** Todas dependem só do utilizador
autenticado. Estavam em série apenas porque foram escritas encaixadas
umas nas outras. E liam a mais: para um aluno, a verificação da password
temporária lia `members/{uid}` **e** `staff/{uid}` — e o segundo nunca
existe —, e a seguir o consentimento voltava a ler `members/{uid}` por
outro caminho.

Passaram a arrancar juntas (`gateScreenProvider`): espera-se pela mais
lenta em vez da soma, vê-se um ecrã de espera em vez de três, e a leitura
garantidamente falhada desapareceu (os roles vêm no token e dizem
exatamente onde procurar).

**O teste apanhou uma regressão que eu não tinha previsto.** Encadeadas,
as verificações seguintes nunca chegavam a correr quando uma anterior já
decidia o ecrã. Em paralelo correm sempre — e uma falha a ler a
mensalidade passava a impedir alguém com password temporária de chegar ao
ecrã onde a trocaria. Ficava preso num erro, sem saída.

Por isso cada verificação responde por si, e o que fazer com cada erro é
uma decisão escrita:

* **password temporária** — o erro sobe. Sem esta resposta não se decide
  nada, e deixar entrar quem devia trocar a password seria saltar o UC22.
* **consentimento** — o erro vale por "não é preciso pedir", que é o que
  já acontecia antes (o ecrã lia `valueOrNull == true`, e um erro dá
  `null`).
* **mensalidade** — o erro sobe, mas só se a decisão chegar lá.

Há dois testes novos a prender os dois lados disto.

#### O logótipo do login tinha 238 KB, e ia um ícone de 229 KB à boleia

O `logo_wordmark.png` era 748×535 para ser mostrado a 72 pontos de
altura. Passou a 403×288 (quatro vezes o que se vê, folga para qualquer
densidade de ecrã) e a 76 KB.

E o `pubspec.yaml` declarava a **pasta** `assets/branding/`, não o
ficheiro. Lá dentro está também o `app_icon.png` — o quadrado 1024×1024
de onde o `flutter_launcher_icons` gera os ícones. Iam 229 KB em todas as
builds, incluindo a web, para nunca serem mostrados: nenhum ecrã usa esse
ficheiro, e o gerador lê-o do disco, não do bundle.

#### O `jimp` deixou de ser carregado por funções que não o usam

O `index.ts` importa tudo, por isso qualquer Cloud Function carrega o
módulo de todas as outras no arranque a frio. Passou a um `await
import('jimp')` dentro do handler da `resizeAvatar`, que é a única que o
usa.

**Sendo honesto sobre o tamanho disto:** o `jimp` medido sozinho levava
99 ms, e foi com esse número que o assinalei. Depois de o tornar
preguiçoso, o `index.js` continua a carregar na mesma casa dos 625 ms —
a diferença está dentro do ruído. Boa parte do que o `jimp` puxa já vinha
do `firebase-admin`. O que mudou de facto e se mede são os módulos
carregados: **842 → 686**. Menos código a analisar e menos memória por
instância, mas não o ganho de arranque que eu tinha anunciado.

#### O que não consegui medir, e por isso não afirmo

Os tamanhos, os tempos de carregamento de módulos e a estrutura do código
são medidos. Os ganhos em **tempo de arranque** que se seguem daí são
estimativas: o painel do browser não devolve tempos de pintura, e a única
forma honesta de os confirmar é abrir a app publicada no DevTools de um
telemóvel a sério, com a rede limitada.

O que **está** verificado num browser: o ecrã de arranque aparece, a
build wasm corre e não recorre ao JavaScript, o ecrã de arranque sai
quando a app assume, e o login renderiza e responde.

### Varredura de performance e de custo

Pedida a seguir à das fotos. Percorri as 34 Cloud Functions, os 24
repositórios, os providers e os ecrãs. Vale a pena registar o que **não**
apareceu, porque também é resultado: nenhum `Timer` ou polling, nenhuma
query sem `limit` numa coleção que cresce sem fim, nenhum `await` dentro
de um ciclo que não fosse preciso, região e `maxInstances` corretos,
persistência offline ligada, e as duas correções da varredura anterior
ainda de pé.

Sete coisas novas. Uma delas era um remédio escrito que nunca curou
nada.

#### A limpeza das imagens de deploy apontava para a região errada

O custo real que apareceu em produção eram imagens de contentor a
acumular no Artifact Registry, e a varredura anterior deixou o remédio
escrito aqui:

```
firebase functions:artifacts:setpolicy --days=3
```

O `--help` do CLI diz o resto da história:

```
--location <location>   If omitted, uses the default functions location
                        (default: "us-central1")
```

As funções estão em `europe-west1`. O comando cria a política num
repositório do Iowa que está vazio, diz que correu bem, e as imagens que
estão mesmo a ocupar espaço continuam onde estavam. Um remédio que
devolve sucesso é pior do que nenhum: ninguém volta lá confirmar.

#### Cada avatar numa lista era uma ida à rede

`avatarUrlProvider` chamava `getDownloadURL()`, que é um pedido HTTP aos
metadados do Storage. Abrir Gestão › Utilizadores com cinquenta pessoas
eram cinquenta pedidos — e outros cinquenta ao sair e voltar, porque o
provider era `autoDispose` e o resultado não ficava em lado nenhum.

Sendo exato: **em euros isto era quase nada**. São operações Classe B e o
nível gratuito dá 50 000 por dia. O que custava era tempo, e custava-o no
sítio errado: a lista abria com cinquenta círculos de iniciais e as fotos
iam caindo à medida que os pedidos voltavam. A funcionalidade existia
precisamente para acabar com a fila de cartões iguais.

Um URL de download do Firebase é só o caminho mais um token guardado nos
metadados do objeto. Se for a `resizeAvatar` a gerar o token, o URL é
construível no servidor e viaja no documento da pessoa, que a app já lê.
Cinquenta pedidos passam a zero e as fotos aparecem com a lista.

Não muda quem vê o quê — o `getDownloadURL()` que isto substitui já
devolvia exatamente este URL; muda só de onde vem, e vem para as mesmas
pessoas. E o token novo a cada envio trata da cache de borla: o URL muda,
por isso a foto nova aparece já, apesar do ano de validade.

De caminho, o `PersonAvatar` deixou de ser um `ConsumerWidget` (já não há
nada para observar) e passou a descodificar a imagem no tamanho em que a
mostra. Sem isso, cada avatar ia para memória com os 160px do ficheiro
para desenhar um círculo de 34 — cinquenta avatares são ~5 MB de bitmaps.

#### O array `sets` de cada treino estava a ser indexado para nada

O Firestore indexa automaticamente todos os campos, incluindo cada campo
dos mapas dentro de um array. `workoutSessions.sets` é um array de mapas
com seis campos, e cada série confirmada faz `arrayUnion` — o documento é
reescrito e as entradas de índice recalculadas. Um treino de trinta
séries anda pelas quatrocentas entradas de índice.

Confirmei que **nenhuma query usa `sets`**. Nem `fcmTokens`, nem os
campos de texto livre.

Ser preciso sobre o que isto custava: **não muda a faturação das
escritas** — o Firestore cobra por documento, não por entrada de índice.
Custa armazenamento de índice, latência em cada série confirmada durante
o treino, e é a direção do limite de 40 000 entradas por documento. Cinco
isenções em `fieldOverrides`.

#### Os lembretes reliam de hora a hora as aulas que já tinham avisado

A janela é de doze horas e a função corre de hora a hora, portanto a
mesma aula entrava na query doze vezes. O `reminderSentAt` já evitava
reler as *marcações*, mas a ocorrência era lida na mesma nas onze vezes
em que não havia nada a fazer — e descartada em memória logo a seguir a
ser paga. O filtro passou para o servidor.

Isto obriga a uma migração, e é a parte que engana: o Firestore **não
encontra `== null` em documentos onde o campo não existe**. Uma
ocorrência criada antes desta mudança fica invisível para a query e nunca
recebe lembrete — sem erro nenhum, só silêncio. As ocorrências novas
nascem com `reminderSentAt: null` explícito, e para as que já existem há
`firebase/scripts/backfill-reminder-field.mjs`, que só toca nas futuras
(reescrever um ano de histórico seria pagar escritas para nada). Há um
teste que prende exatamente este caso, para ser uma decisão registada e
não uma descoberta.

#### Dois ecrãs a ler listas inteiras para desenhar pouco

O **painel do Gestor** mostrava "412 membros ativos" lendo os 412
documentos. É o primeiro ecrã que um Gestor vê. Passou a `count()`, que é
faturado como uma leitura por cada mil documentos contados — e, mais do
que ser mais barato, deixa de crescer com o ginásio. Quem for depois a
Gestão › Membros paga a lista aí, que é quando ela serve para alguma
coisa. A lotação prevista continua a ler as sessões: essa precisa mesmo
da capacidade e das marcações de cada uma.

As **mensalidades** construíam todas as linhas de uma vez (`ListView` com
`children`, não `builder`) e contavam os chips com quatro varreduras
completas da lista — tudo isso a cada tecla escrita na pesquisa. Passou a
uma varredura e a uma lista preguiçosa. O mesmo no diálogo de atribuir
membros do treino livre, onde cada toque numa caixa reconstruía as
cinquenta linhas para mudar uma.

#### Uma que estava mal medida por mim

Tinha assinalado o `getRetentionOverview` como "300 sub-queries → 1". Fui
refazer a conta antes de lhe mexer e estava errada: das ~2300 leituras de
uma abertura do painel, ~2000 são os próprios documentos de presença, que
se leem à mesma de qualquer forma. Uma query de grupo de coleções
pouparia as ~300 do resto — **13%**, não o que eu tinha dito — e obrigava
a denormalizar `tenantId` e a data em cada documento de presença, mais
uma regra nova e um retropreenchimento. Num ecrã só do Gestor, com taxa
limitada a 60 chamadas por minuto, não compensa. Fica como estava, e fica
dito porque.

#### O deploy levava 7,4 MB de símbolos de depuração

Os `.symbols` do CanvasKit nunca são pedidos pelo browser. Passaram a
estar no `ignore` do hosting.

#### Um teste que estourava por causa de outro

A suite dos emuladores começou a falhar num sítio que eu não tinha
tocado: `extra-session-usage.test.ts` passa sozinho em 14 segundos e
estourava os 30 na suite completa. Dei com a resposta errada duas vezes
(culpei a máquina, depois culpei um teste meu que era de facto lento e
que corrigi) antes de ver o que era: aqueles limites estavam escritos à
mão dentro do ficheiro, de quando ainda não havia um valor único, e
ganhavam ao do `vitest.config.ts`. São mais ficheiros a disputar um só
emulador de funções, que serializa arranques a frio. O limite passou a
vir de um sítio só, e subiu para 60 segundos — continua a apanhar um
teste que nunca acaba, que é para o que serve.

#### O que verifiquei e estava bem

O mês corrente das mensalidades já saía do campo denormalizado, sem
leitura nenhuma. Os cabeçalhos de cache do hosting estão certos,
incluindo o ano no CanvasKit. As séries do treino num array em vez de
subcoleção continua a ser a decisão certa. O `minInstances` não está
definido, que é o correto para o custo. O limitador de chamadas custa uma
leitura e uma escrita por chamada protegida, que é o preço da proteção.

### Fotos de perfil (e avatares que deixaram de ser todos iguais)

Perguntado pelo cliente: pôr fotos das pessoas no ícone,
independentemente do papel. Fizemos as duas metades da coisa.

#### Primeiro: as iniciais já não são todas do mesmo vermelho

Todos os avatares usavam o gradiente da marca. Numa lista — a tira da
turma, os cinquenta alunos da Gestão — isso é uma fila de cartões
iguais, e é precisamente aí que o instrutor precisa de distinguir doze
pessoas de relance, a meio da aula.

A cor passa a sair do nome, de uma paleta de oito. É determinística: a
mesma pessoa tem sempre a mesma cor, hoje e daqui a um mês, porque é
isso que faz do avatar uma coisa que se reconhece. A soma dos *code
units* do nome, **não** o `hashCode` — o `hashCode` de uma `String` em
Dart não é estável entre plataformas nem entre versões, e a cor mudava
de um browser para o outro.

Isto entrou sozinho porque vale por si: quem nunca puser uma foto fica
com uma lista legível na mesma.

#### Depois: a foto

Um caminho por pessoa, `tenants/{t}/avatars/{uid}/`, seja ela aluno ou
staff — o avatar é a mesma coisa nos dois casos e não valia a pena
inventar dois sítios.

**A redução é nossa, não do cliente.** Foi decisão de produto, e a
alternativa estava escrita e por implementar quando foi corrigida: o
cliente envia a foto tal como o telemóvel a tirou, e a Cloud Function
`resizeAvatar` corta-a a 160px, guarda `avatar.jpg` e **apaga o
original**. Apagar não é limpeza: é o que garante que ninguém serve
por engano os 3 MB que chegaram. A garantia de que nada grande é
servido deixa de depender de a app estar atualizada.

A conta que justifica o esforço:

| | por abertura do ecrã de Utilizadores |
|---|---|
| 50 fotos como saem do telemóvel | ~150 MB |
| 50 fotos reduzidas a 160px | ~400 KB |

O nível gratuito do Storage são 1 GB/dia. Sem redução, **sete
aberturas desse ecrã esgotavam o dia**. A largura de banda de *entrada*
não é faturada, por isso o custo do original é o instante em que
existe.

Detalhes que só se descobrem a fazer:

* **`cover`, não `resize`** — corta ao centro para dar um quadrado, em
  vez de espremer a pessoa para caber num círculo.
* **`jimp` e não `sharp`** — puro JavaScript, sem compilação nativa no
  deploy. `sharp` é mais rápido; aqui isso não vale o risco de um
  deploy que falha a construir um binário.
* **A função só escreve `photoPath` no fim**, depois de o ficheiro
  existir. Escrevê-lo antes dava um avatar partido no intervalo.
* **Guarda contra o ciclo**: a própria função escreve na pasta que a
  dispara. Sem ignorar o `avatar.jpg`, era um gatilho a chamar-se a si
  próprio.
* **`clearAvatarOnDelete`** limpa o `photoPath` quando o ficheiro
  desaparece. Sem ela, remover a foto deixava o documento a apontar
  para um ficheiro que já não existe — e o avatar ficava partido em
  vez de voltar às iniciais. É o servidor a fazê-lo porque um aluno
  não pode escrever no seu próprio documento (as Rules limitam os
  campos), e abrir a regra só para isto seria pior.

Entre o envio e a foto aparecer passam alguns segundos, que é o preço
de a redução ser do lado do servidor. O botão diz "A preparar…" e a
lista continua a mostrar as iniciais — **sem spinner**: a bolinha a
girar dentro de um círculo de 34px é ruído, e numa lista de cinquenta
pessoas são cinquenta. As iniciais servem de marca de água até a foto
chegar, e servem outra vez se a imagem falhar.

O URL leva `?v={photoUpdatedAt}`. O ficheiro é servido com um ano de
validade e o caminho é fixo por pessoa: sem isto, uma foto nova só
aparecia no ano seguinte.

#### Uma lacuna nas regras que escrevi, apanhada a testá-las

A primeira versão da regra de escrita era
`request.auth.uid == userId || isManager(tenantId)`. O ramo do
"próprio" não verificava o tenant — e o uid é único em toda a
instalação. Alguém do tenant B escrevia em
`tenants/A/avatars/{o-seu-uid}/` e a foto passava a ser servida no
tenant A. Corrigido com `belongsToTenant` à frente dos dois ramos, e
há agora um teste que falha se voltar a acontecer.

Quem pode mudar a foto de quem: a **própria pessoa** e o **Gestor**.
Um Instrutor não — pode carregar vídeos da biblioteca, que são do
estúdio, mas a cara de alguém não é conteúdo do estúdio.

#### RGPD

`deleteMemberData` só apagava Firestore. Assim que passam a existir
fotos, isso é um buraco: o pedido de apagamento cumpria-se nos dados e
deixava a cara da pessoa no Storage. Passa a apagar também os avatares.

#### Onde aparece

Aula de grupo (as duas vistas), seletor de membros, o meu perfil, home
do instrutor, lista de utilizadores da Gestão, ficha do aluno, folha de
início de aula. O ecrã de retenção ficou deliberadamente com as
iniciais: o `MemberAtRisk` não transporta foto, e ir buscá-la seria uma
leitura por pessoa num ecrã que existe para ser barato.

#### A corrida que o teste do gatilho encontrou

A `resizeAvatar` é um gatilho de Storage: ninguém a chama, ela
acontece — o que a torna fácil de dar por adquirida. Montei um teste
que a exercita a sério contra os emuladores (chega uma foto de
1600×1200, fica um `avatar.jpg` de 160×160 com menos de um décimo do
tamanho, o original desaparece, o documento ganha o `photoPath`), e o
log da corrida mostrou um erro que nenhuma asserção apanhava:

```
Your function was killed because it raised an unhandled error.
Finished "europe-west1-clearAvatarOnDelete"
```

É a ordem normal de apagar alguém. A `deleteMemberData` apaga os
documentos **e** o avatar; a `clearAvatarOnDelete` acorda a seguir para
limpar o `photoPath` de um documento que já não existe. Entre o `get` e
o `update` cabe a corrida, e o `update` rebenta com NOT_FOUND — a
função fica marcada como falhada e a **repetir** uma escrita que nunca
vai ter onde cair.

Passou a tolerar o NOT_FOUND explicitamente. Não é `set(…, {merge:
true})`, que seria o outro fim errado do mesmo problema: isso
*recriava* o documento da pessoa que acabou de ser apagada. Há um teste
para esse fim também.

Verificação: **7 testes** novos de widget (cor determinística, foto,
e o estado de carregamento — este obrigou a um futuro que nunca
resolve, porque um `async =>` completa no microtask seguinte e o teste
apanhava já a imagem), **8 testes** de Storage Rules e **5 contra os
emuladores** para o gatilho.

### O âmbito do Instrutor: aulas dele, alunos dele

Perguntado pelo cliente, e a resposta era metade e metade:

* **Aulas: já estava.** "As minhas aulas" filtra por `instructorId`; o
  Gestor reutiliza o mesmo ecrã sem filtro e vê a semana toda.
* **Alunos e treinos: não.** `InstructorStudentsScreen` listava **todos**
  os alunos ativos do estúdio, e daí abria-se o plano de treino e as
  avaliações de qualquer um. Era uma lacuna já documentada no código
  desde a Fase 8 — o mockup pedia "só alunos com serviço na tua
  modalidade", e o âmbito nunca tinha sido modelado.

#### O que define "os meus alunos"

Não existe no domínio uma relação aluno→instrutor. Um aluno contrata um
**serviço**, e o instrutor leciona serviços (`staff.serviceIds`). Os
alunos dele são, portanto, os que têm subscrição ativa a algum desses
serviços — a leitura mais próxima do que o mockup pedia, sem inventar
uma atribuição que ninguém faria à mão.

`visibleMembersProvider` faz isso: Gestor vê todos, Instrutor vê os
dele. Uma query só, com `array-contains-any` sobre o índice
`subscriptions (status, activeServiceIds)` que já existia.

#### ⚠️ Isto é âmbito, não segurança

Vale a pena ser explícito, porque a diferença importa: as Security Rules
deixam **qualquer Instrutor ler qualquer membro** do tenant
(`members`, `allow read: if isInstructor(...)`). Filtrar no cliente tira
o ruído e evita o acesso acidental; **não impede o deliberado**.

Torná-lo uma barreira a sério obrigaria a denormalizar os serviços
contratados no documento do membro, para a Rule os poder comparar sem um
`get()` por documento. É uma decisão de privacidade (e de RGPD, tratando-
se de dados de saúde) que fica em aberto, assinalada.

Verificado: **399 testes Flutter** (1 novo).

### Dois reportados: o vídeo escondido, e o instrutor sem criar aulas

#### 🔴 O ▶ que não era um botão

O aluno não conseguia ver o vídeo de um exercício. Os vídeos estavam lá
(dois, em produção) e as Storage Rules deixavam-no ler. O problema era
de interface, e mau:

A linha de cada exercício em "O meu plano" tinha um **`IconBox` com um
▶** à esquerda — **decoração**, copiada do mockup. Aparecia em TODOS os
exercícios, tivessem vídeo ou não, e tocar nele fazia o mesmo que tocar
em qualquer outro sítio da linha: abrir um menu, onde o vídeo às vezes
estava e às vezes não.

Um aluno que vê um play, toca, e não chega a vídeo nenhum conclui — com
razão — que a app está partida.

* O ▶ passou a existir **só onde há vídeo**, e a levar lá diretamente.
  Sem vídeo, o ícone é neutro e deixa de prometer o que não tem.
* O vídeo saiu do menu de ações: escondido atrás de um toque numa linha
  que não dizia ter vídeo, ninguém lhe chegava.
* **Passou a existir durante o treino.** Só era alcançável em "O meu
  plano", mas o momento em que alguém precisa de rever a execução é a
  meio do treino, antes da série — e daí obrigava a sair, ir ao plano,
  encontrar o exercício e voltar. O `ExerciseLogger` ganhou o botão, o
  que o põe também na aula de grupo, nas duas vistas.

#### 🟠 O instrutor não podia criar aulas — e não sabia porquê

O atalho "Criar aula" existe no ecrã do Instrutor desde a Fase 11, mas
**desaparecia** (`SizedBox.shrink()`) quando ele não tinha serviços
atribuídos. O instrutor ficava a olhar para um ecrã onde criar uma aula
simplesmente não existia, sem nada a dizer que lhe faltava uma
configuração que ele nem pode fazer.

A restrição em si é correta: as Security Rules exigem que a aula seja de
um serviço do instrutor (`instructorOwnsSession`), por isso um atalho
ativo levaria a uma recusa do servidor. O que mudou foi passar a
**mostrar o atalho inativo, com o motivo e a quem pedir**. Mesmo
princípio do "Remover" no treino livre.

E a causa nos dados: `create-test-users.mjs` criava o instrutor de teste
**sem `serviceIds`**, ou seja, um instrutor que não podia fazer nada.
Passa a receber todos os serviços ativos do estúdio — numa conta de
teste não há nada a decidir aí.

*Editar* aulas já funcionava: o botão não é limitado por papel e as
Rules permitem ao instrutor alterar as sessões dele.

Verificado: **398 testes Flutter** (2 novos).

### Corrigir o treino depois de a sessão arrancar

Escolher o treino de quatro ou cinco alunos numa folha é rápido — e
enganar-se numa linha também. Sem forma de corrigir, a única saída era
terminar a sessão e recomeçar, com a aula a decorrer.

O cabeçalho de cada aluno ganhou **"Trocar treino"**, que aparece
**só enquanto não houver séries registadas**.

A condição não é conservadorismo: as séries já feitas pertencem a
exercícios do treino antigo. Trocar por baixo delas deixava-as fora da
lista (o painel filtra pelo treino) mas **a contar nos totais da
sessão** — um estado que não se explica a ninguém.

Escondido em vez de desativado, ao contrário do que esta app faz noutros
sítios: é uma correção dos primeiros segundos, e um botão
permanentemente cinzento no cabeçalho de cada aluno seria ruído durante
a aula inteira. Quando há só um treino no plano, um toque explica em vez
de abrir uma folha com uma linha.

`workoutName` é copiado para a sessão, e não lido do treino a cada
leitura: é o nome que fica no histórico, e um treino renomeado meses
depois não deve reescrever o passado — mesmo raciocínio de
`startSession`.

Verificado: **396 testes Flutter** (2 novos).

### Aula de grupo: que treino cada aluno vai fazer

Levantado pelo cliente logo a seguir à vista por exercício, e era uma
falha a sério que nenhuma das duas vistas tornava visível.

O arranque em grupo abria as sessões com **`workoutId: null`** e o nome
da AULA. O arranque individual (`start_workout_button.dart`) sempre
perguntou qual dos treinos do split o aluno vai fazer e guardou essa
escolha; o de grupo não. Duas consequências:

1. **O painel mostrava o plano inteiro.** O filtro por `workoutId` já
   existia no código — só nunca disparava, porque a sessão nunca tinha
   um. Quem tem um split A/B/C via vinte exercícios em vez dos sete de
   hoje, e tinha de os procurar no meio dos outros com a aula a
   decorrer.
2. **O histórico ficava sem saber que treino foi feito** — a informação
   de que a rotação A/B/C depende.

"Iniciar treino para a turma" passou a abrir uma folha com a turma
listada e, ao lado de cada nome, um seletor com os treinos **desse**
aluno. A escolha é por aluno e não pela turma, porque numa aula de grupo
cada um pode estar num dia diferente do seu split.

Decisões que valem a pena:

* **Vem pré-preenchido com o primeiro treino ativo**, e não com um
  palpite pela rotação. Adivinhar em que dia do split cada um vai
  exigiria ler o histórico de todos — mais um listener por atleta — para
  acertar num palpite que o instrutor corrige num toque.
* **Quem não tem treinos no plano não arranca**, e a folha diz porquê
  ali mesmo. Uma sessão sem exercícios é uma linha no histórico que não
  diz nada e que alguém tem de ir fechar à mão; e sem a explicação,
  ficava a pergunta "porque é que só arrancaram três dos quatro?".
* **A vista por exercício filtra pelo mesmo critério.** Sem isso, a
  lista de exercícios da aula juntava os três treinos do split de cada
  aluno — dezenas de páginas para percorrer a swipe.
* **O cabeçalho passou a dizer que treino está a decorrer.** Com um
  split A/B/C, saber qual é metade da informação, e não aparecia em lado
  nenhum.

Verificado: **394 testes Flutter** (5 novos).

### Aula de grupo: a vista por exercício

O treino de turma já existia, centrado no **aluno**: uma tira com a
turma, um toque salta entre pessoas, cada uma com o seu plano. Isso é
certo para PT e para uma sala onde cada um faz o seu treino.

Mas não é como um instrutor conduz uma aula de grupo. Ele não pensa
"agora a Ana" — **chama o exercício**, e toda a gente o faz. Nesse
momento o ecrã certo tem o exercício no topo e a turma em coluna, para
registar a carga de cada um sem trocar de pessoa.

O ecrã ganhou um alternador na barra: **por aluno** ou **por
exercício**. Cada modo com a sua tira (a turma / os exercícios), o seu
swipe e os seus pontinhos.

#### Sem inventar um "plano da aula"

A tentação óbvia era criar um conceito novo — o treino da aula, comum a
todos. Teria sido uma coleção nova, ecrãs novos, e uma contradição com o
modelo deste estúdio, onde **cada aluno tem o seu plano**.

Em vez disso, `groupExerciseOrder` constrói a lista a partir dos planos
de quem está na sala. Se o instrutor deu o mesmo plano a toda a gente —
o caso comum num circuito — a união É o circuito, pela ordem certa. Se
os planos divergem, cada exercício mostra quem o tem ("3 de 4 alunos") e
os outros simplesmente não aparecem nessa página.

A ordenação tem duas regras que valeram testes próprios:

* **Pela posição mais baixa, não pela média.** Se o agachamento é o
  primeiro exercício de três alunos e o quinto de um, continua a ser por
  onde a aula começa — uma média punha-o depois do supino e a turma
  começava pelo sítio errado.
* **Empate desfaz-se por quantos o fazem**, e depois pelo id. Sem esse
  último critério a lista trocava de ordem a cada reconstrução e o swipe
  saltava sozinho.

**Limitação assinalada:** só aparecem exercícios que alguém tem
prescrito. Um circuito improvisado no momento não cabe aqui — isso sim
exigiria o conceito de plano da aula.

#### Swipe, e o risco que ele traz

Ambos os modos ganharam `PageView`. O risco não é o gesto colidir com o
registo (é tudo em toques): é **registar uma série na pessoa errada**
depois de um swipe que passou despercebido — dado errado, em silêncio,
em duas pessoas ao mesmo tempo.

Por isso a tira acompanha sempre a página (`_revealInStrip`), o nome fica
no topo do painel, e há pontinhos a dizer quantas páginas existem. E a
tira continua a ser o caminho principal: numa turma de doze, chegar ao
nono a swipe são oito gestos.

#### Reutilização

Cada linha da vista por exercício usa o mesmo `ExerciseLogger` do treino
individual — mesma pré-carga da última sessão, mesmo desfazer, mesma
edição de série. Uma segunda implementação seria a forma mais certa de
as duas divergirem.

⚠️ **Custo:** um listener de plano por atleta enquanto o ecrã está
aberto. Numa turma de doze são doze listeners e umas duas centenas de
leituras na abertura — é o preço desta vista, e a razão de "por aluno"
continuar a ser o modo por omissão.

Verificado: **389 testes Flutter** (12 novos).

### Dois bugs reportados: eliminar grelhas, e o aviso de conflito

#### 🔴 Eliminar a grelha de treino livre nunca funcionou

Este foi meu, e a causa é embaraçosa: ao fazer a varredura de
eliminações, li mal a saída do meu próprio `awk` — a linha
`allow delete: if isManager(tenantId)` que apanhei era a dos **blocos**,
não a do documento da semana. O documento da semana é `write: false`.

Resultado: o `deleteSchedule` apagava os blocos num batch e falhava no
documento-pai, e como um batch é atómico, **não apagava nada**. A
funcionalidade foi publicada sem nunca ter funcionado.

Passou para `deleteCatalogueEntry`, pelas mesmas três razões que
levaram lá a eliminação de aulas:

1. `freeTrainingSchedules` é `write: false` — o cliente nunca pôde.
2. `slots/{id}/bookings` também é, por isso apagar os blocos pelo
   cliente deixava as marcações órfãs.
3. O id da semana é o próprio `weekId` (`2026-08-24`): gerar a semana
   outra vez recria o documento com o MESMO id, e as órfãs voltavam
   agarradas a ele.

A lição já tinha sido aprendida com as aulas de série uma ronda antes.
Não a apliquei aqui porque confiei numa leitura em vez de verificar.

#### 🟠 O aviso de conflito estava certo — e a dizer muito pouco

Reproduzi a lógica com as **quatro séries reais de produção**
(`test/presentation/schedule_conflict_test.dart`): dispara nas três
horas ocupadas e cala-se nas sete livres. Segunda às 11:00, às 19:00,
terça inteira, quarta às 18:00, fim de semana — nenhum aviso.

O aviso estava certo. O problema era outro: **o estúdio tem um
instrutor só**, e ele tem quatro séries — incluindo **duas idênticas à
segunda às 18:00**. Qualquer aula criada nesse horário colide mesmo, e
o aviso nomeava só a PRIMEIRA das duas. Quem o lia via "há um
conflito", olhava para o calendário, encontrava uma aula, e não percebia
porque continuava a insistir.

Duas mudanças, nenhuma na deteção:

* **Todas as colisões, não só a primeira.** É assim que se descobre que
  se criou a mesma aula duas vezes.
* **O dia inteiro do instrutor, por baixo do aviso** — "O que ele já
  tem à segunda: 09:00–10:00, 18:00–19:00, 18:00–19:00". O aviso dizia
  que havia um problema e obrigava a sair do ecrã para perceber onde
  estava o espaço livre; agora mostra-o.

Verificado: **377 testes Flutter** (24 novos) · **332 contra o Emulator
Suite**.

### Requisito do cliente: a duração da aula deixou de se escrever

O formulário pedia **"Duração (minutos)"** num campo de texto. Quem
marca uma aula pensa "das seis às sete", não "sessenta" — e escrever o
número obrigava a fazer a conta de cabeça, confiar nela, e nunca ver a
que horas a aula acabava.

Passou a **início + fim**, com a duração mostrada ao lado do fim e
atalhos para as durações do costume (45 min · 1 h · 1 h 30). É o mesmo
gesto que o treino livre já usava e o que o Google Calendar faz: a
duração passa a ser lida, não escrita. `durationMinutes` continua a ser
o que se guarda — só deixou de ser o que se pede.

Detalhes que a interação obrigou a resolver:

* **Mexer no início arrasta o fim**, mantendo a duração. Adiar uma aula
  uma hora não devia obrigar a corrigir as duas pontas.
* **Somar minutos encosta ao fim do dia** em vez de dar a volta.
  Escolher 23:30 e tocar em "1 h 30" devolvia 01:00 — uma hora de
  madrugada que ninguém pediu, e que a validação depois recusava sem
  explicar de onde vinha.
* **Não se atravessa a meia-noite**, de propósito: aceitar isso obrigava
  a distinguir "acaba amanhã" de "escrevi ao contrário", que é o engano
  que a validação existe para apanhar.

#### A lacuna que o pedido expôs

**Editar uma aula não deixava mudar a duração.** Ela era herdada em
silêncio (`result.startAt.add(occurrence.endAt.difference(...))`): uma
aula criada com 60 minutos ficava com 60 minutos para sempre, e a única
saída era apagá-la e criar outra — que as aulas geradas por série nem
sequer permitem. O diálogo passou a devolver `endAt`, e quem o chama
passou a usá-lo.

#### Deduplicação

O treino livre tinha a sua própria cópia de `endsAfterStart` e dois
seletores de hora soltos. Ambos passaram para a peça partilhada, o que
lhes trouxe os atalhos de duração de borla e deixou a validação num
sítio só — `lib/core/utils/time_range.dart`, com testes próprios.

Verificado: **364 testes Flutter** (14 novos) · **330 contra o Emulator
Suite**.

### Requisito do cliente: categorias de exercícios definidas pelo estúdio

Os grupos musculares eram uma lista de oito valores escrita no código
(`Pernas`, `Costas`, `Peito`, `Ombros`, `Braços`, `Core`, `Full body`,
`Hyrox`). Um estúdio que quisesse "Mobilidade" ou "Aquecimento" tinha de
pedir a um programador — exatamente o erro que `Service`, `Plan` e
`Modality` já evitavam desde o início: **nunca um enum fixo na app**,
porque o vocabulário é do estúdio, não do produto.

Metade já funcionava: os filtros da biblioteca sempre foram construídos
a partir dos exercícios que existem, não da constante. O único portão
fechado era o **dropdown do formulário**.

**Grupo muscular passou a categoria.** É a palavra do cliente e acomoda
o que já acontecia na prática — "Hyrox" nunca foi um músculo. A palavra
tinha ficado pequena antes de alguém dar por isso.

#### O exercício guarda o NOME, não o id

A decisão que estrutura o resto. Duas razões:

1. Os ecrãs do aluno mostram a categoria ao lado do exercício. Com um
   id, cada um teria de ir buscar o documento — leituras a mais num
   caminho que tinha acabado de ser optimizado precisamente para as
   evitar.
2. Os exercícios já existentes guardam texto.

O preço é que **renomear tem de propagar**, e é por isso que
`ExerciseCategoryRepository.rename` existe em vez de um `update`
genérico: sem ele, mudar "Braços" para "Bíceps e tríceps" deixava os
exercícios numa categoria fantasma — visível na biblioteca, impossível
de voltar a atribuir. O ecrã diz quantos exercícios foram arrastados.

#### Detalhes que a lista fixa nunca teve de resolver

* **Não há categorias nenhumas.** Em vez de um dropdown vazio que não
  explica nada, o formulário diz o que são e deixa criar a primeira sem
  sair dali. Obrigar a abandonar o exercício a meio é a diferença entre
  a lista ser gerível e ninguém lhe mexer.
* **A categoria deste exercício já não é oferecida** (foi desativada).
  Aparece na mesma, marcada — gravar um exercício não pode ser a forma
  de lhe apagar a categoria sem ninguém pedir.
* **Importar as que já estão em uso.** Um estúdio com a biblioteca
  montada tem categorias em uso sem nenhum documento a defini-las. O
  estado vazio mostra-as e oferece importá-las de uma vez.
* **Escrita a Gestor E Instrutor**, como a própria biblioteca: quem cria
  exercícios é quem precisa de os arrumar, e mandar pedir ao Gestor
  recriava o bloqueio que isto veio resolver.
* **Eliminar** passa pelo `deleteCatalogueEntry`, que recusa e diz
  quantos exercícios usam a categoria. A contagem é pelo nome, não pelo
  id — tem de seguir a mesma regra do armazenamento.

#### Campo renomeado sem camada de compatibilidade

`muscleGroup` passou a `category`, sem leitura dupla. A app ainda não
tem utilizadores reais, e a biblioteca em produção é a que o
`seed-content.mjs` semeou — **uma nova passagem do seed reescreve os 61
exercícios**. Carregar um fallback para sempre por causa de um nome de
campo seria pagar juros de uma dívida que se salda com um comando.

⚠️ Depois de publicar, correr:
`node firebase/scripts/seed-content.mjs --project=<id> --tenant=<t> --only=exercicios --yes`

#### Ainda por fazer, do mesmo tipo

A escala de força nas Avaliações Físicas (`Fraca / Média / Boa / Muito
boa`) continua fixa no código, em `assessment_form_screen.dart`. Mesmo
problema, mesma solução — assinalado, não escondido.

Verificado: **354 testes Flutter** · **330 contra o Emulator Suite**.

### Mensalidades presas ao mês corrente

O ecrã tinha procura por nome/nº e filtros por estado, mas o mês era
sempre `DateTime.now()`. Para saber quem pagou em Junho era preciso
abrir o histórico de cada sócio, um a um — com 50 sócios, meia hora de
cliques para responder a uma pergunta de contabilidade banal.

Ganhou navegação por mês (‹ Agosto 2026 ›) com "Voltar ao mês atual". O
botão de avançar está desativado no mês corrente: não há mensalidades do
futuro para marcar, e deixar avançar seria oferecer meses vazios para
sempre.

A parte interessante é **porque é que isto não existia**: o estado do
mês corrente está denormalizado em `members/{id}`, e sai de graça com a
lista que o ecrã já carrega. Qualquer outro mês obriga a ler
`paymentRecords/{período}` de cada membro — uma leitura por sócio. Foi
por isso que se manteve o caminho barato para o mês atual e só se paga
quando alguém navega para fora dele.

Uma armadilha que valeu a pena evitar: a edição gravava com
`year: now.year, month: now.month`. Sem a mudar, corrigir Junho
escreveria em Agosto sem ninguém dar por nada.

### Blocos de treino livre das 08:10 às 08:00

Encontrado nos dados de produção durante a investigação do botão
"Remover": dois blocos com `endAt` **antes** de `startAt`.

Nenhum dos dois diálogos — criar e editar — verificava que o fim é
depois do início. Um seletor de hora não impede ninguém de escolher ao
contrário, e a app mostrava o resultado tal e qual: "08:10–08:00".

Os dois botões passam a estar desativados nesse caso, com a razão
escrita por baixo ("A hora de fim tem de ser depois da de início") —
mesmo princípio do menu "Remover": um controlo desativado tem de dizer
porquê.

A decisão vive numa função pura (`endsAfterStart`) com testes próprios.
A ligação aos botões não dá para cobrir num teste de widget sem
reimplementar o `showTimePicker` do sistema — assinalado, não escondido.

### Varredura geral — o que a leitura do código encontrou

Pedida uma passagem por tudo à procura de bugs. Quatro achados, e o
segundo era meu, de ontem.

#### 🔴 "Remarcar" abria sempre sem destinos nenhuns

`OccurrenceDetailScreen._reschedule` lia
`allUpcomingOccurrencesProvider` com `valueOrNull` — e **nada naquele
ecrã observa esse provider**. Quando se chega à aula pelo calendário do
instrutor, o provider nunca foi ligado, `valueOrNull` devolve `null`, o
`?? const []` tapa, e o seletor de destinos abre **vazio**.

O Gestor concluía que não havia outra aula para onde remarcar o aluno,
quando havia. Sem erro, sem aviso — o pior tipo de falha.

É a terceira vez que esta classe de bug aparece nesta app (o botão
"Iniciar" do treino de grupo e o registo de presenças foram as outras
duas). A correção é sempre a mesma: `await ref.read(provider.future)`.

#### 🔴 Eliminar uma aula deixava marcações órfãs — e as de série voltavam

Isto foi introduzido por mim na ronda das eliminações, e a Rule que
escrevi parecia suficiente. Não era, por duas razões:

1. **`activeBookingCount == 0` não quer dizer "sem marcações".**
   Cancelar põe `status: 'cancelled'` e **deixa o documento**. Apagar a
   aula deixava esses documentos órfãos — e o cliente não lhes pode
   tocar, porque `bookings` e `waitlist` são `write: false`.
2. **As aulas geradas por série têm id determinístico**
   (`{seriesId}_{data}`). O cron das 03:00 recriava-as com o MESMO id, e
   as órfãs voltavam a aparecer agarradas à aula nova. Além de o próprio
   botão ser trabalho que se desfaz sozinho.

A Rule voltou a `false` e a operação passou para `deleteCatalogueEntry`,
que apaga recursivamente e recusa aulas de série — para essas, cancelar
é a operação certa, e acabar com elas de vez faz-se na série. O ecrã só
oferece "Eliminar sessão" a aulas **avulsas e vazias**.

#### 🟠 Quatro botões que não faziam nada se o utilizador não estivesse resolvido

`manage_payments`, `payment_history`, `training_plan_editor` e
`free_training_slot_detail` liam `currentAppUserProvider.valueOrNull` e
faziam `if (x == null) return;` — um no-op silencioso. Estão hoje
mascarados por `HomeScreen` observar o provider, mas é uma dependência
invisível: qualquer mudança de navegação partia-os sem um único teste a
queixar-se. Passaram todos a `.future`, com o `null` a significar só o
que significa mesmo (sessão terminada).

#### 🟠 Índice em falta: `subscriptions (planId, status)`

`syncPlanSubscriptions` procura as subscrições ativas de um plano, e o
par irmão (`memberId + status`) está declarado desde a Fase 3 — este
não. O Firestore consegue muitas vezes servir queries só de igualdade
juntando índices de campo único, por isso pode nunca ter falhado; mas o
emulador **nunca valida índices**, que é exatamente como o bug do `_` no
email chegou a produção. Declarado.

#### O que verifiquei e estava bem

Todas as outras queries (13 compostas no cliente, 8 nas funções) têm
índice; os `catch` silenciosos são todos deliberados e documentados; não
há TODOs por resolver; `workoutSessions.sets` é um array no documento,
por isso apagar a sessão não deixa nada para trás; os ids dos blocos de
treino livre são gerados pelo Firestore, por isso não há o problema de
reaparecimento que as aulas de série têm.

Verificado: **344 testes Flutter** · **324 contra o Emulator Suite**.

### O botão "Remover" que ficou cinzento

Reportado logo a seguir, e é o tipo de falha que uma mudança de regras
deixa para trás: as Security Rules passaram a permitir eliminar um bloco
de treino livre vazio **mesmo depois de a semana ser publicada**, mas o
ecrã continuava a desativar a opção pela condição antiga (`status !=
published`). A regra dizia sim, a interface dizia não.

Duas correções, e a segunda importa mais do que a primeira:

1. A condição no ecrã passou a ser a mesma da Rule — `activeBookingCount
   == 0`, e nada mais.
2. Quando o item **está** desativado (porque há inscritos), o rótulo
   passa a dizer porquê: **"Remover — tem inscritos"**. Um item cinzento
   sem explicação é exatamente o que faz alguém perguntar "porque não
   consigo tocar aqui?" — e a resposta tem de estar onde a pergunta
   nasce, não numa mensagem que só aparece depois de tocar.

O texto da confirmação também mentia ("só é possível remover blocos
antes de a semana ser publicada") e passou a dizer o que acontece de
facto — incluindo o aviso de que, numa semana publicada, o horário
desaparece já da app dos alunos.

Varri o resto da app à procura do mesmo padrão. Os outros controlos
desativados são todos "enquanto guarda", que se explicam sozinhos.

Nos testes, `.first`/`.last` sobre `PopupMenuButton` não servia: o
`Scaffold` pinta o body antes do `AppBar`, por isso a ordem no widget
tree é o contrário da ordem no ecrã, e o teste abria o menu errado sem
se queixar. Passaram a usar `find.descendant` do `AppBar` e do `Card`.

### Varredura de custo — ler menos

Feita a pedido, depois de aparecer 1 cêntimo de custo em produção. O
cêntimo não era uso: eram as imagens de contentor dos deploys (33
funções, várias publicações). O uso estava em **0% da quota de
invocações** e **0,1% da de escritas**.

Mas a varredura encontrou duas leituras desproporcionadas, ambas no
caminho mais frequente que existe — um aluno a abrir a app.

#### A biblioteca de exercícios inteira, por aluno

`exercisesProvider` traz TODOS os exercícios, e cinco ecrãs do aluno
dependiam dele (o plano, o treino em curso, o histórico, as
estatísticas, o treino de grupo) para resolver o nome de meia dúzia de
exercícios.

O problema não era o número de hoje — era a métrica: **o custo crescia
com o tamanho da biblioteca, não com o que o aluno treina.**

| Biblioteca | 50 alunos/dia | quota diária |
|---|---|---|
| 61 exercícios | ~3 050 leituras/dia | ~6% |
| 300 exercícios | ~15 000 leituras/dia | ~30% |

`ExerciseRepository.getExercisesByIds` traz só os referenciados
(`whereIn`, em blocos de 30 porque é o limite do Firestore), e
`exercisesByIdsProvider` indexa-os por id. Passa de 61 para ~8, e deixa
de crescer com a biblioteca.

Dois detalhes que a implementação obrigou a resolver:

* **A chave da família** é uma string ordenada, não um `Set`. Em Dart
  dois `Set` com o mesmo conteúdo não são iguais, por isso passar a
  coleção diretamente criaria um provider — e uma leitura — nova a cada
  reconstrução do ecrã. O mesmo raciocínio que `serviceIdsKey` já usava
  para as ocorrências.
* **No histórico de treinos, a resolução é feita uma vez para a lista
  toda**, não por cartão: um pedido por sessão seria trocar uma leitura
  grande por dez pequenas.

Os dois ecrãs que precisam mesmo da biblioteca completa — a própria
biblioteca e o seletor do instrutor — continuam com `exercisesProvider`.

#### As 8 semanas de horário, para marcar a aula de amanhã

`_upcomingLimit = 200` limitava por CONTAGEM. As séries geram
ocorrências com 8 semanas de antecedência, portanto o ecrã "Marcar"
descarregava o calendário inteiro do ginásio a cada abertura, para
mostrar as poucas aulas que alguém vai mesmo marcar.

`watchUpcomingOccurrencesForServices` ganhou `weeksAhead`, e o ecrã
começa em **duas semanas** com um "Ver horário completo" no fim da
lista. A decisão real de um aluno é "esta semana ou a próxima"; o resto
vem a pedido.

O botão fica no fim da lista e não num seletor no topo de propósito:
quem procura a aula de amanhã não devia ter de decidir o horizonte
antes de ver seja o que for.

#### O que já estava bem

Vale a pena registar, porque foi verificado e não presumido:

* Os **lembretes de hora a hora** saltam as sessões já avisadas sem ler
  as marcações delas, e marcam até as sessões vazias para não as reler.
  ~300 leituras/dia.
* O **calendário do instrutor** não abre listener para aulas canceladas
  ou vazias.
* A **lista de espera** no ecrã de marcar só é observada nos cartões
  cheios.
* **Vídeos** têm limite de 100 MB e aviso ao instrutor quando são
  grandes.
* Só **2 das 34 funções** correm sozinhas (~760 invocações/mês contra 2
  milhões grátis).

#### O que continua a ser o custo real, mais tarde

Não é o Firestore — é a **largura de banda do Storage**. Um vídeo de
30 MB visto por 40 alunos são 1,2 GB; o nível gratuito dá 1 GB/dia.
Nada a corrigir hoje, mas é aqui que aparece a fatura quando a
biblioteca tiver vídeos a sério. O remédio é comprimir na origem: uma
demonstração de 30 s a 720p ocupa 3-5 MB, não 30.

E as **imagens dos deploys** acumulam se nada as limpar. ⚠️ O comando
precisa da REGIÃO — sem ela aponta para `us-central1`, que está vazio, e
devolve sucesso na mesma:

```bash
firebase functions:artifacts:setpolicy --location=europe-west1 --days=3 --project=gym-sas
```

Verificado: **341 testes Flutter** (7 novos em
`test/infrastructure/cost_queries_test.dart`, que é onde estas duas
correções ficam presas — nenhuma delas é visível na interface) e **323
contra o Emulator Suite**.

### Eliminações — a varredura completa

Levantamento cruzando três camadas (o que as Security Rules permitem, o
que os repositórios expõem, o que a interface oferece). Onze lacunas, e
o resto desta secção é o que se fez com cada uma.

**Passaram pela Cloud Function** (`deleteCatalogueEntry`, que conta
referências e recusa dizendo quais): serviços, planos, modalidades,
**exercícios da biblioteca**, **séries de aulas** e **contas de staff**.

* **Exercícios** — as referências (`planEntries`, `loadHistory`) vivem
  em subcoleções de cada membro, por isso a contagem é por grupo de
  coleção; daí os `fieldOverrides` novos em `firestore.indexes.json`. Um
  grupo de coleção atravessa tenants, e aqui isso importa: os ids do
  seed são fixos (`ex_agachamento_barra`) e portanto **iguais em todos
  os estúdios** — sem o filtro por caminho, um exercício noutro ginásio
  bloqueava a eliminação neste. É a única desta lista que o Instrutor
  também pode fazer, porque já cria e edita a biblioteca.
* **Staff** — apaga também a subcoleção `private` (dados pessoais) e a
  conta de autenticação, por esta ordem: uma falha a meio não pode
  deixar uma conta capaz de entrar numa app onde já não existe perfil.
  Um Gestor não se elimina a si próprio — ficaria trancado fora, a
  precisar exatamente do programador que isto dispensa.

**Passaram a ser decididas pelas Security Rules**, sem gastar uma
chamada de função, porque a condição é uma só e o `activeBookingCount`
é escrito exclusivamente pelas funções de marcação — o cliente nunca lhe
toca, logo não o pode falsear:

* **Aulas** (`sessionOccurrences`) — `allow delete` era sempre `false`,
  para proteger marcações e histórico. Isso apanhava também a aula
  criada por engano há dois minutos: só se podia CANCELAR, e ela ficava
  no calendário para sempre a dizer "cancelada". Sem ninguém inscrito
  não há marcação para libertar nem utilização para devolver — não há
  cascata nenhuma a saltar, que era a razão original do `false`. O ecrã
  reflete isto: com inscritos aparece "Cancelar sessão", sem inscritos
  aparece "Eliminar sessão". Nunca os dois.
* **Blocos de treino livre** — a condição "só antes de publicar" saiu.
  Depois de publicada, um bloco vazio só podia ir a capacidade 0 e
  ficava na grelha a dizer "0/0", visível aos alunos e a não servir para
  nada.

**Escrita direta, sem referências a verificar:**

* **Avaliações físicas** — uma avaliação no aluno errado não é histórico
  de nada, é um engano, e nenhum documento aponta para ela.
* **Sessões de treino registadas** — as cargas dessa sessão vão com ela.
  É para isso que as Rules só permitem apagar `loadHistory` que tenha
  `sessionId`: uma carga escrita à mão pelo instrutor não a tem e
  continua protegida. Só o estúdio elimina treinos — um aluno a apagar
  os treinos maus falseava a própria evolução sem dar por isso.
* **Grelha semanal de treino livre** — conta os inscritos ANTES de
  apagar o que quer que seja. Sem isso, ia apagando blocos até a Rule
  recusar um a meio, e ficava uma grelha meio apagada — pior do que
  qualquer um dos dois estados inteiros.
* **Lista de espera** — `leaveWaitlist` já aceitava staff desde que
  existe; nunca houve por onde carregar. Um aluno que pediu para sair
  por telefone ficava na fila a apanhar a vaga seguinte.
* **Registos de mensalidade** — ⚠️ **assumido explicitamente**: o fluxo
  de RGPD *anonimiza* registos de pagamento em vez de os apagar, por
  retenção fiscal, mas isso vale para o apagamento de uma PESSOA, onde a
  alternativa era perder a contabilidade de um cliente real. Aqui é o
  Gestor a corrigir um lançamento seu, e a app não é o sistema de
  faturação do estúdio. Se um dia passar a ser, isto tem de voltar a
  fechar. Eliminar e "marcar não pago" são ações separadas de propósito,
  e a confirmação diz qual é qual.

**Continuam fechadas, e bem:** membros (têm caminho próprio em
`deleteMemberData` — exportação, anonimização e confirmação pelo número
de sócio), marcações, presenças e subscrições (passam por Cloud
Functions com cascata: cancelar, não apagar — são o histórico do
aluno), e `usage` (é recalculável, não é dado de origem).

#### UX

O caixote do lixo solto na linha passou a menu `⋮`. Em telemóvel o dedo
tapa a linha toda, e uma ação sem retorno a um toque de distância é um
acidente à espera de acontecer; o menu exige dois gestos deliberados
antes de sequer chegar à confirmação. Nos ecrãs de detalhe (série,
staff) a ação vive na barra do topo — é aí que se está a olhar para o
que se vai eliminar.

Todas as confirmações passam por `confirmDestructiveAction`, para se
parecerem umas com as outras: título em forma de pergunta, uma frase que
diz **o que se perde** (não o que se clica), e o botão perigoso sempre à
direita, na cor de erro, a dizer o que faz — nunca "OK".

Apanhado ao escrever os testes: os itens do menu rebentavam a linha em
ecrãs estreitos (`RenderFlex overflowed by 58 pixels`). Um `Flexible` a
menos num menu que é estreito por natureza.

Verificado: **334 testes Flutter** · **323 contra o Emulator Suite**,
incluindo 17 da função de eliminação e as Rules novas de aulas e blocos
vazios (Gestor sim, Instrutor não, Aluno não, com inscritos não).

Um efeito colateral apanhado pela suite: `smoke-fluxo-completo.test.ts`
tinha o email sintético antigo escrito à mão e deixou de encontrar as
contas do seed. Filtrar só por `member-000001@` também não servia — o
seed cria um sócio nº 000001 em DOIS tenants (o real e o fantasma dos
testes de isolamento). O domínio passa a ser derivado pela mesma regra
da app.

### O Gestor passa a poder eliminar o que ele próprio criou

Duas coisas reportadas a testar, com a mesma raiz.

**Planos cancelados enchiam a lista.** Cancelar um plano e voltar a
atribuir o mesmo é rotina — corrigir um preço, retomar depois de uma
pausa. Com tudo numa lista corrida, o detalhe do membro mostrava "Aulas
de Grupo" três vezes seguidas e era preciso ler a etiqueta de estado de
cada uma para saber qual conta. As canceladas/expiradas passaram para
um `Histórico (N planos anteriores)` fechado: continuam lá (são o
histórico financeiro do membro), mas saem da frente.

**Não havia forma de eliminar serviços, planos ou modalidades.** A
regra do domínio era "nunca eliminar, só desativar", e a razão é boa: um
plano eliminado deixa as subscriptions que apontam para ele sem nome nem
preço, e o histórico do membro passa a mostrar ids em vez de "Aulas de
Grupo — 44,90 €".

Mas a regra estava a ser aplicada a tudo, incluindo ao caso que acontece
mais vezes: alguém cria um serviço com o nome errado ou um plano em
duplicado, dá-se conta no minuto seguinte, e fica com ele para sempre.
Desativar não resolve — continua nas listas de gestão. A única saída era
pedir a um programador, que é precisamente o que esta app existe para
evitar.

`deleteCatalogueEntry` (Cloud Function, Manager-only) conta primeiro as
referências e só elimina se não houver nenhuma. Se houver, **recusa e
diz quais**, com números: "3 série(s) de aulas", "12 subscrição(ões) de
membros". É essa lista que permite ao Gestor decidir sozinho entre
eliminar e desativar.

Detalhes que valem a pena:

* A contagem usa `count()` (agregação), não `get()` — uma agregação é
  faturada como uma leitura por cada mil documentos, e nenhuma destas
  contagens precisa do conteúdo.
* Para saber que planos incluem um serviço, um
  `collectionGroup('services')` seria mais curto — mas atravessa
  **tenants**, e `services` é ao mesmo tempo coleção de topo e
  subcoleção de `plans`. Fica um `getAll` exato sobre os planos do
  próprio estúdio.
* O serviço de **treino livre** não aparece em query nenhuma: vive num
  campo de configuração. Tem verificação própria — sem ela, eliminá-lo
  deixava o treino livre a apontar para o vazio (exatamente o problema
  descrito na secção anterior).
* Eliminar um plano apaga também a sua subcoleção `services`. Apagar só
  o documento pai deixava-a órfã — invisível na consola, e a renascer se
  alguém recriasse um plano com o mesmo id.
* Uma subscrição **cancelada** continua a bloquear: é precisamente o
  registo que precisa do nome e do preço do plano.

**Não cobre exercícios da biblioteca.** As referências (`planEntries`,
`loadHistory`) vivem em subcoleções de cada membro e a contagem exigiria
índices de grupo de coleção novos. Assinalado, não escondido — e a
biblioteca já permite editar um exercício, que resolve o caso comum.

Verificado com 11 testes novos contra o Emulator Suite (recusa por cada
tipo de referência, eliminação da subcoleção do plano, instrutor sem
permissão, tipo desconhecido, id inexistente) e 2 testes de widget sobre
o que o Gestor vê quando a eliminação é recusada.

### Mudar o serviço de treino livre deixava os blocos para trás

Reportado como "atribuí o plano de treino livre ao aluno e ele continua
sem acesso". Os dados de produção contavam a história toda: existiam
**dois** serviços de treino livre — um criado à mão, entretanto
desativado, e o `svc_treino_livre` do catálogo. A definição em Gestão ›
Definições apontava (bem) para o novo; os **onze blocos já publicados
continuavam a apontar para o antigo**.

Cada bloco guarda o `serviceId` que estava configurado quando nasceu, e
o Aluno só vê blocos cujo serviço o plano dele inclui. Com o plano a
dar acesso ao serviço novo e os blocos presos ao antigo, a app
mostrava-lhe **"o teu plano não inclui treino livre"** — a alguém cujo
plano incluía mesmo. Um estúdio inteiro podia ficar sem treino livre
sem nada, em lado nenhum, explicar porquê.

A definição estava correta e o filtro também. O que faltava era alguém
notar que os dois deixaram de concordar.

`ManageFreeTrainingScreen` passa a assinalar, na semana que está a ser
vista, quantos blocos apontam para outro serviço — com o efeito
explicado do lado do Aluno — e traz a correção com o aviso ("Ligar ao
serviço atual", `FreeTrainingRepository.retargetSlots`). As Security
Rules já permitiam esta escrita ao Gestor (`update` de um slot, desde
que `activeBookingCount` fique inalterado), por isso não foi preciso
Cloud Function nenhuma.

O aviso vive do lado de quem pode resolver. Do lado do Aluno a mensagem
mantém-se: é o que a app sabe a partir do que vê.

### 🔴 O bug que só aparecia em produção: `_` no email sintético

Encontrado ao criar as primeiras contas de teste no projeto real, e
teria bloqueado o lançamento.

Os alunos entram com número de sócio, não com email — mas o Firebase
Auth só sabe autenticar emails, por isso gera-se um email sintético
determinístico: `member-<numero>@<tenantId>.gymsaas.internal`.

O `tenantId` real é `nxt_performance_studio`. Esse `_` ia parar ao lado
direito do `@`, onde valem as regras de **nomes de domínio** — e
underscore não é um carácter válido num hostname. O **emulador de Auth
aceita; o Firebase Auth real recusa** com `auth/invalid-email`.

Consequência em produção: `createMember` rebentava, e nenhum aluno
conseguia sequer ser criado, quanto mais entrar. A app parecia inteira
até se tentar o primeiro sócio.

**Porque é que 619 testes não apanharam isto:** todos os testes de
`buildSyntheticEmail` usavam o tenant `nxt`, que por acaso já era um
rótulo de domínio válido. E o resto da suite corre contra o emulador,
que é permissivo exatamente neste ponto. Era um bug que, por
construção, só a produção conseguia mostrar.

A correção normaliza o `tenantId` num rótulo válido (só letras, dígitos
e hífenes, sem hífen nas pontas) nos **quatro** sítios que constroem
este email — `login_identifier.dart`, `loginIdentifier.ts`, `seed.mjs` e
`create-test-users.mjs`. Os testes novos usam o `tenantId` a sério e
validam o formato contra a regra do domínio, em vez de comparar com uma
string escrita à mão.

⚠️ **Efeito colateral no ambiente de desenvolvimento:** o email mudou,
por isso as contas de aluno já semeadas no emulador deixam de casar com
o que o login gera. Volta a correr `npm --prefix firebase/scripts run
seed` depois de limpar os dados do emulador.

### Catálogo do estúdio (`seed-content.mjs`)

Um estúdio acabado de criar está tecnicamente pronto e praticamente
inútil: sem exercícios não há planos de treino, sem serviços não há
aulas, sem planos não há subscrições. Preencher isso à mão pela app são
horas de formulários antes de se conseguir testar seja o que for.

`firebase/scripts/seed-content.mjs` escreve um catálogo a sério:

* **61 exercícios** com execução descrita — não nomes soltos. A
  descrição é o que o aluno lê no telemóvel a meio da série, por isso
  cada uma diz o essencial da execução e o erro mais comum. Cobrem os
  8 grupos do dropdown da app, incluindo as estações de Hyrox.
* **5 serviços**, com `exclusiveGroup` já preenchido onde faz sentido
  (treino livre e treino acompanhado são níveis do mesmo produto, não
  produtos distintos).
* **8 modalidades** ligadas aos serviços certos.
* **6 planos** com preços e regras de utilização por serviço.
* Opcionalmente, um **plano de treino de 3 dias** num aluno
  (`--training-plan-for=<nº de sócio>`): 20 exercícios prescritos com
  séries, repetições, cargas, descansos e notas do instrutor.

Diferenças deliberadas em relação ao `create-test-users.mjs`:

* **Não tem `--delete`.** Isto não é dado descartável — é o catálogo do
  estúdio, feito para ficar e ser editado pela app. Apagar um exercício
  já prescrito no plano de alguém deixaria a prescrição a apontar para
  o vazio.
* **Ids fixos e legíveis** (`ex_agachamento_barra`,
  `plan_acompanhado_3x`) com `merge: true` — correr outra vez atualiza,
  não duplica. Verificado a correr duas vezes seguidas: contagens
  idênticas.
* **Não toca no campo `videoPath`.** Se alguém já tiver carregado um
  vídeo pela app, uma segunda corrida do script não o apaga.

⚠️ **Os preços são inventados** e estão todos juntos no topo do
ficheiro, na constante `PLANOS`. Revê-os antes de mostrar isto a um
cliente.

Verificado contra o emulador com um script de referências cruzadas:
todos os `muscleGroup` dentro do dropdown, todas as modalidades e
planos a apontar para serviços existentes, todas as prescrições a
apontar para exercícios e treinos existentes, e a invariante do UC16
(nenhuma carga sem a entrada de histórico correspondente).

### Contas de teste num projeto real

O `seed.mjs` está preso ao emulador de propósito, e bem — mas depois de
publicar continua a ser preciso um punhado de alunos para clicar na app
verdadeira sem inventar sócios reais.

`firebase/scripts/create-test-users.mjs` cria N alunos com números de
sócio a partir de **900001** (os reais começam em 000001 e sobem; as
gamas nunca se cruzam) e uma password partilhada. Opcionalmente também
um instrutor.

Duas decisões que importam, porque isto escreve na base de dados a
sério:

* **A remoção não se guia pelo número de sócio**, guia-se por um campo
  `isTestAccount: true` gravado no documento. Uma convenção de nomes
  apagaria um sócio real que por acaso tivesse um número alto; uma
  marca explícita não.
* **Apagar um aluno com marcações ativas está bloqueado.** O
  `activeBookingCount` da aula é o que decide se há vagas, e nada o
  recalcula — apagar o membro por baixo deixava a aula com uma vaga
  ocupada por alguém que já não existe, para sempre. O script conta
  primeiro e recusa, dizendo para cancelar pela app (que passa pelas
  Cloud Functions e acerta o contador). O `--force` existe, e diz o que
  estraga.

Verificado contra o emulador: criação, segunda corrida idempotente,
remoção bloqueada por marcação ativa, `--force`, e o caso de não haver
nada para apagar.

```
node firebase/scripts/create-test-users.mjs --project=<id>   --tenant=<tenant> --count=5 --yes
node firebase/scripts/create-test-users.mjs --project=<id>   --tenant=<tenant> --delete --yes
```

⚠️ Estas contas têm password fraca por design. Não devem sobreviver ao
período de testes — a remoção é um comando, não há desculpa.

### O que verifiquei e estava bem

* **Rules**: nenhuma coleção fora do `deny` final; `_rateLimits`
  inacessível ao cliente; a suite de isolamento passa.
* **Sem TODOs nem `print`** perdidos no código de produção (o único
  `print` está atrás de `kDebugMode`).
* **Seed de teste** não consegue tocar num projeto real: força o
  emulador e tem o id do projeto de desenvolvimento escrito no código.
* **App Check** fica em modo debug na web até existir a chave reCAPTCHA
  — já estava assinalado, e como o *enforcement* só se liga depois de
  uma ou duas semanas em monitorização, não bloqueia ninguém no dia um.

### Estado final

**436 testes Flutter** · **370 contra o Emulator Suite** · `dart format` limpo · `flutter analyze
--fatal-infos` sem problemas · build e lint das Cloud Functions · build
de produção (wasm) a compilar e a correr num browser.

⚠️ A build de produção é `--wasm`. O `flutter_bootstrap.js` deste
projeto é próprio (traz o ecrã de arranque), e é gerado a partir de
`web/flutter_bootstrap.js` com substituição de marcas — por isso vale a
pena confirmar que o resultado é JavaScript válido antes de publicar:

```bash
node --check build/web/flutter_bootstrap.js
```

(O Emulator Suite exige o seed corrido primeiro — o
`smoke-fluxo-completo` procura as contas do Leo e da Rita e falha sem
elas. Corre os dois na mesma sessão:
`firebase emulators:exec --project=demo-gym-saas-dev --only firestore,functions,auth,storage "npm --prefix firebase/scripts run seed && npm --prefix firebase/tests test"`.)

## Próximo passo

Fechar o que resta do re-skin (avaliações do Aluno, formulários do
Instrutor/Gestor) — é tudo apresentação a partir daqui, o picker de
serviços agrupado era a única peça de negócio e está feita. Depois, a
Fase 11 (lançamento): Security
Rules revistas operação a operação (documento "06 — Security & Business
Rules", ainda por escrever), paginação nas coleções que crescem, rate
limiting em Cloud Functions sensíveis, testes de isolamento entre
tenants corridos de novo antes de um cliente real, e monitorização de
custos por tenant.

## Publicar — a sequência, e como saber que correu

> Esta secção substitui as listas de "por publicar" que estavam
> espalhadas pelo resto do documento. Se houver conflito, é esta que
> vale.

### O problema que isto resolve

`firebase deploy` diz "sucesso" quando publica **o que lhe pediste** —
não quando publica tudo o que era preciso. Publicar as funções e esquecer
os índices dá dois sucessos e uma app partida, e não há nada no terminal
que o denuncie.

Foi exatamente o que aconteceu: a certa altura o projeto tinha os índices
de um dia, as funções de outro e o site de um terceiro. Descobrir isso
obrigou a comparar tudo à mão, contra o projeto real.

### Primeiro: perguntar em que pé estamos

```bash
npm --prefix firebase/functions run build
node firebase/scripts/check-deploy.mjs --project=gym-sas --tenant=nxt_performance_studio
```

Não escreve nada, pode correr as vezes que quiseres, e responde à
pergunta toda: o que está publicado, o que falta, e o comando para cada
coisa que falta. Precisa de `gcloud auth application-default login` uma
vez.

Onde pode, verifica **comportamento** e não configuração — porque a
pergunta não é "o ficheiro foi enviado?" mas "a app funciona?":

* **Funções** — compara o build local com o que está publicado, e avisa
  de funções publicadas que já não existem no código (continuam
  chamáveis, e a custar arranques a frio).
* **Índices** — compara a declaração e depois **corre as queries** que
  dependem deles. Um índice declarado e ainda a construir é
  indistinguível de um publicado se olhares só para a lista; a diferença
  só se vê a correr a query.
* **Regras** — lê sem sessão o que deve ser público **e** tenta ler sem
  sessão o que não deve. As duas juntas provam que as regras novas estão
  em vigor e que a abertura da vitrina não alastrou.
* **Site** — busca o `index.html` publicado e procura o ecrã de arranque
  e a build wasm.
* **Passos de correr uma vez** — catálogo, campo dos lembretes, vitrina,
  informação do estúdio, conta de revisão.

### Depois: a ordem, que não é arbitrária

**1. Regras e índices primeiro.** Os índices demoram minutos a
*construir*, e uma app nova a bater num índice que ainda não existe
falha em produção.

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage --project=gym-sas
```

**2. Funções.**

```bash
firebase deploy --only functions --project=gym-sas
```

**3. Esperar que os índices fiquem prontos.** Volta a correr o
`check-deploy`: a secção 3 corre as queries a sério e só passa a verde
quando eles acabaram mesmo de construir.

**4. Os passos que se correm uma vez** — depois das funções, não antes.
O do lembrete corrige as aulas que já existem; as novas só nascem com o
campo depois de o cron novo estar publicado.

```bash
node firebase/scripts/seed-content.mjs --project=gym-sas --tenant=nxt_performance_studio --only=exercicios --yes
node firebase/scripts/migrate-exercise-category.mjs --project=gym-sas --tenant=nxt_performance_studio --yes
node firebase/scripts/backfill-reminder-field.mjs --project=gym-sas --tenant=nxt_performance_studio --yes
node firebase/scripts/seed-review-account.mjs --project=gym-sas --tenant=nxt_performance_studio --yes
```

Os dois primeiros parecem o mesmo e não são. O seed reescreve os 61
exercícios do **catálogo**, que têm ids determinísticos. Os exercícios
que o estúdio criou **pela app** têm ids aleatórios, o seed não sabe que
existem, e são os únicos que podem ter ficado com o campo antigo
(`muscleGroup` em vez de `category`) — ficam fora dos filtros por
categoria, que é onde as pessoas os vão procurar.

Isto esteve errado no próprio verificador: ele marcava o problema e
mandava correr o seed. Correr o comando sugerido, vê-lo dizer "✓ 61
exercícios" e o verificador continuar vermelho é a forma mais rápida de
ensinar alguém a desconfiar do verificador. Todos os scripts com
`--yes` dizem primeiro o que iam fazer se o omitires.

E, uma vez por projeto, a política de limpeza das imagens de deploy —
**com a região**, senão aponta para `us-central1`, que está vazio, e
devolve sucesso à mesma:

```bash
firebase functions:artifacts:setpolicy --location=europe-west1 --days=3 --project=gym-sas
```

**5. O site por último**, quando tudo o resto já está de pé.

```bash
flutter build web --release --wasm -t lib/main_production.dart
```

```bash
node --check build/web/flutter_bootstrap.js
```

```bash
firebase deploy --only hosting --project=gym-sas
```

O `node --check` não é paranóia: o `flutter_bootstrap.js` deste projeto é
gerado a partir de `web/flutter_bootstrap.js` com substituição de marcas,
e já houve uma vez em que o resultado não era JavaScript válido.

**6. Na app, como Gestor**, abre **Gestão › Informação pública** e
preenche o que faltar — sobretudo a política de privacidade. E em
**Aulas/Horários**, "Gerar agora", para a vitrina ter mapa de aulas sem
esperar pelo cron das 03:00.

**7. Correr o `check-deploy` outra vez.** Verde é a definição de "está
publicado".

### O que o verificador não cobre

* **As regras do Storage.** Publicam-se no passo 1, mas não há forma de
  as distinguir das antigas de fora: os dois conjuntos recusam um
  anónimo, que é o único ângulo que um script sem sessão tem. Confirma-se
  a sério enviando uma foto de perfil pela app.
* **O que está por commitar.** O `firebase deploy` publica a árvore de
  trabalho, não o que está em git — publicar não protege de perder.
* **Aulas futuras para lá das 500 primeiras.** O limite existe porque
  isto se paga por leitura, mas o verificador passou a dizer quando
  trunca em vez de dar um ✓ sobre o que não viu. (A verificação dos
  exercícios tinha o mesmo defeito com um limite de 50 e um catálogo de
  63 — treze nunca eram olhados. Esse limite desapareceu: um catálogo é
  pequeno e isto corre raramente.)
* **Que o conteúdo das funções publicadas é o do código local.** A
  secção 1 compara **nomes**. Uma função cujo interior mudou continua a
  aparecer como publicada — foi o caso das mudanças de contenção desta
  ronda. Na dúvida, publica; `firebase deploy --only functions` é
  idempotente.

Sugestões abertas de fases anteriores continuam por decidir: revisitar
se o Instrutor deve poder criar/gerir as suas próprias séries (Fase
5); configurar a VAPID key/certificado APNs para as notificações push
entregarem de facto (Fase 6); decidir um fornecedor de SMS/email para
a recuperação de password self-service de membros (Fase 6); decidir se
a entidade `Room`/`Sala` deve existir (Fase 8); e se o âmbito por
modalidade do Instrutor (UC28) deve passar a ser uma restrição real em
vez de informativa.
