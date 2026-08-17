import '../domain/entities/session_occurrence.dart';

abstract class SessionOccurrenceRepository {
  /// Fase 2: lista todas as ocorrências futuras de um serviço. Sem
  /// paginação/filtros por instrutor/modalidade ainda — isso é Fase 5+
  /// (Firestore Data Model v1 §47, secção Calendar).
  Stream<List<SessionOccurrence>> watchUpcomingOccurrences(String serviceId);

  /// Todas as ocorrências futuras, qualquer serviço — usado por
  /// `BookTrainingScreen` a partir da Fase 5 (antes disso, a app tinha
  /// sempre só um Service, por isso `watchUpcomingOccurrences` bastava;
  /// com várias séries a poderem apontar para serviços diferentes,
  /// filtrar por um só escondia sessões reais do aluno sem nenhum aviso
  /// — bug real, corrigido depois de reportado).
  Stream<List<SessionOccurrence>> watchUpcomingOccurrencesAllServices();

  Future<SessionOccurrence?> getOccurrence(String occurrenceId);

  /// Fase 6 — versão reativa de [getOccurrence], para
  /// `OccurrenceDetailScreen` refletir ao vivo `activeBookingCount`/
  /// `capacity` depois de ações como reduzir vagas ou cancelar.
  Stream<SessionOccurrence?> watchOccurrence(String occurrenceId);

  /// Fase 5 — ocorrência "só esta data" (UC17/UC19 atualizado), sem
  /// série associada. Escrita direta do cliente pelo Manager
  /// (`firestore.rules`: `activeBookingCount` tem de nascer a 0).
  /// Devolve o id do documento criado.
  Future<String> createOccurrence({
    required String serviceId,
    String? instructorId,
    String? modalityId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  });

  /// Editar UMA ocorrência (ad-hoc ou gerada por série) sem afetar mais
  /// nada — nunca toca em `activeBookingCount` nem em `status` (as
  /// Security Rules bloqueiam ambos por este caminho desde a Fase 6:
  /// cancelar passa sempre por [cancelOccurrence]/Cloud Function).
  Future<void> updateOccurrence({
    required String occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
    String? instructorId,
    String? modalityId,
  });

  /// Fase 6 — cancela esta ocorrência E cancela/devolve usage de TODAS
  /// as marcações ativas nela (UC18/UC10, `cancelOccurrenceForStudio`
  /// Cloud Function — antes da Fase 6 isto era uma escrita direta do
  /// cliente sem cascata nenhuma; a própria Fase 5 já tinha assinalado
  /// essa lacuna).
  Future<void> cancelOccurrence(String occurrenceId);

  /// Ocorrências materializadas a partir de uma [SessionSeries] — usada
  /// por "ajustar uma semana da série" (`SeriesDetailScreen`).
  Stream<List<SessionOccurrence>> watchOccurrencesForSeries(String seriesId);

  /// UC25 — todas as ocorrências (qualquer serviço) com `startAt` em
  /// `[from, to)`, para a "Visão global" do Gestor calcular ocupação
  /// agregada. Ao contrário de [watchUpcomingOccurrences], não filtra
  /// por `serviceId` — é por isso que existe como método separado, não
  /// uma variante do mesmo.
  Stream<List<SessionOccurrence>> watchOccurrencesStartingBetween(
    DateTime from,
    DateTime to,
  );

  /// UC17/UC19 (modelo híbrido, fechado) — atribui manualmente um ou
  /// mais membros a esta ocorrência via Cloud Function
  /// `assignMembersToOccurrence`: mesma validação de
  /// elegibilidade/capacidade/limite semanal de um booking normal,
  /// `source: manager`. Devolve, por `memberId`, se a atribuição teve
  /// sucesso — a falha de um membro (sem vaga, sem plano ativo) nunca
  /// impede os restantes.
  ///
  /// [isExtra] — UC08-A (fechado), "+ Sessão extra" no mockup: isenta
  /// estes membros do limite semanal do PRÓPRIO plano (nunca da
  /// capacidade da sala, que se aplica sempre). `false` por omissão —
  /// atribuição manual normal conta para o limite como uma marcação
  /// qualquer (UC08 fechado: "por omissão, atribuir = contar").
  Future<Map<String, bool>> assignMembers({
    required String occurrenceId,
    required List<String> memberIds,
    bool isExtra = false,
  });

  /// UC18 (atualizado) — "reduzir vagas com seleção explícita de quem
  /// remover": liberta cada `memberId` (vaga + usage SEMPRE devolvida —
  /// estúdio-iniciado, ver `removeMembersFromOccurrence.ts`) e,
  /// opcionalmente, baixa `capacity` para [newCapacity]. Devolve os
  /// `memberId`s efetivamente libertados (quem já não estava `booked`
  /// é ignorado, não é erro).
  Future<List<String>> removeMembers({
    required String occurrenceId,
    required List<String> memberIds,
    int? newCapacity,
  });

  /// UC10-B — remarcar um membro de uma ocorrência para outra (Cloud
  /// Function `rescheduleBooking`). **Não é atómico**: se a marcação
  /// no destino falhar, a origem já foi cancelada — ver nota de
  /// arquitetura em `rescheduleBooking.ts`. Lança
  /// [RescheduleFailedException] nesse caso (distingue de "não tinha
  /// marcação na origem", que é um erro comum/esperado).
  Future<void> rescheduleBooking({
    required String fromOccurrenceId,
    required String toOccurrenceId,
    required String memberId,
  });
}

/// UC10-B — a origem já foi cancelada quando isto é lançado (ver
/// `rescheduleBooking.ts`); a mensagem já reflete isso, não é um erro
/// "nada aconteceu" como as outras exceções de booking.
class RescheduleFailedException implements Exception {
  const RescheduleFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}
