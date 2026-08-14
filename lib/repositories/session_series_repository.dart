import '../domain/entities/session_series.dart';

/// Fase 5 (guia-desenvolvimento.md) — Repository Pattern (Platform
/// Foundation §12). Ao contrário de `createSubscription`/`createBooking`
/// (Cloud Functions — validam invariantes cross-documento), criar/editar
/// uma série é escrita direta do cliente (mesmo padrão de
/// `PlanRepository`): não há nenhuma invariante entre séries a validar
/// aqui, só role (Manager, via `firestore.rules`). A materialização das
/// ocorrências e a auto-atribuição de `preAssignedMemberIds` continuam
/// sempre do lado do servidor — ver [generateNow].
abstract class SessionSeriesRepository {
  Stream<List<SessionSeries>> watchSeries();

  /// Devolve o id do documento criado.
  Future<String> createSeries({
    required String serviceId,
    String? instructorId,
    required int dayOfWeek,
    required String startTime,
    required int durationMinutes,
    required int capacity,
    required DateTime startDate,
    List<String> preAssignedMemberIds = const [],
  });

  Future<void> updateSeries(SessionSeries series);

  /// Cancela a série E todas as suas ocorrências futuras (`startAt` >
  /// agora) — ocorrências passadas ficam intocadas (critério "Done" da
  /// Fase 5). Escrita atómica (`WriteBatch`): cada alteração individual
  /// já é autorizada isoladamente pelas Security Rules (Manager do
  /// tenant), não há nenhuma invariante cross-documento nova a proteger
  /// aqui — só queremos as duas coisas juntas na mesma operação.
  Future<void> cancelSeries(String seriesId);

  /// Chama a Cloud Function `generateRecurringOccurrencesNow` — força a
  /// materialização das próximas ocorrências sem esperar pelo cron
  /// diário (`generateRecurringOccurrences.ts`). Principal forma de
  /// testar isto localmente, e também ferramenta operacional.
  Future<void> generateNow();
}
