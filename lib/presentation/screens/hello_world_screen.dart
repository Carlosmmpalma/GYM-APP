import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/firebase_providers.dart';
import '../../core/config/environment.dart';
import '../../domain/entities/ping_result.dart';

/// Ecrã de diagnóstico da Fase 0.
///
/// Critério "Done" do guia-desenvolvimento.md: "app Flutter arranca, liga
/// ao emulador local, e um hello world lê/escreve um documento de teste no
/// Firestore emulado". Este ecrã existe só para provar isso — não faz
/// parte de nenhum use case de negócio e deve ser removido/substituído
/// quando a Fase 1 tiver um ecrã de login real.
class HelloWorldScreen extends ConsumerStatefulWidget {
  const HelloWorldScreen({super.key});

  @override
  ConsumerState<HelloWorldScreen> createState() => _HelloWorldScreenState();
}

class _HelloWorldScreenState extends ConsumerState<HelloWorldScreen> {
  PingResult? _lastResult;
  String? _error;
  bool _isLoading = false;

  Future<void> _writeAndRead() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final useCase = ref.read(pingFirestoreUseCaseProvider);
      await useCase('hello from ${DateTime.now().toIso8601String()}');
      final repository = ref.read(pingRepositoryProvider);
      final result = await repository.readLastPing();
      setState(() => _lastResult = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(environmentConfigProvider).environment;
    return Scaffold(
      appBar: AppBar(title: Text('Gym SaaS — Fase 0 (${env.label})')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                env == Environment.development
                    ? 'A ligar ao Firebase Emulator Suite local.'
                    : 'A ligar ao Firebase Project real deste ambiente.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _writeAndRead,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Escrever + ler no Firestore'),
              ),
              const SizedBox(height: 24),
              if (_lastResult != null)
                Text(
                  'Último ping: "${_lastResult!.message}" '
                  'em ${_lastResult!.recordedAt}',
                  textAlign: TextAlign.center,
                ),
              if (_error != null)
                Text(
                  'Erro: $_error',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
