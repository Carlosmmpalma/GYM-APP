import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../repositories/catalogue_admin_repository.dart';

/// Confirmar e eliminar uma entrada do catálogo (serviço, plano,
/// modalidade).
///
/// Um único caminho para os três ecrãs, porque a parte difícil não é o
/// botão — é o que acontece quando a eliminação é recusada. O servidor
/// devolve a lista do que depende da entrada; mostrá-la é o que permite
/// ao Gestor decidir sozinho entre eliminar e desativar, em vez de
/// ficar com um "não foi possível" e o telefone na mão.
///
/// Devolve `true` quando eliminou.
Future<bool> confirmAndDeleteCatalogueEntry(
  BuildContext context,
  WidgetRef ref, {
  required CatalogueKind kind,
  required String id,
  required String name,
}) async {
  final label = switch (kind) {
    CatalogueKind.service => 'o serviço',
    CatalogueKind.plan => 'o plano',
    CatalogueKind.modality => 'a modalidade',
  };

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Eliminar $name?'),
      content: Text(
        'Isto elimina $label de vez. Só é possível se nada depender '
        'dele — planos, aulas, subscrições. Se alguma coisa depender, '
        'a app diz-te o quê e não elimina nada.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await ref.read(catalogueAdminRepositoryProvider).delete(kind: kind, id: id);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" eliminado.')),
    );
    return true;
  } on CatalogueEntryInUseException catch (e) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('"$name" está a ser usado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Não dá para eliminar porque isto depende dele:'),
            const SizedBox(height: 12),
            for (final blocker in e.blockers)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $blocker'),
              ),
            const SizedBox(height: 12),
            const Text(
              'Desativar tira-o das listas de escolha e mantém o '
              'histórico intacto — é quase sempre o que se quer.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return false;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(userFacingError(e,
            fallback: 'Não foi possível eliminar. Tenta outra vez.')),
      ),
    );
    return false;
  }
}
