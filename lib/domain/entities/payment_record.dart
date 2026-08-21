import 'package:equatable/equatable.dart';

/// Fase 9 (UC27 fechado) — três estados, não um booleano: o mockup
/// distingue "pago dentro do prazo" de "pago com atraso" (ambos contam
/// como pagos para efeitos de acesso — só `overdue` bloqueia o login,
/// UC01), e o Gestor precisa de saber qual dos dois aconteceu para o
/// histórico fazer sentido.
enum PaymentStatus {
  paid,
  overdue,
  paidLate;

  static PaymentStatus fromValue(String value) => PaymentStatus.values
      .firstWhere((s) => s.name == value, orElse: () => PaymentStatus.overdue);

  String get label => switch (this) {
        PaymentStatus.paid => 'Pago',
        PaymentStatus.overdue => 'Em atraso',
        PaymentStatus.paidLate => 'Pago com atraso',
      };
}

/// Devolve a chave "YYYY-MM" do mês a que [date] pertence — mesmo
/// formato usado como id de `PaymentRecord` (Firestore Data Model v1
/// §46). Cálculo em UTC, mesma limitação já assinalada em
/// `core/utils/iso_week.dart` (sem biblioteca de timezone nas
/// dependências) — perto da meia-noite entre dois meses, o "mês atual"
/// pode divergir por até 1h do que seria com o timezone real do
/// tenant. Inofensivo aqui: ninguém decide "em que mês estamos" à
/// meia-noite entre o dia 1 e o dia 2.
String paymentPeriodKey(DateTime date) {
  final utc = date.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}';
}

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// "Agosto 2026" — usado por `ManagePaymentsScreen`/`PaymentHistoryScreen`.
/// [month] é 1-12 (mesma convenção de [PaymentRecord.month]).
String paymentMonthLabel(int month, int year) =>
    '${_monthNames[month - 1]} $year';

/// Registo de mensalidade de UM mês de UM membro (Domain Model v1 §36,
/// Firestore Data Model v1 §46). Ao contrário de `LoadHistoryEntry`
/// (Fase 8, UC16 fechado — nunca sobrescrito, cada alteração é um
/// registo novo), este É atualizável: o próprio Domain Model diz
/// "append/update CONTROLADO" — o histórico é sobre haver um registo
/// POR MÊS (não um único `pago: sim/não` global), não sobre cada
/// correção virar uma linha nova. `changedBy`/`changedAt` guardam quem
/// fez a ÚLTIMA alteração — auditoria suficiente para o MVP, sem
/// duplicar `loadHistory`'s modelo de imutabilidade onde o próprio UC27
/// nunca o pede.
class PaymentRecord extends Equatable {
  const PaymentRecord({
    required this.memberId,
    required this.year,
    required this.month,
    required this.status,
    required this.changedAt,
    required this.changedBy,
    this.amount,
    this.subscriptionId,
  });

  final String memberId;
  final int year;

  /// 1-12.
  final int month;
  final PaymentStatus status;
  final DateTime changedAt;
  final String changedBy;

  /// Opcional — "registo manual, sem gateway" (Fase 9): o Gestor pode
  /// não saber/não querer registar o valor exato. `null` quando omitido.
  final double? amount;

  /// Opcional (Firestore Data Model v1 §46 deixa em aberto se a
  /// mensalidade é obrigação do Membro ou da Subscription — um membro
  /// pode ter várias subscriptions ativas em simultâneo, Domain Model
  /// v1 §15, e o mockup mostra sempre UM pill por membro por mês, não
  /// um por subscription). Nunca usado pela UI atual; guardado para não
  /// perder a informação se um dia for preciso.
  final String? subscriptionId;

  String get periodKey => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';

  bool get isOverdue => status == PaymentStatus.overdue;

  @override
  List<Object?> get props => [
        memberId,
        year,
        month,
        status,
        changedAt,
        changedBy,
        amount,
        subscriptionId,
      ];
}
