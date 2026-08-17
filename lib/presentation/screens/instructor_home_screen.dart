import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/staff_summary.dart';
import 'exercise_library_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_students_screen.dart';
import 'send_notification_screen.dart';

/// Fase 8 (auditoria funcional, mockup "Início — Dashboard do
/// instrutor") — até aqui um Instrutor PURO (sem `Role.manager` e sem
/// `Role.member`) caía no mesmo `HomeScreen` do Aluno: via os
/// separadores "Marcar treino"/"Treino livre"/"Minhas marcações", que
/// não se aplicam a ele (não tem plano nem marcações próprias), e as
/// suas ferramentas reais estavam escondidas atrás de ícones na
/// AppBar. Este ecrã substitui isso pelo dashboard que o mockup
/// mostra: duas estatísticas do dia + os atalhos das ações que um
/// instrutor faz mesmo.
///
/// "Nova avaliação" do mockup não aparece como atalho de topo porque
/// criar uma avaliação exige escolher primeiro o aluno — passa sempre
/// por "Alunos" → aluno → avaliação (`StudentTrainingScreen`).
/// Sinalizado, não escondido.
class InstructorHomeScreen extends ConsumerWidget {
  const InstructorHomeScreen({super.key, required this.appUser});

  final AppUser appUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffProvider);
    final membersAsync = ref.watch(membersProvider);
    final modalitiesAsync = ref.watch(modalitiesProvider);

    final now = DateTime.now();
    final occurrencesAsync =
        ref.watch(occurrencesForWeekProvider(isoWeekRange(now).start));

    final me = (staffAsync.valueOrNull ?? const <StaffSummary>[])
        .where((s) => s.uid == appUser.uid)
        .firstOrNull;

    final modalitiesById = <String, Modality>{
      for (final m in modalitiesAsync.valueOrNull ?? const <Modality>[])
        m.id: m,
    };
    final myModalities = (me?.modalityIds ?? const <String>{})
        .map((id) => modalitiesById[id]?.name)
        .whereType<String>()
        .join(' / ');

    // "Sessões hoje" — só as do próprio instrutor, mesmo filtro que
    // `InstructorCalendarScreen` aplica quando aberto por um Instrutor.
    final todayCount =
        (occurrencesAsync.valueOrNull ?? const <SessionOccurrence>[])
            .where((o) =>
                o.instructorId == appUser.uid &&
                o.status == SessionOccurrenceStatus.scheduled &&
                o.startAt.year == now.year &&
                o.startAt.month == now.month &&
                o.startAt.day == now.day)
            .length;

    // "Alunos ativos" — o mockup diz "só alunos com serviço na tua
    // modalidade", mas o âmbito por modalidade (UC28) nunca foi
    // modelado como restrição real: `InstructorStudentsScreen` (Fase 8)
    // já lista TODOS os alunos ativos do tenant, e as Security Rules
    // permitem-no. Esta contagem reflete o que o ecrã de facto mostra,
    // em vez de prometer um filtro que não existe — mesma lacuna, já
    // assinalada, não uma nova.
    final activeMembers =
        (membersAsync.valueOrNull ?? const []).where((m) => m.active).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  myModalities.isEmpty
                      ? 'Instrutor'
                      : 'Instrutor · $myModalities',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  me?.name ?? '',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(value: '$todayCount', label: 'Sessões hoje'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(value: '$activeMembers', label: 'Alunos ativos'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Alunos'),
            subtitle: const Text('Plano de treino e avaliações (UC13/14/16)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const InstructorStudentsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Biblioteca de exercícios'),
            subtitle: const Text('Exercícios e vídeos partilhados (UC15)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('As minhas aulas'),
            subtitle: const Text('Semana a semana, por dia (UC20)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    InstructorCalendarScreen(instructorId: appUser.uid),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Enviar notificação'),
            subtitle: const Text('A um aluno específico (UC21)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SendNotificationScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
