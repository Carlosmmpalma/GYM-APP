import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/iso_week.dart';
import '../../domain/entities/attendance.dart';
import '../../domain/entities/booking.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/session_series.dart';
import '../../domain/entities/usage.dart';
import '../../domain/entities/waitlist_entry.dart';
import '../../infrastructure/firebase/firebase_attendance_repository.dart';
import '../../infrastructure/firebase/firebase_booking_repository.dart';
import '../../infrastructure/firebase/firebase_service_repository.dart';
import '../../infrastructure/firebase/firebase_session_occurrence_repository.dart';
import '../../infrastructure/firebase/firebase_session_series_repository.dart';
import '../../infrastructure/firebase/firebase_subscription_repository.dart';
import '../../infrastructure/firebase/firebase_usage_repository.dart';
import '../../infrastructure/firebase/firebase_waitlist_repository.dart';
import '../../repositories/attendance_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/service_repository.dart';
import '../../repositories/session_occurrence_repository.dart';
import '../../repositories/session_series_repository.dart';
import '../../repositories/subscription_repository.dart';
import '../../repositories/usage_repository.dart';
import '../../repositories/waitlist_repository.dart';
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

/// Fase 8 (revisão geral) — TODOS os `.family` deste ficheiro (e de
/// `free_training_providers`/`plan_providers`/`training_providers`)
/// passaram a `autoDispose`. Um `.family` sem `autoDispose` cria uma
/// instância de provider POR ARGUMENTO e mantém-na viva o resto da
/// sessão: abrir 30 sessões ao longo de um turno deixava 30 listeners
/// Firestore abertos em simultâneo, cada um a faturar leituras a cada
/// alteração; um instrutor a percorrer 40 alunos deixava 40+ listeners
/// de avaliações/planos/histórico. Era fuga de memória E custo real de
/// Firestore, não só arrumação.
///
/// A exceção deliberada é `fcmTokenRegistrationProvider`
/// (`notification_providers.dart`), que TEM de sobreviver à navegação —
/// está documentado lá.
///
/// Fase 6 — roster de uma ocorrência (presença, reduzir vagas, remarcar).
final occurrenceBookingsProvider = StreamProvider.autoDispose
    .family<List<Booking>, String>((ref, occurrenceId) {
  return ref
      .watch(bookingRepositoryProvider)
      .watchBookingsForOccurrence(occurrenceId);
});

