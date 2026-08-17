import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_summary.dart';

/// Fase 8 (UC13 — "seleção a partir da biblioteca", UC15) — procurar
/// um exercício da biblioteca partilhada e defini-lo (séries/reps/
/// carga) para o plano deste membro.
class AddPlanEntryScreen extends ConsumerStatefulWidget {
  const AddPlanEntryScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  ConsumerState<AddPlanEntryScreen> createState() => _AddPlanEntryScreenState();
}

class _AddPlanEntryScreenState extends ConsumerState<AddPlanEntryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar exercício')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Procurar exercício...',
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: exercisesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Erro: $error')),
              data: (exercises) {
                final filtered = _query.isEmpty
                    ? exercises
                    : exercises
                        .where((e) => e.name.toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('Nenhum exercício encontrado.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final exercise = filtered[index];
                    return Card(
                      child: ListTile(
                        title: Text(exercise.name),
                        subtitle:
                            Text('Grupo muscular: ${exercise.muscleGroup}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _configureAndAdd(context, exercise),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configureAndAdd(BuildContext context, Exercise exercise) async {
    final result = await showDialog<({int sets, int reps, double? load})>(
      context: context,
      builder: (_) => _ConfigureEntryDialog(exercise: exercise),
    );
    if (result == null) return;

    final recordedBy = ref.read(currentAppUserProvider).valueOrNull?.uid ?? '';
    try {
      await ref.read(trainingPlanRepositoryProvider).addEntry(
            memberId: widget.member.uid,
            exerciseId: exercise.id,
            sets: result.sets,
            reps: result.reps,
            initialLoad: result.load,
            recordedBy: recordedBy,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar ao plano: $e')),
      );
    }
  }
}

class _ConfigureEntryDialog extends StatefulWidget {
  const _ConfigureEntryDialog({required this.exercise});

  final Exercise exercise;

  @override
  State<_ConfigureEntryDialog> createState() => _ConfigureEntryDialogState();
}

class _ConfigureEntryDialogState extends State<_ConfigureEntryDialog> {
  final _setsController = TextEditingController(text: '4');
  final _repsController = TextEditingController(text: '10');
  final _loadController = TextEditingController();

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    _loadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.exercise.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _setsController,
            decoration: const InputDecoration(labelText: 'Séries'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repsController,
            decoration: const InputDecoration(labelText: 'Repetições'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loadController,
            decoration: const InputDecoration(
              labelText: 'Carga (kg)',
              hintText: 'Deixa em branco se não aplicável (ex.: Prancha)',
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
            final sets = int.tryParse(_setsController.text.trim());
            final reps = int.tryParse(_repsController.text.trim());
            if (sets == null || reps == null) return;
            final loadText = _loadController.text.trim();
            final load = loadText.isEmpty
                ? null
                : double.tryParse(loadText.replaceAll(',', '.'));
            Navigator.of(context).pop((sets: sets, reps: reps, load: load));
          },
          child: const Text('Adicionar ao plano'),
        ),
      ],
    );
  }
}
