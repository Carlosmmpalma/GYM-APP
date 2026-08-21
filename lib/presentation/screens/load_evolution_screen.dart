import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers/training_providers.dart';
import '../widgets/design_system.dart';

final _dateFormat = DateFormat('dd/MM/yyyy', 'pt_PT');

/// Fase 8 (UC16 atualizado) — "Evolução da carga": "cada atualização
/// fica registada, nunca sobrescreve a anterior". Mostra a carga atual
/// + delta desde o primeiro registo + a lista completa, mais recente
/// primeiro (mesmo formato do mockup).
class LoadEvolutionScreen extends ConsumerWidget {
  const LoadEvolutionScreen({
    super.key,
    required this.memberId,
    required this.exerciseId,
    required this.exerciseName,
  });

  final String memberId;
  final String exerciseId;
  final String exerciseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(
      loadHistoryProvider((memberId: memberId, exerciseId: exerciseId)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(exerciseName)),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Ainda não há histórico de carga para este exercício.'),
              ),
            );
          }
          // `history` já vem mais recente primeiro (watchHistory ordena
          // por `recordedAt desc`) — o primeiro registo HISTÓRICO
          // (mais antigo) é o último da lista.
          final current = history.first;
          final oldest = history.last;
          final delta = current.load - oldest.load;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carga atual: ${current.load} kg',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (history.length > 1)
                        Text(
                          '${delta >= 0 ? '+' : ''}$delta kg desde '
                          '${_dateFormat.format(oldest.recordedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Histórico', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final entry in history)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_dateFormat.format(entry.recordedAt)),
                    trailing: Text('${entry.load} kg'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
