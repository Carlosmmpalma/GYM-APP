import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../repositories/auth_repository.dart';

/// UC01 — login por nº de sócio + password (não email) para o Aluno,
/// tal como o mockup (nxt-studio-screens.html) mostra. Staff faz login
/// com o email real (ver assunção documentada em
/// firebase/functions/src/createStaff.ts) — desde a Fase 3, o MESMO
/// campo/ecrã aceita as duas coisas (ver
/// `firebase_auth_repository.dart`): quem digita um email entra como
/// staff, quem digita um número entra como Aluno. Continua a não haver
/// um ecrã de login separado para staff — deixou de ser necessário.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _memberNumberController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _memberNumberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final tenantId = ref.read(tenantAppConfigProvider).tenantId;
      final useCase = ref.read(signInWithMemberNumberUseCaseProvider);
      await useCase(
        tenantId: tenantId,
        memberNumber: _memberNumberController.text,
        password: _passwordController.text,
      );
      // Não navegamos manualmente: currentAppUserProvider vai emitir o
      // novo estado e o AuthGate troca de ecrã sozinho.
    } on InvalidCredentialsException catch (e) {
      setState(() => _errorMessage = e.toString());
    } catch (e) {
      setState(() =>
          _errorMessage = 'Não foi possível iniciar sessão. Tenta novamente.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Text(
                    'Treina ao teu ritmo',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _memberNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Nº de sócio ou email',
                    ),
                    // Não restrito a números: staff entra com o email
                    // real neste mesmo campo (Fase 3) — ver
                    // firebase_auth_repository.dart.
                    keyboardType: TextInputType.text,
                    autofillHints: const [AutofillHints.username],
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Introduz o teu nº de sócio ou email'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Introduz a tua password'
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
                        : const Text('Entrar'),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  // UC01-A — recuperação de password fica para quando o
                  // fornecedor de notificações (SMS/email) for decidido.
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
