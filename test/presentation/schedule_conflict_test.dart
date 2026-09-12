import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/session_series.dart';
import 'package:gym_saas/presentation/screens/create_series_screen.dart';

/// Reproduz o horário REAL de produção (25/08/2026) para separar
/// "o aviso está errado" de "o aviso está certo e o horário é que está
/// cheio".
///
/// Só existe um instrutor no estúdio, e é dele que são as quatro
/// séries. Qualquer aula nova é criada contra este calendário.
void main() {
  const instrutor = 'instrutor_teste';

  SessionSeries serie({
    required String id,
    required int dayOfWeek,
    required String startTime,
    required int durationMinutes,
  }) {
    return SessionSeries(
      id: id,
      serviceId: 'svc_aulas_grupo',
      instructorId: instrutor,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      durationMinutes: durationMinutes,
      capacity: 6,
      startDate: DateTime(2026, 8, 24),
      preAssignedMemberIds: const [],
      status: SessionSeriesStatus.active,
    );
  }

  // Exatamente o que está em produção.
  final horarioReal = [
    serie(id: 's1', dayOfWeek: 1, startTime: '09:00', durationMinutes: 60),
    serie(id: 's2', dayOfWeek: 1, startTime: '18:00', durationMinutes: 60),
    serie(id: 's3', dayOfWeek: 1, startTime: '18:00', durationMinutes: 60),
    serie(id: 's4', dayOfWeek: 3, startTime: '21:00', durationMinutes: 90),
  ];

  List<String> conflito({
    required int dayOfWeek,
    required int startMinutes,
    required int endMinutes,
  }) {
    return findScheduleConflicts(
      recurring: true,
      instructorId: instrutor,
      dayOfWeek: dayOfWeek,
      date: DateTime(2026, 8, 31),
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      series: horarioReal,
      occurrences: const [],
      servicesById: const {},
    );
  }

  group('o aviso dispara onde deve', () {
    test('segunda às 18:00 bate com as DUAS séries que lá estão', () {
      // O estúdio tem mesmo duas séries iguais nesta hora.
      expect(conflito(dayOfWeek: 1, startMinutes: 18 * 60, endMinutes: 19 * 60),
          isNotEmpty);
    });

    test('segunda às 09:00 bate com a das 9h', () {
      expect(conflito(dayOfWeek: 1, startMinutes: 9 * 60, endMinutes: 10 * 60),
          isNotEmpty);
    });

    test('sobreposição parcial conta como conflito', () {
      // 18:30–19:30 apanha o fim da aula das 18:00.
      expect(
        conflito(
            dayOfWeek: 1, startMinutes: 18 * 60 + 30, endMinutes: 19 * 60 + 30),
        isNotEmpty,
      );
    });
  });

  group('e CALA-SE onde não há nada', () {
    test('segunda às 11:00 — entre as 9h e as 18h', () {
      expect(conflito(dayOfWeek: 1, startMinutes: 11 * 60, endMinutes: 12 * 60),
          isEmpty);
    });

    test('segunda às 19:00 — logo a seguir à das 18h', () {
      // Encostada, não sobreposta: a das 18:00 acaba às 19:00.
      expect(conflito(dayOfWeek: 1, startMinutes: 19 * 60, endMinutes: 20 * 60),
          isEmpty);
    });

    test('segunda às 08:00 — encostada por baixo da das 9h', () {
      expect(conflito(dayOfWeek: 1, startMinutes: 8 * 60, endMinutes: 9 * 60),
          isEmpty);
    });

    test('terça a qualquer hora — não há nada às terças', () {
      expect(conflito(dayOfWeek: 2, startMinutes: 18 * 60, endMinutes: 19 * 60),
          isEmpty);
    });

    test('quarta às 18:00 — a de quarta é às 21:00', () {
      expect(conflito(dayOfWeek: 3, startMinutes: 18 * 60, endMinutes: 19 * 60),
          isEmpty);
    });

    test('sábado e domingo estão livres', () {
      expect(conflito(dayOfWeek: 6, startMinutes: 10 * 60, endMinutes: 11 * 60),
          isEmpty);
      expect(conflito(dayOfWeek: 7, startMinutes: 10 * 60, endMinutes: 11 * 60),
          isEmpty);
    });
  });

  test('um instrutor diferente nunca colide com estas', () {
    expect(
      findScheduleConflicts(
        recurring: true,
        instructorId: 'outro_instrutor',
        dayOfWeek: 1,
        date: DateTime(2026, 8, 31),
        startMinutes: 18 * 60,
        endMinutes: 19 * 60,
        series: horarioReal,
        occurrences: const [],
        servicesById: const {},
      ),
      isEmpty,
    );
  });

  group('mostra o dia inteiro, não só a colisão', () {
    // O aviso antigo dizia "há conflito" e nomeava UMA aula. Com duas
    // séries iguais à segunda às 18:00 — que é o que está em produção —
    // isso escondia metade da história, e não havia como escolher uma
    // hora livre sem sair do ecrã.
    List<String> diaDe(int dayOfWeek) => instructorDaySchedule(
          recurring: true,
          instructorId: instrutor,
          dayOfWeek: dayOfWeek,
          date: DateTime(2026, 8, 31),
          series: horarioReal,
          occurrences: const [],
          servicesById: const {},
        );

    test('lista as três aulas de segunda, por ordem de hora', () {
      expect(diaDe(1), [
        '09:00–10:00 · svc_aulas_grupo',
        '18:00–19:00 · svc_aulas_grupo',
        '18:00–19:00 · svc_aulas_grupo',
      ]);
    });

    test('as duas séries duplicadas aparecem AS DUAS', () {
      // É como o Gestor descobre que criou a mesma aula duas vezes.
      expect(
        conflito(dayOfWeek: 1, startMinutes: 18 * 60, endMinutes: 19 * 60),
        hasLength(2),
      );
    });

    test('um dia livre não tem nada para mostrar', () {
      expect(diaDe(2), isEmpty);
    });

    test('a duração é convertida em hora de fim', () {
      // A série de quarta tem 90 minutos: 21:00 + 90 = 22:30.
      expect(diaDe(3), ['21:00–22:30 · svc_aulas_grupo']);
    });
  });
}
