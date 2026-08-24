import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/utils/offline_write.dart';

/// Com a cache offline ligada, o `Future` de uma escrita no Firestore
/// só completa quando o SERVIDOR confirma. Num ginásio com má rede,
/// isso é um botão a rodar para sempre — e alguém a tocar outra vez,
/// convencido de que não funcionou.
void main() {
  test('escrita confirmada devolve confirmed', () async {
    final outcome = await writeOrQueue(Future<void>.value());
    expect(outcome, WriteOutcome.confirmed);
  });

  test('escrita que não responde a tempo conta como em fila', () async {
    // Nunca completa — é exatamente o que acontece sem ligação.
    final pending = Completer<void>();

    final outcome = await writeOrQueue(
      pending.future,
      timeout: const Duration(milliseconds: 50),
    );

    expect(outcome, WriteOutcome.queued);
    expect(pending.isCompleted, isFalse,
        reason: 'desistir de esperar não pode cancelar a escrita');
  });

  test('um erro tardio não fica por tratar', () async {
    // O caso perigoso: desistimos de esperar e, mais tarde, a escrita
    // falha (as Rules recusam quando o pedido finalmente chega). Sem
    // ninguém a apanhar esse erro, ele rebentava como erro não tratado
    // num sítio sem relação nenhuma com o que se estava a fazer.
    final pending = Completer<void>();

    final outcome = await writeOrQueue(
      pending.future,
      timeout: const Duration(milliseconds: 50),
    );
    expect(outcome, WriteOutcome.queued);

    pending.completeError(StateError('permission-denied'));
    // Se o erro não estivesse tratado, o teste falhava aqui com um
    // erro assíncrono por apanhar.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('um erro imediato continua a subir para quem chamou', () async {
    // Desistir de esperar é uma coisa; engolir uma falha que aconteceu
    // à frente do utilizador é outra. Se as Rules recusam a escrita
    // enquanto a pessoa espera, ela tem de saber — dizer "guardado"
    // seria mentira.
    await expectLater(
      writeOrQueue(Future<void>.error(StateError('recusado'))),
      throwsStateError,
    );
  });

  test('a mensagem diz a verdade sobre o que aconteceu', () {
    expect(
      writeOutcomeMessage(WriteOutcome.confirmed, confirmed: 'Guardado.'),
      'Guardado.',
    );
    expect(
      writeOutcomeMessage(WriteOutcome.queued, confirmed: 'Guardado.'),
      contains('ligação'),
    );
  });
}
