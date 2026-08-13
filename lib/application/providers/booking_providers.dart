import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/booking.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/usage.dart';
import '../../infrastructure/firebase/firebase_booking_repository.dart';
import '../../infrastructure/firebase/firebase_service_repository.dart';
import '../../infrastructure/firebase/firebase_session_occurrence_repository.dart';
import '../../infrastructure/firebase/firebase_subscription_repository.dart';
import '../../infrastructure/firebase/firebase_usage_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/session_occurrence_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../repositories/usage_repository.dart';
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
    ref.watch(functionsProvider),
  );
});

/// Fase 4 — leitura do read model de utilização (`usage/{...}`, ver
/// `usage_repository.dart`). Quem escreve são sempre as Cloud
/// Functions de booking, nunca este provider.
final usageRepositoryProvider = Provider<UsageRepository>((ref) {
  return FirebaseUsageRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// Fase 4 story 7 — "barra X/Y sessões esta semana". `.family` por
/// (memberId, serviceId, period) — `book_training_screen.dart` passa
/// sempre `isoWeekKey(DateTime.now())` como período (a semana ATUAL, não
/// a semana da sessão sendo marcada: a barra mostra "quanto já usei esta
/// semana", não uma projeção por sessão).
final usageProvider = StreamProvider.family<
    Usage?, ({String memberId, String serviceId, String period})>((ref, args) {
  return ref.watch(usageRepositoryProvider).watchUsage(
        memberId: args.memberId,
        serviceId: args.serviceId,
        period: args.period,
      );
});

/// Fase 3 — usado tanto para o `createSubscription` (ecrãs de gestão)
/// como para a query de elegibilidade que bloqueia o booking.
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return FirebaseSubscriptionRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final bookSessionUseCaseProvider = Provider<BookSessionUseCase>((ref) {
  return BookSessionUseCase(
    ref.watch(bookingRepositoryProvider),
    ref.watch(subscriptionRepositoryProvider),
  );
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

/// Fase 4 — usado por `my_bookings_screen.dart` para saber a que horas
/// é a sessão de uma marcação, e assim conseguir avisar o membro se
/// cancelar agora vai ou não devolver a utilização semanal (antes de
/// ele confirmar, não só depois). `FutureProvider`, não `Stream` — só
/// precisamos do valor uma vez para este cálculo, não de o seguir ao
/// vivo.
final occurrenceProvider = FutureProvider.family<SessionOccurrence?, String>(
  (ref, occurrenceId) {
    return ref.watch(sessionOccurrenceRepositoryProvider).getOccurrence(occurrenceId);
  },
);

final myBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null) return const Stream.empty();
  return ref.watch(bookingRepositoryProvider).watchMyBookings(appUser.uid);
});
