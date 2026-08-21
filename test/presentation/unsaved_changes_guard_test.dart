import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/presentation/widgets/unsaved_changes_guard.dart';

/// Fase 11 — o aviso de saída sem gravar.
///
/// Fácil de partir sem se dar por isso: o comportamento só se vê a
/// tentar sair, e um `canPop` mal ligado ou passa sempre ou nunca passa.
void main() {
  /// Um ecrã empilhado sobre outro, para haver de onde sair.
  Future<void> pumpGuarded(
    WidgetTester tester, {
    required bool Function() hasChanges,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UnsavedChangesGuard(
                      hasChanges: hasChanges,
                      child: Scaffold(
                        appBar: AppBar(title: const Text('Formulário')),
                        body: const Text('campos'),
                      ),
                    ),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Formulário'), findsOneWidget);
  }

  testWidgets('sem alterações, sai sem perguntar nada', (tester) async {
    await pumpGuarded(tester, hasChanges: () => false);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Um diálogo que aparecesse sempre seria ruído, e ruído ensina a
    // carregar em "sair" sem ler.
    expect(find.text('Sair sem gravar?'), findsNothing);
    expect(find.text('Formulário'), findsNothing);
  });

  testWidgets('com alterações, pergunta e "continuar a editar" fica',
      (tester) async {
    await pumpGuarded(tester, hasChanges: () => true);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Sair sem gravar?'), findsOneWidget);

    await tester.tap(find.text('Continuar a editar'));
    await tester.pumpAndSettle();

    // O ponto todo: não saiu, e o que estava escrito continua lá.
    expect(find.text('Formulário'), findsOneWidget);
  });

  testWidgets('com alterações, "sair sem gravar" sai mesmo', (tester) async {
    await pumpGuarded(tester, hasChanges: () => true);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair sem gravar'));
    await tester.pumpAndSettle();

    expect(find.text('Formulário'), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('lê hasChanges no momento de sair, não no build', (tester) async {
    // Se o guarda avaliasse `hasChanges` durante o build, um formulário
    // que começa limpo e é preenchido a seguir sairia sem avisar — que é
    // exatamente o caso que isto existe para apanhar.
    var dirty = false;
    await pumpGuarded(tester, hasChanges: () => dirty);

    dirty = true;
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Sair sem gravar?'), findsOneWidget);
  });
}
