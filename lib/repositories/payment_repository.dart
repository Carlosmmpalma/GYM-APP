import '../domain/entities/payment_record.dart';

/// Fase 9 (UC27 fechado) — histórico mensal de mensalidades, "registo
/// manual, sem gateway" (Domain Model v1 §36, D17). Escrita direta do
/// cliente (Gestor) — sem invariante cross-documento a proteger além
/// da denormalização em `MemberSummary.currentPaymentStatus/Period`
/// (ver nota lá), que [setPaymentStatus] garante ficar coerente através
/// de um `WriteBatch`, mesmo padrão já usado em `TrainingPlanEntry`/
/// `loadHistory` na Fase 8.
abstract class PaymentRepository {
  /// Mais recente primeiro. Cada mês é UM documento — ao contrário de
  /// `loadHistory` (Fase 8), corrigir um mês ATUALIZA o registo desse
  /// mês, não cria um novo (Domain Model v1 §46: "append/update
  /// controlado", não imutável).
  Stream<List<PaymentRecord>> watchPaymentHistory(String memberId);

  /// Cria (1ª vez) ou atualiza (correção) o registo de [memberId] para
  /// [year]/[month]. Quando [year]/[month] é o MÊS ATUAL, atualiza
  /// também `members/{memberId}.currentPaymentStatus/currentPaymentPeriod`
  /// no mesmo `WriteBatch` — nunca para um mês passado, que sobrescreveria
  /// silenciosamente o estado do mês atual com o de uma correção
  /// histórica.
  Future<void> setPaymentStatus({
    required String memberId,
    required int year,
    required int month,
    required PaymentStatus status,
    required String changedBy,
    double? amount,
    String? subscriptionId,
  });
}
