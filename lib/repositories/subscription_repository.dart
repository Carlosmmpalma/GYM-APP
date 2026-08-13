import '../domain/entities/subscription.dart';

/// Fase 3 (guia-desenvolvimento.md) — Repository Pattern (Platform
/// Foundation §12).
abstract class SubscriptionRepository {
  /// UC06/07/08/09 — fonte usada pela query de elegibilidade
  /// (`is_eligible_for_service_use_case.dart`) e pelo ecrã "Minhas
  /// marcações" no futuro (mostrar o plano do membro).
  Stream<List<Subscription>> watchMemberSubscriptions(String memberId);

  /// Cria a subscription via Cloud Function `createSubscription` — ver
  /// nota de arquitetura em `firebase_subscription_repository.dart`
  /// sobre porque isto não é uma transação client-side como em Fase 2.
  ///
  /// Lança [SubscriptionServiceConflictException] se o membro já tiver
  /// outra subscription ativa que dá acesso a algum dos serviços deste
  /// Plan (Domain Model v1 §15).
  Future<void> createSubscription({
    required String memberId,
    required String planId,
    required double agreedPrice,
    required String currency,
  });

  /// UC06/07/08/09 — "este membro pode reservar este serviço?" Usada
  /// por [BookSessionUseCase] para bloquear a marcação antes de sequer
  /// tentar a transação de booking, e pelo futuro picker de atribuição
  /// manual (UC08-A/17/19, Fase 5+).
  Future<bool> isEligibleForService({
    required String memberId,
    required String serviceId,
  });
}
