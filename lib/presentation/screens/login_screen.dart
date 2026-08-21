import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../repositories/auth_repository.dart';
import '../widgets/design_system.dart';

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

  // UC01-A — só é genuinamente self-service para staff (email real): o
  // Firebase Auth envia o link de reset diretamente. Para nº de sócio
  // (email sintético, nunca entregável), não fingimos um mecanismo que
  // não existe — a mensagem diz para contactar o Gestor. Fica
  // documentado (README) que a parte de membros continua por decidir
  // (fornecedor SMS/email).
  Future<void> _forgotPassword() async {
    final identifier = _memberNumberController.text.trim();
    if (!identifier.contains('@')) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Recuperar password'),
          content: const Text(
            'A recuperação de password para alunos (por nº de sócio) ainda '
            'não está disponível de forma self-service — contacta o Gestor '
            'do ginásio para repor a tua password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(identifier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Email de recuperação enviado para $identifier.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar o email: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantConfig = ref.watch(tenantAppConfigProvider);
    final studioName = tenantConfig.displayName;
    final logoAsset = tenantConfig.logoAsset;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // O mockup abre com a marca em cima e o claim em
                      // Oswald itálico maiúsculas, não com um título
                      // Material centrado. Usa o logótipo do estúdio
                      // quando a build o traz; sem
                      // ele, o nome em texto. Nunca o `tenantId` — é um
                      // ID, não uma marca.
                      if (logoAsset != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Image.asset(
                            logoAsset,
                            height: 72,
                            // Se o asset faltar numa build, o ecrã de
                            // login não pode ser uma cruz vermelha: cai
                            // no nome em texto.
                            errorBuilder: (context, error, stack) =>
                                _StudioNameFallback(name: studioName),
                          ),
                        )
                      else
                        _StudioNameFallback(name: studioName),
                      const SizedBox(height: 26),
                      Text(
                        'TREINA AO\nTEU RITMO',
                        style: AppTheme.display(fontSize: 30, height: 1.15),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Entra com o teu número de sócio para aceder ao '
                        'estúdio.',
                        style: TextStyle(
                          color: AppColors.mute,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
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
                        decoration:
                            const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Introduz a tua password'
                            : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      // O erro vem ANTES do botão, como no mockup ("Login —
                      // exceções"): quem falha o login olha para o botão que
                      // acabou de premir, não para o fundo do ecrã. Mensagem
                      // genérica de propósito — nunca diz qual dos dois
                      // campos falhou.
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        AppBanner(text: _errorMessage!, tone: PillTone.danger),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Entrar'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _isSubmitting ? null : _forgotPassword,
                        child: const Text('Esqueci-me da password'),
                      ),
                      // Esta linha existe para responder à pergunta que o
                      // ecrã de login de uma app fechada levanta sempre — e
                      // que não tinha resposta em lado nenhum: não há
                      // registo, as contas são criadas pelo estúdio.
                      const Text(
                        'Sem conta? Só o estúdio pode criar o teu acesso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioNameFallback extends StatelessWidget {
  const _StudioNameFallback({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    if (name == null) return const IconBox(Icons.bolt);
    return Row(
      children: [
        const IconBox(Icons.bolt),
        const SizedBox(width: 10),
        // `Expanded` + ellipsis: um nome comprido de estúdio
        // transbordava a linha (apanhado pelos testes de widget, não à
        // vista).
        Expanded(
          child: Text(
            name!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display(fontSize: 13, color: AppColors.mute),
          ),
        ),
      ],
    );
  }
}
