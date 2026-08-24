import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/firebase_error_text.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../domain/entities/app_user.dart';
import '../widgets/design_system.dart';

/// UC22 — "password inicial é temporária... obriga o utilizador a
/// definir uma password nova logo no primeiro login". O AuthGate só
/// mostra este ecrã quando `hasTemporaryPasswordProvider` é true —
/// nunca é uma opção, é obrigatório (sem botão de "saltar"/"agora não").
class ForcePasswordChangeScreen extends ConsumerStatefulWidget {
  const ForcePasswordChangeScreen({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState
    extends ConsumerState<ForcePasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final useCase = ref.read(completeTemporaryPasswordChangeUseCaseProvider);
      await useCase(
          user: widget.user, newPassword: _newPasswordController.text);
      // hasTemporaryPasswordProvider (autoDispose) é recalculado e o
      // AuthGate avança sozinho assim que a flag ficar false.
    } catch (e) {
      setState(() => _errorMessage = userFacingError(e,
          fallback:
              'Não foi possível definir a nova password. Tenta outra vez.'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Define a tua nova password'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'A tua password atual é temporária. Define uma nova '
                    'antes de continuar.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _newPasswordController,
                    decoration:
                        const InputDecoration(labelText: 'Nova password'),
                    obscureText: true,
                    validator: (value) => (value == null || value.length < 8)
                        ? 'Mínimo de 8 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration:
                        const InputDecoration(labelText: 'Confirmar password'),
                    obscureText: true,
                    validator: (value) => value != _newPasswordController.text
                        ? 'As passwords não coincidem'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar e continuar'),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    AppBanner(text: _errorMessage!, tone: PillTone.danger),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
