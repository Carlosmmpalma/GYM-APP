import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/environment.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/widgets/auth_gate.dart';

/// Testa só a decisão de routing do AuthGate — os ecrãs individuais
/// (LoginScreen, ForcePasswordChangeScreen, HelloWorldScreen) já têm
/// os seus próprios testes/serão testados à parte quando ganharem lógica
/// própria maior.
void main() {
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
        ],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pumpAndSettle();

    // "Marcar treino" é o título do AppBar (tab inicial); os dois
    // destinos da bottom nav estão sempre visíveis, independentemente
    // do tab ativo.
    expect(find.text('Marcar treino'), findsOneWidget);
    expect(find.text('Marcar'), findsOneWidget);
    expect(find.text('Marcações'), findsOneWidget);
  });
}
