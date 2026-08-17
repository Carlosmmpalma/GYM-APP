import 'package:flutter/material.dart';

import 'assign_subscription_screen.dart';
import 'gestor_dashboard_screen.dart';
import 'exercise_library_screen.dart';
import 'instructor_calendar_screen.dart';
import 'instructor_students_screen.dart';
import 'manage_free_training_screen.dart';
import 'manage_members_screen.dart';
import 'manage_modalities_screen.dart';
import 'manage_plans_screen.dart';
import 'manage_series_screen.dart';
import 'manage_services_screen.dart';
import 'manage_staff_screen.dart';
import 'send_notification_screen.dart';
import 'tenant_settings_screen.dart';

/// Hub do Gestor (Fase 3 + extensão pedida a seguir) — ponto de
/// entrada para os ecrãs de gestão: Serviços, Planos, Membros (ver
/// planos/histórico de cada um) e Atribuir plano. Só é alcançável a
/// partir de [HomeScreen] quando
/// `AppUser.isManager` (ver `home_screen.dart`); este ecrã em si não
/// repete essa verificação porque não tem forma de ser navegado sem
/// passar por lá primeiro — a fonte de verdade real continua a ser as
/// Security Rules do lado do servidor.
class ManagerScreen extends StatelessWidget {
  const ManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestão')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Visão global'),
              subtitle: const Text('Membros, séries e ocupação da semana'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const GestorDashboardScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fitness_center_outlined),
              title: const Text('Serviços'),
              subtitle:
                  const Text('Criar e ativar/desativar os serviços do ginásio'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageServicesScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Modalidades'),
              subtitle:
                  const Text('Pilates, Hyrox... e a que serviços se aplicam'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ManageModalitiesScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.card_membership_outlined),
              title: const Text('Planos'),
              subtitle: const Text(
                  'Criar/editar planos, associar serviços já criados'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManagePlansScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Membros'),
              subtitle:
                  const Text('Ver os planos e o histórico de cada membro'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageMembersScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Alunos'),
              subtitle: const Text('Avaliações e plano de treino (Fase 8)'),
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
              subtitle:
                  const Text('Partilhada por todos os instrutores (UC15)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ExerciseLibraryScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Staff'),
              subtitle:
                  const Text('Instrutores e Gestores — criar, ver, desativar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageStaffScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_repeat_outlined),
              title: const Text('Aulas / Horários'),
              subtitle:
                  const Text('Séries recorrentes e sessões "só esta data"'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageSeriesScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.self_improvement_outlined),
              title: const Text('Treino livre'),
              subtitle:
                  const Text('Configurar, aprovar e publicar a grelha semanal'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ManageFreeTrainingScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Calendário'),
              subtitle: const Text(
                  'Semana a semana, por dia, todas as sessões (UC20)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const InstructorCalendarScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add_alt_outlined),
              title: const Text('Atribuir plano a membro'),
              subtitle: const Text('Criar uma subscription para um membro'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AssignSubscriptionScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notificar um membro'),
              subtitle: const Text(
                  'Enviar uma notificação push a um membro específico'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const SendNotificationScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Definições'),
              subtitle:
                  const Text('Antecedência mínima para cancelar (Fase 4)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TenantSettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
