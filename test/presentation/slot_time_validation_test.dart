import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/presentation/screens/manage_free_training_screen.dart';

/// Em produção apareceram blocos de treino livre das **08:10 às 08:00**.
/// Um seletor de hora não impede ninguém de escolher ao contrário, e
/// nenhum dos dois diálogos (criar e editar) estava a verificar.
///
/// O que fica preso aqui é a decisão. A ligação aos botões não dá para
/// cobrir num teste de widget sem reimplementar o `showTimePicker` do
/// sistema — assinalado, não escondido.
void main() {
  test('um fim depois do início é válido', () {
    expect(
      endsAfterStart(const TimeOfDay(hour: 6, minute: 0),
          const TimeOfDay(hour: 8, minute: 0)),
      isTrue,
    );
  });

  test('o caso real: 08:10 às 08:00 é recusado', () {
    expect(
      endsAfterStart(const TimeOfDay(hour: 8, minute: 10),
          const TimeOfDay(hour: 8, minute: 0)),
      isFalse,
    );
  });

  test('um bloco de duração zero também não serve', () {
    expect(
      endsAfterStart(const TimeOfDay(hour: 7, minute: 30),
          const TimeOfDay(hour: 7, minute: 30)),
      isFalse,
    );
  });

  test('minutos contam, não só a hora', () {
    expect(
      endsAfterStart(const TimeOfDay(hour: 7, minute: 0),
          const TimeOfDay(hour: 7, minute: 1)),
      isTrue,
    );
  });
}
