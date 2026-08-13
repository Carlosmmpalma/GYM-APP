import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/booking.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../infrastructure/firebase/firebase_booking_repository.dart';
import '../../infrastructure/firebase/firebase_service_repository.dart';
import '../../infrastructure/firebase/firebase_session_occurrence_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/session_occurrence_repository.dart';
import '../use_cases/book_session_use_case.dart';
import '../use_cases/cancel_booking_use_case.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) {
  return FirebaseServiceRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final sessionOccurrenceRepositoryProvider =
    Provider<SessionOccurrenceRepository>((ref) {
  return FirebaseSessionOccurrenceRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return FirebaseBookingRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final bookSessionUseCaseProvider = Provider<BookSessionUseCase>((ref) {
  return BookSessionUseCase(ref.watch(bookingRepositoryProvider));
});

final cancelBookingUseCaseProvider = Provider<CancelBookingUseCase>((ref) {
  return CancelBookingUseCase(ref.watch(bookingRepositoryProvider));
});

/// Fase 2 é deliberadamente single-service: em vez de hardcodar o id do
/// serviço de teste no código Dart (o que violaria Platform Foundation
/// §13 — nada de configuração de negócio hardcoded), vamos buscar o
/// primeiro serviço ativo. Isto deixa de fazer sentido a partir do
/// momento em que existir mais do que um serviço e um ecrã para
/// escolher entre eles (Fase 3+).
final primaryServiceProvider = FutureProvider<Service?>((ref) async {
  final services = await ref.watch(serviceRepositoryProvider).getActiveServices();
  return services.isEmpty ? null : services.first;
});

final upcomingOccurrencesProvider =
    StreamProvider.family<List<SessionOccurrence>, String>((ref, serviceId) {
  return ref.watch(sessionOccurrenceRepositoryProvider).watchUpcomingOccurrences(serviceId);
});

final myBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null) return const Stream.empty();
  return ref.watch(bookingRepositoryProvider).watchMyBookings(appUser.uid);
});
