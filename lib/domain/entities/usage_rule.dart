import 'package:equatable/equatable.dart';

/// Domain Model v1 §13 / Firestore Data Model v1 §15 — a regra de
/// utilização pertence à relação Plan↔Service (ver [PlanService]), não
/// ao Plan nem ao Service isoladamente: o mesmo Plan pode dar 3x/semana
/// a um serviço e 2x/semana a outro.
///
/// Só `limited` (com [limit]/[period]) e `unlimited` são suportados no
/// MVP — os documentos deixam explícito que outros [UsagePeriod] (ex.
/// `day`) e outros tipos de regra podem ser acrescentados no futuro sem
/// alterar a estrutura principal; não implementámos mais do que o
/// necessário para a Fase 3/4.
enum UsageRuleType { limited, unlimited }

enum UsagePeriod {
  day,
  week,
  month;

  static UsagePeriod fromValue(String value) => UsagePeriod.values.firstWhere(
        (p) => p.name == value,
        orElse: () => throw ArgumentError('Período desconhecido: $value'),
      );
}

class UsageRule extends Equatable {
  const UsageRule.unlimited()
      : type = UsageRuleType.unlimited,
        limit = null,
        period = null;

  const UsageRule.limited({required this.limit, required this.period})
      : type = UsageRuleType.limited;

  final UsageRuleType type;
  final int? limit;
  final UsagePeriod? period;

  bool get isUnlimited => type == UsageRuleType.unlimited;

  /// Descrição curta para UI (ecrãs de gestão de Plans — Fase 3).
  String describe() {
    if (isUnlimited) return 'Ilimitado';
    final periodLabel = switch (period!) {
      UsagePeriod.day => 'dia',
      UsagePeriod.week => 'semana',
      UsagePeriod.month => 'mês',
    };
    return '$limit x / $periodLabel';
  }

  @override
  List<Object?> get props => [type, limit, period];
}
