import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/plan_providers.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../repositories/catalogue_admin_repository.dart';

/// Confirmação para qualquer ação sem retorno.
///
/// Existe para que TODAS as eliminações da app se pareçam umas com as
/// outras: mesmo título em forma de pergunta, mesma explicação do que
/// desaparece, e o botão perigoso sempre à direita e sempre a dizer o
/// que faz — nunca "OK".
///
/// [consequence] é a frase que evita o arrependimento: diz o que se
/// perde, não o que se clica.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String consequence,
  String confirmLabel = 'Eliminar',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(consequence),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

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
    CatalogueKind.exercise => 'o exercício',
    CatalogueKind.series => 'a série de aulas',
    CatalogueKind.staff => 'esta conta',
    CatalogueKind.occurrence => 'esta aula',
  };

  final confirmed = await confirmDestructiveAction(
    context,
    title: 'Eliminar $name?',
    consequence: 'Isto elimina $label de vez. Só é possível se nada '
        'depender dele — planos, aulas, subscrições. Se alguma coisa '
        'depender, a app diz-te o quê e não elimina nada.',
  );
  if (!confirmed || !context.mounted) return false;

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

/// Menu `⋮` de fim de linha com a ação de eliminar.
///
/// Um caixote do lixo solto numa lista é um toque acidental à espera de
/// acontecer — sobretudo em telemóvel, onde o dedo tapa a linha toda.
/// Um menu exige dois gestos deliberados antes de sequer chegar à
/// confirmação, e deixa espaço para as ações que vierem a seguir sem
/// voltar a mexer no layout.
class CatalogueRowMenu extends ConsumerWidget {
  const CatalogueRowMenu({
    super.key,
    required this.kind,
    required this.id,
    required this.name,
    this.onDeleted,
  });

  final CatalogueKind kind;
  final String id;
  final String name;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Mais opções',
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline,
                  size: 20, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              // Sem `Flexible`, um rótulo longo rebenta a linha do
              // menu em ecrãs estreitos — e o menu é estreito por
              // natureza.
              Flexible(
                child: Text('Eliminar',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ),
      ],
      onSelected: (_) async {
        final deleted = await confirmAndDeleteCatalogueEntry(
          context,
          ref,
          kind: kind,
          id: id,
          name: name,
        );
        if (deleted) onDeleted?.call();
      },
    );
  }
}
