import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/plan_service.dart';
import '../../domain/entities/service.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/entities/usage_rule.dart';
import '../../infrastructure/firebase/firebase_member_repository.dart';
import '../../infrastructure/firebase/firebase_plan_repository.dart';
import '../../repositories/member_repository.dart';
import '../../repositories/plan_repository.dart';
import 'booking_providers.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return FirebasePlanRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return FirebaseMemberRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final plansProvider = StreamProvider<List<Plan>>((ref) {
  return ref.watch(planRepositoryProvider).watchPlans();
});

final membersProvider = StreamProvider<List<MemberSummary>>((ref) {
  return ref.watch(memberRepositoryProvider).watchMembers();
});

/// UC02 — o próprio membro a ver/editar o seu perfil (`MyProfileScreen`).
/// `.family` por uid em vez de derivar de `currentAppUserProvider`
/// diretamente: mantém o provider testável sem depender de sessão real.
final memberProfileProvider =
    StreamProvider.family<MemberSummary?, String>((ref, uid) {
  return ref.watch(memberRepositoryProvider).watchMember(uid);
});

/// `FutureProvider.family`, não `StreamProvider` — a lista de serviços
/// de um Plan (Fase 3) não precisa de atualização em tempo real ao
/// nível da UI de gestão; um `ref.invalidate(planServicesProvider(id))`
/// depois de cada escrita (mesmo padrão já usado em
/// `booking_providers.dart` para contornar a propagação de listeners)
/// chega, e evita manter uma subscrição aberta por cada Plan visitado.
final planServicesProvider =
    FutureProvider.family<List<PlanService>, String>((ref, planId) {
  return ref.watch(planRepositoryProvider).getPlanServices(planId);
});

/// Fase 3 (UC26) — TODOS os Services do tenant (ativos e inativos), para
/// `ManageServicesScreen`. `serviceRepositoryProvider` já existe em
/// `booking_providers.dart` desde a Fase 2 (`getActiveServices()`, usado
/// no fluxo de booking); este provider reaproveita o mesmo repository,
/// só adiciona a visão sem filtro que a gestão precisa.
final servicesProvider = StreamProvider<List<Service>>((ref) {
  return ref.watch(serviceRepositoryProvider).watchServices();
});

/// Pedido pelo Carlos depois de testar a Fase 3: nem `AssignSubscriptionScreen`
/// nem nenhum outro ecrã mostravam os planos que um membro já tem — só se
/// descobria um conflito depois de tentar submeter. `subscriptionRepositoryProvider`
/// já expõe `watchMemberSubscriptions()` desde a Fase 3 (é a mesma fonte
/// usada por `isEligibleForService`); só faltava um provider Riverpod
/// `.family` para o usar por `memberId` a partir da UI.
final memberSubscriptionsProvider =
    StreamProvider.family<List<Subscription>, String>((ref, memberId) {
  return ref
      .watch(subscriptionRepositoryProvider)
      .watchMemberSubscriptions(memberId);
});

/// Fase 4 story 7 — a [UsageRule] aplicável a um membro+serviço, para
/// `book_training_screen.dart` decidir se mostra a barra "X/Y sessões
/// esta semana" (só quando `!rule.isUnlimited`). Só para DISPLAY — não
/// é a fonte de verdade da validação, que é sempre a Cloud Function
/// `createBooking` (ver `subscription_repository.dart`,
/// `getGrantingPlanId`). `null` quando o membro não tem nenhuma
/// subscription ativa que dê acesso a este serviço (o mesmo caso que
/// bloqueia o booking com `NotEligibleForServiceException`).
final applicableUsageRuleProvider =
    FutureProvider.family<UsageRule?, ({String memberId, String serviceId})>(
        (ref, args) async {
  final planId =
      await ref.watch(subscriptionRepositoryProvider).getGrantingPlanId(
            memberId: args.memberId,
            serviceId: args.serviceId,
          );
  if (planId == null) return null;

  final planServices =
      await ref.watch(planRepositoryProvider).getPlanServices(planId);
  for (final planService in planServices) {
    if (planService.serviceId == args.serviceId && planService.enabled) {
      return planService.usage;
    }
  }
  return null;
});

/// Fase 5 (UC08-A fechado) — membros elegíveis para um serviço (têm uma
/// subscription ativa que dá acesso a ele), para o picker de
/// pré-atribuição em `ManageSeriesScreen`. Cruza
/// `watchEligibleMemberIds` (só ids) com `membersProvider` (para
/// mostrar nomes) — mesmo raciocínio de `memberSubscriptionsProvider`
/// acima: nenhum ecrã anterior precisava disto, por isso não existia
/// nenhum provider que já desse a lista de membros filtrada por
/// elegibilidade a um serviço.
final eligibleMembersProvider =
    StreamProvider.family<List<MemberSummary>, String>((ref, serviceId) {
  final eligibleIdsAsync = ref
      .watch(subscriptionRepositoryProvider)
      .watchEligibleMemberIds(serviceId);
  final membersAsync = ref.watch(membersProvider);

  return eligibleIdsAsync.map((eligibleIds) {
    final members = membersAsync.valueOrNull ?? const <MemberSummary>[];
    return members.where((m) => eligibleIds.contains(m.uid)).toList();
  });
});
