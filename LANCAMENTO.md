# Checklist de lançamento

Tudo o que **só tu podes fazer** — envolve billing, consolas, contas
Google e decisões que não são de código. Por ordem de dependência: cada
secção assume as anteriores feitas.

O que já está feito do lado do código está no fim, para saberes o que
não precisas de repetir.

---

## 0. Antes de tudo — a parte legal

Não é código e é o único item que te pode impedir de operar, não só de
lançar bem. A app trata **dados de saúde** (pressão arterial,
percentagem de massa gorda, gordura visceral, metabolismo basal), que o
artigo 9.º do RGPD coloca numa categoria especial.

> **Há um dossier completo em [`legal/`](legal/README.md)** — nove
> documentos redigidos a partir do que o código faz, para o advogado
> rever em vez de partir do zero. Os pontos de decisão jurídica estão
> marcados [ADVOGADO].

- [ ] **Política de privacidade revista por alguém que perceba do
  assunto.** O texto que a app mostra hoje está em
  `lib/presentation/screens/consent_screen.dart` (`_PolicySummary`) e
  descreve fielmente o que o código faz — serve de base, não de versão
  final. Se o texto mudar de forma relevante, sobe
  `kPrivacyPolicyVersion` em `lib/domain/entities/consent.dart`: isso
  volta a pedir aceitação a toda a gente no arranque seguinte.
- [ ] **Registo de atividades de tratamento** (artigo 30.º). Obrigatório
  mesmo para uma empresa pequena quando se tratam dados do artigo 9.º.
- [ ] **Contrato de subcontratação com a Google** (artigo 28.º). A
  Google disponibiliza-o; é aceite na consola quando ativas o projeto.
- [ ] Decidir o **prazo de conservação** dos dados de um aluno que saia
  do ginásio. O código dá-te a ferramenta de apagamento; quando a usar é
  política tua.
- [ ] Se um dia tiveres alunos menores de idade: o consentimento é dos
  pais e o ecrã atual não trata disso.

---

## 1. Criar o projeto Firebase de produção

