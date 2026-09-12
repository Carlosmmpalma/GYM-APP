import '../domain/entities/attendance.dart';
import '../domain/entities/booking.dart';
import '../domain/entities/free_training_schedule.dart';
import '../domain/entities/free_training_slot.dart';

/// Fase 7 (UC09/UC17-A) — "Treino sem acompanhamento": grelha semanal
/// (`FreeTrainingSchedule`) + blocos reserváveis (`FreeTrainingSlot`).
/// Reutiliza [Booking]/[Attendance] (mesmo conceito geral, Firestore
/// Data Model v1 §40) em vez de entidades próprias — só o caminho
/// muda (`freeTrainingSchedules/{weekId}/slots/{slotId}/...` em vez de
/// `sessionOccurrences/{id}/...`), por isso os métodos abaixo pedem
/// sempre `weekId`+`slotId` em vez de um único `occurrenceId`.
abstract class FreeTrainingRepository {
  Stream<FreeTrainingSchedule?> watchSchedule(String weekId);

  Stream<List<FreeTrainingSlot>> watchSlots(String weekId);

  /// UC09/UC17 fechado — só o Gestor/Instrutor conseguem listar todas
  /// (nomes); um Aluno só lê a própria (`firestore.rules` aplica isto
  /// a sério, não só esconde na UI). Chamado pelo ecrã do Aluno com
  /// `memberId` do próprio para saber "já reservei este horário?"
  /// (via `getMyBooking`), não por esta stream.
  Stream<List<Booking>> watchSlotBookings(String weekId, String slotId);

  /// UC09 — o Aluno só precisa de saber se TEM uma marcação neste
  /// slot (para trocar "Reservar" por "Cancelar"), nunca de ver quem
  /// mais está — `get`, não `list` (a Security Rule só permite a
  /// primeira ao próprio membro).
  Future<Booking?> getMyBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  });

  Stream<List<Attendance>> watchSlotAttendance(String weekId, String slotId);

  /// UC17-A fechado — idempotente por `weekId` (derivado de
  /// [weekStart] no servidor): chamar outra vez para uma semana que já
  /// tem grelha (rascunho, sugestão ou publicada) devolve-a sem a
  /// alterar. Copia a semana anterior quando existir (nasce
  /// `suggested`); sem semana anterior, nasce `draft` vazia.
  Future<({String weekId, String status, bool created, int slotsCopied})>
      suggestSchedule({
    required DateTime weekStart,
    required String serviceId,
  });

  /// UC17-A fechado — só fica visível ao Aluno depois disto. Lança se
  /// a semana não tiver nenhum horário ainda.
  Future<void> publishSchedule(String weekId);

  /// Escrita direta do Gestor — montar/ajustar a grelha antes de
  /// publicar (mesmo padrão de ocorrências "só esta data" da Fase 5).
  Future<String> createSlot({
    required String weekId,
    required String serviceId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  });

  /// Fase 8 (auditoria funcional, UC17-A fechado) — editar hora/
  /// capacidade de um bloco já criado (era só `updateSlotCapacity`,
  /// nunca ligado a nenhum ecrã; ganhou `startAt`/`endAt` porque não
  /// fazia sentido só a capacidade ser editável). Nunca toca em
  /// `activeBookingCount` — Security Rules exigem que fique
  /// inalterado nesta escrita, mesmo padrão de
  /// `SessionOccurrenceRepository.updateOccurrence`. Permitido mesmo
  /// depois de publicada (ao contrário de [deleteSlot]).
  Future<void> updateSlot({
    required String weekId,
    required String slotId,
    required DateTime startAt,
    required DateTime endAt,
    required int capacity,
  });

  /// Reaponta para [serviceId] os blocos desta semana que apontam para
  /// outro serviço. Devolve quantos foram corrigidos.
  ///
  /// Existe porque mudar o serviço de treino livre nas Definições não
  /// mexia nos blocos JÁ criados: eles guardam o `serviceId` que estava
  /// configurado no momento em que nasceram. Depois da mudança, o
  /// filtro de elegibilidade do Aluno comparava o serviço do plano com
  /// o serviço (antigo) do bloco, não encontrava nada, e mostrava-lhe
  /// "o teu plano não inclui treino livre" — a alunos cujo plano
  /// incluía mesmo. Um estúdio inteiro podia ficar sem treino livre
  /// sem nada, em lado nenhum, dizer porquê.
  ///
  /// Não toca em `activeBookingCount` (as Security Rules exigem que
  /// fique inalterado nesta escrita, mesmo padrão de [updateSlot]).
  Future<int> retargetSlots({
    required String weekId,
    required String serviceId,
  });

  /// Fase 8 (auditoria funcional, UC17-A fechado) — remover um bloco
  /// só é permitido ANTES de a semana ser publicada (Security Rules).
  /// Depois de publicada, um bloco só pode ser esvaziado (reduzir a
  /// capacidade), nunca apagado — alunos podem já ter marcado.
  Future<void> deleteSlot({
    required String weekId,
    required String slotId,
  });

  /// Lança [SessionNotBookableException], [BookingCapacityExceededException],
  /// [AlreadyBookedException], [NotEligibleForServiceException] ou
  /// [UsageLimitReachedException] — mesmas exceções de
  /// `BookingRepository.createBooking`, mesmo mecanismo por baixo
  /// (`bookingLogic.ts`).
  Future<void> bookSlot({
    required String weekId,
    required String slotId,
    required String memberId,
  });

  /// Lança [BookingNotFoundException] se não houver marcação ativa.
  /// Devolve se a utilização semanal foi devolvida — mesmo contrato de
  /// `BookingRepository.cancelBooking`.
  Future<bool> cancelSlotBooking({
    required String weekId,
    required String slotId,
    required String memberId,
  });

  /// UC08-A/UC17 fechado — atribuição manual pelo Gestor, um resultado
  /// por membro (nunca falha o pedido inteiro por causa de um só).
  Future<Map<String, bool>> assignMembers({
    required String weekId,
    required String slotId,
    required List<String> memberIds,
  });

  /// UC10-A fechado — Manager-only para treino livre (ao contrário de
  /// `AttendanceRepository`, que também aceita Instrutor).
  Future<void> recordAttendance({
    required String weekId,
    required String slotId,
    required String memberId,
    required AttendanceStatus status,
    required String recordedBy,
  });
}
