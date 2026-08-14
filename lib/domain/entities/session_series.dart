import 'package:equatable/equatable.dart';

enum SessionSeriesStatus { active, cancelled }

/// Definição de uma série recorrente semanal (Domain Model v1 §20,
/// Firestore Data Model v1 §21) — "aulas/PT todas as semanas a esta
/// hora" (Fase 5, guia-desenvolvimento.md). A série em si nunca é
/// reservável: quem gera as ocorrências concretas (reserváveis) é a
/// Cloud Function `generateRecurringOccurrences`
/// (`firebase/functions/src/generateRecurringOccurrences.ts`), que
/// materializa `SessionOccurrence`s com `seriesId` apontando para aqui.
///
/// `dayOfWeek` segue a mesma convenção já usada em `iso_week.dart`
/// (`DateTime.weekday`: segunda=1 … domingo=7).
class SessionSeries extends Equatable {
  const SessionSeries({
    required this.id,
    required this.serviceId,
    required this.dayOfWeek,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
    required this.startDate,
    required this.status,
    this.instructorId,
    this.modalityId,
    this.preAssignedMemberIds = const [],
  });

  final String id;
  final String serviceId;

  /// Instrutor responsável (opcional — Domain Model v1 §31, relação
  /// informativa; não bloqueia nenhuma atribuição). `null` quando a
  /// série não tem instrutor definido.
  final String? instructorId;

  /// Fase 6 (Domain Model v1 §8-9) — opcional; `null` em séries
  /// anteriores a esta fase ou sem modalidade definida (nem todo
  /// serviço tem modalidade, ex.: "Treino sem acompanhamento").
  final String? modalityId;

  /// segunda=1 … domingo=7 (`DateTime.weekday`).
  final int dayOfWeek;

  /// "HH:mm" (ex.: "18:00") — espelha o exemplo do Firestore Data
  /// Model v1 §21. Formato validado na criação (`SessionSeriesRepository`),
  /// não neste construtor.
  final String startTime;

  final int durationMinutes;
  final int capacity;

  /// A partir de quando a série passa a gerar ocorrências — permite
  /// criar hoje uma série que só começa daqui a duas semanas (ex.:
  /// depois de um feriado), sem gerar ocorrências retroativas.
  final DateTime startDate;

  /// UC17/UC19 (fechado) — modelo híbrido: estes membros são marcados
  /// automaticamente em CADA ocorrência que a Cloud Function materializa
  /// a partir desta série (`source: manager`, mesma validação de
  /// elegibilidade/limite/capacidade de um booking normal — falhas
  /// individuais não impedem a geração da ocorrência nem a atribuição
  /// dos restantes). As vagas que sobrarem ficam abertas para
  /// auto-marcação, como qualquer outra ocorrência.
  final List<String> preAssignedMemberIds;

  final SessionSeriesStatus status;

  bool get isActive => status == SessionSeriesStatus.active;

  /// UC19 — label de conveniência para a UI; nunca persistida. O
  /// "tipo" (Individual/Duo/Trio/Grupo) é sempre calculado a partir de
  /// `capacity`, nunca um enum no modelo de dados.
  String get capacityLabel => switch (capacity) {
        1 => 'Individual',
        2 => 'Duo',
        3 => 'Trio',
        _ => 'Grupo ($capacity)',
      };

  SessionSeries copyWith({SessionSeriesStatus? status}) => SessionSeries(
        id: id,
        serviceId: serviceId,
        instructorId: instructorId,
        modalityId: modalityId,
        dayOfWeek: dayOfWeek,
        startTime: startTime,
        durationMinutes: durationMinutes,
        capacity: capacity,
        startDate: startDate,
        preAssignedMemberIds: preAssignedMemberIds,
        status: status ?? this.status,
      );

  @override
  List<Object?> get props => [
        id,
        serviceId,
        instructorId,
        modalityId,
        dayOfWeek,
        startTime,
        durationMinutes,
        capacity,
        startDate,
        preAssignedMemberIds,
        status,
      ];
}
