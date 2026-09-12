import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/training_providers.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../domain/entities/exercise_category.dart';
import '../../repositories/catalogue_admin_repository.dart';
import '../widgets/catalogue_delete.dart';
import '../widgets/design_system.dart';

/// Como o estúdio arruma a sua biblioteca de exercícios.
///
/// A lista estava escrita no código (`Pernas`, `Costas`, `Peito`,
/// `Ombros`, `Braços`, `Core`, `Full body`, `Hyrox`) e qualquer estúdio
/// que quisesse "Mobilidade" ou "Aquecimento" tinha de pedir a um
/// programador. Mesmo padrão de Serviços e Modalidades, que nunca
/// tiveram esse problema.
class ManageExerciseCategoriesScreen extends ConsumerWidget {
  const ManageExerciseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(exerciseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias de exercícios')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context, ref),
        tooltip: 'Nova categoria',
        child: const Icon(Icons.add),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorState(error: error),
        data: (categories) {
          if (categories.isEmpty) {
            return _EmptyView(onCreate: () => _create(context, ref));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                child: ListTile(
                  title: Text(category.name),
                  subtitle: Text(category.active ? 'Ativa' : 'Inativa'),
                  onTap: () => _rename(context, ref, category),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: category.active,
                        onChanged: (value) => _setActive(
                          context,
                          ref,
                          category,
                          value,
                        ),
                      ),
                      CatalogueRowMenu(
                        kind: CatalogueKind.exerciseCategory,
                        id: category.id,
                        name: category.name,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, title: 'Nova categoria');
    if (name == null || !context.mounted) return;

    try {
      await ref
          .read(exerciseCategoryRepositoryProvider)
          .createCategory(name: name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(e,
              fallback: 'Não foi possível criar a categoria.')),
        ),
      );
    }
  }

  /// Renomear arrasta os exercícios que usam esta categoria.
  ///
  /// Eles guardam o texto, não uma referência (ver
  /// `exercise_category.dart`), por isso o número que aparece a
  /// confirmar não é decoração — é quantos documentos foram tocados.
  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    ExerciseCategory category,
  ) async {
    final name = await _askName(
      context,
      title: 'Mudar o nome',
      initial: category.name,
    );
    if (name == null || name == category.name || !context.mounted) return;

    try {
      final updated = await ref
          .read(exerciseCategoryRepositoryProvider)
          .rename(categoryId: category.id, newName: name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updated == 0
              ? 'Categoria renomeada.'
              : updated == 1
                  ? 'Categoria renomeada — 1 exercício atualizado.'
                  : 'Categoria renomeada — $updated exercícios atualizados.'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              userFacingError(e, fallback: 'Não foi possível mudar o nome.')),
        ),
      );
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    ExerciseCategory category,
    bool active,
  ) async {
    try {
      await ref.read(exerciseCategoryRepositoryProvider).setCategoryActive(
            categoryId: category.id,
            active: active,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(userFacingError(e, fallback: 'Não foi possível guardar.')),
        ),
      );
    }
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(title: title, initial: initial),
    );
  }
}

/// O estado vazio faz duas coisas, e a segunda é a que importa.
///
/// Um estúdio que já tenha a biblioteca montada tem categorias em uso
/// sem nenhum documento a defini-las — são o texto que ficou nos
/// exercícios de quando a lista estava no código. Perdê-las e obrigar a
/// escrevê-las à mão seria trabalho inventado.
class _EmptyView extends ConsumerStatefulWidget {
  const _EmptyView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  ConsumerState<_EmptyView> createState() => _EmptyViewState();
}

class _EmptyViewState extends ConsumerState<_EmptyView> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final inUseAsync = ref.watch(exerciseCategoryNamesInUseProvider);
    final inUse = inUseAsync.valueOrNull ?? const <String>{};

    // `Center > SingleChildScrollView > Column(min)` é o mesmo que o
    // [EmptyState] partilhado faz, e é o que faltava aqui: este estado
    // vazio tem ícone, título, parágrafo, chips e dois botões, e não
    // cabia num iPhone SE nem com o tamanho de letra normal (32 px a
    // mais) — quanto mais com o texto a 2.0×, onde faltavam 403 px.
    // Sem rolamento, o botão "Criar uma de raiz" ficava fora do ecrã:
    // o ecrã que existe para resolver o vazio não tinha como o
    // resolver.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sell_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Categorias de exercícios',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'É como a biblioteca fica arrumada: Pernas, Costas, '
              'Mobilidade, Hyrox — o que fizer sentido para este estúdio. '
              'Aparecem ao criar um exercício e nos filtros da biblioteca.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (inUse.isNotEmpty) ...[
              Text(
                inUse.length == 1
                    ? 'A biblioteca já usa 1 categoria que ainda não está '
                        'definida aqui.'
                    : 'A biblioteca já usa ${inUse.length} categorias que '
                        'ainda não estão definidas aqui.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [for (final name in inUse) Chip(label: Text(name))],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _importing ? null : () => _import(inUse),
                child: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Importar as que já estão em uso'),
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: widget.onCreate,
              child: const Text('Criar uma de raiz'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(Set<String> names) async {
    setState(() => _importing = true);
    try {
      final repository = ref.read(exerciseCategoryRepositoryProvider);
      for (final name in names) {
        await repository.createCategory(name: name);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(userFacingError(e, fallback: 'Não foi possível importar.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nome',
          hintText: 'Pernas, Mobilidade, Hyrox…',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
