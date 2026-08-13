import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/member_summary.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/plan_service.dart';
import '../../domain/entities/service.dart';
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
