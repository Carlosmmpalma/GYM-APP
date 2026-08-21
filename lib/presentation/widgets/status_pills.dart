import 'package:flutter/material.dart';

import '../../domain/entities/payment_record.dart';
import '../../domain/entities/subscription.dart';
import 'design_system.dart';

/// Fase 10 — a tradução "estado do domínio → etiqueta + cor" vivia
/// copiada em cada ecrã que a precisava: `PaymentStatus` estava em
/// `ManagePaymentsScreen`, em `PaymentHistoryScreen` e em
/// `MyProfileScreen`, e as três versões já não diziam o mesmo ("✓ Pago"
/// num sítio, "Em dia" noutro) nem usavam as mesmas cores (duas ainda
/// em `Colors.green`/`Colors.orange`, fora da paleta do mockup).
///
/// O mesmo estado tem de se ler igual em toda a app — é o que torna a
/// cor informação em vez de decoração. Daí este ficheiro: um sítio só
/// para essa tradução, em cima do [Pill] do design system.
class PaymentStatusPill extends StatelessWidget {
  const PaymentStatusPill(this.status, {super.key});

  /// `null` = não há registo nenhum para o período (não é o mesmo que
  /// "em atraso": o Gestor pode simplesmente ainda não ter lançado o
  /// mês).
  final PaymentStatus? status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = labelAndToneFor(status);
    return Pill(label, tone: tone);
  }

  /// Exposto à parte do widget para os sítios que precisam do texto sem
  /// o pill (uma linha de lista densa, por exemplo).
  static (String, PillTone) labelAndToneFor(PaymentStatus? status) {
    return switch (status) {
      PaymentStatus.paid => ('Pago', PillTone.ok),
      PaymentStatus.paidLate => ('Pago com atraso', PillTone.warn),
      PaymentStatus.overdue => ('Em atraso', PillTone.danger),
      null => ('Sem registo', PillTone.neutral),
    };
  }
}

class SubscriptionStatusPill extends StatelessWidget {
  const SubscriptionStatusPill(this.status, {super.key});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      SubscriptionStatus.active => ('Ativo', PillTone.ok),
      SubscriptionStatus.paused => ('Em pausa', PillTone.warn),
      SubscriptionStatus.cancelled => ('Cancelado', PillTone.neutral),
      SubscriptionStatus.expired => ('Expirado', PillTone.neutral),
    };
    return Pill(label, tone: tone);
  }
}
