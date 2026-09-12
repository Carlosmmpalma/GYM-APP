import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/presentation/widgets/time_range_field.dart';

/// O campo que substituiu "Duração (minutos)".
///
/// O `showTimePicker` é do sistema e não se conduz num teste de widget;
/// o que se prende aqui é tudo o resto — os atalhos, a duração
/// mostrada, e o aviso quando as horas estão ao contrário.
void main() {
  Widget host({
    required TimeOfDay start,
    required TimeOfDay end,
    required void Function(TimeOfDay, TimeOfDay) onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TimeRangeField(start: start, end: end, onChanged: onChanged),
      ),
    );
  }

  testWidgets('mostra a duração ao lado do fim', (tester) async {
    // É a informação que o campo de minutos dava de graça e que um
    // relógio sozinho perderia.
    await tester.pumpWidget(host(
      start: const TimeOfDay(hour: 18, minute: 0),
      end: const TimeOfDay(hour: 19, minute: 30),
      onChanged: (_, __) {},
    ));

    expect(find.text('1 h 30'), findsWidgets);
  });

  testWidgets('um atalho define o fim a partir do início', (tester) async {
    TimeOfDay? newStart;
    TimeOfDay? newEnd;
    await tester.pumpWidget(host(
      start: const TimeOfDay(hour: 18, minute: 0),
      end: const TimeOfDay(hour: 19, minute: 0),
      onChanged: (s, e) {
        newStart = s;
        newEnd = e;
      },
    ));

    await tester.tap(find.widgetWithText(ChoiceChip, '45 min'));
    await tester.pumpAndSettle();

    expect(newStart, const TimeOfDay(hour: 18, minute: 0));
    expect(newEnd, const TimeOfDay(hour: 18, minute: 45));
  });

  testWidgets('o atalho da duração atual aparece selecionado', (tester) async {
    await tester.pumpWidget(host(
      start: const TimeOfDay(hour: 18, minute: 0),
      end: const TimeOfDay(hour: 19, minute: 0),
      onChanged: (_, __) {},
    ));

    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '1 h'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('horas ao contrário são assinaladas, não escondidas',
      (tester) async {
    // O caso que chegou a produção no treino livre: 08:10 às 08:00.
    await tester.pumpWidget(host(
      start: const TimeOfDay(hour: 8, minute: 10),
      end: const TimeOfDay(hour: 8, minute: 0),
      onChanged: (_, __) {},
    ));

    expect(find.textContaining('depois da de início'), findsOneWidget);
    // E não inventa uma duração para o que não é um intervalo.
    expect(find.text('—'), findsNothing);
  });
}
