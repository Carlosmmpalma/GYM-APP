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

## Fase 1 — Identidade, Tenant e isolamento 🔴 crítica, código escrito, **por verificar**

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

### O que NÃO fiz (mesma limitação da Fase 0: sem acesso a `npm`/Flutter/Firebase CLI aqui)

1. **Nada disto correu.** Nem `flutter analyze`/`flutter test` sobre o
   código novo, nem `npm install` em `firebase/functions`,
   `firebase/scripts` ou `firebase/tests`, nem os testes de isolamento
   contra o emulador a sério. Escrevi tudo com cuidado (verifiquei
   balanceamento de chaves/parênteses e que todos os imports apontam
   para ficheiros existentes), mas isso não substitui compilar e correr.
2. **`zod` é uma dependência nova** em `firebase/functions/package.json`
   — não commitada nenhuma lockfile atualizada, o `npm install` vai
   gerá-la.
3. A conta de Gestor semeada (`seed.mjs`) usa uma password fixa
   (`DevPass123!`) — só faz sentido contra o emulador local. Nunca
   correr este script contra um Firebase Project real.
4. **Sem `package-lock.json` commitado em `firebase/functions/`,** o job
   `functions` da CI (`.github/workflows/ci.yml`) vai falhar logo no
   passo de cache do `setup-node` — esse passo exige que o lockfile
   exista. Isto já era verdade desde a Fase 0 (nunca correu `npm
   install`); passo 1 abaixo resolve-o, mas **tens de commitar o
   `package-lock.json` gerado** para a CI passar a funcionar. O mesmo
   não se aplica a `firebase/scripts` e `firebase/tests` — esses jobs
   não usam cache do `setup-node`.

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

## Próximo passo

Fase 2 do guia — vertical slice de uma marcação ponta a ponta (🔴
crítica também): `createBooking`/`cancelBooking` transacionais, e o
teste de concorrência na última vaga.
