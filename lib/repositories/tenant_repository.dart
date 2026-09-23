import '../domain/entities/tenant.dart';

abstract class TenantRepository {
  Future<Tenant?> getTenant(String tenantId);

  /// Fase 4 — "Cancelamento devolve usage se dentro da janela permitida
  /// (antecedência mínima)". Decisão (Carlos): um único valor por
  /// tenant, não por Plan/Service. Lido de
  /// `tenants/{tenantId}/config/bookingPolicy`; `0` (sem restrição) se
  /// o documento ainda não existir — é o default seguro: não bloqueia
  /// nada até o Gestor configurar explicitamente um valor.
  Future<int> getMinCancellationNoticeHours(String tenantId);

  /// Só chamável pelo Gestor (Security Rules: `config/{configId}`
  /// exige `isManager`).
  Future<void> setMinCancellationNoticeHours({
    required String tenantId,
    required int hours,
  });

  /// Fase 8 (auditoria funcional, UC06/UC07/UC08/UC09 fechado) —
  /// "antecedência mínima para MARCAR" (não confundir com
  /// [getMinCancellationNoticeHours], que é sobre cancelar). Mesmo
  /// documento (`tenants/{tenantId}/config/bookingPolicy`), campo
  /// irmão `minBookingNoticeMinutes`. Só se aplica a marcação
  /// self-service (`createBooking`/`bookFreeTrainingSlot`) — atribuição
  /// manual por Instrutor/Gestor nunca passa por esta validação, mesmo
  /// espírito de UC08-A. `0` (sem restrição) se o documento ainda não
  /// existir.
  Future<int> getMinBookingNoticeMinutes(String tenantId);

  /// Fase 11 — qual dos serviços do estúdio É o treino livre.
  ///
  /// O treino livre precisa de um serviço como qualquer outra marcação:
  /// é o que liga o bloco ao plano do aluno e ao limite semanal. Mas é
  /// SEMPRE o mesmo serviço — e a app perguntava-o duas vezes, ao criar
  /// a grelha da semana e outra vez em cada bloco.
  ///
  /// Passou a ser uma escolha única, nas Definições. `null` = ainda não
  /// foi escolhido, e nesse caso o ecrã de treino livre diz o que
  /// falta em vez de pedir um serviço a cada passo.
  Future<String?> getFreeTrainingServiceId(String tenantId);

  Future<void> setFreeTrainingServiceId({
    required String tenantId,
    required String? serviceId,
  });

  Future<void> setMinBookingNoticeMinutes({
    required String tenantId,
    required int minutes,
  });

  /// Quantos dias para a frente o aluno consegue marcar.
  ///
  /// As séries geram ocorrências com 8 semanas de antecedência, para o
  /// estúdio poder planear. O aluno via-as todas — dois meses de aulas
  /// numa lista, quando a decisão que ele está a tomar é sobre esta
  /// semana ou a próxima.
  ///
  /// Não é só ruído: marcar com dois meses de antecedência ocupa uma
  /// vaga que ninguém mais pode usar, e quem marcou já não se lembra de
  /// lá ir. Um horizonte curto é o que mantém as vagas a circular.
  ///
  /// Vive ao lado de `minBookingNoticeMinutes`, no mesmo documento —
  /// são as duas pontas da mesma janela: não marcar demasiado em cima
  /// da hora, nem demasiado longe.
  ///
  /// `0` = sem limite, e é o valor por omissão para não mudar o
  /// comportamento de um estúdio que já esteja a usar a app sem saber
  /// desta definição.
  Future<int> getBookingHorizonDays(String tenantId);

  Future<void> setBookingHorizonDays({
    required String tenantId,
    required int days,
  });

  /// Fase 11 — com quantas horas de antecedência sai o lembrete da
  /// aula. `0` = lembretes desligados.
  ///
  /// Vive em `config/notificationPolicy` e não em `bookingPolicy`
  /// porque não decide se uma marcação é válida — decide só quando é
  /// que se avisa. 12 horas por omissão: apanha a aula da manhã
  /// seguinte na noite anterior, que é quando ainda dá para cancelar a
  /// tempo de alguém da lista de espera aproveitar o lugar.
  Future<int> getSessionReminderHours(String tenantId);

  Future<void> setSessionReminderHours({
    required String tenantId,
    required int hours,
  });
}
