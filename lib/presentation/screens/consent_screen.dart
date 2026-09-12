import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/privacy_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/consent.dart';
import '../widgets/design_system.dart';
import '../widgets/privacy_policy_link.dart';

/// Fase 11 (RGPD) — o ecrã que recolhe o consentimento, mostrado pelo
/// `AuthGate` antes de qualquer outro assim que falta o registo da
/// versão em vigor.
///
/// A decisão de desenho que importa: **os dados de saúde são um
/// interruptor separado e desligado por omissão**. O artigo 7.º, n.º 4
/// diz que o consentimento não é livre se for condição para um serviço
/// que dele não depende — marcar aulas não depende de autorizar
/// avaliações físicas. Por isso "Continuar" funciona com o interruptor
/// desligado, e quem recusa usa a app inteira menos as avaliações.
///
/// Não há botão de "recusar tudo": a aceitação do aviso de privacidade
/// não é consentimento (a base legal do tratamento corrente é a
/// execução do contrato com o ginásio) — é o cumprimento do dever de
/// informar. Quem não quer que o ginásio trate os seus dados de todo
/// cancela a inscrição, e isso é uma conversa no estúdio, não um botão.
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _healthDataGranted = false;
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(privacyRepositoryProvider).recordConsent(
            privacyPolicyVersion: kPrivacyPolicyVersion,
            healthDataGranted: _healthDataGranted,
          );
      // O gate lê o perfil do membro; sem isto ficaria a mostrar este
      // mesmo ecrã depois de gravar.
      ref.invalidate(needsConsentProvider);
      ref.invalidate(myConsentProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível registar a tua escolha. Tenta '
            'outra vez.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              shrinkWrap: true,
              children: [
                Text('OS TEUS DADOS', style: AppTheme.display(fontSize: 24)),
                const SizedBox(height: 8),
                const SlashDivider(),
                const SizedBox(height: 18),
                const Text(
                  'Antes de continuares, precisas de saber o que o estúdio '
                  'guarda sobre ti e para quê.',
                  style: TextStyle(
                    color: AppColors.mute,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                const _PolicySummary(),
                // A política a sério, não o resumo acima. O
                // consentimento para dados de saúde tem de ser
                // informado (artigo 9.º), e isso quer dizer poder ler
                // o documento ANTES de carregar em aceitar.
                const PrivacyPolicyLink(),
                const SizedBox(height: 20),
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _healthDataGranted,
                        onChanged: _submitting
                            ? null
                            : (value) =>
                                setState(() => _healthDataGranted = value),
                        title: const Text('Autorizo avaliações físicas'),
                        subtitle: const Text(
                          'Peso, massa gorda, pressão arterial e outras '
                          'medidas que o instrutor registe.',
                          style: TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'É opcional. Sem isto continuas a marcar aulas e '
                        'treino livre normalmente — só não podem ser feitas '
                        'avaliações. Podes mudar de ideias a qualquer '
                        'momento no teu perfil.',
                        style: TextStyle(
                          color: AppColors.dim,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  AppBanner(text: _errorMessage!, tone: PillTone.danger),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continuar'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ao continuar confirmas que leste esta informação.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.dim, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// O aviso de privacidade em si.
///
/// Está aqui em código, e não num documento remoto, por uma razão
/// prática: é a versão que ESTA build mostrou, e é a que
/// `kPrivacyPolicyVersion` identifica no registo de consentimento. Um
/// texto que muda no servidor sem mudar a versão tornaria o registo
/// inútil como prova.
///
/// O texto abaixo descreve fielmente o que o código faz. Não substitui
/// uma política de privacidade revista por quem perceba do assunto —
/// ver o checklist de lançamento no README.
class _PolicySummary extends StatelessWidget {
  const _PolicySummary();

  static const _sections = [
    (
      Icons.badge_outlined,
      'Quem trata os teus dados',
      'O estúdio onde estás inscrito. É ele quem decide o que é '
          'recolhido e para quê.',
    ),
    (
      Icons.folder_outlined,
      'O que é guardado',
      'Nome, número de sócio, contactos, data de nascimento, NIF, morada '
          'e contacto de emergência. As tuas marcações e presenças. As '
          'mensalidades. E, se autorizares, as avaliações físicas e o '
          'histórico de cargas do teu plano de treino.',
    ),
    (
      Icons.task_alt_outlined,
      'Para quê',
      'Gerir a tua inscrição, deixar-te marcar treinos, controlar o '
          'limite semanal do teu plano e acompanhar a tua evolução.',
    ),
    (
      Icons.visibility_outlined,
      'Quem vê',
      'O Gestor do estúdio e os instrutores. Mais ninguém — nenhum outro '
          'aluno vê os teus dados, e nada é partilhado com terceiros para '
          'publicidade.',
    ),
    (
      Icons.download_outlined,
      'Os teus direitos',
      'Podes pedir uma cópia de tudo o que temos sobre ti, corrigir o que '
          'estiver errado, ou pedir que seja apagado. A exportação está no '
          'teu perfil; o apagamento pede-se ao estúdio, que confirma a tua '
          'identidade antes de o fazer.',
    ),
    (
      Icons.receipt_long_outlined,
      'O que fica mesmo depois de apagar',
      'Os registos de pagamento, sem o teu nome associado: a lei obriga o '
          'estúdio a guardar a contabilidade durante 10 anos.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, title, body) in _sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: AppColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: const TextStyle(
                            color: AppColors.mute,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
