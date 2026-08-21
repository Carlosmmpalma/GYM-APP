import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/consent.dart';
import '../../infrastructure/firebase/firebase_privacy_repository.dart';
import '../../repositories/privacy_repository.dart';
import 'firebase_providers.dart';
import 'plan_providers.dart';
import 'tenant_context_providers.dart';

final privacyRepositoryProvider = Provider<PrivacyRepository>((ref) {
  return FirebasePrivacyRepository(ref.watch(functionsProvider));
});

/// Fase 11 (RGPD) — falta o consentimento deste utilizador para a
/// versão atual da política?
///
/// `true` leva o `AuthGate` ao `ConsentScreen` antes de qualquer outro
/// ecrã. Três decisões escondidas aqui:
///
/// - **Só membros.** Staff não tem dados de saúde tratados pela app e a
///   sua relação é laboral, não de cliente. Um Gestor que também seja
///   membro cai no caso de membro, como em todo o resto da app.
/// - **Erro não bloqueia.** Se a leitura do perfil falhar, deixamos
///   entrar: prender toda a gente fora da app por causa de uma falha de
///   rede seria pior do que atrasar um registo de consentimento que a
///   próxima sessão volta a pedir.
/// - **Sem registo ≠ recusa.** Contas criadas antes disto existir têm
///   `consent` vazio e são levadas ao ecrã — é precisamente o caso que
///   este gate serve.
final needsConsentProvider = FutureProvider.autoDispose<bool>((ref) async {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null || !appUser.isMember) return false;

  try {
    final member = await ref.watch(memberProfileProvider(appUser.uid).future);
    if (member == null) return false;
    return !member.consent.isCurrent;
  } catch (_) {
    return false;
  }
});

/// O consentimento atual do próprio utilizador, para o ecrã "Os meus
/// dados" poder mostrar o que está autorizado e permitir retirá-lo
/// (artigo 7.º, n.º 3 — retirar tem de ser tão fácil como dar).
final myConsentProvider =
    FutureProvider.autoDispose<MemberConsent?>((ref) async {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null || !appUser.isMember) return null;
  final member = await ref.watch(memberProfileProvider(appUser.uid).future);
  return member?.consent;
});
