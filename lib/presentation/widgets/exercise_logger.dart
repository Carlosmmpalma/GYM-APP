import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/training_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/entities/load_history_entry.dart';
import '../../domain/entities/training_plan_entry.dart';
import '../../domain/entities/workout_session.dart';
import 'design_system.dart';
import '../screens/exercise_video_screen.dart';

/// O registo de UM exercício dentro de uma sessão a decorrer.
///
/// Vivia dentro de `active_workout_screen.dart`, privado. Saiu para
/// aqui quando o mesmo registo passou a ser preciso em dois sítios: o
/// treino individual e o **treino de turma** (`GroupWorkoutScreen`),
/// onde o instrutor salta entre alunos sem sair do ecrã. É a mesma
/// peça nos dois — o que muda é de quem é a sessão.
/// Um exercício dentro da sessão: a prescrição, as séries já feitas, e a
/// linha para confirmar a próxima.
class ExerciseLogger extends ConsumerStatefulWidget {
  const ExerciseLogger({
    super.key,
    required this.memberId,
    required this.sessionId,
    required this.entry,
    required this.exercise,
    required this.done,
  });

  final String memberId;
  final String sessionId;
  final TrainingPlanEntry entry;
  final Exercise? exercise;
  final List<SetLog> done;

  @override
  ConsumerState<ExerciseLogger> createState() => _ExerciseLoggerState();
}

class _ExerciseLoggerState extends ConsumerState<ExerciseLogger> {
  late final _repsController = TextEditingController();
  late final _loadController = TextEditingController();
  bool _busy = false;

  /// Validação do campo de repetições.
  ///
  /// Estava num SnackBar: a pessoa tocava em "Registar", a mensagem
  /// subia do fundo do ecrã a dizer o que faltava, e quatro segundos
  /// depois desaparecia — enquanto ela ainda olhava para o campo. Uma
  /// mensagem de validação tem de ficar ONDE está o erro, e ficar até
  /// ele ser corrigido.
  String? _erroReps;
  bool _prefilled = false;

  @override
  void dispose() {
    _repsController.dispose();
    _loadController.dispose();
    super.dispose();
  }

