import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import 'exercise_form_screen.dart';

/// Fase 8 (UC15 fechado) — "lista partilhada por todos os
/// instrutores". Sem filtro por instrutor de propósito — a biblioteca
/// não tem dono.
class ExerciseLibraryScreen extends ConsumerWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        error: (error, stack) => Center(child: Text('Erro: $error')),
        data: (exercises) {
          if (exercises.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ainda não existe nenhum exercício. Usa o botão "+" para '
                  'criar o primeiro.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
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
        },
      ),
    );
  }
}
