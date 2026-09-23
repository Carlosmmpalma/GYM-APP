import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/tenant_app_config.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/public_schedule.dart';
import '../../domain/entities/studio_info.dart';
import '../../infrastructure/firebase/firebase_account_repository.dart';
import '../../infrastructure/firebase/firebase_auth_repository.dart';
import '../../infrastructure/firebase/firebase_public_schedule_repository.dart';
import '../../infrastructure/firebase/firebase_tenant_repository.dart';
import '../../repositories/account_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/public_schedule_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../use_cases/complete_temporary_password_change_use_case.dart';
import '../use_cases/sign_in_with_member_number_use_case.dart';
import 'firebase_providers.dart';

/// Sobrescrito no bootstrap, tal como [environmentConfigProvider] — ver
/// lib/core/bootstrap/bootstrap.dart. Diz à app qual tenant esta build
/// serve (Platform Foundation §9 — Tenant Context).
final tenantAppConfigProvider = Provider<TenantAppConfig>((ref) {
  throw UnimplementedError(
    'tenantAppConfigProvider tem de ser sobrescrito no bootstrap.',
  );
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return FirebaseTenantRepository(ref.watch(firestoreProvider));
});

final publicScheduleRepositoryProvider =
    Provider<PublicScheduleRepository>((ref) {
  return FirebasePublicScheduleRepository(ref.watch(firestoreProvider));
});

/// O mapa de aulas da vitrina.
///
/// `FutureProvider` e não `Stream`: isto é lido por quem ainda não tem
/// conta, muda uma vez por dia, e um listener aberto num ecrã público
/// seria pagar uma ligação permanente por cada pessoa que abre a app
/// para ver o horário.
final publicScheduleProvider =
    FutureProvider.autoDispose<PublicSchedule>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref.watch(publicScheduleRepositoryProvider).getSchedule(tenantId);
});

/// Morada, contactos, horário e política de privacidade do estúdio.
///
/// Lê-se sem sessão (é o que a vitrina mostra a quem ainda não tem
/// conta) e é o mesmo provider que o ecrã de consentimento usa para
/// ligar à política — ver `StudioInfo`.
final studioInfoProvider = FutureProvider.autoDispose<StudioInfo>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref.watch(publicScheduleRepositoryProvider).getStudioInfo(tenantId);
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return FirebaseAccountRepository(ref.watch(firestoreProvider));
});

/// Fonte única de verdade de "quem está autenticado, em que tenant, com
/// que roles" (Platform Foundation §9 — CurrentUser/CurrentTenant/
/// CurrentRole). `null` cobre tanto "sem sessão" como "sessão sem claims
/// utilizáveis ainda" — ver AuthRepository.authStateChanges().
final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// UC22 — só faz sentido perguntar isto quando já há um [AppUser]
/// resolvido. `autoDispose` porque isto só interessa durante o fluxo de
/// login/AuthGate, não deve ficar em memória depois de decidido.
final hasTemporaryPasswordProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null) return false;
  return ref.watch(accountRepositoryProvider).hasTemporaryPassword(appUser);
});

final signInWithMemberNumberUseCaseProvider =
    Provider<SignInWithMemberNumberUseCase>((ref) {
  return SignInWithMemberNumberUseCase(ref.watch(authRepositoryProvider));
});

final completeTemporaryPasswordChangeUseCaseProvider =
    Provider<CompleteTemporaryPasswordChangeUseCase>((ref) {
  return CompleteTemporaryPasswordChangeUseCase(
    ref.watch(authRepositoryProvider),
    ref.watch(accountRepositoryProvider),
  );
});

/// Fase 4 — "antecedência mínima para cancelar", único valor por
/// tenant. `autoDispose` porque só interessa enquanto
/// `TenantSettingsScreen` estiver aberto.
final minCancellationNoticeHoursProvider =
    FutureProvider.autoDispose<int>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref
      .watch(tenantRepositoryProvider)
      .getMinCancellationNoticeHours(tenantId);
});

/// Fase 8 (auditoria funcional) — "antecedência mínima para marcar",
/// irmã de [minCancellationNoticeHoursProvider] mas para o lado
/// oposto do booking (marcar, não cancelar).
/// Fase 11 — o serviço que representa o treino livre neste estúdio.
///
/// `null` = ainda não foi escolhido nas Definições. Os ecrãs de treino
/// livre tratam esse caso dizendo o que falta, em vez de pedirem um
/// serviço a cada passo — que era o que faziam antes.
final freeTrainingServiceIdProvider =
    FutureProvider.autoDispose<String?>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref.watch(tenantRepositoryProvider).getFreeTrainingServiceId(tenantId);
});

/// Fase 11 — antecedência do lembrete da aula (`0` = desligado).
final sessionReminderHoursProvider = FutureProvider.autoDispose<int>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref.watch(tenantRepositoryProvider).getSessionReminderHours(tenantId);
});

/// Quantos dias para a frente o aluno consegue marcar. `0` = sem
/// limite. Ver [TenantRepository.getBookingHorizonDays].
///
/// NÃO é `autoDispose`: os dois ecrãs de marcar leem-no, e recarregá-lo
/// a cada navegação entre separadores era uma leitura por toque numa
/// definição que muda uma vez por ano.
final bookingHorizonDaysProvider = FutureProvider<int>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref.watch(tenantRepositoryProvider).getBookingHorizonDays(tenantId);
});

final minBookingNoticeMinutesProvider = FutureProvider.autoDispose<int>((ref) {
  final tenantId = ref.watch(tenantAppConfigProvider).tenantId;
  return ref
      .watch(tenantRepositoryProvider)
      .getMinBookingNoticeMinutes(tenantId);
});