  /// Pré-preenche com o que faz sentido tentar hoje: a carga da última
  /// série feita nesta sessão, ou a do plano. Poupar duas escritas por
  /// série é a diferença entre registar e desistir de registar.
  void _prefill(LoadHistoryEntry? last) {
    if (_prefilled) return;
    _prefilled = true;
    final lastInSession = widget.done.isNotEmpty ? widget.done.last : null;
    final load = lastInSession?.load ?? last?.load ?? widget.entry.currentLoad;
    if (load != null) _loadController.text = load.toStringAsFixed(0);
    final reps = int.tryParse(widget.entry.reps);
    if (reps != null) _repsController.text = reps.toString();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(
      loadHistoryProvider(
        (memberId: widget.memberId, exerciseId: widget.entry.exerciseId),
      ),
    );
    final history = historyAsync.valueOrNull ?? const <LoadHistoryEntry>[];
    // O histórico vem do mais recente para o mais antigo.
    final last = history.isNotEmpty ? history.first : null;
    _prefill(last);

    final nextSetNumber = widget.done.isEmpty
        ? 1
        : widget.done.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) +
            1;
    final target = widget.entry.sets;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.exercise?.name ?? widget.entry.exerciseId,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              // O vídeo só existia em "O meu plano". Mas o momento em
              // que alguém precisa de rever a execução é ESTE — a meio
              // do treino, antes da série — e daqui obrigava a sair do
              // treino, ir ao plano, encontrar o exercício e voltar.
              if (widget.exercise?.hasVideo ?? false)
                IconButton(
                  tooltip: 'Ver vídeo demonstrativo',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.play_circle_outline, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ExerciseVideoScreen(exercise: widget.exercise!),
                    ),
                  ),
                ),
              Pill(
                '${widget.done.length}/$target',
                tone: widget.done.length >= target
                    ? PillTone.ok
                    : PillTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Plano: $target × ${widget.entry.reps}'
            '${widget.entry.restSeconds != null ? ' · ${widget.entry.restSeconds}s descanso' : ''}',
            style: const TextStyle(color: AppColors.mute, fontSize: 11),
          ),
          if (last != null) ...[
            const SizedBox(height: 2),
            Text(
              // A referência que faz a progressão acontecer. Ninguém se
              // lembra do peso da semana passada.
              'Da última vez: ${last.load.toStringAsFixed(0)} kg × ${last.reps}',
              style: const TextStyle(color: AppColors.dim, fontSize: 11),
            ),
          ],
          if (widget.entry.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              widget.entry.notes,
              style: const TextStyle(
                  color: AppColors.mute, fontSize: 11, height: 1.4),
            ),
          ],
          if (widget.done.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Cada série confirmada é tocável para corrigir. "Anular a
            // última" só resolve quando o erro foi na última — enganar-se
            // na 2.ª de quatro obrigava a apagar as outras duas e a
            // registá-las outra vez de cabeça.
            for (final set in widget.done)
              InkWell(
                onTap: _busy ? null : () => _editSet(set),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: AppColors.ok),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Série ${set.setNumber}: '
                          '${set.load != null ? '${set.load!.toStringAsFixed(0)} kg × ' : ''}'
                          '${set.reps} reps',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const Icon(Icons.edit_outlined,
                          size: 13, color: AppColors.dim),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _loadController,
                  decoration: const InputDecoration(
                    labelText: 'kg',
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _repsController,
                  decoration: InputDecoration(
                    labelText: 'reps',
                    isDense: true,
                    errorText: _erroReps,
                  ),
                  keyboardType: TextInputType.number,
                  // Some assim que a pessoa começa a corrigir: manter o
                  // erro enquanto ela escreve é ralhar com quem já está
                  // a resolver.
                  onChanged: (_) {
                    if (_erroReps != null) setState(() => _erroReps = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _logSet(nextSetNumber),
                  child: Text('Série $nextSetNumber'),
                ),
              ),
              if (widget.done.isNotEmpty)
                IconButton(
                  tooltip: 'Anular a última série',
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: _busy ? null : _undo,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _logSet(int setNumber) async {
    final reps = int.tryParse(_repsController.text.trim());
    if (reps == null || reps <= 0) {
      setState(() => _erroReps = 'Quantas repetições?');
      return;
    }
    if (_erroReps != null) setState(() => _erroReps = null);
    final loadText = _loadController.text.trim().replaceAll(',', '.');
    // Sem carga é válido: prancha, corrida, peso do corpo.
    final load = loadText.isEmpty ? null : double.tryParse(loadText);

    final performedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (performedBy == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(workoutSessionRepositoryProvider).logSet(
            memberId: widget.memberId,
            sessionId: widget.sessionId,
            exerciseId: widget.entry.exerciseId,
            setNumber: setNumber,
            reps: reps,
            load: load,
            performedBy: performedBy,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível registar a série. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Corrigir ou apagar uma série já confirmada.
  ///
  /// Corrigir mexe também no histórico de cargas (a série sabe que
  /// registo criou) — senão o valor errado ficava para sempre no
  /// gráfico de evolução, que é exatamente onde mais incomoda.
  Future<void> _editSet(SetLog set) async {
    final result = await showDialog<_SetEdit>(
      context: context,
      builder: (_) => _EditSetDialog(set: set),
    );
    if (result == null) return;

    final performedBy = ref.read(currentAppUserProvider).valueOrNull?.uid;
    if (performedBy == null) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(workoutSessionRepositoryProvider);
      if (result.delete) {
        await repository.deleteSet(
          memberId: widget.memberId,
          sessionId: widget.sessionId,
          exerciseId: widget.entry.exerciseId,
          setNumber: set.setNumber,
        );
      } else {
        await repository.updateSet(
          memberId: widget.memberId,
          sessionId: widget.sessionId,
          exerciseId: widget.entry.exerciseId,
          setNumber: set.setNumber,
          reps: result.reps!,
          load: result.load,
          performedBy: performedBy,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(userFacingError(e,
                fallback:
                    'Não foi possível corrigir a série. Tenta outra vez.'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      await ref.read(workoutSessionRepositoryProvider).undoLastSet(
            memberId: widget.memberId,
            sessionId: widget.sessionId,
            exerciseId: widget.entry.exerciseId,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// O resultado do diálogo de correção: valores novos, ou apagar.
class _SetEdit {
  const _SetEdit.update(this.reps, this.load) : delete = false;
  const _SetEdit.remove()
      : reps = null,
        load = null,
        delete = true;

  final int? reps;
  final double? load;
  final bool delete;
}

class _EditSetDialog extends StatefulWidget {
  const _EditSetDialog({required this.set});

  final SetLog set;

  @override
  State<_EditSetDialog> createState() => _EditSetDialogState();
}

class _EditSetDialogState extends State<_EditSetDialog> {
  late final _repsController =
      TextEditingController(text: widget.set.reps.toString());
  late final _loadController = TextEditingController(
    text: widget.set.load?.toStringAsFixed(0) ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _repsController.dispose();
    _loadController.dispose();
    super.dispose();
  }

  void _save() {
    final reps = int.tryParse(_repsController.text.trim());
    if (reps == null || reps <= 0) {
      setState(() => _error = 'Escreve quantas repetições fizeste.');
      return;
    }
    final loadText = _loadController.text.trim().replaceAll(',', '.');
    final load = loadText.isEmpty ? null : double.tryParse(loadText);
    if (loadText.isNotEmpty && load == null) {
      setState(() => _error = 'A carga tem de ser um número.');
      return;
    }
    Navigator.of(context).pop(_SetEdit.update(reps, load));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Série ${widget.set.setNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _loadController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'kg'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _repsController,
                  decoration: const InputDecoration(labelText: 'reps'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppBanner(text: _error!, tone: PillTone.danger),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _SetEdit.remove()),
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          child: const Text('Apagar série'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
