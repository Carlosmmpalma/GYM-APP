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
  /// Quantas séries ativas há, sem trazer nenhuma — ver
  /// `MemberRepository.countActiveMembers`.
  Future<int> countActiveSeries();

  Stream<List<SessionSeries>> watchSeries();

  /// Devolve o id do documento criado.
  Future<String> createSeries({
    required String serviceId,
    String? instructorId,
    String? modalityId,
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

  /// Atribuir alunos à série inteira — "todas as semanas", e não só a
  /// uma aula.
  ///
  /// Entra em `preAssignedMemberIds` (que a geração semanal já usa
  /// para marcar as aulas futuras assim que as cria) E marca as aulas
  /// que já estão geradas, uma a uma, com as mesmas validações de
  /// capacidade, plano e limite semanal.
  ///
  /// Uma semana que falhe — sala cheia, limite esgotado — não impede
  /// as outras. Daí devolver a contagem por aluno em vez de um
  /// sim/não: "marcado em 6 das 8 semanas" é acionável, um erro só não
  /// é.
  Future<SeriesAssignmentResult> assignMembersToSeries({
    required String seriesId,
    required List<String> memberIds,
    bool isExtra = false,
  });
}

/// O que aconteceu ao atribuir alunos a uma série inteira.
class SeriesAssignmentResult {
  const SeriesAssignmentResult({
    required this.occurrences,
    required this.porMembro,
  });

  /// Quantas aulas futuras já geradas foram percorridas.
  final int occurrences;

  /// Por aluno: quantas semanas ficaram marcadas e quantas não deram.
  final Map<String, ({int assigned, int skipped})> porMembro;

  int get totalAssigned =>
      porMembro.values.fold(0, (soma, r) => soma + r.assigned);
  int get totalSkipped =>
      porMembro.values.fold(0, (soma, r) => soma + r.skipped);
}
