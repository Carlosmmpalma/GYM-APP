import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/member_summary.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../../domain/entities/training_workout.dart';
import '../widgets/design_system.dart';
import 'add_plan_entry_screen.dart';

/// Fase 8 (UC13, "Editor de plano" no mockup) — o Instrutor monta o
/// plano de treino de UM membro, sempre a partir da biblioteca
/// partilhada (UC15). Atualizar a carga de uma entrada cria sempre um
/// novo registo de histórico (UC16 fechado) — nunca um simples
/// `update` do valor.
///
/// Fase 11 — o plano ganhou a camada que lhe faltava: **treinos**.
/// Era uma lista corrida de exercícios, sem forma de dizer "isto é o
/// treino de costas e aquilo o de pernas". Um aluno que treina três
/// vezes por semana via os exercícios dos três dias todos misturados, e
/// nem ele nem o instrutor sabiam o que fazer em que dia. É a estrutura
/// que qualquer instrutor usa para prescrever, e a que as apps da área
/// implementam: plano → treinos → exercícios ordenados.
class TrainingPlanEditorScreen extends ConsumerWidget {
  const TrainingPlanEditorScreen({super.key, required this.member});

  final MemberSummary member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(trainingPlanProvider(member.uid));
    final workoutsAsync = ref.watch(memberWorkoutsProvider(member.uid));
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Plano — ${member.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _createWorkout(context, ref, workoutsAsync.valueOrNull ?? const []),
        icon: const Icon(Icons.add),
        label: const Text('Novo treino'),
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (entries) {
          final workouts =
              workoutsAsync.valueOrNull ?? const <TrainingWorkout>[];
          final exercisesById = <String, Exercise>{
            for (final e in exercisesAsync.valueOrNull ?? const <Exercise>[])
              e.id: e,
          };

          // Exercícios de antes de existirem treinos, ou que ficaram
          // soltos ao apagar um. Aparecem num grupo próprio para o
          // instrutor os arrumar, em vez de desaparecerem.
          final orphans = entries.where((e) => e.workoutId == null).toList();

          if (workouts.isEmpty && orphans.isEmpty) {
            return EmptyState(
              icon: Icons.fitness_center_outlined,
              title: 'Sem plano de treino',
              message: 'Um plano organiza-se por treinos — "Treino A — '
                  'Costas e Bíceps", "Treino B — Pernas" — e cada treino '
                  'tem os seus exercícios pela ordem em que se fazem.',
              actionLabel: 'Criar o primeiro treino',
              onAction: () => _createWorkout(context, ref, workouts),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              for (final workout in workouts.where((w) => w.active)) ...[
                _WorkoutSection(
                  member: member,
                  workout: workout,
                  entries:
                      entries.where((e) => e.workoutId == workout.id).toList(),
                  exercisesById: exercisesById,
                ),
                const SizedBox(height: 20),
              ],
              if (orphans.isNotEmpty) ...[
                const SectionLabel('Sem treino atribuído'),
                const SizedBox(height: 2),
                const Text(
                  'Exercícios que não estão em nenhum treino. Move-os para '
                  'um, ou remove-os.',
                  style: TextStyle(
                      color: AppColors.dim, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 8),
                for (final entry in orphans) ...[
                  _PlanEntryTile(
                    key: ValueKey(entry.id),
                    member: member,
                    entry: entry,
                    exercise: exercisesById[entry.exerciseId],
                    workouts: workouts,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _createWorkout(
    BuildContext context,
    WidgetRef ref,
    List<TrainingWorkout> existing,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _WorkoutNameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(trainingPlanRepositoryProvider).addWorkout(
            memberId: member.uid,
            name: name.trim(),
            // No fim da lista: a ordem dos treinos é a sequência da
            // semana, e um treino novo entra a seguir aos que já lá
            // estão.
            position: existing.length,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível criar o treino. Tenta outra vez.'))),
      );
    }
  }
}

/// Um treino do plano, com os seus exercícios pela ordem em que se
/// fazem. É a unidade com que um instrutor pensa: "hoje é o Treino B".
class _WorkoutSection extends ConsumerWidget {
  const _WorkoutSection({
    required this.member,
    required this.workout,
    required this.entries,
    required this.exercisesById,
  });

  final MemberSummary member;
  final TrainingWorkout workout;
  final List<TrainingPlanEntry> entries;
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                workout.name.toUpperCase(),
                style: AppTheme.display(fontSize: 15),
              ),
            ),
            Text(
              '${entries.length} exercício(s)',
              style: const TextStyle(color: AppColors.mute, fontSize: 11),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opções do treino',
              onSelected: (value) => _onMenu(context, ref, value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Mudar o nome')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('Apagar treino'),
                ),
              ],
            ),
          ],
        ),
        if (workout.notes.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            workout.notes,
            style: const TextStyle(
                color: AppColors.mute, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const PanelCard(
            child: Text(
              'Este treino ainda não tem exercícios.',
              style: TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          )
        else
          // `ReorderableListView` dentro de um `ListView`: `shrinkWrap`
          // e sem física própria — quem rola é o ecrã.
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            onReorder: (oldIndex, newIndex) =>
                _reorder(ref, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Padding(
                key: ValueKey(entry.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlanEntryTile(
                  member: member,
                  entry: entry,
                  exercise: exercisesById[entry.exerciseId],
                  workouts: const [],
                ),
              );
            },
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddPlanEntryScreen(
                member: member,
                workoutId: workout.id,
                nextPosition: entries.length,
              ),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar exercício'),
        ),
      ],
    );
  }

  Future<void> _reorder(WidgetRef ref, int oldIndex, int newIndex) async {
    final reordered = [...entries];
    // O `newIndex` que o `ReorderableListView` dá conta com o item ainda
    // na lista; depois de o remover, tudo o que estava à frente recua um.
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    await ref.read(trainingPlanRepositoryProvider).reorderEntries(
          memberId: member.uid,
          orderedEntryIds: reordered.map((e) => e.id).toList(),
        );
  }

  Future<void> _onMenu(
      BuildContext context, WidgetRef ref, String value) async {
    final repository = ref.read(trainingPlanRepositoryProvider);
    if (value == 'rename') {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _WorkoutNameDialog(initial: workout.name),
      );
      if (name == null || name.trim().isEmpty) return;
      await repository.updateWorkout(
        memberId: member.uid,
        workoutId: workout.id,
        name: name.trim(),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Apagar "${workout.name}"?'),
        content: Text(
          entries.isEmpty
              ? 'O treino está vazio — não se perde nada.'
              : 'Os ${entries.length} exercícios deste treino NÃO são '
                  'apagados: ficam sem treino atribuído, no fim do plano, '
                  'para os poderes mover para outro. O histórico de cargas '
                  'deles mantém-se.',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.removeWorkout(
      memberId: member.uid,
      workoutId: workout.id,
    );
  }
}

/// Dá nome a um treino. O `hintText` sugere o formato que os instrutores
/// usam, sem o impor.
class _WorkoutNameDialog extends StatefulWidget {
  const _WorkoutNameDialog({this.initial});

  final String? initial;

  @override
  State<_WorkoutNameDialog> createState() => _WorkoutNameDialogState();
}

class _WorkoutNameDialogState extends State<_WorkoutNameDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo treino' : 'Mudar o nome'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nome do treino',
          hintText: 'Treino A — Costas e Bíceps',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PlanEntryTile extends ConsumerWidget {
  const _PlanEntryTile({
    super.key,
    required this.member,
    required this.entry,
    required this.exercise,
    required this.workouts,
  });

  final MemberSummary member;
  final TrainingPlanEntry entry;
  final Exercise? exercise;

  /// Treinos para onde este exercício pode ser movido. Vazio quando já
  /// está dentro de um — mover entre treinos faz-se a partir do grupo
  /// "sem treino atribuído", que é onde o caso aparece.
  final List<TrainingWorkout> workouts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = [
      '${entry.sets} × ${entry.reps}',
      if (entry.currentLoad != null) '${entry.currentLoad} kg',
      if (entry.restSeconds != null) '${entry.restSeconds}s descanso',
    ].join(' · ');

    return Card(
      child: ListTile(
        title: Text(exercise?.name ?? entry.exerciseId),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            if (entry.notes.isNotEmpty)
              Text(
                entry.notes,
                style: const TextStyle(
                    color: AppColors.mute, fontSize: 11, height: 1.4),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opções do exercício',
          onSelected: (value) {
            if (value == 'load') {
              _updateLoad(context, ref);
            } else if (value == 'remove') {
              _remove(context, ref);
            } else if (value.startsWith('move:')) {
              _move(context, ref, value.substring(5));
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'load', child: Text('Atualizar carga')),
            for (final workout in workouts.where((w) => w.active))
              PopupMenuItem(
                value: 'move:${workout.id}',
                child: Text('Mover para ${workout.name}'),
              ),
            const PopupMenuItem(
                value: 'remove', child: Text('Remover do plano')),
          ],
        ),
      ),
    );
  }

  Future<void> _move(
      BuildContext context, WidgetRef ref, String workoutId) async {
    try {
      await ref.read(trainingPlanRepositoryProvider).moveEntry(
            memberId: member.uid,
            entryId: entry.id,
            workoutId: workoutId,
            // No fim do treino de destino. Uma posição a meio seria uma
            // decisão que o instrutor não tomou; reordenar depois é um
            // arrasto.
            position: 999,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível mover. Tenta outra vez.'))),
      );
    }
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
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível atualizar a carga. Tenta outra vez.'))),
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
        SnackBar(
            content: Text(userFacingError(e,
                fallback: 'Não foi possível remover. Tenta outra vez.'))),
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

  /// Pré-preenchido com a prescrição QUANDO ela é um número simples.
  /// "8-12" ou "45s" não são um número de repetições feitas, e sugerir
  /// um valor que não existe seria pior do que deixar em branco.
  late final _repsController = TextEditingController(
    text: int.tryParse(widget.entry.reps)?.toString() ?? '',
  );

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
          const Text(
            'Regista o que foi MESMO feito hoje. A prescrição do plano '
            'não muda com isto.',
            style: TextStyle(fontSize: 12, color: AppColors.mute),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loadController,
            decoration: const InputDecoration(labelText: 'Carga (kg)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _repsController,
            decoration: const InputDecoration(labelText: 'Repetições feitas'),
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
