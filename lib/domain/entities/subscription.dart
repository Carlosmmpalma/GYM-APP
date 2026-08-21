import 'package:equatable/equatable.dart';

/// Domain Model v1 §16 — uma subscription nunca é apagada quando deixa
/// de estar ativa; o histórico fica disponível. `expired` cobre o caso
/// de `endDate` já ter passado (calculado, não necessariamente um
/// estado escrito explicitamente pelo MVP — ver `SubscriptionRepository`).
enum SubscriptionStatus {
  active,
  paused,
  cancelled,
  expired;

  static SubscriptionStatus fromValue(String value) =>
      SubscriptionStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => throw ArgumentError('Estado desconhecido: $value'),
      );
}

/// Domain Model v1 §14/18 — a contratação concreta de um [Plan] por um
/// membro. `agreedPrice` é deliberadamente separado do `currentPrice`
/// do Plan (Domain Model v1 §18): subir o preço do Plan não deve mudar
/// retroativamente o que um membro já contratado paga.
///
/// [activeServiceIds] é informação DERIVADA do Plan no momento da
/// contratação (Firestore Data Model v1 §18) — guardada aqui para
/// permitir a pergunta "este membro tem acesso a este serviço?" sem
/// nenhuma query extra (Plan → PlanService → Service). A fonte
/// conceptual continua a ser o Plan; isto é só um índice de leitura
/// rápida, montado pela Cloud Function `createSubscription`.
class Subscription extends Equatable {
  const Subscription({
    required this.id,
    required this.memberId,
    required this.planId,
    required this.status,
    required this.startDate,
    required this.agreedPrice,
    required this.currency,
    required this.activeServiceIds,
    this.endDate,
  });

  final String id;
  final String memberId;
  final String planId;
  final SubscriptionStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final double agreedPrice;
  final String currency;
  final Set<String> activeServiceIds;

  bool get isActive => status == SubscriptionStatus.active;

  /// UC06/07/08/09 + Firestore Data Model v1 §18 — "este membro tem uma
  /// subscription ativa que concede acesso a este service?".
  bool grantsAccessTo(String serviceId) =>
      isActive && activeServiceIds.contains(serviceId);

  @override
  List<Object?> get props => [
        id,
        memberId,
        planId,
        status,
        startDate,
        endDate,
        agreedPrice,
        currency,
        activeServiceIds,
      ];
}

/// UC06/07/08/09 (fechado) — "aluno sem o serviço contratado é
/// bloqueado ao tentar marcar-se" (Fase 3, critério "Done"). Exceção
/// dedicada para a UI mostrar uma mensagem específica, distinta de
/// "sem vagas" ou "já marcado" (Fase 2).
class NotEligibleForServiceException implements Exception {
  const NotEligibleForServiceException();

  @override
  String toString() => 'Não tens um plano ativo que dê acesso a este serviço.';
}

/// Domain Model v1 §15 — "por defeito, um membro não pode possuir
/// simultaneamente duas subscriptions ativas que concedam acesso ao
/// mesmo Service". Lançada pela Cloud Function `createSubscription` e
/// mapeada para esta exceção no cliente (ver
/// `firebase_subscription_repository.dart`).
class SubscriptionServiceConflictException implements Exception {
  const SubscriptionServiceConflictException(this.conflictingServiceNames);

  final List<String> conflictingServiceNames;

  @override
  String toString() => conflictingServiceNames.isEmpty
      ? 'Este membro já tem uma subscription ativa com serviços em comum.'
      : 'Este membro já tem acesso a: ${conflictingServiceNames.join(', ')} '
          'através de outra subscription ativa.';
}
