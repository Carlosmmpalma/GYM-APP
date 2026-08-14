import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/domain/entities/attendance.dart';

Attendance _attendance({
  AttendanceStatus status = AttendanceStatus.attended,
  DateTime? recordedAt,
}) {
  return Attendance(
    memberId: 'member_1',
    status: status,
    recordedBy: 'staff_1',
    recordedAt: recordedAt ?? DateTime(2026, 1, 5, 18, 0),
  );
}

void main() {
  group('Equatable', () {
    test('duas presenças com os mesmos campos são iguais', () {
      expect(_attendance(), equals(_attendance()));
    });

    test('status diferente torna-as diferentes', () {
      expect(
        _attendance(status: AttendanceStatus.attended),
        isNot(equals(_attendance(status: AttendanceStatus.noShow))),
      );
    });

    test('recordedAt diferente torna-as diferentes', () {
      expect(
        _attendance(recordedAt: DateTime(2026, 1, 5)),
        isNot(equals(_attendance(recordedAt: DateTime(2026, 1, 6)))),
      );
    });
  });
}
