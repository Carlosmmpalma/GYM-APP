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
  /// Fase 11 — cancelar, pausar ou reativar. Sem isto, uma subscrição
  /// ficava ativa para sempre e trocar um aluno de nível de plano era
  /// impossível dentro da app (o `exclusiveGroup` recusa o segundo, e
  /// não havia como terminar o primeiro).
  ///
  /// Não mexe nas marcações já feitas — ver `updateSubscriptionStatus.ts`.
  Future<void> updateSubscriptionStatus({
    required String subscriptionId,
    required SubscriptionStatus status,
  });

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

  /// Fase 4 story 7 — só para MOSTRAR a barra "X/Y sessões esta
  /// semana" (`book_training_screen.dart`); a autoridade sobre
  /// elegibilidade/limite continua a ser sempre a Cloud Function
  /// `createBooking`, que faz esta mesma pesquisa outra vez do lado do
  /// servidor. Devolve o `planId` da subscription ativa que dá acesso
  /// a [serviceId], ou `null` se não houver nenhuma (Domain Model v1
  /// §15 garante que nunca há mais do que uma).
  Future<String?> getGrantingPlanId({
    required String memberId,
    required String serviceId,
  });

  /// Fase 5 (UC08-A fechado) — TODOS os memberIds com uma subscription
  /// ativa que dá acesso a [serviceId]. Usado pelo picker de
  /// pré-atribuição em `ManageSeriesScreen`/criação de série ou
  /// ocorrência, para só mostrar quem já tem o serviço contratado —
  /// a mesma regra que já bloqueava a marcação, aplicada agora à
  /// pesquisa em vez de só ao bloquear depois de escolhido.
  Stream<Set<String>> watchEligibleMemberIds(String serviceId);
}
