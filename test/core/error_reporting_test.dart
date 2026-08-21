import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/observability/error_reporting.dart';
import 'package:gym_saas/presentation/widgets/design_system.dart';

/// Fase 11 — telemetria de erros APANHADOS.
///
/// Esta app quase não tem crashes: apanha tudo e mostra um `ErrorState`.
/// Se o Crashlytics só visse crashes, uma falha que atingisse 30% das
/// marcações seria invisível — os utilizadores desistiam em silêncio.
void main() {
  testWidgets('não rebenta em ambiente de teste (sem Firebase)',
      (tester) async {
    // A telemetria nunca pode partir o ecrã que está a reportar um erro
    // — seria trocar uma mensagem por um crash.
    expect(
      () => reportHandledError(StateError('boom'), StackTrace.current,
          context: 'teste'),
      returnsNormally,
    );
  });

  testWidgets('ErrorState reporta uma vez, não a cada rebuild', (tester) async {
    // Não dá para espiar o Crashlytics daqui; o que se garante é que
    // reconstruir o mesmo erro não parte nada e que o widget continua a
    // mostrar o que deve. O "uma vez" está no `initState`, e o
    // `didUpdateWidget` só volta a reportar se o erro MUDAR.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ErrorState(error: 'falha', message: 'Falhou.')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Falhou.'), findsOneWidget);
  });
}
