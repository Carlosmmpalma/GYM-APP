import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/retention_overview.dart';
import '../widgets/design_system.dart';
import 'member_detail_screen.dart';

/// Fase 11 — painel de retenção do Gestor.
///
/// Num ginásio de proximidade, quem desiste não cancela: deixa de
/// aparecer, continua a pagar dois ou três meses e só depois cancela —
/// altura em que já não há conversa possível. O sinal existia nos
/// dados desde a Fase 6 (presenças e faltas), mas só se via aula a
/// aula, uma de cada vez.
///
/// A lista de quem não aparece vem PRIMEIRO e ocupa o resto do ecrã,
/// com as taxas reduzidas a três números no topo. É deliberado: a
/// ocupação e a taxa de faltas informam, mas só a lista se traduz numa
/// ação hoje — ligar a estas pessoas.
class RetentionScreen extends ConsumerStatefulWidget {
  const RetentionScreen({super.key});

  @override
  ConsumerState<RetentionScreen> createState() => _RetentionScreenState();
}

class _RetentionScreenState extends ConsumerState<RetentionScreen> {
  int _riskWeeks = 3;

  static const _windowDays = 30;

  @override
  Widget build(BuildContext context) {
    final args = (windowDays: _windowDays, riskWeeks: _riskWeeks);
    final overviewAsync = ref.watch(retentionOverviewProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Retenção'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(retentionOverviewProvider(args)),
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(
          error: error,
          message: 'Não foi possível calcular a retenção.',
          onRetry: () => ref.invalidate(retentionOverviewProvider(args)),
        ),
        data: (overview) => _Body(
          overview: overview,
          riskWeeks: _riskWeeks,
          onRiskWeeksChanged: (weeks) => setState(() => _riskWeeks = weeks),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.overview,
    required this.riskWeeks,
    required this.onRiskWeeksChanged,
  });

  final RetentionOverview overview;
  final int riskWeeks;
  final ValueChanged<int> onRiskWeeksChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Ocupação\n(${overview.windowDays} dias)',
                value: overview.occupancyPercent == null
                    ? '—'
                    : '${overview.occupancyPercent}%',
                hint: '${overview.sessions} sessões realizadas',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'Faltas\n(${overview.windowDays} dias)',
                value: overview.noShowPercent == null
                    ? '—'
                    : '${overview.noShowPercent}%',
                // Sem presenças registadas não se diz "0% de faltas":
                // isso soaria a "está tudo bem" quando na verdade não
                // se sabe nada.
                hint: overview.attendanceRecorded == 0
                    ? 'Sem presenças registadas'
                    : '${overview.noShows} de ${overview.attendanceRecorded}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'Em risco',
                value: overview.atRisk.length.toString(),
                hint: 'de ${overview.membersWithActivePlan} com plano',
                valueColor:
                    overview.atRisk.isEmpty ? AppColors.ok : AppColors.warn,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Quem não aparece há',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 2, label: Text('2 sem.')),
            ButtonSegment(value: 3, label: Text('3 sem.')),
            ButtonSegment(value: 4, label: Text('1 mês')),
            ButtonSegment(value: 8, label: Text('2 meses')),
          ],
          selected: {riskWeeks},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              onRiskWeeksChanged(selection.first),
        ),
        const SizedBox(height: 6),
        const Text(
          'Só alunos com plano ativo. Quem já não tem plano não está em '
          'risco de sair — já saiu.',
          style: TextStyle(color: AppColors.mute, fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (overview.atRisk.isEmpty)
          const EmptyState(
            icon: Icons.sentiment_satisfied_alt,
            title: 'Ninguém em risco',
            message: 'Todos os alunos com plano ativo apareceram dentro do '
                'período escolhido. Se isto parecer bom demais, confirma que '
                'as presenças estão a ser registadas nas aulas.',
          )
        else
          ...overview.atRisk.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AtRiskTile(member: member, scanDays: overview.scanDays),
            ),
          ),
      ],
    );
  }
}

class _AtRiskTile extends ConsumerWidget {
  const _AtRiskTile({required this.member, required this.scanDays});

  final MemberAtRisk member;
  final int scanDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = member.lastAttendanceAt;
    final days = last == null ? null : DateTime.now().difference(last).inDays;

    return PanelCard(
      padding: const EdgeInsets.all(12),
      // Toca → ficha do aluno, que é onde estão o contacto e o plano.
      // Sem isto a lista dizia quem ligar e obrigava a procurá-lo
      // outra vez noutro ecrã.
      onTap: () async {
        final members = await ref.read(membersProvider.future);
        final summary = members.where((m) => m.uid == member.memberId);
        if (summary.isEmpty || !context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MemberDetailScreen(member: summary.first),
          ),
        );
      },
      child: Row(
        children: [
          // Iniciais com cor, não foto: `MemberAtRisk` vem da Cloud
          // Function de retenção e não traz o caminho da foto. Numa
          // lista de análise a cara não acrescenta nada — quem a lê
          // está a olhar para números, não a reconhecer pessoas.
          Avatar(member.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  // "Nunca veio" seria mentira: só se procurou até
                  // `scanDays` atrás.
                  days == null
                      ? 'Sem presença nos últimos $scanDays dias'
                      : 'Última presença há $days dias',
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.mute, size: 20),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    this.valueColor,
  });

  final String label;
  final String value;
  final String hint;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(color: AppColors.mute, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
