import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/gate_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../screens/account_blocked_screen.dart';
import '../screens/consent_screen.dart';
import '../screens/force_password_change_screen.dart';
import '../screens/home_screen.dart';
import '../screens/studio_showcase_screen.dart';
import 'design_system.dart';

/// Decide qual ecrã mostrar consoante o estado de autenticação
/// (Platform Foundation §9 — Tenant Context como camada da app, não
/// decisão espalhada pelos ecrãs).
///
///   sem sessão               → LoginScreen (UC01)
///   sessão + password temp.  → ForcePasswordChangeScreen (UC22)
///   sessão + mensalidade em
///     atraso (só Aluno puro) → AccountBlockedScreen (Fase 9, UC01 fechado)
///   sessão normal             → HomeScreen (Marcar treino / Minhas
///                                marcações — Fase 2; o diagnóstico da
///                                Fase 0 continua acessível a partir daí)
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // UMA espera, não três.
    //
    // Isto encadeava as verificações: password temporária, depois
    // consentimento, depois mensalidade — cada uma só arrancava quando a
    // anterior respondesse, e cada uma com o seu ecrã de espera. Eram
    // três idas ao servidor em fila entre autenticar e ver a app, todas
    // as vezes, logo a seguir a o utilizador já ter esperado pela app
    // inteira a descarregar.
    //
    // Nenhuma dependia do resultado das outras — estavam em série só
    // porque estavam escritas umas dentro das outras. Ver
    // `gateScreenProvider`, que as resolve ao mesmo tempo.
    final screenAsync = ref.watch(gateScreenProvider);
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;

    return screenAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _GateError(
        error: error,
        message: 'Não foi possível confirmar o estado da tua conta.',
        onRetry: () => ref.invalidate(gateScreenProvider),
      ),
      data: (screen) => switch (screen) {
        // Sem sessão, a app abre na VITRINA e não no formulário de
        // login — que fica a um toque, dentro dela. Ver
        // `StudioShowcaseScreen`: quem instala a app antes de se
        // inscrever tinha uma porta fechada e sem placa.
        //
        // Não custa um toque a quem já é membro: a sessão do Firebase
        // sobrevive a fechar a app, por isso isto só aparece no
        // primeiro arranque e depois de sair.
        GateScreen.login => const StudioShowcaseScreen(),
        // O `appUser` vem do mesmo stream que o provider já leu; se
        // estiver `null` aqui, a sessão caiu entretanto e o login é a
        // resposta certa.
        GateScreen.forcePasswordChange => appUser == null
            ? const StudioShowcaseScreen()
            : ForcePasswordChangeScreen(user: appUser),
        GateScreen.consent => const ConsentScreen(),
        GateScreen.blocked => const AccountBlockedScreen(),
        GateScreen.home => const HomeScreen(),
      },
    );
  }
}

/// Erro no próprio AuthGate — o pior sítio para uma exceção crua: é o
/// primeiro ecrã depois do arranque e não há nada por trás dele.
/// Além do [ErrorState] normal, dá sempre uma saída ("Sair"): sem isso,
/// uma falha a ler o perfil deixava a app num ecrã sem nenhuma ação
/// possível a não ser fechá-la.
class _GateError extends ConsumerWidget {
  const _GateError({
    required this.error,
    required this.message,
    required this.onRetry,
  });

  final Object error;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ErrorState(
              error: error,
              message: message,
              onRetry: onRetry,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sair'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
