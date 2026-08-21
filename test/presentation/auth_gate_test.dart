import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/payment_providers.dart';
import 'package:gym_saas/application/providers/privacy_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/widgets/auth_gate.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

// Fase 7 — `HomeScreen` ganhou um 3º tab (`FreeTrainingScreen`); como
// os três tabs vivem num `IndexedStack`, TODOS constroem mesmo só o
// primeiro estar visível, e `FreeTrainingScreen` formata uma data logo
// no primeiro build (cabeçalho da semana) — precisa do locale.
class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

/// Testa só a decisão de routing do AuthGate — os ecrãs individuais
/// (LoginScreen, ForcePasswordChangeScreen, HelloWorldScreen) já têm
/// os seus próprios testes/serão testados à parte quando ganharem lógica
/// própria maior.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  testWidgets('sem sessão mostra o ecrã de login (UC01)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          currentAppUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nº de sócio ou email'), findsOneWidget);
  });

  testWidgets('sessão com password temporária força a troca (UC22)',
      (tester) async {
    const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
          hasTemporaryPasswordProvider.overrideWith((ref) async => true),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Define a tua nova password'), findsOneWidget);
  });

  testWidgets('sessão normal mostra o ecrã principal', (tester) async {
    const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider
              .overrideWithValue(EnvironmentConfig.development),
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
          hasTemporaryPasswordProvider.overrideWith((ref) async => false),
          firestoreProvider.overrideWithValue(fakeFirestore),
          functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();

    // Fase 10 — o separador inicial de um Aluno passou a ser "Início"
    // (`MemberHomeScreen`), não "Marcar treino". "Início" aparece duas
    // vezes de propósito (título da AppBar + rótulo do destino na barra
    // inferior); "Marcar treino" deixou de servir como asserção porque
    // também é o rótulo de um card de atalho do dashboard — passaria
    // pela razão errada.
    expect(find.text('Início'), findsNWidgets(2));
    expect(find.text('Marcar'), findsOneWidget);
    expect(find.text('Livre'), findsOneWidget);
    expect(find.text('Marcações'), findsOneWidget);
  });

  group('shell por papel (Fase 10)', () {
    testWidgets(
        'Gestor abre em "Visão global" e NÃO vê separadores de marcação',
        (tester) async {
      const manager = AppUser(uid: 'm1', tenantId: 't1', roles: {Role.manager});
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(manager)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
            firestoreProvider.overrideWithValue(fakeFirestore),
            functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      // Título + destino da barra inferior.
      expect(find.text('Visão global'), findsNWidgets(2));
      expect(find.text('Gestão'), findsOneWidget);

      // O pedido explícito: um Gestor não tem nada que ver ecrãs de
      // marcação de treino.
      expect(find.text('Marcar'), findsNothing);
      expect(find.text('Livre'), findsNothing);
      expect(find.text('Marcações'), findsNothing);
    });

    testWidgets('Gestor sem conta de membro não vê o separador "Treino"',
        (tester) async {
      const manager = AppUser(uid: 'm1', tenantId: 't1', roles: {Role.manager});
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(manager)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
            firestoreProvider.overrideWithValue(fakeFirestore),
            functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Treino'), findsNothing);
    });
  });

  group('consentimento RGPD (Fase 11)', () {
    testWidgets('membro sem consentimento registado vai para o ConsentScreen',
        (tester) async {
      // O ConsentScreen é mais alto do que os 800x600 por omissão do
      // ambiente de teste (é um aviso de privacidade inteiro): sem
      // aumentar a superfície, o botão "Continuar" fica fora do
      // viewport e o finder não o encontra.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            needsConsentProvider.overrideWith((ref) async => true),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OS TEUS DADOS'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      // Não entra na app enquanto não decidir.
      expect(find.text('Início'), findsNothing);
    });

    testWidgets('a autorização de dados de saúde começa DESLIGADA',
        (tester) async {
      // O ConsentScreen é mais alto do que os 800x600 por omissão do
      // ambiente de teste (é um aviso de privacidade inteiro): sem
      // aumentar a superfície, o botão "Continuar" fica fora do
      // viewport e o finder não o encontra.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Artigo 7.º, n.º 4 — o consentimento não é livre se vier
      // pré-dado, nem se for condição para usar a app. Tem de ser um
      // ato do titular, e "Continuar" tem de funcionar sem ele.
      const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            needsConsentProvider.overrideWith((ref) async => true),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchWidget.value, isFalse);
    });

    testWidgets('com consentimento em dia, entra na app normalmente',
        (tester) async {
      const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            needsConsentProvider.overrideWith((ref) async => false),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
            firestoreProvider.overrideWithValue(fakeFirestore),
            functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OS TEUS DADOS'), findsNothing);
      expect(find.text('Início'), findsNWidgets(2));
    });
  });

  group('mensalidade em atraso (Fase 9, UC01 fechado)', () {
    testWidgets('bloqueia o login e mostra o ecrã de conta inativa',
        (tester) async {
      const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => true),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Mensalidade em atraso'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
      // Nunca os dois ao mesmo tempo — bloqueado é bloqueado.
      expect(find.text('Marcar treino'), findsNothing);
    });

    testWidgets('sem bloqueio, mostra o ecrã principal normalmente',
        (tester) async {
      const appUser = AppUser(uid: 'u1', tenantId: 't1', roles: {Role.member});
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentConfigProvider
                .overrideWithValue(EnvironmentConfig.development),
            tenantAppConfigProvider
                .overrideWithValue(TenantAppConfig.development),
            currentAppUserProvider.overrideWith((ref) => Stream.value(appUser)),
            hasTemporaryPasswordProvider.overrideWith((ref) async => false),
            isBlockedForOverduePaymentProvider
                .overrideWith((ref) async => false),
            firestoreProvider.overrideWithValue(fakeFirestore),
            functionsProvider.overrideWithValue(_MockFirebaseFunctions()),
          ],
          child: const MaterialApp(home: AuthGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marcar treino'), findsOneWidget);
      expect(find.textContaining('Mensalidade em atraso'), findsNothing);
    });
  });
}
