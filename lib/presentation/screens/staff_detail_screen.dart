import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
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
                    : 'Inativo — mantém o histórico (aulas dadas, etc.), '
                        'mas devias reatribuir as sessões futuras dele.',
              ),
              value: currentStaff.active,
              onChanged: (value) async {
                try {
                  await ref.read(staffRepositoryProvider).setStaffActive(
                        staffId: currentStaff.uid,
                        active: value,
                      );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Não foi possível atualizar o staff: $e')),
                  );
                }
              },
            ),
          ),
          if (!currentStaff.active)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Nota: desativar aqui não cancela automaticamente as sessões '
                'futuras deste instrutor (UC24) — isso é gestão de sessões, '
                'ainda não construída (Fase 5+ do guia).',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
