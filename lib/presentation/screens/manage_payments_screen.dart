import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

          int countOf(_PaymentFilter filter) =>
              relevant.where((m) => _matchesFilter(m, filter, now)).length;

          final visible = relevant.where((member) {
            if (_statusFilter != null &&
                !_matchesFilter(member, _statusFilter!, now)) {
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
              Text(
                paymentMonthLabel(now.month, now.year),
                style: Theme.of(context).textTheme.titleMedium,
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
                  _PaymentRow(member: member, now: now),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }
}

bool _matchesFilter(
  MemberSummary member,
  _PaymentFilter filter,
  DateTime now,
) {
  final status = member.currentMonthStatus(now);
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
    required this.now,
  });

  final MemberSummary member;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = member.currentMonthStatus(now);

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
      periodLabel: paymentMonthLabel(now.month, now.year),
      initialStatus: member.currentMonthStatus(now),
    );
    if (result == null) return;

    final changedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (changedBy == null) return;

    try {
      await ref.read(paymentRepositoryProvider).setPaymentStatus(
            memberId: member.uid,
            year: now.year,
            month: now.month,
            status: result.status,
            changedBy: changedBy,
            amount: result.amount,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $e')),
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
