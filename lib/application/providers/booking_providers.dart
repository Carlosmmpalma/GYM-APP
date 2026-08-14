import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import '../../domain/entities/usage.dart';
import '../../infrastructure/firebase/firebase_attendance_repository.dart';
import '../../infrastructure/firebase/firebase_booking_repository.dart';
import '../../infrastructure/firebase/firebase_service_repository.dart';
import '../../infrastructure/firebase/firebase_session_occurrence_repository.dart';
import '../../infrastructure/firebase/firebase_session_series_repository.dart';
import '../../infrastructure/firebase/firebase_subscription_repository.dart';
import '../../infrastructure/firebase/firebase_usage_repository.dart';
import '../../repositories/attendance_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/session_occurrence_repository.dart';
import '../../repositories/session_series_repository.dart';
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
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return FirebaseBookingRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// Fase 6 — roster de uma ocorrência (presença, reduzir vagas, remarcar).
final occurrenceBookingsProvider =
    StreamProvider.family<List<Booking>, String>((ref, occurrenceId) {
  return ref
      .watch(bookingRepositoryProvider)
      .watchBookingsForOccurrence(occurrenceId);
});

/// Fase 6 — versão reativa de `getOccurrence`, para
/// `OccurrenceDetailScreen` refletir capacidade/contagem ao vivo depois
/// de ações (reduzir vagas, cancelar).
final liveOccurrenceProvider =
    StreamProvider.family<SessionOccurrence?, String>((ref, occurrenceId) {
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchOccurrence(occurrenceId);
});

/// Fase 6 (UC10-A).
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return FirebaseAttendanceRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final occurrenceAttendanceProvider =
    StreamProvider.family<List<Attendance>, String>((ref, occurrenceId) {
  return ref
      .watch(attendanceRepositoryProvider)
      .watchAttendanceForOccurrence(occurrenceId);
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
final usageProvider = StreamProvider.family<Usage?,
    ({String memberId, String serviceId, String period})>((ref, args) {
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

/// `BookTrainingScreen` mostrava só as ocorrências do "primeiro serviço
/// ativo" (era o único jeito de a Fase 2 evitar hardcodar um id de
/// serviço, Platform Foundation §13). Desde a Fase 5, um tenant pode
/// ter várias séries em serviços diferentes — filtrar por um só
/// escondia sessões reais sem nenhum aviso (bug real, reportado depois
/// de a Fase 5 tornar isto visível). `BookTrainingScreen` passou a usar
/// `allUpcomingOccurrencesProvider`, abaixo; este provider (e o
/// `Service?` que devolvia) deixou de ter consumidor.
final allUpcomingOccurrencesProvider =
    StreamProvider<List<SessionOccurrence>>((ref) {
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchUpcomingOccurrencesAllServices();
});

/// Fase 4 — usado por `my_bookings_screen.dart` para saber a que horas
/// é a sessão de uma marcação, e assim conseguir avisar o membro se
/// cancelar agora vai ou não devolver a utilização semanal (antes de
/// ele confirmar, não só depois). `FutureProvider`, não `Stream` — só
/// precisamos do valor uma vez para este cálculo, não de o seguir ao
/// vivo.
final occurrenceProvider = FutureProvider.family<SessionOccurrence?, String>(
  (ref, occurrenceId) {
    return ref
        .watch(sessionOccurrenceRepositoryProvider)
        .getOccurrence(occurrenceId);
  },
);

final myBookingsProvider = StreamProvider<List<Booking>>((ref) {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null) return const Stream.empty();
  return ref.watch(bookingRepositoryProvider).watchMyBookings(appUser.uid);
});

/// Fase 5 — sessões recorrentes (séries).
final sessionSeriesRepositoryProvider =
    Provider<SessionSeriesRepository>((ref) {
  return FirebaseSessionSeriesRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final seriesProvider = StreamProvider<List<SessionSeries>>((ref) {
  return ref.watch(sessionSeriesRepositoryProvider).watchSeries();
});

/// "Ajustar uma semana da série" (`SeriesDetailScreen`) — todas as
/// ocorrências já materializadas a partir de uma série.
final seriesOccurrencesProvider =
    StreamProvider.family<List<SessionOccurrence>, String>((ref, seriesId) {
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchOccurrencesForSeries(seriesId);
});

/// UC25 — "Visão global" do Gestor: ocorrências (qualquer serviço) dos
/// próximos 7 dias, para calcular ocupação agregada. Não é `.family`
/// por intervalo (ao contrário de `seriesOccurrencesProvider`) porque
/// só há um consumidor (`GestorDashboardScreen`), sempre com a mesma
/// janela — não há necessidade de generalizar já.
final upcomingWeekOccurrencesProvider =
    StreamProvider<List<SessionOccurrence>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchOccurrencesStartingBetween(
        now,
        now.add(const Duration(days: 7)),
      );
});

/// UC20 — `InstructorCalendarScreen`: janela maior que
/// [upcomingWeekOccurrencesProvider] (2 semanas em vez de 1), qualquer
/// serviço/instrutor — o ecrã filtra client-side por `instructorId`
/// quando aberto por um Instrutor; o Gestor vê tudo sem filtro.
final upcomingTwoWeeksOccurrencesProvider =
    StreamProvider<List<SessionOccurrence>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchOccurrencesStartingBetween(
        now,
        now.add(const Duration(days: 14)),
      );
});
