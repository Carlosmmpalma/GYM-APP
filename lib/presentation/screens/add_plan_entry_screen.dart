import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../core/utils/offline_write.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_summary.dart';
import '../widgets/design_system.dart';

/// Fase 8 (UC13 — "seleção a partir da biblioteca", UC15) — procurar
/// um exercício da biblioteca partilhada e defini-lo (séries/reps/
/// carga) para o plano deste membro.
class AddPlanEntryScreen extends ConsumerStatefulWidget {
  const AddPlanEntryScreen({
    super.key,
    required this.member,
    this.workoutId,
    this.nextPosition = 0,
  });

  final MemberSummary member;

  /// Fase 11 — a que treino do plano este exercício vai. `null` só
  /// acontece se este ecrã for aberto fora de um treino, e nesse caso o
  /// exercício fica no grupo "sem treino atribuído".
  final String? workoutId;

  /// Onde entra na ordem do treino — no fim, que é onde um exercício
  /// novo pertence até o instrutor decidir outra coisa.
  final int nextPosition;

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
              error: (error, stack) => ErrorState(error: error),
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
                        subtitle: Text('Categoria: ${exercise.category}'),
                        trailing: IconButton(
                          tooltip: 'Adicionar ao plano',
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
    final result = await showDialog<
        ({
          int sets,
          String reps,
          double? load,
          int? restSeconds,
          String notes
        })>(
      context: context,
      builder: (_) => _ConfigureEntryDialog(exercise: exercise),
    );
    if (result == null) return;

    final recordedBy = ref.read(currentAppUserProvider).valueOrNull?.uid ?? '';
    try {
      // Sem `writeOrQueue`, o instrutor com má rede ficava neste ecrã
      // sem nada acontecer: o exercício ia para a fila local, o ecrã
      // nunca fechava, e ele voltava a adicioná-lo.
      final outcome = await writeOrQueue(
        ref.read(trainingPlanRepositoryProvider).addEntry(
              memberId: widget.member.uid,
              exerciseId: exercise.id,
              sets: result.sets,
              reps: result.reps,
              initialLoad: result.load,
              recordedBy: recordedBy,
              workoutId: widget.workoutId,
              position: widget.nextPosition,
              restSeconds: result.restSeconds,
              notes: result.notes,
            ),
      );
      if (!context.mounted) return;
      if (outcome == WriteOutcome.queued) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(writeOutcomeMessage(outcome, confirmed: ''))),
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível adicionar ao plano. Tenta outra vez.'))),
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
  final _restController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    _loadController.dispose();
    _restController.dispose();
    _notesController.dispose();
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
            // Texto e não número: um instrutor prescreve "8-12", "45s"
            // ou "até à falha", e o modelo antigo — um inteiro — não
            // conseguia representar nada disso. O comentário do próprio
            // domínio dava o exemplo da prancha, que não cabia lá.
            decoration: const InputDecoration(
              labelText: 'Repetições',
              hintText: '10, 8-12, 45s, até à falha',
            ),
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
          const SizedBox(height: 12),
          TextField(
            controller: _restController,
            decoration: const InputDecoration(
              labelText: 'Descanso entre séries (segundos)',
              hintText: 'Opcional',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Nota',
              hintText: 'Cadência, amplitude, cuidados — opcional',
            ),
            maxLines: 2,
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
            final reps = _repsController.text.trim();
            if (sets == null || reps.isEmpty) return;
            final loadText = _loadController.text.trim();
            final load = loadText.isEmpty
                ? null
                : double.tryParse(loadText.replaceAll(',', '.'));
            Navigator.of(context).pop((
              sets: sets,
              reps: reps,
              load: load,
              restSeconds: int.tryParse(_restController.text.trim()),
              notes: _notesController.text.trim(),
            ));
          },
          child: const Text('Adicionar ao plano'),
        ),
      ],
    );
  }
}
