import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/booking_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../application/providers/plan_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/iso_week.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/modality.dart';
import '../../domain/entities/session_occurrence.dart';
import '../../domain/entities/staff_summary.dart';
import '../widgets/design_system.dart';
import '../widgets/today_classes.dart';
import 'exercise_library_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_students_screen.dart';
import 'send_notification_screen.dart';
import 'create_series_screen.dart';
import '../widgets/person_avatar.dart';

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
    final membersAsync = ref.watch(visibleMembersProvider);
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
    final todayOccurrences = (occurrencesAsync.valueOrNull ??
            const <SessionOccurrence>[])
        .where((o) =>
            o.instructorId == appUser.uid &&
            o.status == SessionOccurrenceStatus.scheduled &&
            o.startAt.year == now.year &&
            o.startAt.month == now.month &&
            o.startAt.day == now.day)
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final todayCount = todayOccurrences.length;

    // "Alunos ativos" — os DELE, não os do estúdio todo. O mockup pedia
    // "só alunos com serviço na tua modalidade" e durante muito tempo
    // isto contava (e o ecrã listava) toda a gente, porque o âmbito
    // nunca tinha sido modelado. Passou a ser: os alunos com subscrição
    // ativa a um serviço que ele leciona.
    final activeMembers =
        (membersAsync.valueOrNull ?? const []).where((m) => m.active).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cabeçalho com avatar de iniciais, como o mockup: quem abre a
        // app quer reconhecer-se de imediato, e o papel/modalidade é a
        // legenda, não o título.
        PanelCard(
          gradient: true,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PersonAvatar(
                name: me?.name ?? '',
                photoUrl: me?.photoUrl,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me?.name ?? '',
                      style: AppTheme.display(fontSize: 17),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      myModalities.isEmpty
                          ? 'Instrutor'
                          : 'Instrutor · $myModalities',
                      style:
                          const TextStyle(color: AppColors.mute, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
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
        // As aulas de hoje, com o estado da chamada e um toque para a
        // fazer. Ver `TodayClasses` — o painel do Gestor mostra a mesma
        // lista, sem o filtro por instrutor.
        TodayClasses(instructorId: appUser.uid),
        // Fase 11 — o Instrutor passou a criar as suas próprias aulas.
        // Antes tinha de pedir ao Gestor para lhe montar o horário,
        // mesmo sabendo as suas horas melhor do que ninguém.
        //
        // Só aparece quando ele tem serviços associados: sem isso o
        // servidor recusa a criação, e um atalho que leva a uma recusa
        // é pior do que atalho nenhum. O Gestor atribui-os na ficha de
        // staff.
        Consumer(
          builder: (context, ref, _) {
            final me = ref.watch(staffProvider).valueOrNull?.firstWhere(
                  (s) => s.uid == appUser.uid,
                  orElse: () => const StaffSummary(
                    uid: '',
                    name: '',
                    email: '',
                    roles: {},
                    active: false,
                    modalityIds: {},
                  ),
                );
            if (me == null) return const SizedBox.shrink();

            // Sem serviços atribuídos o atalho DESAPARECIA, e o
            // instrutor ficava a olhar para um ecrã onde criar uma aula
            // simplesmente não existia — sem nada a dizer que lhe
            // faltava uma configuração que ele nem pode fazer.
            //
            // As Security Rules exigem que a aula seja de um serviço do
            // instrutor (`instructorOwnsSession`), por isso o atalho
            // continua inativo; o que muda é passar a dizer porquê e a
            // quem pedir.
            if (me.serviceIds.isEmpty) {
              return const Column(
                children: [
                  _Shortcut(
                    icon: Icons.add_circle_outline,
                    title: 'Criar aula',
                    subtitle: 'Precisas de ter serviços atribuídos. Pede ao '
                        'Gestor para te associar os que lecionas '
                        '(Gestão › Utilizadores › o teu perfil).',
                    onTap: null,
                  ),
                  SizedBox(height: 8),
                ],
              );
            }
            return Column(
              children: [
                _Shortcut(
                  icon: Icons.add_circle_outline,
                  title: 'Criar aula',
                  subtitle: 'Uma série semanal ou uma sessão avulsa, nos '
                      'serviços que lecionas',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateSeriesScreen(
                        restrictedServiceIds: me.serviceIds,
                        lockedInstructorId: appUser.uid,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
        _Shortcut(
          icon: Icons.groups_outlined,
          title: 'Alunos',
          subtitle: 'Plano de treino e avaliações de cada aluno',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InstructorStudentsScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _Shortcut(
          icon: Icons.video_library_outlined,
          title: 'Biblioteca de exercícios',
          subtitle: 'Exercícios e vídeos partilhados por todos',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _Shortcut(
          icon: Icons.calendar_month_outlined,
          title: 'As minhas aulas',
          subtitle: 'Semana a semana, com os inscritos de cada sessão',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    InstructorCalendarScreen(instructorId: appUser.uid)),
          ),
        ),
        const SizedBox(height: 8),
        _Shortcut(
          icon: Icons.notifications_outlined,
          title: 'Enviar notificação',
          subtitle: 'Avisar um aluno específico',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SendNotificationScreen()),
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
    // `StatNumber` é o par número-em-Oswald + etiqueta do mockup, para o
    // número ler primeiro.
    return PanelCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: StatNumber(value: value, label: label),
    );
  }
}

/// Atalho do dashboard: `IconBox` + título + a linha que diz o que se faz
/// lá dentro. Os subtítulos deixaram de citar códigos de use case
/// ("UC13/14/16") — isso diz algo a quem escreveu os documentos, nada a
/// quem usa a app.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// `null` = o atalho aparece mas não leva a lado nenhum. É como se
  /// mostra que a ação existe e o que falta para a poder usar, em vez
  /// de a esconder e deixar a pergunta no ar.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          IconBox(icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.mute, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 18, color: AppColors.dim)
          else
            const Icon(Icons.lock_outline, size: 16, color: AppColors.dim),
        ],
      ),
    );
  }
}
