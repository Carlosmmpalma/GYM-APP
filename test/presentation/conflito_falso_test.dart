import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/service.dart';
import 'package:gym_saas/domain/entities/session_occurrence.dart';
import 'package:gym_saas/domain/entities/session_series.dart';
import 'package:gym_saas/presentation/screens/create_series_screen.dart';

const _instrutor = 'hyZDzXrKbnS6oBHcETjsp5sUlpo2';

SessionSeries _serie(String id, int dia, String hora, int dur) => SessionSeries(
      id: id,
      serviceId: 'svc',
      dayOfWeek: dia,
      startTime: hora,
      durationMinutes: dur,
      capacity: 10,
      startDate: DateTime(2026, 1, 1),
      status: SessionSeriesStatus.active,
      instructorId: _instrutor,
    );

/// As séries que estão MESMO em produção, lidas do Firestore.
final _producao = [
  _serie('a', DateTime.monday, '09:00', 60),
  _serie('b', DateTime.monday, '18:00', 60),
  _serie('c', DateTime.monday, '18:00', 60),
  _serie('d', DateTime.monday, '20:00', 60),
  _serie('e', DateTime.wednesday, '21:00', 90),
];

const _servicos = {'svc': Service(id: 'svc', name: 'Aula', active: true)};

void main() {
  group('conflito falso — reportado em produção', () {
    test('sexta à 01:00 não colide com nada (séries de segunda e quarta)', () {
      final conflitos = findScheduleConflicts(
        recurring: true,
        instructorId: _instrutor,
        dayOfWeek: DateTime.friday,
        date: DateTime(2026, 9, 25),
        startMinutes: 60,
        endMinutes: 120,
        series: _producao,
        occurrences: const [],
        servicesById: _servicos,
      );
      expect(conflitos, isEmpty);
    });

    test('segunda à 01:00 também não colide — as aulas são às 9, 18 e 20', () {
      final conflitos = findScheduleConflicts(
        recurring: true,
        instructorId: _instrutor,
        dayOfWeek: DateTime.monday,
        date: DateTime(2026, 9, 21),
        startMinutes: 60,
        endMinutes: 120,
        series: _producao,
        occurrences: const [],
        servicesById: _servicos,
      );
      expect(conflitos, isEmpty);
    });

    test('mas segunda às 18:00 colide MESMO — é o valor por omissão', () {
      // Isto tem de continuar a avisar: é o horário com que o
      // formulário abre, e é por isso que há duas séries iguais em
      // produção.
      final conflitos = findScheduleConflicts(
        recurring: true,
        instructorId: _instrutor,
        dayOfWeek: DateTime.monday,
        date: DateTime(2026, 9, 21),
        startMinutes: 18 * 60,
        endMinutes: 19 * 60,
        series: _producao,
        occurrences: const [],
        servicesById: _servicos,
      );
      expect(conflitos, hasLength(2));
    });

    test('"só esta data" à 01:00 não colide com uma aula das 18:00', () {
      final dia = DateTime(2026, 9, 25);
      final conflitos = findScheduleConflicts(
        recurring: false,
        instructorId: _instrutor,
        dayOfWeek: dia.weekday,
        date: dia,
        startMinutes: 60,
        endMinutes: 120,
        series: const [],
        occurrences: [
          SessionOccurrence(
            id: 'o1',
            serviceId: 'svc',
            startAt: DateTime(2026, 9, 25, 18),
            endAt: DateTime(2026, 9, 25, 19),
            capacity: 10,
            activeBookingCount: 0,
            status: SessionOccurrenceStatus.scheduled,
            instructorId: _instrutor,
          ),
        ],
        servicesById: _servicos,
      );
      expect(conflitos, isEmpty);
    });

    test('uma aula que atravessa a meia-noite não engole o dia seguinte', () {
      // `otherEnd` era lido como HORA DO DIA (`endAt.hour * 60 + ...`),
      // ignorando a data. Uma aula das 23:00 às 00:00 dá `otherEnd = 0`,
      // e a partir daí a comparação diz o que lhe apetecer.
      final dia = DateTime(2026, 9, 25);
      final conflitos = findScheduleConflicts(
        recurring: false,
        instructorId: _instrutor,
        dayOfWeek: dia.weekday,
        date: dia,
        startMinutes: 60,
        endMinutes: 120,
        series: const [],
        occurrences: [
          SessionOccurrence(
            id: 'o1',
            serviceId: 'svc',
            startAt: DateTime(2026, 9, 25, 23),
            endAt: DateTime(2026, 9, 26),
            capacity: 10,
            activeBookingCount: 0,
            status: SessionOccurrenceStatus.scheduled,
            instructorId: _instrutor,
          ),
        ],
        servicesById: _servicos,
      );
      expect(conflitos, isEmpty);
    });
  });
}
