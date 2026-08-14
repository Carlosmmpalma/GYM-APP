import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/modality_providers.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/staff_summary.dart';

/// Detalhe de staff (Instrutor/Gestor): dados + toggle ativo/inativo.
/// Mesmo raciocínio de `MemberDetailScreen` (desativar, nunca eliminar
/// — mockup "Editar / desativar utilizador", UC23/UC24), sem a secção
/// de subscriptions (staff não tem Plans).
class StaffDetailScreen extends ConsumerWidget {
  const StaffDetailScreen({super.key, required this.staff});

  final StaffSummary staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve pelo `staffProvider` ao vivo, mesmo padrão de
    // `currentPlan`/`currentMember` — `staff` é a cópia imutável de
    // quando `ManageStaffScreen` construiu este ecrã.
    final currentStaff = ref.watch(staffProvider).valueOrNull?.firstWhere(
              (s) => s.uid == staff.uid,
              orElse: () => staff,
            ) ??
        staff;

    return Scaffold(
      appBar: AppBar(title: Text(currentStaff.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentStaff.email,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Papel: ${currentStaff.roles.map((r) => r.name).join(', ')}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Staff ativo'),
              subtitle: Text(
                currentStaff.active
                    ? 'Pode continuar a fazer login e a dar aulas/PT.'
                    : 'Inativo — mantém o histórico (aulas dadas, etc.).'
                        '${currentStaff.roles.contains(Role.instructor) ? ' As séries/sessões futuras dele já foram canceladas (UC24).' : ''}',
              ),
              value: currentStaff.active,
              onChanged: (value) => _toggleActive(context, ref, currentStaff, value),
            ),
          ),
          if (currentStaff.roles.contains(Role.instructor)) ...[
            const SizedBox(height: 24),
            Text('Modalidades', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final modalitiesAsync = ref.watch(modalitiesProvider);
                return modalitiesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Text('Erro: $error'),
                  data: (modalities) {
                    final active = modalities.where((m) => m.active).toList();
                    if (active.isEmpty) {
                      return const Text(
                        'Ainda não existe nenhuma modalidade ativa.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      );
                    }
                    return Column(
                      children: active
                          .map(
                            (m) => CheckboxListTile(
                              title: Text(m.name),
                              value: currentStaff.modalityIds.contains(m.id),
                              onChanged: (checked) async {
                                final updated = {...currentStaff.modalityIds};
                                if (checked ?? false) {
                                  updated.add(m.id);
                                } else {
                                  updated.remove(m.id);
                                }
                                try {
                                  await ref.read(staffRepositoryProvider).setModalityIds(
                                        staffId: currentStaff.uid,
                                        modalityIds: updated,
                                      );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Não foi possível atualizar: $e')),
                                  );
                                }
                              },
                            ),
                          )
                          .toList(),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    StaffSummary currentStaff,
    bool active,
  ) async {
    final isInstructor = currentStaff.roles.contains(Role.instructor);

    // UC24 — desativar um instrutor cancela em cadeia as suas séries/
    // sessões futuras; um Gestor puro não tem nada para cascatar.
    // Reativar nunca cascata (não faz sentido "des-cancelar" sessões
    // sozinho) — continua a escrita simples de sempre.
    if (!active && isInstructor) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Desativar instrutor?'),
          content: Text(
            'As séries ativas e as sessões futuras de ${currentStaff.name} vão '
            'ser canceladas automaticamente (UC24) — quem estiver inscrito '
            'recupera a utilização semanal, como um cancelamento pelo estúdio.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desativar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        final summary = await ref
            .read(staffRepositoryProvider)
            .deactivateInstructorWithCascade(currentStaff.uid);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Instrutor desativado — ${summary.seriesCancelled} série(s) e '
              '${summary.occurrencesCancelled} sessão/sessões futura(s) '
              'canceladas (${summary.bookingsCancelled} marcação(ões) '
              'afetada(s)).',
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível desativar: $e')),
        );
      }
      return;
    }

    try {
      await ref.read(staffRepositoryProvider).setStaffActive(
            staffId: currentStaff.uid,
            active: active,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o staff: $e')),
      );
    }
  }
}
