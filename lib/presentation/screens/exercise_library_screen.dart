import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../core/utils/search_text.dart';
import '../../domain/entities/exercise.dart';
import '../widgets/design_system.dart';
import 'exercise_form_screen.dart';

/// Fase 8 (UC15 fechado) — "lista partilhada por todos os
/// instrutores". Sem filtro por instrutor de propósito — a biblioteca
/// não tem dono.
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  String _query = '';

  /// Os grupos musculares não são um enum — são texto livre escrito por
  /// quem cria o exercício (ver `Exercise.muscleGroup`). Por isso os
  /// filtros são construídos a partir do que existe, e não de uma lista
  /// fixa que ficaria desatualizada.
  String? _muscleGroup;

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca de exercícios')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExerciseFormScreen()),
        ),
        tooltip: 'Novo exercício',
        child: const Icon(Icons.add),
      ),
      body: exercisesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (exercises) {
          if (exercises.isEmpty) {
            return EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Biblioteca vazia',
              message: 'A biblioteca é partilhada por todos os instrutores '
                  'e é de onde saem os exercícios dos planos de treino. '
                  'Cada um pode ter um vídeo de demonstração que o aluno '
                  'vê na app.',
              actionLabel: 'Criar o primeiro exercício',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExerciseFormScreen()),
              ),
            );
          }
          final groups = <String, int>{};
          for (final exercise in exercises) {
            final group = exercise.muscleGroup.trim();
            if (group.isEmpty) continue;
            groups[group] = (groups[group] ?? 0) + 1;
          }
          final sortedGroups = groups.keys.toList()..sort();

          final visible = exercises.where((exercise) {
            if (_muscleGroup != null &&
                exercise.muscleGroup.trim() != _muscleGroup) {
              return false;
            }
            return searchMatchesAny(
              [exercise.name, exercise.description, exercise.muscleGroup],
              _query,
            );
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    SearchField(
                      hintText: 'Procurar exercício',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    if (sortedGroups.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      FilterChipsRow<String>(
                        allCount: exercises.length,
                        selected: _muscleGroup,
                        onSelected: (value) =>
                            setState(() => _muscleGroup = value),
                        options: [
                          for (final group in sortedGroups)
                            (group, group, groups[group]!),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (visible.isEmpty)
                Expanded(
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nada encontrado',
                    message: _query.isEmpty
                        ? 'Nenhum exercício deste grupo muscular.'
                        : 'Nenhum exercício corresponde a "$_query".',
                  ),
                )
              else
                Expanded(child: _buildList(visible)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<Exercise> exercises) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: exercises.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final exercise = exercises[index];
        return Card(
          child: ListTile(
            title: Text(exercise.name),
            subtitle: Text('Grupo muscular: ${exercise.muscleGroup}'),
            trailing: Chip(
              label: Text(exercise.hasVideo ? 'Com vídeo' : 'Sem vídeo'),
              visualDensity: VisualDensity.compact,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExerciseFormScreen(exercise: exercise),
              ),
            ),
          ),
        );
      },
    );
  }
}
