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
import '../../infrastructure/firebase/firebase_catalogue_admin_repository.dart';
import '../../repositories/catalogue_admin_repository.dart';
import 'admin_providers.dart';

final catalogueAdminRepositoryProvider =
    Provider<CatalogueAdminRepository>((ref) {
  return FirebaseCatalogueAdminRepository(ref.watch(functionsProvider));
});

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return FirebasePlanRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
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

/// Só o NÚMERO de membros ativos, para o painel do Gestor.
///
/// Ver `MemberRepository.countActiveMembers`: o painel é o primeiro
/// ecrã que um Gestor vê, e mostrava dois números lendo as coleções
/// inteiras. Quem for depois a Gestão › Membros paga a lista nessa
/// altura, que é quando ela serve para alguma coisa.
final activeMemberCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(memberRepositoryProvider).countActiveMembers();
});

final membersProvider = StreamProvider<List<MemberSummary>>((ref) {
  return ref.watch(memberRepositoryProvider).watchMembers();
});

/// UC02 — o próprio membro a ver/editar o seu perfil (`MyProfileScreen`).
/// `.family` por uid em vez de derivar de `currentAppUserProvider`
/// diretamente: mantém o provider testável sem depender de sessão real.
final memberProfileProvider =
    StreamProvider.autoDispose.family<MemberSummary?, String>((ref, uid) {
  return ref.watch(memberRepositoryProvider).watchMember(uid);
});

