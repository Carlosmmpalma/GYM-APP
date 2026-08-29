import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/payment_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/payment_record.dart';
import '../widgets/design_system.dart';
import '../widgets/status_pills.dart';
import 'manage_payments_screen.dart' show showPaymentStatusDialog;
import '../widgets/catalogue_delete.dart';

/// Fase 9 (UC27 fechado) — "um registo por mês, nunca só o estado
/// atual" (mockup: "Histórico de mensalidades"). Acessível ao Gestor
/// (a partir de `ManagePaymentsScreen`) e ao PRÓPRIO membro — as
/// Security Rules já permitem essa leitura (`firestore.rules`,
/// `paymentRecords`), mas nenhum ecrã de Aluno navega para aqui ainda
/// (o mockup não mostra este ecrã do lado do Aluno; `MyProfileScreen`
/// só mostra o estado do mês atual — ver nota lá). Só o Gestor pode
/// EDITAR uma linha (o botão de edição em cada card só aparece quando
/// `canEdit`).
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen(
      {super.key, required this.member, this.canEdit = true});

  final MemberSummary member;

  /// `false` quando aberto pelo próprio membro (leitura pura) — hoje
  /// sempre `true`, porque só `ManagePaymentsScreen` (Gestor) navega
  /// para aqui; o parâmetro já existe para quando um ecrã de Aluno for
  /// ligado a isto, sem precisar de reescrever o ecrã nessa altura.
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(paymentHistoryProvider(member.uid));

    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (records) {
          if (records.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não há nenhum registo de mensalidade para este membro.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Agrupado por ano, com o resumo do ano no cabeçalho. Doze
          // linhas por ano tornam-se depressa quarenta, e a pergunta
          // que se faz a um histórico de mensalidades é sobre o ano
          // ("2025 esteve em dia?"), não sobre a lista toda.
          final byYear = <int, List<PaymentRecord>>{};
          for (final record in records) {
            byYear.putIfAbsent(record.year, () => []).add(record);
          }
          final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final year in years) ...[
                _YearHeader(year: year, records: byYear[year]!),
                const SizedBox(height: 8),
                for (final record in byYear[year]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title:
                            Text(paymentMonthLabel(record.month, record.year)),
                        subtitle: record.amount != null
                            ? Text('€ ${record.amount!.toStringAsFixed(2)}')
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PaymentStatusPill(record.status),
                            if (canEdit)
                              IconButton(
                                tooltip: 'Eliminar registo',
                                visualDensity: VisualDensity.compact,
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _delete(context, ref, record),
                              ),
                          ],
                        ),
                        onTap:
                            canEdit ? () => _edit(context, ref, record) : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Eliminar NÃO é o mesmo que marcar "não pago": é fazer o mês
  /// desaparecer do histórico, para quando foi lançado no membro
  /// errado ou em duplicado. Para corrigir o estado de um mês que
  /// existe, edita-se — daí as duas ações estarem separadas.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PaymentRecord record,
  ) async {
    final label = paymentMonthLabel(record.month, record.year);
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Eliminar o registo de $label?',
      consequence: 'O mês desaparece do histórico de ${member.name}, como '
          'se nunca tivesse sido lançado. Para marcar como não pago, '
          'toca no registo e muda o estado — isso mantém-no visível.',
      confirmLabel: 'Eliminar registo',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(paymentRepositoryProvider).deletePaymentRecord(
            memberId: member.uid,
            period: paymentPeriodKey(DateTime(record.year, record.month)),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registo de $label eliminado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível eliminar. Tenta outra vez.')),
        ),
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    PaymentRecord record,
  ) async {
    final result = await showPaymentStatusDialog(
      context: context,
      title: member.name,
      periodLabel: paymentMonthLabel(record.month, record.year),
      initialStatus: record.status,
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
            year: record.year,
            month: record.month,
            status: result.status,
            changedBy: changedBy,
            amount: result.amount ?? record.amount,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível corrigir. Tenta outra vez.'))),
      );
    }
  }
}

/// O ano e o que aconteceu nele — quantos meses em dia, quantos em
/// atraso. É a leitura que o Gestor faz antes de entrar nos detalhes.
class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year, required this.records});

  final int year;
  final List<PaymentRecord> records;

  @override
  Widget build(BuildContext context) {
    final overdue =
        records.where((r) => r.status == PaymentStatus.overdue).length;
    final late =
        records.where((r) => r.status == PaymentStatus.paidLate).length;

    return Row(
      children: [
        Expanded(child: SectionLabel('$year')),
        if (overdue > 0) ...[
          Pill('$overdue em atraso', tone: PillTone.danger),
          const SizedBox(width: 6),
        ],
        if (late > 0) ...[
          Pill('$late fora de prazo', tone: PillTone.warn),
          const SizedBox(width: 6),
        ],
        if (overdue == 0 && late == 0) const Pill('Em dia', tone: PillTone.ok),
      ],
    );
  }
}
