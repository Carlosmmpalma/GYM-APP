import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../screens/force_password_change_screen.dart';
import '../screens/hello_world_screen.dart';
import '../screens/login_screen.dart';

/// Decide qual ecrã mostrar consoante o estado de autenticação
/// (Platform Foundation §9 — Tenant Context como camada da app, não
/// decisão espalhada pelos ecrãs).
///
///   sem sessão              → LoginScreen (UC01)
///   sessão + password temp. → ForcePasswordChangeScreen (UC22)
///   sessão normal            → HelloWorldScreen (placeholder até haver
///                               um ecrã "Início" real — Fase 2+)
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(currentAppUserProvider);

    return appUserAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro de autenticação: $error'),
          ),
        ),
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
          error: (error, stack) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro ao verificar a conta: $error'),
              ),
            ),
          ),
          data: (hasTemporaryPassword) {
            if (hasTemporaryPassword) {
              return ForcePasswordChangeScreen(user: appUser);
            }
            return const HelloWorldScreen();
          },
        );
      },
    );
  }
}
