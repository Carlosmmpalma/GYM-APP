import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/payment_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/payment_record.dart';
import '../../core/utils/search_text.dart';
import '../widgets/status_pills.dart';
import '../widgets/design_system.dart';
import 'payment_history_screen.dart';

/// Fase 9 (UC27 fechado) — "Mensalidades — mês atual" (mockup):
/// registo manual, sem gateway, um pill por membro. Reaproveita
/// `membersProvider` (já existente) em vez de uma query própria — os
/// campos `currentPaymentStatus`/`currentPaymentPeriod` já vêm
/// denormalizados nele (ver `MemberSummary`), por isso este ecrã não
/// abre NENHUM listener novo.
///
/// Um membro sem registo para o mês atual (`currentPaymentPeriod` não
/// bate com o mês de agora — nunca marcado, ou só marcado em meses
/// anteriores) aparece como "Sem registo", nunca como "Em atraso": só
/// uma marcação EXPLÍCITA bloqueia o login (UC01), nunca a ausência de
/// dados — decisão fechada, ver `MemberSummary.isOverdueFor`.
class ManagePaymentsScreen extends ConsumerStatefulWidget {
  const ManagePaymentsScreen({super.key});

  @override
  ConsumerState<ManagePaymentsScreen> createState() =>
      _ManagePaymentsScreenState();
}

/// Sentinela para o filtro "Sem registo": `PaymentStatus?` já usa
/// `null` para "sem filtro", por isso a ausência de registo precisa de
/// um valor próprio na linha de chips.
enum _PaymentFilter { paid, paidLate, overdue, noRecord }

class _ManagePaymentsScreenState extends ConsumerState<ManagePaymentsScreen> {
  String _query = '';
  _PaymentFilter? _statusFilter;

