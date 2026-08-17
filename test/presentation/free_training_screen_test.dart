import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/free_training_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/domain/entities/app_user.dart';
import 'package:gym_saas/domain/entities/attendance.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/domain/entities/free_training_schedule.dart';
import 'package:gym_saas/domain/entities/free_training_slot.dart';
import 'package:gym_saas/domain/entities/role.dart';
import 'package:gym_saas/presentation/screens/free_training_screen.dart';
import 'package:gym_saas/repositories/free_training_repository.dart';
import 'package:intl/date_symbol_data_local.dart';

const _tenantId = 'tenant_test';
const _memberId = 'member_1';

/// Fase 7 — mesma justificação de outros ecrãs de booking: mockar a
/// cadeia `httpsCallable(...).call(...)` diretamente exigiria confirmar
/// a forma exata de `HttpsCallableResult`; um fake do repository chega
/// (mesmo padrão de `book_training_screen_test.dart`).
class _FakeFreeTrainingRepository implements FreeTrainingRepository {
  _FakeFreeTrainingRepository({required this.schedule, required this.slots});

  final FreeTrainingSchedule? schedule;
  final List<FreeTrainingSlot> slots;
  final Set<String> _bookedSlotIds = {};
  bool bookCalled = false;
  bool cancelCalled = false;

  @override
  Stream<FreeTrainingSchedule?> watchSchedule(String weekId) =>
      Stream.value(schedule);

  @override
  Stream<List<FreeTrainingSlot>> watchSlots(String weekId) =>
      Stream.value(slots);

  @override
  Stream<List<Booking>> watchSlotBookings(String weekId, String slotId) =>
      const Stream.empty();

  @override
  Future<Booking?> getMyBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    if (!_bookedSlotIds.contains(slotId)) return null;
    return Booking(
      id: memberId,
      occurrenceId: slotId,
      memberId: memberId,
      status: BookingStatus.booked,
      source: BookingSource.self,
      isExtra: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Stream<List<Attendance>> watchSlotAttendance(String weekId, String slotId) =>
      const Stream.empty();

  @override
  Future<({String weekId, String status, bool created, int slotsCopied})>
      suggestSchedule(
              {required DateTime weekStart, required String serviceId}) =>
          throw UnimplementedError();

  @override
  Future<void> publishSchedule(String weekId) => throw UnimplementedError();

  @override
  Future<String> createSlot({
    required String weekId,
    required String serviceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateSlot({
    required String weekId,
    required String slotId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteSlot({
    required String weekId,
    required String slotId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> bookSlot({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    bookCalled = true;
    _bookedSlotIds.add(slotId);
  }

  @override
  Future<bool> cancelSlotBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async {
    cancelCalled = true;
    _bookedSlotIds.remove(slotId);
    return true;
  }

  @override
  Future<Map<String, bool>> assignMembers({
    required String weekId,
    required String slotId,
    required List<String> memberIds,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> recordAttendance({
    required String weekId,
    required String slotId,
    required String memberId,
    required AttendanceStatus status,
    required String recordedBy,
  }) =>
      throw UnimplementedError();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_PT');
  });

  Widget buildApp(_FakeFreeTrainingRepository repository) {
    return ProviderScope(
      overrides: [
        freeTrainingRepositoryProvider.overrideWithValue(repository),
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(
            const AppUser(
                uid: _memberId, tenantId: _tenantId, roles: {Role.member}),
          ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: FreeTrainingScreen())),
    );
  }

  testWidgets('semana sem grelha publicada mostra estado vazio explícito',
      (tester) async {
    final repository =
        _FakeFreeTrainingRepository(schedule: null, slots: const []);
    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(
      find.text('Ainda não há grelha publicada para esta semana.'),
      findsOneWidget,
    );
  });

  testWidgets('grelha publicada mostra só a contagem de vagas — nunca nomes',
      (tester) async {
    final now = DateTime.now();
    final schedule = FreeTrainingSchedule(
      weekId: 'week_1',
      weekStart: now,
      status: FreeTrainingScheduleStatus.published,
    );
    final slot = FreeTrainingSlot(
      id: 'slot_1',
      weekId: 'week_1',
      serviceId: 'service_1',
      startAt: now.add(const Duration(hours: 1)),
      endAt: now.add(const Duration(hours: 3)),
      capacity: 10,
      activeBookingCount: 4,
    );
    final repository =
        _FakeFreeTrainingRepository(schedule: schedule, slots: [slot]);

    await tester.pumpWidget(buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('6 vaga(s) restante(s)'), findsOneWidget);
    expect(find.text('Reservar'), findsOneWidget);

    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();

    expect(repository.bookCalled, isTrue);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.cancelCalled, isTrue);
    expect(find.text('Reservar'), findsOneWidget);
  });
}
