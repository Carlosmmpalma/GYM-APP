import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/attendance.dart';

Attendance _registo(String memberId, AttendanceStatus status) => Attendance(
      memberId: memberId,
      status: status,
      recordedBy: 'instrutor_1',
      recordedAt: DateTime(2026, 9, 12, 19),
    );

void main() {
  group('AttendanceSummary', () {
    test('conta presentes, faltas e quem ainda não foi marcado', () {
      final resumo = AttendanceSummary.de(
        [
          _registo('a', AttendanceStatus.attended),
          _registo('b', AttendanceStatus.attended),
          _registo('c', AttendanceStatus.noShow),
        ],
        inscritos: 5,
      );

      expect(resumo.presentes, 2);
      expect(resumo.faltas, 1);
      expect(resumo.marcados, 3);
      expect(resumo.porMarcar, 2);
      expect(resumo.completa, isFalse);
    });

    test('sem ninguém por marcar, a chamada está completa', () {
      final resumo = AttendanceSummary.de(
        [
          _registo('a', AttendanceStatus.attended),
          _registo('b', AttendanceStatus.noShow),
        ],
        inscritos: 2,
      );

      expect(resumo.porMarcar, 0);
      expect(resumo.completa, isTrue);
    });

    test('uma aula sem inscritos NÃO conta como feita', () {
      // Sem isto, uma aula onde ninguém se inscreveu aparecia com o
      // visto verde de "chamada feita" — a dizer que houve uma turma
      // que não houve. `porMarcar` é zero nos dois casos; é `inscritos`
      // que os separa.
      final resumo = AttendanceSummary.de(const [], inscritos: 0);

      expect(resumo.porMarcar, 0);
      expect(resumo.completa, isFalse);
      expect(resumo.vazia, isTrue);
    });

    test('mais registos do que inscritos nunca dá "por marcar" negativo', () {
      // Acontece a sério: o membro é dado como presente e só depois
      // desmarca a aula. O registo de presença sobrevive ao booking —
      // são documentos diferentes, de propósito — e `activeBookingCount`
      // desce. Mostrar "-1 por marcar" seria pior do que mostrar zero.
      final resumo = AttendanceSummary.de(
        [
          _registo('a', AttendanceStatus.attended),
          _registo('b', AttendanceStatus.attended),
        ],
        inscritos: 1,
      );

      expect(resumo.porMarcar, 0);
    });
  });
}
