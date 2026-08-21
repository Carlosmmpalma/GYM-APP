import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/payment_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../application/providers/privacy_providers.dart';
import '../screens/account_blocked_screen.dart';
import '../screens/consent_screen.dart';
import '../screens/force_password_change_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
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
    final appUserAsync = ref.watch(currentAppUserProvider);

    return appUserAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _GateError(
        error: error,
        message: 'Não foi possível confirmar a tua sessão.',
        onRetry: () => ref.invalidate(currentAppUserProvider),
      ),
      data: (appUser) {
        if (appUser == null) {
          return const LoginScreen();
        }

        final hasTemporaryPasswordAsync =
            ref.watch(hasTemporaryPasswordProvider);
        return hasTemporaryPasswordAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => _GateError(
            error: error,
            message: 'Não foi possível verificar o estado da tua conta.',
            onRetry: () => ref.invalidate(hasTemporaryPasswordProvider),
          ),
          data: (hasTemporaryPassword) {
            if (hasTemporaryPassword) {
              return ForcePasswordChangeScreen(user: appUser);
            }

            // RGPD (Fase 11) — antes de qualquer ecrã da app, o
            // consentimento da versão em vigor tem de estar registado.
            // Fica DEPOIS da troca de password temporária (não faz
            // sentido pedir consentimento a quem ainda não controla a
            // própria conta) e ANTES do bloqueio por mensalidade: quem
            // está em atraso continua a ter direito a decidir sobre os
            // seus dados.
            final needsConsentAsync = ref.watch(needsConsentProvider);
            if (needsConsentAsync.valueOrNull == true) {
              return const ConsentScreen();
            }

            final blockedAsync = ref.watch(isBlockedForOverduePaymentProvider);
            return blockedAsync.when(
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => _GateError(
                error: error,
                message: 'Não foi possível verificar a tua mensalidade.',
                onRetry: () =>
                    ref.invalidate(isBlockedForOverduePaymentProvider),
              ),
              data: (blocked) =>
                  blocked ? const AccountBlockedScreen() : const HomeScreen(),
            );
          },
        );
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
