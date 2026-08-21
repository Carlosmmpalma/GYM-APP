import 'package:flutter/material.dart';

/// Fase 11 — avisa antes de sair de um formulário com dados por gravar.
///
/// A app tinha 21 ecrãs com campos de texto e nenhum aviso: preencher a
/// ficha de um membro novo (nome, contactos, data de nascimento, NIF,
/// morada, contacto de emergência), tocar sem querer no "voltar" — ou
/// fazer o gesto de voltar no Android, que é fácil de acionar por
/// engano — e perder tudo, sem uma palavra.
///
/// Envolve o `Scaffold` do ecrã. [hasChanges] é lido no momento em que
/// se tenta sair, por isso pode ser uma função que compara o estado
/// atual com o inicial — não é preciso manter uma flag "sujo" à mão.
///
/// Só pergunta quando há mesmo alterações: um diálogo de confirmação
/// que aparece sempre é ruído, e ruído ensina a carregar em "sair" sem
/// ler.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasChanges,
    required this.child,
    this.message = 'Tens alterações por gravar. Se saíres agora, perdes o que '
        'escreveste.',
  });

  final bool Function() hasChanges;
  final Widget child;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // `canPop: false` intercepta SEMPRE e decide no callback; usar
      // `canPop: !hasChanges()` avaliaria no build, e o valor podia
      // estar desatualizado no instante do gesto.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);

        if (!hasChanges()) {
          navigator.pop(result);
          return;
        }

        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Sair sem gravar?'),
            content: Text(message, style: const TextStyle(height: 1.45)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Continuar a editar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Sair sem gravar'),
              ),
            ],
          ),
        );

        if (shouldLeave == true) navigator.pop(result);
      },
      child: child,
    );
  }
}
