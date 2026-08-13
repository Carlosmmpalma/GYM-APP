import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/presentation/screens/login_screen.dart';
import 'package:gym_saas/repositories/auth_repository.dart';

class _FakeAuthRepository implements AuthRepository {
  String? lastMemberNumber;
  String? lastPassword;
  bool throwInvalidCredentials = false;

  @override
  Future<void> signInWithMemberNumber({
    required String tenantId,
    required String memberNumber,
    required String password,
  }) async {
    lastMemberNumber = memberNumber;
    lastPassword = password;
    if (throwInvalidCredentials) {
      throw const InvalidCredentialsException();
    }
  }

  @override
  Stream<AppUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

void main() {
  testWidgets(
      'submeter vazio mostra erros de validação sem chamar o repository',
      (tester) async {
    final authRepo = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Introduz o teu nº de sócio'), findsOneWidget);
    expect(find.text('Introduz a tua password'), findsOneWidget);
    expect(authRepo.lastMemberNumber, isNull);
  });

  testWidgets(
      'preenchido corretamente chama o repository com os valores certos',
      (tester) async {
    final authRepo = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), '000123');
    await tester.enterText(find.byType(TextFormField).at(1), 'segredo123');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(authRepo.lastMemberNumber, '000123');
    expect(authRepo.lastPassword, 'segredo123');
  });

  testWidgets('credenciais inválidas mostram mensagem genérica (UC01)',
      (tester) async {
    final authRepo = _FakeAuthRepository()..throwInvalidCredentials = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tenantAppConfigProvider
              .overrideWithValue(TenantAppConfig.development),
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), '999999');
    await tester.enterText(find.byType(TextFormField).at(1), 'errada');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Número de sócio ou password inválidos.'), findsOneWidget);
  });
}
