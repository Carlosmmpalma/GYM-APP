# Gym SaaS — Fase 0 (fundação do projeto)

Este projeto implementa a **Fase 0** do `Technical/guia-desenvolvimento.md`:
o esqueleto da aplicação, sem nenhuma feature de negócio ainda.

## O que está feito

- **Estrutura de camadas** (Platform Foundation §10): `lib/presentation`,
  `lib/domain`, `lib/application`, `lib/repositories`, `lib/infrastructure`,
  com um exemplo ponta-a-ponta (`PingResult` / `PingRepository` /
  `FirebasePingRepository` / `PingFirestoreUseCase` / `HelloWorldScreen`)
  que atravessa todas as camadas.
- **Riverpod** configurado (`lib/application/providers/firebase_providers.dart`),
  com o `environmentConfigProvider` sobrescrito no bootstrap consoante o
  ambiente.
- **Três ambientes**: `lib/main_development.dart`, `lib/main_staging.dart`,
  `lib/main_production.dart`, todos a chamar `lib/core/bootstrap/bootstrap.dart`.
  `lib/main.dart` (default) aponta para development.
- **Firebase Emulator Suite**: `firebase.json` (Firestore/Auth/Functions/Storage
  + UI na porta 4000), `firestore.rules` e `storage.rules` (deny-all por
  omissão, exceto a coleção de diagnóstico `_diagnostics/`),
  `firestore.indexes.json` vazio, `.firebaserc.example`.
- **Cloud Functions** — esqueleto mínimo em `firebase/functions/` (TypeScript,
  uma função `healthCheck` de diagnóstico).
- **CI** — `.github/workflows/ci.yml`: `flutter analyze` + `flutter test`
  + lint/build das Cloud Functions em cada push/PR para `main`.
- **Crashlytics** — dependência e wiring em `bootstrap.dart`
  (`runZonedGuarded` + `FlutterError.onError`), ativo fora de `kDebugMode`.
- **Testes**:
  - `test/domain/`, `test/application/`, `test/repositories/`,
    `test/presentation/` — unitários e de widget, usando fakes/mocks
    (`fake_cloud_firestore`), sem depender de rede.
  - `integration_test/emulator_smoke_test.dart` — o único teste que fala
    a sério com o Firebase Emulator Suite. É este que comprova o critério
    "Done" da Fase 0.

## O que NÃO está feito (e porquê)

Não tenho acesso a Flutter SDK, `pub.dev`, Firebase CLI nem à tua conta
Google Cloud/Firebase a partir deste ambiente (sandbox sem esses
domínios na allowlist de rede). Por isso:

1. **Nunca corri `flutter pub get`, `flutter analyze` nem `flutter test`
   sobre este código.** Escrevi-o com cuidado e a seguir os padrões atuais
   das packages (`flutter_riverpod` 2.5, `cloud_firestore` 5.x, etc.), mas
   isto **não está verificado por compilação** — a primeira coisa a fazer
   na tua máquina é `flutter pub get` seguido de `flutter analyze`.
2. **`android/` e `ios/` estão vazios.** Não corri `flutter create`, por
   isso faltam os projetos nativos (Gradle, Xcode, etc.). Depois de
   clonar isto para uma pasta com Flutter instalado:

   ```bash
   flutter create --org com.nxtperformancestudio --platforms=android,ios,web .
   ```

   Isto preenche `android/`, `ios/`, `web/` sem tocar em `lib/`, mas
   **pode sobrescrever** `analysis_options.yaml`, `.gitignore` e
   `test/widget_test.dart` (o `flutter create` cria um `widget_test.dart`
   default que não existe aqui, e os outros dois já existem — confirma o
   diff antes de aceitar).
3. **Nenhum Firebase Project real foi criado.** O ambiente de
   `development` usa um `projectId` `demo-gym-saas-dev` — o Firebase
   Emulator Suite trata qualquer `projectId` com prefixo `demo-` como
   totalmente local, sem tocar em nenhuma cloud real. Isto é suficiente
   para a Fase 0 correr sem criares nada na consola Firebase. Para
   staging/production, `firebase_options_staging.dart` e
   `firebase_options_production.dart` são placeholders que lançam
   `UnsupportedError` — substitui-os por `flutterfire configure` depois
   de criares os respetivos Firebase Projects.
4. **`integration_test/emulator_smoke_test.dart` nunca correu.** É o teste
   que efetivamente demonstra "app liga ao emulador e lê/escreve um
   documento" — precisa de um dispositivo/simulador real e do emulador a
   correr em paralelo, nenhum dos quais tenho aqui.

## Passos para correr localmente

```bash
# 1. Instalar dependências Flutter
flutter pub get

# 2. Gerar os projetos nativos (ver aviso acima sobre ficheiros existentes)
flutter create --org com.nxtperformancestudio --platforms=android,ios,web .

# 3. Instalar a Firebase CLI, se ainda não tiveres
npm install -g firebase-tools
firebase login

# 4. Copiar o ficheiro de projetos e ajustar staging/production
cp .firebaserc.example .firebaserc

# 5. Arrancar o Firebase Emulator Suite
firebase emulators:start

# 6. Noutro terminal, correr a app de development
flutter run -t lib/main_development.dart

# 7. Verificar lint e testes (o que a CI vai correr)
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# 8. Teste de integração real contra o emulador (precisa de um device/-d)
flutter test integration_test/emulator_smoke_test.dart -d <device-id>
```

## Critério "Done" da Fase 0

> app Flutter arranca, liga ao emulador local, e um hello world lê/escreve
> um documento de teste no Firestore emulado

O ecrã `HelloWorldScreen` (aberto por omissão em `main_development.dart`)
tem um botão "Escrever + ler no Firestore" que faz exatamente isto contra
o emulador local. Confirma visualmente ao correr o passo 6 acima, e depois
corre o passo 8 para teres isto como teste automatizado repetível.

## Próximo passo

Fase 1 do guia — Identidade, Tenant e isolamento (🔴 crítica): modelar
`tenants/{tenantId}`, `TenantContext`, Security Rules reais de isolamento
entre tenants, e sobretudo os **testes automatizados que tentam
ativamente invadir outro tenant** antes de avançar.