- [ ] Criar o projeto na [Firebase Console](https://console.firebase.google.com).
- [ ] **Ativar o plano Blaze.** As Cloud Functions v2 exigem-no — sem
  isto nada funciona. Define já um **orçamento com alertas** (ver §6).
- [ ] Escolher a região **`europe-west1`** (Bélgica) para Firestore.
  Duas razões: latência a partir de Portugal, e manter dados pessoais na
  UE evita a conversa toda sobre transferências internacionais. **A
  região do Firestore não se muda depois de criada** — é uma decisão
  definitiva.
- [ ] Ativar Authentication (Email/Password), Firestore, Storage,
  Cloud Messaging e Crashlytics.

> **As Cloud Functions já estão fixadas em `europe-west1`** no código
> (`setGlobalOptions` em `firebase/functions/src/index.ts`, e
> `kFunctionsRegion` do lado da app). Escolhe a MESMA região para o
> Firestore. Uma função já implantada não muda de região — migrar obriga
> a apagar e recriar.

Depois, no projeto:

```bash
flutterfire configure --project=<id-do-projeto> --out=lib/infrastructure/config/firebase_options_production.dart
```

- [ ] Substituir `SUBSTITUIR-pelo-id-real-do-projeto-production` em
  `.firebaserc`.
- [ ] A classe gerada tem de se chamar `ProductionFirebaseOptions` (o
  `flutterfire` gera `DefaultFirebaseOptions` — renomeia, é o nome que o
  `bootstrap.dart` importa).
- [ ] Repetir para staging, se quiseres um ambiente intermédio. Não é
  obrigatório para lançar com um único estúdio.

---

## 2. Deploy

Pela primeira vez, e por esta ordem:

```bash
firebase deploy --project=production --only firestore:rules,firestore:indexes
```

```bash
firebase deploy --project=production --only storage
```

```bash
firebase deploy --project=production --only functions
```

```bash
firebase deploy --project=production --only hosting
```

> O `firebase.json` ganhou a secção de **hosting** (não existia): serve
> o `build/web` como SPA e traz os cabeçalhos de cache certos — o
> CanvasKit com um ano, o `main.dart.js` a revalidar (devolve `304` e
> zero bytes quando a app não mudou), e o `index.html`/service worker
> sem cache.

> ⚠️ **A build tem de ser a de produção — com `-t`.** `flutter build
> web` sem mais nada compila `lib/main.dart`, que aponta para o
> ambiente de **development**: publicavas uma app com aspeto normal a
> escrever na base de dados errada. O comando certo, antes de cada
> deploy de hosting:
>
> ```bash
> flutter build web --release -t lib/main_production.dart
> ```
>
> Como rede de segurança, tudo o que não é produção passou a mostrar
> uma **fita laranja no canto** com o nome do ambiente. Se vires
> "DEVELOPMENT" no site do estúdio, foi publicada a build errada.

### Aplicações móveis

Mesma regra, mesmo `-t`:

```bash
flutter build appbundle --release -t lib/main_production.dart
```

```bash
flutter build ipa --release -t lib/main_production.dart
```

Os índices demoram alguns minutos a construir; as funções que os usam
falham até estarem prontos. Confirma na consola antes de continuar.

- [ ] **Criar o primeiro Gestor.** Não há forma de o fazer pela app
  (criar staff exige já ser Gestor — é intencional), e a **consola do
  Firebase não sabe atribuir custom claims**: sem `tenantId` e `roles`
  no token, a conta autentica-se e fica presa num estado que nenhum ecrã
  trata. Ou seja, sem este passo não se entra na app acabada de
  publicar.

  Há um script para isso, e cria tudo o que é preciso (documento do
  tenant com o fuso horário, conta de Auth, claims e documento de
  staff):

  ```bash
  gcloud auth application-default login
  ```

  ```bash
  node firebase/scripts/create-first-manager.mjs --project=<id-do-projeto> --tenant=nxt_performance_studio --name="Leo Gil" --email=leo@exemplo.pt --password='UmaPasswordForte123!' --yes
  ```

  Sem `--yes` ele diz o que ia fazer e não faz nada — a rede de
  segurança contra correr isto no projeto errado. Testado contra o
  emulador; correr duas vezes é seguro (não duplica nada).

  A partir daqui, todos os outros utilizadores criam-se pela app.

---

## 3. App Check

O código já ativa o App Check no arranque (`bootstrap.dart`). Falta o
lado do servidor:

- [ ] **Android**: registar a app com **Play Integrity** na consola
  (Firebase → App Check).
- [ ] **iOS**: registar com **App Attest**.
- [ ] **Web**: criar uma chave **reCAPTCHA v3**, registá-la na consola, e
  pôr a *site key* em `EnvironmentConfig.production.recaptchaSiteKey`
  (`lib/core/config/environment.dart`). Sem ela a web usa o debug
  provider, que não serve em produção.
- [ ] Correr **uma ou duas semanas em modo monitorização** antes de
  ativar o *enforcement*. A consola mostra a percentagem de pedidos
  verificados; se ligares o enforcement cedo demais, bloqueias
  utilizadores reais com dispositivos que não conseguem atestar.
- [ ] Só depois: ativar enforcement para Cloud Functions, Firestore e
  Storage.

---

## 4. Backups

Hoje não existem. Um `delete` errado é irreversível.

- [ ] Ativar **PITR** (point-in-time recovery) no Firestore. Dá 7 dias
  de recuperação a qualquer instante e ativa-se com um clique.
- [ ] Agendar **exports diários** para um bucket do Cloud Storage
  (Firestore → Backups → agendar). Sete dias de PITR não chegam para
  descobrir uma corrupção antiga.
- [ ] Testar um restauro **uma vez**, antes de precisares dele a sério.
  Um backup nunca testado não é um backup.

---

## 5. Notificações push

O código envia notificações em três eventos (cancelamento de sessão,
remoção de um membro de uma sessão, desativação de instrutor). Nunca
foram entregues de verdade — falta a configuração:

- [ ] **iOS**: carregar a chave **APNs** na Firebase Console. Sem isto
  nenhuma notificação chega a um iPhone.
- [ ] **Web**: gerar a **VAPID key** e ligá-la à app.
- [ ] Testar num dispositivo real de cada plataforma.

Desde a última ronda há mais dois eventos automáticos a depender disto,
e são os que os alunos vão notar em primeiro lugar:

- **Lembrete antes da aula** (`sendSessionReminders`, de hora a hora).
  Antecedência configurável em Gestão › Definições — 12 horas por
  omissão, "0" desliga. Existe para reduzir faltas: pede o cancelamento
  a quem já não pode vir, e esse cancelamento liberta o lugar para a
  lista de espera.
- **Promoção da lista de espera** — quem sobe da fila para a aula é
  avisado. Sem push, fica com o lugar na mesma (a marcação é real e
  aparece em "Marcações"), mas só dá por isso ao abrir a app.

- [ ] **Cloud Scheduler** tem de estar ativo no projeto: as duas funções
  agendadas (`generateRecurringOccurrences`, diária, e
  `sendSessionReminders`, de hora a hora) são criadas no deploy mas o
  serviço faz parte do Blaze. Confirma na consola que ambas aparecem
  agendadas depois do primeiro `firebase deploy --only functions`.

---

## 6. Custos

- [ ] Definir um **orçamento com alertas** no Google Cloud Billing (50%,
  90%, 100%). É a rede de segurança contra um ciclo infinito num cliente.
- [ ] Ver a consola nos primeiros dias. Firestore cobra por **leitura de
  documento**; a app foi afinada para uma sessão de aluno custar ~140
  leituras (ver "Onde está o dinheiro" no README).
- [ ] **Não ligar `minInstances`** nas Cloud Functions. Tira o arranque
  a frio e passa a custar dinheiro 24 horas por dia, mesmo sem ninguém
  a usar a app. `maxInstances: 10` já está definido e é o que interessa.
- [ ] **Vigiar o tráfego do Storage**, não o do Firestore. É a rubrica
  que pode crescer a sério: cada aluno que abre um exercício descarrega
  o vídeo inteiro. Os vídeos já sobem com 30 dias de cache (a segunda
  visualização no mesmo dispositivo não custa nada), mas a primeira
  paga-se sempre — e é por isso que o tamanho do ficheiro conta.
- [ ] Se algum mês surpreender, olhar primeiro para **Storage → tráfego
  de saída** e só depois para o Firestore.

---

## 7. Publicação nas lojas

- [ ] Contas de developer: Google Play (25 USD, uma vez) e Apple
  Developer (99 USD/ano).
- [ ] Assinatura das builds: keystore Android e certificados iOS.
- [ ] **Declaração de privacidade nas lojas.** Ambas perguntam que dados
  recolhes; a resposta tem de incluir dados de saúde e bater certo com a
  política de privacidade.
- [ ] O `applicationId` Android e o `bundleId` iOS são definitivos depois
  da primeira publicação — confirma-os antes.

---

## 8. Antes de abrir a alunos reais

- [ ] Correr a suite de isolamento entre tenants **contra o projeto real**,
  não só contra o emulador.
- [ ] **Confirmar que os índices ficaram construídos** antes de abrir a
  app a alguém. O emulador NÃO exige índices compostos — uma query sem
  índice funciona em testes e falha em produção com "The query requires
  an index". Os ecrãs que dependem disso: evolução da carga
  (`loadHistory`), "tens um treino a decorrer?" (`workoutSessions`,
  usado no ecrã inicial de qualquer aluno), horário, marcações,
  mensalidades e lembretes. Na consola: Firestore → Índices, todos em
  "Ativado".
- [ ] Entrar como Aluno, como Instrutor e como Gestor, e percorrer um
  ciclo completo: marcar, cancelar, marcar presença, registar uma
  avaliação, lançar uma mensalidade.
- [ ] Confirmar que o consentimento aparece no primeiro arranque e que
  recusar dados de saúde **não** impede marcar treinos.
- [ ] **Registar presenças durante uma ou duas semanas antes de olhar
  para o painel de retenção.** Ele lê presenças e faltas; sem ninguém a
  marcá-las, mostra toda a gente "em risco" e a taxa de faltas a "—".
  Não é um erro do painel — é a única resposta honesta a dados que não
  existem, e o próprio ecrã o diz.
- [ ] Confirmar que a faixa vermelha "Running in emulator mode"
  desapareceu (é injetada pelo SDK só em modo emulador — se ainda
  aparecer, a build está a apontar para o sítio errado).

---

## O que ficou por fazer, e é decisão tua

Nenhum destes bloqueia o lançamento, mas nenhum se resolve sozinho:

| | Estado |
|---|---|
| **Recuperação de password self-service** | O Gestor já repõe a password de qualquer pessoa dentro da app (entrega-a em mão). O que falta é o aluno resolver isto sozinho às 23h de domingo — precisa de um fornecedor SMS/email |
| **Pagamentos** | É registo manual do que foi pago, não cobrança. Decisão da Fase 9 |
| **Lembretes de sessão** | O UC11 previa avisos antes da aula; só existem notificações de cancelamento |
| **Multi-tenant a sério** | O `tenantId` é fixo por build. Com um segundo estúdio, isto precisa de resolução por subdomínio ou config remota |

---

## O que já está feito (não repetir)

- **RGPD em código**: consentimento explícito para dados de saúde,
  aplicado pelas Security Rules e não só pela UI; registo com timestamp
  do servidor e histórico append-only; exportação (artigos 15.º/20.º);
  apagamento (artigo 17.º) com retenção fiscal dos registos de
  pagamento. 10 testes contra o emulador.
- **App Check** inicializado no arranque, com debug providers em
  desenvolvimento e falha aberta se o dispositivo não conseguir atestar.
- **Poderes do Gestor**: repor passwords, cancelar/pausar/reativar
  subscrições e promover/despromover staff — sem precisar de um
  developer. 13 testes contra o emulador.
- **Rate limiting** em 14 funções sensíveis (marcações, criação de
  utilizadores, notificações, exportação, apagamento).
- **Sem endpoints abertos**: o `healthCheck` sem autenticação e a
  coleção `_diagnostics` com `allow read, write: if true` foram
  removidos.
- **Ícone e nome** em Android, iOS e web.
- Verificado: `dart format` limpo, `flutter analyze --fatal-infos` sem
  problemas, **209 testes Flutter**, **173 contra o Emulator Suite**,
  build e lint das Functions, build web de produção a compilar.
