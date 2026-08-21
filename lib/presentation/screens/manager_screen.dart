import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';
import 'assign_subscription_screen.dart';
import 'exercise_library_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_students_screen.dart';
import 'manage_free_training_screen.dart';
import 'manage_modalities_screen.dart';
import 'manage_payments_screen.dart';
import 'manage_plans_screen.dart';
import 'manage_series_screen.dart';
import 'manage_services_screen.dart';
import 'manage_users_screen.dart';
import 'send_notification_screen.dart';
import 'tenant_settings_screen.dart';

/// Hub do Gestor. Até à Fase 10 era uma lista de 14 cards sem nenhuma
/// ordem — "Serviços" antes de "Planos" (quando um Plano é feito DE
/// serviços), "Membros" separado de "Alunos" e de "Staff" (as três são
/// pessoas), "Atribuir plano" no fundo, longe de "Membros". Era a queixa
/// concreta: difícil perceber o que fazer e por que ordem.
///
/// Agora está agrupado por PERGUNTA que o Gestor tem na cabeça, e dentro
/// de cada grupo por ordem de dependência — o que é preciso existir
/// primeiro aparece primeiro. "Oferta" segue Planos → Serviços →
/// Modalidades porque é essa a ordem em que se pensa o negócio (que
/// planos vendo? que serviços incluem? que modalidades os concretizam),
/// mesmo que tecnicamente o Serviço tenha de existir antes de ser
/// associado a um Plano — a UI não é um diagrama de dependências.
class ManagerScreen extends StatelessWidget {
  const ManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: const [
        _Group(
          label: 'Pessoas',
          hint: 'Quem frequenta e quem trabalha no estúdio.',
          items: [
            // Uma entrada só, como no mockup: alunos e staff na mesma
            // lista, com separadores. "Criar utilizador" deixou de estar
            // atrás de dois FABs em ecrãs diferentes.
            _Item(
              icon: Icons.people_outline,
              title: 'Utilizadores',
              subtitle: 'Alunos, instrutores e gestores — criar e gerir contas',
              screen: ManageUsersScreen(),
            ),
            _Item(
              icon: Icons.groups_outlined,
              title: 'Alunos — treino',
              subtitle: 'Avaliações físicas e plano de treino de cada aluno',
              screen: InstructorStudentsScreen(),
            ),
          ],
        ),
        _Group(
          label: 'Oferta',
          hint: 'O que o estúdio vende e como está organizado.',
          items: [
            _Item(
              icon: Icons.card_membership_outlined,
              title: 'Planos',
              subtitle: 'O que um membro contrata, e que serviços inclui',
              screen: ManagePlansScreen(),
            ),
            _Item(
              icon: Icons.fitness_center_outlined,
              title: 'Serviços',
              subtitle: 'Aula de grupo, PT, treino livre — a base dos planos',
              screen: ManageServicesScreen(),
            ),
            _Item(
              icon: Icons.category_outlined,
              title: 'Modalidades',
              subtitle: 'Hyrox, Pilates… e a que serviços se aplicam',
              screen: ManageModalitiesScreen(),
            ),
          ],
          trailing: _InlineAction(
            icon: Icons.assignment_ind_outlined,
            label: 'Atribuir um plano a um membro',
            screen: AssignSubscriptionScreen(),
          ),
        ),
        _Group(
          label: 'Agenda',
          hint: 'Aulas, horários e ocupação da semana.',
          items: [
            _Item(
              icon: Icons.event_repeat_outlined,
              title: 'Aulas / Horários',
              subtitle: 'Séries semanais e sessões "só esta data"',
              screen: ManageSeriesScreen(),
            ),
            _Item(
              icon: Icons.self_improvement_outlined,
              title: 'Treino livre',
              subtitle: 'Configurar, aprovar e publicar a grelha semanal',
              screen: ManageFreeTrainingScreen(),
            ),
            _Item(
              icon: Icons.calendar_month_outlined,
              title: 'Calendário',
              subtitle: 'Semana a semana, por dia, com quem está inscrito',
              screen: InstructorCalendarScreen(),
            ),
          ],
        ),
        _Group(
          label: 'Dinheiro',
          hint: 'Mensalidades — registo manual, sem gateway.',
          items: [
            _Item(
              icon: Icons.payments_outlined,
              title: 'Mensalidades',
              subtitle: 'Marcar pago/em atraso e ver o histórico por membro',
              screen: ManagePaymentsScreen(),
            ),
          ],
        ),
        _Group(
          label: 'Conteúdos e definições',
          hint: null,
          items: [
            _Item(
              icon: Icons.video_library_outlined,
              title: 'Biblioteca de exercícios',
              subtitle: 'Partilhada por todos os instrutores',
              screen: ExerciseLibraryScreen(),
            ),
            _Item(
              icon: Icons.notifications_outlined,
              title: 'Notificar um membro',
              subtitle: 'Enviar uma mensagem push a um aluno',
              screen: SendNotificationScreen(),
            ),
            _Item(
              icon: Icons.settings_outlined,
              title: 'Definições',
              subtitle: 'Antecedência mínima para marcar e para cancelar',
              screen: TenantSettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}

class _Item {
  const _Item({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
}

/// Ação que pertence ao grupo mas não é um "sítio" — fica no fim, com
/// aspeto diferente das entradas de navegação, para não parecer mais um
/// ecrã da lista. "Atribuir um plano" é isto: é um VERBO, no meio de
/// substantivos.
class _InlineAction {
  const _InlineAction({
    required this.icon,
    required this.label,
    required this.screen,
  });

  final IconData icon;
  final String label;
  final Widget screen;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.hint,
    required this.items,
    this.trailing,
  });

  final String label;
  final String? hint;
  final List<_Item> items;
  final _InlineAction? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        SectionLabel(label),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: const TextStyle(color: AppColors.dim, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        for (final item in items) ...[
          PanelCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => item.screen),
            ),
            child: Row(
              children: [
                IconBox(item.icon),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: AppColors.bone,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          color: AppColors.mute,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.dim),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (trailing != null)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => trailing!.screen),
            ),
            icon: Icon(trailing!.icon, size: 18),
            label: Text(trailing!.label),
          ),
      ],
    );
  }
}
