import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/retention_overview.dart';
import '../../domain/entities/staff_private_profile.dart';
import '../../domain/entities/staff_summary.dart';
import '../../infrastructure/firebase/firebase_retention_repository.dart';
import '../../infrastructure/firebase/firebase_staff_repository.dart';
import '../../infrastructure/firebase/firebase_user_provisioning_repository.dart';
import '../../repositories/retention_repository.dart';
import '../../repositories/staff_repository.dart';
import '../../repositories/user_provisioning_repository.dart';
import 'firebase_providers.dart';
import 'tenant_context_providers.dart';

/// Providers para as ferramentas de gestão encontradas em falta ao
/// comparar a app com `Functional/nxt-studio-screens.html`: criar
/// utilizador (UC22, nunca ligado a nenhuma UI) e gestão de Staff
/// (nunca existia repository nenhum, só `MemberRepository`).
final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return FirebaseStaffRepository(
    ref.watch(firestoreProvider),
    ref.watch(functionsProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

final staffProvider = StreamProvider<List<StaffSummary>>((ref) {
  return ref.watch(staffRepositoryProvider).watchStaff();
});

/// Os dados pessoais de um membro do staff, numa leitura à parte.
///
/// `.family` e `autoDispose` porque só a ficha aberta precisa deles —
/// e porque só o próprio e o Gestor os conseguem ler.
final staffPrivateProfileProvider = StreamProvider.autoDispose
    .family<StaffPrivateProfile, String>((ref, staffId) {
  return ref.watch(staffRepositoryProvider).watchPrivateProfile(staffId);
});

final userProvisioningRepositoryProvider =
    Provider<UserProvisioningRepository>((ref) {
  return FirebaseUserProvisioningRepository(ref.watch(functionsProvider));
});

/// Fase 11 — painel de retenção. `.family` pelos dois parâmetros que o
/// Gestor pode mexer no ecrã (janela das taxas, semanas sem aparecer);
/// `autoDispose` porque cada combinação nova é uma chamada nova e
/// manter as antigas vivas não serve de nada.
final retentionRepositoryProvider = Provider<RetentionRepository>((ref) {
  return FirebaseRetentionRepository(ref.watch(functionsProvider));
});

final retentionOverviewProvider = FutureProvider.autoDispose
    .family<RetentionOverview, ({int windowDays, int riskWeeks})>((ref, args) {
  return ref.watch(retentionRepositoryProvider).getOverview(
        windowDays: args.windowDays,
        riskWeeks: args.riskWeeks,
      );
});