  /// O mês que está a ser visto. Começa no corrente.
  ///
  /// O ecrã vivia preso a `DateTime.now()`: para saber quem pagou em
  /// Junho era preciso abrir o histórico de cada membro, um a um. Com
  /// 50 sócios isso é meia hora de cliques para responder a uma
  /// pergunta de contabilidade banal.
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensalidades'),
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (members) {
          if (members.isEmpty) {
            return const EmptyState(
              icon: Icons.payments_outlined,
              title: 'Nada para cobrar',
              message: 'As mensalidades são por membro: assim que existir '
                  'pelo menos um, aparece aqui a lista para marcares quem '
                  'pagou em cada mês.',
              prerequisite: 'Cria membros em Gestão › Membros.',
            );
          }
          // Só membros ativos: um inativo não deve mensalidade deste
          // mês, e mantê-lo na lista fazia a contagem de "Em atraso"
          // mentir.
          final relevant = members.where((m) => m.active).toList();

          // No mês corrente, o estado sai do campo denormalizado em
          // `members/{id}` e não custa leitura nenhuma. Noutro mês,
          // vai-se buscar os registos — uma leitura por membro, só
          // quando alguém navega para lá.
          final periodKey = paymentPeriodKey(_month);
          final pastRecords = _isCurrentMonth
              ? const <String, PaymentRecord>{}
              : ref
                      .watch(paymentsForPeriodProvider(paymentsPeriodKey(
                        periodKey,
                        relevant.map((m) => m.uid),
                      )))
                      .valueOrNull ??
                  const <String, PaymentRecord>{};

          PaymentStatus? statusOf(MemberSummary member) => _isCurrentMonth
              ? member.currentMonthStatus(now)
              : pastRecords[member.uid]?.status;

          int countOf(_PaymentFilter filter) =>
              relevant.where((m) => _matches(statusOf(m), filter)).length;

          final visible = relevant.where((member) {
            if (_statusFilter != null &&
                !_matches(statusOf(member), _statusFilter!)) {
              return false;
            }
            return searchMatchesAny(
              [member.name, member.memberNumber],
              _query,
            );
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Mês anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1)),
                  ),
                  Text(
                    paymentMonthLabel(_month.month, _month.year),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: 'Mês seguinte',
                    // Não há mensalidades do futuro para marcar: deixar
                    // avançar seria oferecer meses vazios para sempre.
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _isCurrentMonth
                        ? null
                        : () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1)),
                  ),
                ],
              ),
              if (!_isCurrentMonth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _month = DateTime(
                            DateTime.now().year, DateTime.now().month)),
                        icon: const Icon(Icons.today_outlined, size: 16),
                        label: const Text('Voltar ao mês atual'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              const Text(
                'Registo manual, sem gateway de pagamento — histórico '
                'completo por membro através do ícone de histórico.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              SearchField(
                hintText: 'Procurar por nome ou nº de sócio',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 10),
              // A contagem em cada chip é o que torna este ecrã útil de
              // relance: "Em atraso (3)" responde à pergunta antes de se
              // tocar em nada.
              FilterChipsRow<_PaymentFilter>(
                allCount: relevant.length,
                selected: _statusFilter,
                onSelected: (value) => setState(() => _statusFilter = value),
                options: [
                  (
                    _PaymentFilter.overdue,
                    'Em atraso',
                    countOf(_PaymentFilter.overdue)
                  ),
                  (
                    _PaymentFilter.noRecord,
                    'Sem registo',
                    countOf(_PaymentFilter.noRecord)
                  ),
                  (_PaymentFilter.paid, 'Pagas', countOf(_PaymentFilter.paid)),
                  (
                    _PaymentFilter.paidLate,
                    'Com atraso',
                    countOf(_PaymentFilter.paidLate)
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nada encontrado',
                    message: _query.isEmpty
                        ? 'Nenhum membro ativo neste estado.'
                        : 'Nenhum membro corresponde a "$_query".',
                  ),
                )
              else
                for (final member in visible) ...[
                  _PaymentRow(
                    member: member,
                    month: _month,
                    status: statusOf(member),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Recebe o estado já resolvido, em vez de o ir buscar ao membro.
///
/// Antes lia sempre `member.currentMonthStatus(now)` — o campo
/// denormalizado, que só sabe do mês corrente. Era isso que prendia o
/// ecrã a um único mês.
bool _matches(PaymentStatus? status, _PaymentFilter filter) {
  return switch (filter) {
    _PaymentFilter.paid => status == PaymentStatus.paid,
    _PaymentFilter.paidLate => status == PaymentStatus.paidLate,
    _PaymentFilter.overdue => status == PaymentStatus.overdue,
    // "Sem registo" NÃO é "em atraso": só uma marcação explícita
    // bloqueia o login. Ver nota no topo deste ficheiro.
    _PaymentFilter.noRecord => status == null,
  };
}

class _PaymentRow extends ConsumerWidget {
  const _PaymentRow({
    required this.member,
    required this.month,
    required this.status,
  });

  final MemberSummary member;

  /// O mês que o ecrã está a mostrar — não necessariamente o corrente.
  final DateTime month;

  /// Já resolvido pelo ecrã: do campo denormalizado no mês atual, do
  /// registo lido no Firestore em qualquer outro.
  final PaymentStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(member.name),
        subtitle: Text('Nº de sócio ${member.memberNumber}'),
        onTap: () => _markStatus(context, ref),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaymentStatusPill(status),
            IconButton(
              tooltip: 'Histórico de mensalidades',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentHistoryScreen(member: member),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markStatus(BuildContext context, WidgetRef ref) async {
    final result = await showPaymentStatusDialog(
      context: context,
      title: member.name,
      periodLabel: paymentMonthLabel(month.month, month.year),
      initialStatus: status,
    );
    if (result == null) return;

    // `.future` e não `valueOrNull`: se o provider ainda não
    // tivesse emitido, o `return` seguinte fazia o botão não
    // fazer NADA — sem erro, sem aviso. É o sintoma mais caro
    // que uma app pode ter, e já foi reportado duas vezes aqui.
    final currentUser = await ref.read(currentAppUserProvider.future);
    // `null` aqui só acontece com a sessão terminada — aí o ecrã
    // já não devia estar aberto e não há nada a fazer.
    if (currentUser == null) return;
    final changedBy = currentUser.uid;

    try {
      await ref.read(paymentRepositoryProvider).setPaymentStatus(
            memberId: member.uid,
            // O mês que está no ecrã, não o de hoje: sem isto, corrigir
            // Junho gravava em Agosto sem ninguém dar por nada.
            year: month.year,
            month: month.month,
            status: result.status,
            changedBy: changedBy,
            amount: result.amount,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível guardar. Tenta outra vez.'))),
      );
    }
  }
}

/// Resultado de [showPaymentStatusDialog].
typedef PaymentStatusInput = ({PaymentStatus status, double? amount});

/// Partilhado por [ManagePaymentsScreen] (mês atual) e
/// `PaymentHistoryScreen` (corrigir qualquer mês do histórico) — mesmo
/// formulário, só muda o [periodLabel] mostrado.
Future<PaymentStatusInput?> showPaymentStatusDialog({
  required BuildContext context,
  required String title,
  required String periodLabel,
  PaymentStatus? initialStatus,
}) {
  return showDialog<PaymentStatusInput>(
    context: context,
    builder: (_) => _PaymentStatusDialog(
      title: title,
      periodLabel: periodLabel,
      initialStatus: initialStatus,
    ),
  );
}

class _PaymentStatusDialog extends StatefulWidget {
  const _PaymentStatusDialog({
    required this.title,
    required this.periodLabel,
    this.initialStatus,
  });

  final String title;
  final String periodLabel;
  final PaymentStatus? initialStatus;

  @override
  State<_PaymentStatusDialog> createState() => _PaymentStatusDialogState();
}

class _PaymentStatusDialogState extends State<_PaymentStatusDialog> {
  late PaymentStatus _status = widget.initialStatus ?? PaymentStatus.paid;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.periodLabel,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          // `groupValue`/`onChanged` no RadioListTile ficaram
          // deprecated no Flutter 3.32 a favor de um `RadioGroup`
          // ancestral partilhado — mesmo padrão de `plan_detail_screen.dart`.
          RadioGroup<PaymentStatus>(
            groupValue: _status,
            onChanged: (v) => setState(() => _status = v!),
            child: Column(
              children: [
                for (final option in PaymentStatus.values)
                  RadioListTile<PaymentStatus>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.label),
                    value: option,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Valor (opcional)',
              prefixText: '€ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(
                _amountController.text.trim().replaceAll(',', '.'));
            Navigator.of(context).pop((status: _status, amount: amount));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