/// `FutureProvider.family`, não `StreamProvider` — a lista de serviços
/// de um Plan (Fase 3) não precisa de atualização em tempo real ao
/// nível da UI de gestão; um `ref.invalidate(planServicesProvider(id))`
/// depois de cada escrita (mesmo padrão já usado em
/// `booking_providers.dart` para contornar a propagação de listeners)
/// chega, e evita manter uma subscrição aberta por cada Plan visitado.
final planServicesProvider =
    FutureProvider.autoDispose.family<List<PlanService>, String>((ref, planId) {
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
final memberSubscriptionsProvider = StreamProvider.autoDispose
    .family<List<Subscription>, String>((ref, memberId) {
  return ref
      .watch(subscriptionRepositoryProvider)
      .watchMemberSubscriptions(memberId);
});

/// Fase 11 — os serviços a que o utilizador autenticado tem MESMO
/// direito hoje.
///
/// Um aluno via o horário inteiro do ginásio e só descobria que não
/// podia marcar Pilates ao tocar em "Marcar" e receber um erro. Isto é
/// mau de duas formas: obriga a tentar para saber, e mostra como oferta
/// aquilo que na verdade é uma venda por fazer.
///
/// Deriva das MESMAS subscrições que o servidor consulta
/// (`isEligibleForService` faz `status == active` +
/// `activeServiceIds arrayContains`) — de propósito. Se a UI filtrasse
/// por outro critério, haveria sempre um caso em que mostra o que a
/// Cloud Function recusa, ou esconde o que ela aceitaria.
///
/// Nota sobre o que isto NÃO é: não substitui a validação do servidor,
/// que continua a ser a única que conta (`createBooking`/
/// `bookFreeTrainingSlot` verificam elegibilidade, capacidade e limite
/// semanal dentro de uma transação). Isto só evita mostrar portas
/// fechadas.
///
/// Conjunto VAZIO e `null` querem dizer coisas diferentes: vazio é "não
/// tem direito a nada" (mostra-se o estado próprio); `null`, enquanto
/// carrega, evita esconder o horário todo por um instante.
final myEligibleServiceIdsProvider =
    StreamProvider.autoDispose<Set<String>>((ref) {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null) return Stream.value(const <String>{});

  return ref
      .watch(subscriptionRepositoryProvider)
      .watchMemberSubscriptions(appUser.uid)
      .map((subscriptions) {
    // `grantsAccessAt` e não `isActive`: um plano com data de fim já
    // passada continua com `status: active` na base de dados, e
    // durante muito tempo continuava a dar acesso por causa disso.
    final now = DateTime.now();
    return {
      for (final subscription in subscriptions)
        if (subscription.grantsAccessAt(now)) ...subscription.activeServiceIds,
    };
  });
});

/// Fase 4 story 7 — a [UsageRule] aplicável a um membro+serviço, para
/// `book_training_screen.dart` decidir se mostra a barra "X/Y sessões
/// esta semana" (só quando `!rule.isUnlimited`). Só para DISPLAY — não
/// é a fonte de verdade da validação, que é sempre a Cloud Function
/// `createBooking` (ver `subscription_repository.dart`,
/// `getGrantingPlanId`). `null` quando o membro não tem nenhuma
/// subscription ativa que dê acesso a este serviço (o mesmo caso que
/// bloqueia o booking com `NotEligibleForServiceException`).
final applicableUsageRuleProvider = FutureProvider.autoDispose
    .family<UsageRule?, ({String memberId, String serviceId})>(
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

/// Fase 10 (UC26 atualizado) — a que grupo exclusivo pertence cada
/// Plan ativo, para o picker agrupado de `AssignSubscriptionScreen`.
///
/// O mockup mostra a atribuição orientada a SERVIÇOS, com os níveis do
/// mesmo produto em seleção única ("Nível de treino de sala: Sem
/// acompanhamento / Standard / Plus / Premium") e os extras em seleção
/// múltipla ("Aulas de grupo"). No nosso modelo o que se atribui é um
/// Plan, e a exclusividade vive no Service (`Service.exclusiveGroup`,
/// acrescentado na auditoria da Fase 8) — por isso o grupo de um Plan
/// deriva dos serviços a que ele dá acesso.
///
/// Um Plan cujos serviços caiam em DOIS grupos exclusivos diferentes
/// não pode ser uma opção única de nenhum deles (estaria em dois sítios
/// ao mesmo tempo); esse caso conta como plano independente, e é
/// deliberado — a alternativa seria escolher um dos grupos à sorte.
/// Devolve `{planId: grupo ou null}`; `null` = plano independente.
final planExclusiveGroupsProvider =
    FutureProvider.autoDispose<Map<String, String?>>((ref) async {
  final plans = await ref.watch(plansProvider.future);
  final services = await ref.watch(servicesProvider.future);
  // Lido ANTES do primeiro await do ciclo: `ref.watch` depois de um
  // await async assinaria o provider fora do build e o Riverpod avisa.
  final planRepository = ref.watch(planRepositoryProvider);

  final groupOfService = {
    for (final service in services) service.id: service.exclusiveGroup,
  };

  final result = <String, String?>{};
  for (final plan in plans.where((p) => p.active)) {
    final planServices = await planRepository.getPlanServices(plan.id);
    final groups = planServices
        .where((ps) => ps.enabled)
        .map((ps) => groupOfService[ps.serviceId])
        .whereType<String>()
        .toSet();
    result[plan.id] = groups.length == 1 ? groups.single : null;
  }
  return result;
});

/// Fase 5 (UC08-A fechado) — membros elegíveis para um serviço (têm uma
/// subscription ativa que dá acesso a ele), para o picker de
/// pré-atribuição em `ManageSeriesScreen`. Cruza
/// `watchEligibleMemberIds` (só ids) com `membersProvider` (para
/// mostrar nomes) — mesmo raciocínio de `memberSubscriptionsProvider`
/// acima: nenhum ecrã anterior precisava disto, por isso não existia
/// nenhum provider que já desse a lista de membros filtrada por
/// elegibilidade a um serviço.
/// Os alunos que o utilizador atual deve ver.
///
/// O Gestor vê todos — é ele que gere o estúdio. Um **Instrutor** passa
/// a ver só os alunos que contrataram algum dos serviços que ele
/// leciona (`staff.serviceIds`).
///
/// Não existe no domínio uma relação "aluno → instrutor": um aluno
/// contrata um SERVIÇO, e o instrutor leciona serviços. Isso é o que
/// define "os meus alunos", e é a leitura mais próxima do que o mockup
/// pedia ("só alunos com serviço na tua modalidade") sem inventar uma
/// atribuição que ninguém faria à mão.
///
/// ⚠️ **Isto é âmbito, não segurança.** As Security Rules deixam
/// qualquer Instrutor ler qualquer membro do tenant (`members`, `allow
/// read: if isInstructor(...)`). Filtrar aqui tira o ruído e evita o
/// acesso acidental; não impede o deliberado. Tornar isto uma barreira
/// a sério obrigaria a denormalizar os serviços contratados no
/// documento do membro, para a Rule os poder comparar sem um `get()`
/// por documento — assinalado, não escondido.
final visibleMembersProvider = StreamProvider<List<MemberSummary>>((ref) {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  final members = ref.watch(membersProvider).valueOrNull ?? const [];

  if (appUser == null) return Stream.value(const <MemberSummary>[]);
  if (appUser.isManager) return Stream.value(members);

  final me = (ref.watch(staffProvider).valueOrNull ?? const [])
      .where((s) => s.uid == appUser.uid)
      .firstOrNull;
  final myServices = me?.serviceIds ?? const <String>{};

  return ref
      .watch(subscriptionRepositoryProvider)
      .watchEligibleMemberIdsForServices(myServices)
      .map((ids) => members.where((m) => ids.contains(m.uid)).toList());
});

final eligibleMembersProvider = StreamProvider.autoDispose
    .family<List<MemberSummary>, String>((ref, serviceId) {
  final eligibleIdsAsync = ref
      .watch(subscriptionRepositoryProvider)
      .watchEligibleMemberIds(serviceId);
  final membersAsync = ref.watch(membersProvider);

  return eligibleIdsAsync.map((eligibleIds) {
    final members = membersAsync.valueOrNull ?? const <MemberSummary>[];
    return members.where((m) => eligibleIds.contains(m.uid)).toList();
  });
});
