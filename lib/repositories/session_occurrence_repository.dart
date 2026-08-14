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

  /// Fase 5 — ocorrência "só esta data" (UC17/UC19 atualizado), sem
  /// série associada. Escrita direta do cliente pelo Manager
  /// (`firestore.rules`: `activeBookingCount` tem de nascer a 0).
  /// Devolve o id do documento criado.
  Future<String> createOccurrence({
    required String serviceId,
    String? instructorId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  });

  /// Editar UMA ocorrência (ad-hoc ou gerada por série) sem afetar mais
  /// nada — nunca toca em `activeBookingCount` (as Security Rules
  /// bloqueiam essa alteração por este caminho; só as Cloud Functions
  /// de booking podem mudar esse campo).
  Future<void> updateOccurrence({
    required String occurrenceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
    String? instructorId,
  });

  /// Cancela só esta ocorrência (`status = cancelled`) — não cascata
  /// para bookings/usage (isso é Fase 6, "Cancelamento de sessão pelo
  /// estúdio", UC18/UC10). Bookings ativos ficam por resolver
  /// manualmente até essa fase; sinalizado, não escondido.
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
  Future<Map<String, bool>> assignMembers({
    required String occurrenceId,
    required List<String> memberIds,
  });
}