/// Fase 6 — versão reativa de `getOccurrence`, para
/// `OccurrenceDetailScreen` refletir capacidade/contagem ao vivo depois
/// de ações (reduzir vagas, cancelar).
final liveOccurrenceProvider = StreamProvider.autoDispose
    .family<SessionOccurrence?, String>((ref, occurrenceId) {
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

final occurrenceAttendanceProvider = StreamProvider.autoDispose
    .family<List<Attendance>, String>((ref, occurrenceId) {
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
final usageProvider = StreamProvider.autoDispose
    .family<Usage?, ({String memberId, String serviceId, String period})>(
        (ref, args) {
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
final occurrenceProvider =
    FutureProvider.autoDispose.family<SessionOccurrence?, String>(
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

/// As sessões que ESTE aluno pode mesmo marcar, perguntadas ao
/// servidor já filtradas pelos serviços do plano dele.
///
/// A chave da família é a lista de serviços **ordenada e junta numa
/// string**, e não o `Set` — em Dart dois `Set` com o mesmo conteúdo
/// não são iguais, por isso uma família com `Set` criaria um provider
/// (e um listener Firestore) novo a cada rebuild do ecrã. String vazia
/// = sem direito a nada, e nesse caso não se faz query nenhuma.
final occurrencesForServicesProvider = StreamProvider.autoDispose
    .family<List<SessionOccurrence>, ({String serviceIdsKey, int weeksAhead})>(
        (ref, args) {
  final serviceIds = args.serviceIdsKey.isEmpty
      ? <String>{}
      : args.serviceIdsKey.split(',').toSet();
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchUpcomingOccurrencesForServices(
        serviceIds,
        weeksAhead: args.weeksAhead,
      );
});

/// Quantas semanas o ecrã "Marcar" mostra de início.
///
/// As séries geram ocorrências com 8 semanas de antecedência, e o ecrã
/// trazia-as todas — até 200 documentos a cada abertura da app, para
/// mostrar as poucas que alguém vai mesmo marcar. Duas semanas cobrem a
/// decisão real ("esta semana e a próxima"); o resto vem a pedido.
const defaultBookingWeeksAhead = 2;

/// O horizonte completo que a geração de ocorrências produz.
const maxBookingWeeksAhead = 8;

/// A chave estável para [occurrencesForServicesProvider].
String serviceIdsKey(Set<String> serviceIds) =>
    (serviceIds.toList()..sort()).join(',');

/// Os slots de treino livre que o utilizador tem reservados, por
/// semana (`{weekId: {slotId}}`).
///
/// Otimização de custo (Fase 11): o ecrã de treino livre perguntava
/// "reservei este bloco?" com uma leitura por bloco — vinte blocos numa
/// semana eram vinte leituras de cada vez que o separador abria, e o
/// aluno abre-o várias vezes por semana. As marcações de treino livre
/// já vinham TODAS em `myBookingsProvider` (a mesma collection group
/// query que serve "as minhas marcações"), só não havia como saber a
/// que slot pertenciam — desde que a marcação passou a distinguir o
/// tipo e a guardar a semana, passa a dar para derivar isto sem uma
/// única leitura extra.
final myFreeTrainingSlotIdsProvider = Provider<Set<String>>((ref) {
  final bookings = ref.watch(myBookingsProvider).valueOrNull ?? const [];
  return {
    for (final booking in bookings)
      if (booking.kind == BookingKind.freeTraining &&
          booking.status == BookingStatus.booked)
        '${booking.weekId}/${booking.occurrenceId}',
  };
});

/// Fase 11 — lista de espera.
final waitlistRepositoryProvider = Provider<WaitlistRepository>((ref) {
  return FirebaseWaitlistRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// A entrada do utilizador autenticado na fila de UMA sessão, ou `null`
/// se não estiver nela. É um listener por sessão cheia visível no ecrã,
/// e só por essas — `book_training_screen.dart` só o observa quando a
/// ocorrência está cheia, que é o único momento em que a fila existe.
final myWaitlistEntryProvider =
    StreamProvider.autoDispose.family<WaitlistEntry?, String>(
  (ref, occurrenceId) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return Stream.value(null);
    return ref.watch(waitlistRepositoryProvider).watchEntry(
          occurrenceId: occurrenceId,
          memberId: appUser.uid,
        );
  },
);

/// A fila inteira de uma sessão, para Instrutor/Gestor. Um aluno não
/// consegue lê-la (as Rules recusam a listagem) — por isso este
/// provider só é observado nos ecrãs de gestão.
final occurrenceWaitlistProvider =
    StreamProvider.autoDispose.family<List<WaitlistEntry>, String>(
  (ref, occurrenceId) {
    return ref.watch(waitlistRepositoryProvider).watchQueue(occurrenceId);
  },
);

/// Fase 5 — sessões recorrentes (séries).
final sessionSeriesRepositoryProvider =
    Provider<SessionSeriesRepository>((ref) {
  return FirebaseSessionSeriesRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// Só o NÚMERO de séries ativas — ver [activeMemberCountProvider].
final activeSeriesCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(sessionSeriesRepositoryProvider).countActiveSeries();
});

final seriesProvider = StreamProvider<List<SessionSeries>>((ref) {
  return ref.watch(sessionSeriesRepositoryProvider).watchSeries();
});

/// "Ajustar uma semana da série" (`SeriesDetailScreen`) — todas as
/// ocorrências já materializadas a partir de uma série.
final seriesOccurrencesProvider = StreamProvider.autoDispose
    .family<List<SessionOccurrence>, String>((ref, seriesId) {
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

/// Fase 8 (auditoria funcional, UC20 atualizado) — `InstructorCalendarScreen`
/// passou de "próximas 2 semanas, tudo junto numa lista" (janela fixa,
/// `upcomingTwoWeeksOccurrencesProvider`, agora removido) para
/// navegação por semana com tabs por dia (mockup "Semana — visão do
/// gestor"): uma família por semana (chave: segunda-feira 00:00 dessa
/// semana) em vez de uma janela fixa a partir de "agora", para poder
/// navegar para trás/à frente — mesmo padrão de
/// `freeTrainingScheduleProvider`/`freeTrainingSlotsProvider` (chave
/// por semana), só que por `DateTime` em vez de `weekId` String porque
/// não há nenhum documento Firestore correspondente a "a semana X de
/// sessionOccurrences" (ao contrário de `freeTrainingSchedules`).
final occurrencesForWeekProvider = StreamProvider.autoDispose
    .family<List<SessionOccurrence>, DateTime>((ref, weekStart) {
  final range = isoWeekRange(weekStart);
  return ref
      .watch(sessionOccurrenceRepositoryProvider)
      .watchOccurrencesStartingBetween(range.start, range.end);
});
