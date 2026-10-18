import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/repositories/auth_repository.dart';
import 'package:gym_saas/presentation/widgets/logout_button.dart';
import 'package:mocktail/mocktail.dart';

class _AuthFalso extends Mock implements AuthRepository {}

/// Terminar sessão.
///
/// Antes disto, o `signOut` só existia no ecrã de conta bloqueada e no
/// estado de erro do `AuthGate`. Em uso normal nenhum dos três papéis
/// tinha saída — quem entrasse num telemóvel emprestado ficava lá.

Widget _app(AuthRepository auth, {required Set<Role> papeis}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      currentAppUserProvider.overrideWith(
        (ref) => Stream.value(
          AppUser(uid: 'u1', tenantId: 't1', roles: papeis),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Início'),
          actions: const [LogoutButton()],
        ),
      ),
    ),
  );
}

void main() {
  late _AuthFalso auth;

  setUp(() {
    auth = _AuthFalso();
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  testWidgets('pergunta antes, e "Ficar" não termina a sessão', (tester) async {
    // O botão é pequeno e fica ao lado de outros. Sem confirmação, um
    // toque errado punha um aluno fora da conta — e repor a password
    // dele obriga a passar pelo estúdio.
    await tester.pumpWidget(_app(auth, papeis: {Role.member}));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Terminar sessão?'), findsOneWidget);

    await tester.tap(find.text('Ficar'));
    await tester.pumpAndSettle();

    verifyNever(() => auth.signOut());
  });

  testWidgets('confirmar termina mesmo a sessão', (tester) async {
    await tester.pumpWidget(_app(auth, papeis: {Role.member}));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Terminar sessão'));
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
  });

  testWidgets('ao ALUNO diz que só o estúdio repõe a password', (tester) async {
    await tester.pumpWidget(_app(auth, papeis: {Role.member}));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('só o estúdio a pode repor'), findsOneWidget);
  });

  testWidgets('ao GESTOR não diz isso — ele repõe a sua sozinho',
      (tester) async {
    // O contraponto: sem ele, bastava mostrar sempre o aviso do aluno
    // para o teste de cima passar, e o staff levava com um medo que
    // não se lhe aplica.
    await tester.pumpWidget(_app(auth, papeis: {Role.manager}));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('só o estúdio a pode repor'), findsNothing);
    expect(find.textContaining('email e password'), findsOneWidget);
  });
}
