import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/payment_record.dart';
import '../../domain/entities/role.dart';
import '../../infrastructure/firebase/firebase_payment_repository.dart';
import '../../repositories/payment_repository.dart';
import 'firebase_providers.dart';
import 'plan_providers.dart';
import 'tenant_context_providers.dart';

/// Fase 9 (UC27 fechado) — histórico mensal de mensalidades.
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return FirebasePaymentRepository(
    ref.watch(firestoreProvider),
    ref.watch(tenantAppConfigProvider).tenantId,
  );
});

/// `PaymentHistoryScreen` (Gestor e o próprio membro). `autoDispose` —
/// mesmo raciocínio já aplicado a todos os `.family` deste projeto na
/// revisão geral da Fase 8: sem isto, cada membro cujo histórico já foi
/// aberto uma vez ficaria com um listener Firestore aberto pelo resto
/// da sessão.
final paymentHistoryProvider = StreamProvider.autoDispose
    .family<List<PaymentRecord>, String>((ref, memberId) {
  return ref.watch(paymentRepositoryProvider).watchPaymentHistory(memberId);
});

/// Fase 9 (UC01 fechado) — "conta bloqueada no próximo login" quando a
/// mensalidade do MÊS ATUAL está `overdue` (nunca por ausência de
/// registo — só uma marcação EXPLÍCITA bloqueia, ver
/// `MemberSummary.isOverdueFor`). Consultado por `AuthGate`.
///
/// Só se aplica a contas PURAMENTE de Aluno (`roles == {member}`): um
/// Instrutor/Gestor que também seja membro (Domain Model v1 §6 admite
/// isto) nunca fica bloqueado da app por causa da própria mensalidade —
/// o risco operacional de um Gestor ficar sem acesso à própria gestão
/// seria pior do que o benefício de aplicar a regra também a ele.
/// Decisão pragmática não coberta explicitamente pelo mockup (que só
/// mostra o ecrã de bloqueio a partir do login de Aluno); sinalizada,
/// não escondida.
///
/// Reaproveita `memberProfileProvider` (já existente, `MyProfileScreen`)
/// em vez de uma leitura própria — o documento já vem com os campos
/// denormalizados (`FirebaseMemberRepository._fromDoc`), evitar duas
/// queries ao mesmo documento a cada abertura da app.
final isBlockedForOverduePaymentProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final appUser = ref.watch(currentAppUserProvider).valueOrNull;
  if (appUser == null ||
      appUser.roles.length != 1 ||
      !appUser.roles.contains(Role.member)) {
    return false;
  }
  final member = await ref.watch(memberProfileProvider(appUser.uid).future);
  return member?.isOverdueFor(DateTime.now()) ?? false;
});
