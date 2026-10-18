import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/app_user.dart';

/// Terminar sessão, no canto da AppBar, para qualquer papel.
///
/// Até aqui o `signOut` só existia em dois sítios de emergência — o
/// ecrã de conta bloqueada e o estado de erro do `AuthGate`. Em uso
/// normal não havia saída nenhuma: nem Gestor, nem Instrutor, nem
/// Aluno. Quem entrasse num telemóvel emprestado ficava lá.
///
/// É um widget partilhado e não três botões iguais porque são três
/// shells diferentes em `HomeScreen`, e a saída tem de estar sempre no
/// mesmo sítio — último da direita, em todos.
///
/// ## Porque pergunta antes
///
/// Sair é barato para quem tem email e password à mão. Para um ALUNO
/// não é: as contas são criadas pelo estúdio, o login é por número de
/// sócio, e **não há recuperação self-service** — o próprio ecrã de
/// login diz para contactar o Gestor. Um toque acidental aqui deixa a
/// pessoa de fora até alguém do estúdio lhe repor a password.
///
/// Daí o aviso ser diferente consoante quem está a sair. Avisos iguais
/// para situações desiguais são ruído; este diz à pessoa o que lhe vai
/// custar voltar.
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `watch` e não um `read` dentro do onPressed: um `read` de um
    // StreamProvider que ninguém observa devolve `AsyncLoading`, e o
    // aviso saía sempre na versão genérica. Na app funcionava por
    // acaso — o `HomeScreen` observa o mesmo provider — e um widget
    // que depende de outro estar subscrito parte no dia em que for
    // usado noutro sítio.
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;

    return IconButton(
      tooltip: 'Terminar sessão',
      icon: const Icon(Icons.logout_outlined),
      onPressed: () => _confirmar(context, ref, appUser),
    );
  }

  Future<void> _confirmar(
    BuildContext context,
    WidgetRef ref,
    AppUser? appUser,
  ) async {
    // Staff entra por email e repõe a password sozinho; o aluno não.
    final precisaDoEstudio = appUser != null &&
        appUser.isMember &&
        !appUser.isManager &&
        !appUser.isInstructor;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Terminar sessão?'),
        content: Text(
          precisaDoEstudio
              ? 'Para voltar a entrar precisas do teu número de sócio e da '
                  'password. Se não a tiveres à mão, só o estúdio a pode '
                  'repor — não há recuperação automática para alunos.'
              : 'Para voltar a entrar precisas do teu email e password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ficar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terminar sessão'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    // Sem navegação a seguir: o `AuthGate` observa o estado de
    // autenticação e troca para o login sozinho. Empurrar um ecrã
    // daqui dava dois caminhos para o mesmo sítio, e eles acabariam por
    // divergir.
    await ref.read(authRepositoryProvider).signOut();
  }
}
