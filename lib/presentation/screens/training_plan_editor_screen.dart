import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/training_plan_entry.dart';
import 'add_plan_entry_screen.dart';

/// Fase 8 (UC13, "Editor de plano" no mockup) — o Instrutor monta o
/// plano de treino de UM membro, sempre a partir da biblioteca
/// partilhada (UC15). Atualizar a carga de uma entrada cria sempre um
/// novo registo de histórico (UC16 fechado) — nunca um simples
/// `update` do valor.
class TrainingPlanEditorScreen extends ConsumerWidget {
  const TrainingPlanEditorScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(trainingPlanProvider(member.uid));
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Plano — ${member.name}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddPlanEntryScreen(member: member)),
        ),
        tooltip: 'Adicionar exercício da biblioteca',
        child: const Icon(Icons.add),
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sem plano atribuído. Usa o botão "+" para adicionar o '
                  'primeiro exercício da biblioteca.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final exercisesById = <String, Exercise>{
            for (final e in exercisesAsync.valueOrNull ?? const <Exercise>[])
              e.id: e,
          };
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _PlanEntryTile(
              member: member,
              entry: entries[index],
              exercise: exercisesById[entries[index].exerciseId],
            ),
          );
        },
      ),
    );
  }
}

class _PlanEntryTile extends ConsumerWidget {
  const _PlanEntryTile(
      {required this.member, required this.entry, required this.exercise});

  final MemberSummary member;
  final TrainingPlanEntry entry;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(exercise?.name ?? entry.exerciseId),
        subtitle: Text(
          '${entry.sets} séries × ${entry.reps} reps'
          '${entry.currentLoad != null ? ' — ${entry.currentLoad} kg' : ' — —'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'load') {
              _updateLoad(context, ref);
            } else if (value == 'remove') {
              _remove(context, ref);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'load', child: Text('Atualizar carga')),
            PopupMenuItem(value: 'remove', child: Text('Remover do plano')),
          ],
        ),
      ),
    );
  }

  Future<void> _updateLoad(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({double load, int reps})>(
      context: context,
      builder: (_) => _UpdateLoadDialog(entry: entry),
    );
    if (result == null) return;

    final recordedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (recordedBy == null) return;
    try {
      await ref.read(trainingPlanRepositoryProvider).updateLoad(
            memberId: member.uid,
            entryId: entry.id,
            exerciseId: entry.exerciseId,
            load: result.load,
            reps: result.reps,
            recordedBy: recordedBy,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar a carga: $e')),
      );
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(trainingPlanRepositoryProvider)
          .removeEntry(memberId: member.uid, entryId: entry.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível remover: $e')),
      );
    }
  }
}

class _UpdateLoadDialog extends StatefulWidget {
  const _UpdateLoadDialog({required this.entry});

  final TrainingPlanEntry entry;

  @override
  State<_UpdateLoadDialog> createState() => _UpdateLoadDialogState();
}

class _UpdateLoadDialogState extends State<_UpdateLoadDialog> {
  late final _loadController =
      TextEditingController(text: widget.entry.currentLoad?.toString() ?? '');
  late final _repsController =
      TextEditingController(text: widget.entry.reps.toString());

  @override
  void dispose() {
    _loadController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atualizar carga'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _loadController,
            decoration: const InputDecoration(labelText: 'Carga (kg)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repsController,
            decoration: const InputDecoration(labelText: 'Repetições'),
            keyboardType: TextInputType.number,
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
            final load = double.tryParse(
                _loadController.text.trim().replaceAll(',', '.'));
            final reps = int.tryParse(_repsController.text.trim());
            if (load == null || reps == null) return;
            Navigator.of(context).pop((load: load, reps: reps));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
