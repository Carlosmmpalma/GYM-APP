import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme/app_theme.dart';
import 'package:gym_saas/presentation/widgets/async_action_button.dart';

Widget _app(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('dois toques rápidos correm a ação UMA vez', (tester) async {
    // O bug que isto existe para fechar. `start_workout_button` chamava
    // `startSession` sem guarda nenhuma: dois toques criavam dois
    // treinos para a mesma pessoa, e o segundo ficava aberto para
    // sempre porque o ecrã só mostra um.
    var corridas = 0;
    final completer = Completer<void>();

    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Começar',
      onPressed: () async {
        corridas++;
        await completer.future;
      },
    )));

    await tester.tap(find.text('Começar'));
    await tester.pump();
    // Segundo toque enquanto a primeira ainda corre.
    await tester.tap(find.text('Começar'), warnIfMissed: false);
    await tester.pump();

    expect(corridas, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('enquanto corre mostra progresso e desativa', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Guardar',
      onPressed: () => completer.future,
    )));

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Guardar'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('quando acaba bem, confirma NO botão e depois apaga-se',
      (tester) async {
    // A confirmação fica onde o dedo tocou. É isto que permite não
    // mostrar um SnackBar por cima de uma coisa que o ecrã já mostra —
    // e a app tinha 59 confirmações desse tipo.
    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Guardar',
      onPressed: () async {},
    )));

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.check), findsOneWidget);

    // Um visto permanente deixaria de significar "acabou agora".
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('volta a ficar utilizável depois de FALHAR', (tester) async {
    // O `finally` é a linha que mais se esquece ao escrever esta guarda
    // à mão — e esquecê-la deixa o botão morto para sempre, com o ecrã
    // a parecer bloqueado sem dizer porquê.
    var corridas = 0;
    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Enviar',
      onPressed: () async {
        corridas++;
        throw Exception('falhou');
      },
    )));

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    expect(corridas, 2);
  });

  testWidgets('um erro pode ir para outro sítio que não o SnackBar',
      (tester) async {
    // Quem tem um banner no formulário tem um sítio melhor: o erro fica
    // à vista até ser resolvido, em vez de desaparecer em quatro
    // segundos.
    Object? apanhado;
    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Enviar',
      onError: (e) => apanhado = e,
      onPressed: () async => throw Exception('falhou'),
    )));

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(apanhado, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('desativado por fora nunca corre', (tester) async {
    var corridas = 0;
    await tester.pumpWidget(_app(AsyncActionButton(
      label: 'Guardar',
      enabled: false,
      onPressed: () async => corridas++,
    )));

    await tester.tap(find.text('Guardar'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(corridas, 0);
  });
}
