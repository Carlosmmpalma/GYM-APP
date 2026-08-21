import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/design_system.dart';

/// UC01 (fechado) — "conta bloqueada no próximo login" quando a
/// mensalidade do mês atual está `overdue` (ver
/// `isBlockedForOverduePaymentProvider`). Mostrado pelo `AuthGate` em
/// vez do `HomeScreen`, mesma cópia do mockup ("Login — exceções"):
/// título "Conta inativa", corpo "Mensalidade em atraso. Contacta o
/// estúdio para reativar o acesso."
///
/// Sem fluxo de auto-resolução — a decisão é sempre do Gestor
/// (`ManagePaymentsScreen`), nunca do próprio Aluno; o único botão aqui
/// é "Sair", para não deixar a pessoa presa numa sessão sem nada para
/// fazer.
class AccountBlockedScreen extends ConsumerWidget {
  const AccountBlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta inativa'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // O mockup mostra isto como o banner de aviso, com
                // título e corpo dentro do mesmo bloco — não como um
                // ícone gigante centrado.
                const AppBanner(
                  icon: Icons.lock_outline,
                  title: 'Conta inativa',
                  text: 'Mensalidade em atraso. Contacta o estúdio para '
                      'reativar o acesso.',
                ),
                const SizedBox(height: 20),
                // Sem passos que o Aluno possa dar sozinho, o mínimo é
                // dizer-lhe o que acontece a seguir — senão o ecrã é só
                // uma porta fechada.
                const Text(
                  'Assim que o estúdio registar o pagamento, o acesso volta '
                  'a abrir sozinho no próximo login.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.mute,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
