import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/free_training_schedule.dart';
import '../../domain/entities/free_training_slot.dart';
import '../../infrastructure/firebase/firebase_free_training_repository.dart';
import '../../repositories/free_training_repository.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

/// Fase 7 — Treino livre (UC09/UC17-A).
final freeTrainingRepositoryProvider = Provider<FreeTrainingRepository>((ref) {
  return FirebaseFreeTrainingRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final freeTrainingScheduleProvider = StreamProvider.autoDispose
    .family<FreeTrainingSchedule?, String>((ref, weekId) {
  return ref.watch(freeTrainingRepositoryProvider).watchSchedule(weekId);
});

final freeTrainingSlotsProvider = StreamProvider.autoDispose
    .family<List<FreeTrainingSlot>, String>((ref, weekId) {
  return ref.watch(freeTrainingRepositoryProvider).watchSlots(weekId);
});

/// UC09/UC17 fechado — lista completa (nomes), só para Gestor/Instrutor
/// (a Security Rule bloqueia `list` a um Aluno; ver
/// `myFreeTrainingBookingProvider` para o caminho do Aluno).
final freeTrainingSlotBookingsProvider = StreamProvider.autoDispose
    .family<List<Booking>, ({String weekId, String slotId})>((ref, args) {
  return ref
      .watch(freeTrainingRepositoryProvider)
      .watchSlotBookings(args.weekId, args.slotId);
});

/// UC09 — "já reservei este horário?", `get` em vez de `list` (única
/// leitura que a Security Rule permite a um Aluno sobre bookings de
/// outrem — aqui é sempre o dele próprio). `FutureProvider`, não
/// `Stream`: o ecrã do Aluno relê isto depois de reservar/cancelar via
/// `ref.invalidate`, mesmo padrão já usado noutros pontos da app para
/// contornar a propagação de listeners.
final myFreeTrainingBookingProvider = FutureProvider.autoDispose
    .family<Booking?, ({String weekId, String slotId, String memberId})>(
        (ref, args) {
  return ref.watch(freeTrainingRepositoryProvider).getMyBooking(
        weekId: args.weekId,
        slotId: args.slotId,
        memberId: args.memberId,
      );
});

final freeTrainingSlotAttendanceProvider = StreamProvider.autoDispose
    .family<List<Attendance>, ({String weekId, String slotId})>((ref, args) {
  return ref
      .watch(freeTrainingRepositoryProvider)
      .watchSlotAttendance(args.weekId, args.slotId);
});
