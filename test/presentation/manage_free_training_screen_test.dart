import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/application/providers/firebase_providers.dart';
import 'package:gym_saas/application/providers/free_training_providers.dart';
import 'package:gym_saas/application/providers/tenant_context_providers.dart';
import 'package:gym_saas/core/config/tenant_app_config.dart';
import 'package:gym_saas/domain/entities/attendance.dart';
import 'package:gym_saas/domain/entities/booking.dart';
import 'package:gym_saas/domain/entities/free_training_schedule.dart';
import 'package:gym_saas/domain/entities/free_training_slot.dart';
import 'package:gym_saas/domain/entities/service.dart';
import 'package:gym_saas/presentation/screens/manage_free_training_screen.dart';
import 'package:gym_saas/repositories/free_training_repository.dart';
import 'package:intl/date_symbol_data_local.dart';

const _tenantId = 'tenant_test';

/// Mesmo padrão dos outros testes de gestão desta fase — fake do
/// repository em vez de mockar `cloud_functions`/escrita direta.
///
/// Usa `StreamController.broadcast` (não `Stream.value`) porque o
/// ecrã depende de reagir a mutações DEPOIS do primeiro build (gerar
/// sugestão, adicionar bloco, publicar) — `Stream.value` só emitiria
/// o valor capturado no momento em que o provider é observado pela
/// primeira vez, nunca as mutações seguintes (ao contrário de um
/// `FakeFirebaseFirestore` real, cujo `snapshots()` já é reativo por
/// natureza).
class _FakeFreeTrainingRepository implements FreeTrainingRepository {
  FreeTrainingSchedule? _schedule;
  final List<FreeTrainingSlot> slots = [];
  bool publishCalled = false;
  ({DateTime weekStart, String serviceId})? lastSuggestCall;
  ({
    String weekId,
    String serviceId,
    DateTime startAt,
    DateTime endAt,
    int capacity
  })? lastCreateSlotCall;

  final _scheduleController =
      StreamController<FreeTrainingSchedule?>.broadcast();
  final _slotsController = StreamController<List<FreeTrainingSlot>>.broadcast();

  set schedule(FreeTrainingSchedule? value) {
    _schedule = value;
    _scheduleController.add(_schedule);
  }

  FreeTrainingSchedule? get schedule => _schedule;

  void _emitSlots() => _slotsController.add(List.unmodifiable(slots));

  @override
  Stream<FreeTrainingSchedule?> watchSchedule(String weekId) async* {
    yield _schedule;
    yield* _scheduleController.stream;
  }

  @override
  Stream<List<FreeTrainingSlot>> watchSlots(String weekId) async* {
    yield List.unmodifiable(slots);
    yield* _slotsController.stream;
  }

  @override
  Stream<List<Booking>> watchSlotBookings(String weekId, String slotId) =>
      const Stream.empty();

  @override
  Future<Booking?> getMyBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) async =>
      null;

  @override
  Stream<List<Attendance>> watchSlotAttendance(String weekId, String slotId) =>
      const Stream.empty();

  @override
  Future<({String weekId, String status, bool created, int slotsCopied})>
      suggestSchedule(
          {required DateTime weekStart, required String serviceId}) async {
    lastSuggestCall = (weekStart: weekStart, serviceId: serviceId);
    schedule = FreeTrainingSchedule(
      weekId: 'week_1',
      weekStart: weekStart,
      status: FreeTrainingScheduleStatus.draft,
    );
    return (weekId: 'week_1', status: 'draft', created: true, slotsCopied: 0);
  }

  @override
  Future<void> publishSchedule(String weekId) async {
    publishCalled = true;
    final current = schedule;
    if (current != null) {
      schedule = FreeTrainingSchedule(
        weekId: current.weekId,
        weekStart: current.weekStart,
        status: FreeTrainingScheduleStatus.published,
      );
    }
  }

  @override
  Future<String> createSlot({
    required String weekId,
    required String serviceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  }) async {
    lastCreateSlotCall = (
      weekId: weekId,
      serviceId: serviceId,
      startAt: startAt,
      endAt: endAt,
      capacity: capacity
    );
    final slot = FreeTrainingSlot(
      id: 'slot_${slots.length + 1}',
      weekId: weekId,
      serviceId: serviceId,
      startAt: startAt,
      endAt: endAt,
      capacity: capacity,
      activeBookingCount: 0,
    );
    slots.add(slot);
    _emitSlots();
    return slot.id;
  }

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
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> cancelSlotBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  }) =>
      throw UnimplementedError();

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

  Future<FakeFirebaseFirestore> seedFirestore() async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('tenants')
        .doc(_tenantId)
        .collection('services')
        .doc('service_1')
        .set({'name': 'Treino sem acompanhamento', 'active': true});
    return firestore;
  }

  Widget buildApp(
      FakeFirebaseFirestore firestore, _FakeFreeTrainingRepository repository) {
    return ProviderScope(
      overrides: [
        tenantAppConfigProvider.overrideWithValue(
          const TenantAppConfig(tenantId: _tenantId),
        ),
        firestoreProvider.overrideWithValue(firestore),
        freeTrainingRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: ManageFreeTrainingScreen()),
    );
  }

  testWidgets(
      'semana sem grelha: escolher serviço e gerar grelha chama suggestSchedule',
      (tester) async {
    final firestore = await seedFirestore();
    final repository = _FakeFreeTrainingRepository();

    await tester.pumpWidget(buildApp(firestore, repository));
    await tester.pumpAndSettle();

    expect(
      find.text('Esta semana ainda não tem nenhuma grelha de treino livre.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<Service>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treino sem acompanhamento').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gerar grelha desta semana'));
    await tester.pumpAndSettle();

    expect(repository.lastSuggestCall?.serviceId, 'service_1');
    expect(
        find.text('Rascunho — ainda não publicada, os alunos não veem isto.'),
        findsOneWidget);
  });

  testWidgets('adicionar bloco cria slots e publicar chama publishSchedule',
      (tester) async {
    final firestore = await seedFirestore();
    final repository = _FakeFreeTrainingRepository()
      ..schedule = FreeTrainingSchedule(
        weekId: 'week_1',
        weekStart: DateTime.now(),
        status: FreeTrainingScheduleStatus.draft,
      );

    await tester.pumpWidget(buildApp(firestore, repository));
    await tester.pumpAndSettle();

    // Sem slots ainda — botão de publicar desativado.
    final publishButtonFinder =
        find.widgetWithText(FilledButton, 'Aprovar e publicar semana');
    expect(tester.widget<FilledButton>(publishButtonFinder).onPressed, isNull);

    await tester.tap(find.text('Adicionar bloco de horário'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Seg'));
    await tester.tap(find.widgetWithText(FilterChip, 'Ter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<Service>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treino sem acompanhamento').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    expect(repository.slots.length, 2);
    expect(repository.lastCreateSlotCall?.capacity, 10);

    await tester.tap(publishButtonFinder);
    await tester.pumpAndSettle();

    expect(repository.publishCalled, isTrue);
    expect(find.text('✓ Publicada — visível aos alunos.'), findsOneWidget);
  });
}
