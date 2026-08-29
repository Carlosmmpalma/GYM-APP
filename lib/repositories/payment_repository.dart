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
  /// Elimina o registo de mensalidade de um mês.
  ///
  /// ⚠️ Isto NÃO é o mesmo que marcar "não pago": é fazer o mês
  /// desaparecer do histórico, para quando foi lançado no membro
  /// errado ou em duplicado.
  ///
  /// O fluxo de RGPD anonimiza registos de pagamento em vez de os
  /// apagar, por causa da retenção fiscal — mas isso vale para o
  /// apagamento de uma PESSOA, onde a alternativa era perder a
  /// contabilidade de um cliente real. Aqui é o Gestor a corrigir um
  /// lançamento seu, e a app não é o sistema de faturação do estúdio.
  /// Assumido explicitamente; se um dia passar a ser, isto tem de
  /// voltar a fechar.
  /// O registo de um MÊS concreto para vários membros de uma vez.
  ///
  /// O ecrã de mensalidades vivia só no mês corrente, porque o estado
  /// desse mês está denormalizado em `members/{id}` e sai de graça com a
  /// lista. Para qualquer outro mês não havia por onde: ver quem pagou
  /// em Junho obrigava a abrir o histórico de cada membro, um a um.
  ///
  /// Isto é uma leitura por membro, e é por isso que só acontece quando
  /// alguém navega para fora do mês corrente — o caso comum continua a
  /// não custar nada.
  Future<Map<String, PaymentRecord>> getRecordsForPeriod({
    required Iterable<String> memberIds,
    required String period,
  });

  Future<void> deletePaymentRecord({
    required String memberId,
    required String period,
  });

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
