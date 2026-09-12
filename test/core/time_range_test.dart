import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/utils/time_range.dart';

/// As contas por trás de "das seis às sete" — que substituíram um campo
/// de texto a pedir a duração em minutos.
void main() {
  group('endsAfterStart', () {
    test('um fim depois do início é válido', () {
      expect(
        endsAfterStart(const TimeOfDay(hour: 18, minute: 0),
            const TimeOfDay(hour: 19, minute: 0)),
        isTrue,
      );
    });

    test('o caso real: 08:10 às 08:00 é recusado', () {
      // Chegaram a existir blocos assim em produção, porque nada
      // verificava.
      expect(
        endsAfterStart(const TimeOfDay(hour: 8, minute: 10),
            const TimeOfDay(hour: 8, minute: 0)),
        isFalse,
      );
    });

    test('duração zero não serve', () {
      expect(
        endsAfterStart(const TimeOfDay(hour: 7, minute: 30),
            const TimeOfDay(hour: 7, minute: 30)),
        isFalse,
      );
    });

    test('não deixa atravessar a meia-noite', () {
      // Deliberado: uma aula das 23:00 às 00:30 não é um caso real, e
      // aceitá-la obrigava a distinguir "acaba amanhã" de "escrevi ao
      // contrário" — que é o engano que isto apanha.
      expect(
        endsAfterStart(const TimeOfDay(hour: 23, minute: 0),
            const TimeOfDay(hour: 0, minute: 30)),
        isFalse,
      );
    });
  });

  group('durationInMinutes', () {
    test('conta os minutos entre as duas horas', () {
      expect(
        durationInMinutes(const TimeOfDay(hour: 18, minute: 0),
            const TimeOfDay(hour: 19, minute: 30)),
        90,
      );
    });

    test('atravessa a hora corretamente', () {
      expect(
        durationInMinutes(const TimeOfDay(hour: 18, minute: 45),
            const TimeOfDay(hour: 19, minute: 15)),
        30,
      );
    });
  });

  group('addMinutes', () {
    test('soma dentro do dia', () {
      expect(
        addMinutes(const TimeOfDay(hour: 18, minute: 0), 90),
        const TimeOfDay(hour: 19, minute: 30),
      );
    });

    test('encosta ao fim do dia em vez de dar a volta', () {
      // Sem o limite, escolher 23:30 e tocar em "1 h 30" devolvia
      // 01:00 — uma hora de madrugada que ninguém pediu, e que a
      // validação depois recusava sem explicar de onde vinha.
      expect(
        addMinutes(const TimeOfDay(hour: 23, minute: 30), 90),
        const TimeOfDay(hour: 23, minute: 59),
      );
    });
  });

  group('formatDuration', () {
    test('escreve como as pessoas dizem', () {
      expect(formatDuration(45), '45 min');
      expect(formatDuration(60), '1 h');
      expect(formatDuration(90), '1 h 30');
      expect(formatDuration(120), '2 h');
      expect(formatDuration(135), '2 h 15');
    });

    test('uma duração impossível não finge ser um número', () {
      expect(formatDuration(0), '—');
      expect(formatDuration(-30), '—');
    });
  });
}
