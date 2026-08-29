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

/// Os registos de mensalidade de UM mês, para os membros indicados.
///
/// Só é usado quando o Gestor navega para fora do mês corrente: o mês
/// atual sai de graça do campo denormalizado em `members/{id}`, e pagar
/// N leituras por ele seria pagar por nada.
///
/// A chave junta o período e os membros numa string porque as famílias
/// do Riverpod comparam por `==`, e listas não têm igualdade por valor
/// — mesmo motivo de `serviceIdsKey` e `exerciseKeyFor`.
final paymentsForPeriodProvider =
    FutureProvider.autoDispose.family<Map<String, PaymentRecord>, String>(
  (ref, key) async {
    final parts = key.split('|');
    final period = parts[0];
    final memberIds =
        parts.length < 2 || parts[1].isEmpty ? <String>[] : parts[1].split(',');
    if (memberIds.isEmpty) return const {};
    return ref.watch(paymentRepositoryProvider).getRecordsForPeriod(
          memberIds: memberIds,
          period: period,
        );
  },
);

/// A chave estável para [paymentsForPeriodProvider].
String paymentsPeriodKey(String period, Iterable<String> memberIds) =>
    '$period|${(memberIds.toList()..sort()).join(',')}';
