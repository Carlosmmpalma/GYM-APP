import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/staff_summary.dart';
import '../../infrastructure/firebase/firebase_staff_repository.dart';
import '../../infrastructure/firebase/firebase_user_provisioning_repository.dart';
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

final userProvisioningRepositoryProvider =
    Provider<UserProvisioningRepository>((ref) {
  return FirebaseUserProvisioningRepository(ref.watch(functionsProvider));
});
