import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/plan_providers.dart';
import 'package:gym_saas/application/providers/booking_providers.dart';
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

  /// [eligible] — os serviços a que o plano deste aluno dá acesso.
  /// `null` deixa o provider real responder (nestes testes fica em
  /// loading, que é o caminho de "não filtrar enquanto não se sabe").
  Widget buildApp(
    _FakeFreeTrainingRepository repository, {
    Set<String>? eligible,
    List<Booking> myBookings = const [],
  }) {
    return ProviderScope(
      overrides: [
        freeTrainingRepositoryProvider.overrideWithValue(repository),
        // Otimização de custo (Fase 11): "já reservei este bloco?"
        // deixou de ser uma leitura por bloco e passa a derivar das
        // marcações que já vinham carregadas.
        myBookingsProvider.overrideWith((ref) => Stream.value(myBookings)),
        if (eligible != null)
          myEligibleServiceIdsProvider
              .overrideWith((ref) => Stream.value(eligible)),
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
      find.text('Semana ainda não publicada'),
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
  });

  testWidgets('um bloco já reservado mostra "Cancelar"', (tester) async {
    // O estado do botão vem das marcações do próprio aluno, e não de
    // uma leitura por bloco — ver `myFreeTrainingSlotIdsProvider`.
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

    await tester.pumpWidget(buildApp(
      repository,
      myBookings: [
        Booking(
          id: _memberId,
          occurrenceId: 'slot_1',
          memberId: _memberId,
          status: BookingStatus.booked,
          source: BookingSource.self,
          isExtra: false,
          createdAt: now,
          kind: BookingKind.freeTraining,
          weekId: 'week_1',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.cancelCalled, isTrue);
  });

  testWidgets('a marcação de OUTRA semana não marca este bloco',
      (tester) async {
    // O id do slot pode repetir-se entre semanas; a chave tem de
    // incluir a semana.
    final now = DateTime.now();
    final repository = _FakeFreeTrainingRepository(
      schedule: FreeTrainingSchedule(
        weekId: 'week_1',
        weekStart: now,
        status: FreeTrainingScheduleStatus.published,
      ),
      slots: [
        FreeTrainingSlot(
          id: 'slot_1',
          weekId: 'week_1',
          serviceId: 'service_1',
          startAt: now.add(const Duration(hours: 1)),
          endAt: now.add(const Duration(hours: 3)),
          capacity: 10,
          activeBookingCount: 4,
        ),
      ],
    );

    await tester.pumpWidget(buildApp(
      repository,
      myBookings: [
        Booking(
          id: _memberId,
          occurrenceId: 'slot_1',
          memberId: _memberId,
          status: BookingStatus.booked,
          source: BookingSource.self,
          isExtra: false,
          createdAt: now,
          kind: BookingKind.freeTraining,
          weekId: 'week_OUTRA',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Reservar'), findsOneWidget);
  });

  group('só o que o plano dá (Fase 11)', () {
    FreeTrainingSlot slotOf(String serviceId) {
      final now = DateTime.now();
      return FreeTrainingSlot(
        id: 'slot_$serviceId',
        weekId: 'week_1',
        serviceId: serviceId,
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        capacity: 10,
        activeBookingCount: 0,
      );
    }

    _FakeFreeTrainingRepository publishedWith(List<FreeTrainingSlot> slots) {
      return _FakeFreeTrainingRepository(
        schedule: FreeTrainingSchedule(
          weekId: 'week_1',
          weekStart: DateTime.now(),
          status: FreeTrainingScheduleStatus.published,
        ),
        slots: slots,
      );
    }

    testWidgets('blocos de um serviço sem direito não aparecem',
        (tester) async {
      final repository =
          publishedWith([slotOf('service_1'), slotOf('service_pt')]);

      await tester.pumpWidget(
        buildApp(repository, eligible: const {'service_1'}),
      );
      await tester.pumpAndSettle();

      // Um bloco visível (o do serviço a que tem direito), não dois.
      expect(find.text('Reservar'), findsOneWidget);
    });

    testWidgets('sem direito a treino livre, explica porquê', (tester) async {
      final repository = publishedWith([slotOf('service_pt')]);

      await tester.pumpWidget(
        buildApp(repository, eligible: const {'service_1'}),
      );
      await tester.pumpAndSettle();

      // Distinto de "semana não publicada": a grelha existe, o plano é
      // que não inclui isto.
      expect(
        find.text('O teu plano não inclui treino livre'),
        findsOneWidget,
      );
      expect(find.text('Reservar'), findsNothing);
    });
  });
}
