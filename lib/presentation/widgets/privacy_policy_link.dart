import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../screens/privacy_policy_screen.dart';

/// Abre um URL externo, dizendo-o quando não consegue.
///
/// Sem `canLaunchUrl` antes: no Android 11+ ele responde `false` para
/// esquemas que a app não declarou consultar, e o resultado era um botão
/// que não fazia nada nem explicava porquê. Tentar e tratar a falha é
/// mais honesto do que esconder o botão.
Future<void> abrirLigacaoExterna(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var aberto = false;
  if (uri != null) {
    try {
      aberto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      aberto = false;
    }
  }
  if (aberto || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Não foi possível abrir esta ligação.')),
  );
}

/// Um campo por preencher esconde-se, em vez de desenhar um espaço em
/// branco ou um botão que não abre nada. Quem avisa que falta é o ecrã
/// de gestão, não o utilizador.
bool temValorReal(String? valor) => valor != null && valor.trim().isNotEmpty;

/// A ligação para a política de privacidade.
///
/// Aparece em quatro sítios, e por quatro razões diferentes:
///
/// - **No ecrã de consentimento**, porque a app trata dados de saúde
///   (artigo 9.º do RGPD) e o consentimento tem de ser *informado*: quem
///   consente tem de conseguir ler aquilo a que está a consentir, antes
///   de o fazer. O resumo desse ecrã descreve fielmente o que o código
///   faz, mas não é a política — é isto.
/// - **No login**, porque é onde quem revê a app na App Store a procura,
///   e quem hesita antes de entrar não devia ter de voltar atrás.
/// - **Em "Os meus dados"**, para quem quiser reler depois.
/// - **Na vitrina**, para quem ainda nem conta tem.
///
/// Abre o ecrã da app, e não um endereço: a política vive em código,
/// versionada, porque é a versão mostrada que o registo de
/// consentimento identifica — ver [PrivacyPolicyScreen]. Antes disto a
/// ligação dependia de alguém ter publicado o documento noutro sítio e
/// colado o endereço, e até lá não havia política nenhuma para ler.
class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key, this.label, this.centered = true});

  final String? label;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final botao = TextButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()),
      ),
      icon: const Icon(Icons.shield_outlined, size: 14, color: AppColors.mute),
      label: Text(
        label ?? 'Ler a política de privacidade',
        style: const TextStyle(fontSize: 12, color: AppColors.mute),
      ),
    );
    return centered
        ? Center(child: botao)
        : Align(alignment: Alignment.centerLeft, child: botao);
  }
}
