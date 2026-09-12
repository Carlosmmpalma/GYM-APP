import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/privacy_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/consent.dart';
import 'design_system.dart';
import 'privacy_policy_link.dart';

/// Fase 11 (RGPD) — a secção "Os meus dados" do perfil do Aluno.
///
/// Três direitos, num sítio onde a pessoa os encontra sozinha (artigo
/// 12.º: a informação tem de ser "de forma concisa, transparente,
/// inteligível e de fácil acesso"):
///
/// - **Ver e mudar** o consentimento de dados de saúde. O artigo 7.º,
///   n.º 3 exige que retirar seja tão fácil como dar — daí ser o mesmo
///   interruptor, no mesmo sítio, e não um pedido por email.
/// - **Exportar** (artigos 15.º/20.º).
/// - **Apagar** — aqui só explicado, porque a ação é do estúdio; ver
///   `deleteMemberData.ts` sobre porquê.
class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key});

  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  bool _busy = false;

  Future<void> _setHealthConsent(bool granted) async {
    setState(() => _busy = true);
    try {
      await ref.read(privacyRepositoryProvider).recordConsent(
            privacyPolicyVersion: kPrivacyPolicyVersion,
            healthDataGranted: granted,
          );
      ref.invalidate(myConsentProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Avaliações físicas autorizadas.'
                : 'Autorização retirada. As avaliações já feitas continuam '
                    'guardadas — pede ao estúdio para as apagar se quiseres.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível mudar a autorização.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await ref.read(privacyRepositoryProvider).exportMemberData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Os teus dados'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              // Copiar em vez de descarregar um ficheiro: guardar no
              // disco depende da plataforma (e na web um download a
              // partir da app precisaria de mais do que isto). Copiar
              // funciona em todas e chega para colar num email ou num
              // documento — que é o que o titular normalmente quer.
              onPressed: () async {
                // O messenger é capturado ANTES do await: depois dele o
                // `context` do ecrã pode já não estar montado, e é o
                // `dialogContext` que a análise consegue verificar.
                final messenger = ScaffoldMessenger.of(dialogContext);
                final navigator = Navigator.of(dialogContext);
                await Clipboard.setData(ClipboardData(text: pretty));
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Copiado.')),
                );
              },
              child: const Text('Copiar tudo'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível exportar os dados.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final consentAsync = ref.watch(myConsentProvider);
    final consent = consentAsync.valueOrNull;
    if (consent == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionLabel('Os meus dados'),
        const PrivacyPolicyLink(centered: false),
        const SizedBox(height: 8),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: consent.healthDataGranted,
                onChanged: _busy ? null : _setHealthConsent,
                title: const Text('Avaliações físicas'),
                subtitle: Text(
                  consent.healthDataGranted
                      ? 'O instrutor pode registar peso, medidas e outros '
                          'dados de saúde.'
                      : 'Não autorizado. Continuas a marcar treinos '
                          'normalmente.',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              const Divider(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined, size: 20),
                title: const Text('Exportar os meus dados'),
                subtitle: const Text(
                  'Uma cópia de tudo o que o estúdio guarda sobre ti.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: _busy ? null : _export,
              ),
              const Divider(height: 20),
              const Text(
                'Para apagares a tua conta e os teus dados, fala com o '
                'estúdio. É pedido em pessoa para confirmarmos que és mesmo '
                'tu antes de apagar algo que não volta atrás. Os registos '
                'de pagamento ficam sem o teu nome, porque a lei obriga a '
                'guardá-los.',
                style: TextStyle(
                  color: AppColors.dim,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
