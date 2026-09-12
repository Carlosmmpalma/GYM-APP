import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/consent.dart';
import '../widgets/design_system.dart';
import '../widgets/privacy_policy_link.dart';

/// A política de privacidade, dentro da app.
///
/// ## Porque está aqui em código e não num URL
///
/// Pela mesma razão que o resumo do [ConsentScreen]: é a versão que ESTA
/// build mostrou, e é a que [kPrivacyPolicyVersion] identifica no registo
/// de consentimento. Um texto que muda no servidor sem mudar a versão
/// tornaria esse registo inútil como prova — o artigo 7.º, n.º 1 exige
/// poder demonstrar a que a pessoa consentiu, não apenas que consentiu.
///
/// Também resolve um problema prático: sem isto, a app só tinha política
/// se alguém se lembrasse de publicar uma noutro sítio e colar o
/// endereço. Enquanto isso não acontecesse, o ecrã de consentimento
/// pedia aceitação de um documento que não existia em lado nenhum.
///
/// ## ⚠️ Este texto ainda não passou por um advogado
///
/// Foi escrito a partir do que o código faz mesmo — cada afirmação aqui
/// corresponde a algo verificável nas Security Rules, nas Cloud Functions
/// ou nos ecrãs. Isso torna-o exato, não torna-o suficiente: descrever
/// bem o tratamento não é o mesmo que ter as bases legais e os prazos
/// revistos por quem responde por eles.
///
/// Ao contrário do que possa parecer tentador, **não leva aviso nenhum
/// de "rascunho" para o utilizador**: uma política que se anuncia como
/// provisória não serve como política. Quem tem de saber que falta a
/// revisão é o estúdio, e isso está dito em Gestão › Informação pública.
///
/// Quando a versão revista existir, substitui-se o texto **e sobe-se a
/// [kPrivacyPolicyVersion]** — senão ninguém volta a ser perguntado
/// sobre um documento que mudou.
///
/// ## O URL opcional
///
/// Se o estúdio publicar a política num site (o App Store Connect exige
/// um endereço público para a ficha da loja), esse endereço aparece no
/// fim, como "versão publicada". A do ecrã continua a ser a que conta
/// para o consentimento.
class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estudio =
        ref.watch(tenantAppConfigProvider).displayName ?? 'o estúdio';
    final info = ref.watch(studioInfoProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Política de privacidade')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const Text(
            'Versão $kPrivacyPolicyVersion',
            style: TextStyle(color: AppColors.dim, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Como $estudio trata os teus dados',
            style: const TextStyle(
              color: AppColors.bone,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          for (final seccao in _politica(estudio, info?.email ?? '')) ...[
            _Seccao(titulo: seccao.$1, paragrafos: seccao.$2),
            const SizedBox(height: 20),
          ],
          if (temValorReal(info?.privacyPolicyUrl)) ...[
            const SlashDivider(),
            const SizedBox(height: 12),
            const Text(
              'Esta é a versão que a app te mostrou e sobre a qual foi '
              'registada a tua aceitação. O estúdio publica também uma '
              'cópia em linha:',
              style: TextStyle(color: AppColors.dim, fontSize: 11, height: 1.5),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => abrirLigacaoExterna(
                  context,
                  info!.privacyPolicyUrl,
                ),
                icon: const Icon(Icons.open_in_new,
                    size: 14, color: AppColors.mute),
                label: const Text(
                  'Abrir a versão publicada',
                  style: TextStyle(fontSize: 12, color: AppColors.mute),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// O texto, em secções.
///
/// Cada afirmação aqui é verificável no código — e onde o código mudar, o
/// texto tem de mudar com ele. Os sítios que sustentam cada parte estão
/// nos comentários, para quem vier a seguir saber onde confirmar.
List<(String, List<String>)> _politica(String estudio, String emailEstudio) {
  final contacto = emailEstudio.isEmpty
      ? 'pelos contactos do estúdio'
      : 'para $emailEstudio';
  return [
    (
      'Quem trata os teus dados',
      [
        '$estudio é o responsável pelo tratamento: é quem decide que '
            'dados são recolhidos e para quê. A app é a ferramenta que o '
            'estúdio usa para isso.',
        'Para qualquer questão sobre os teus dados, ou para exercer '
            'qualquer um dos direitos descritos abaixo, fala com o '
            'estúdio $contacto.',
      ],
    ),
    (
      'Que dados são guardados',
      [
        // `MemberSummary` + `StaffPrivateProfile`.
        'Identificação e contacto: nome, número de sócio, telefone, '
            'email, data de nascimento, morada, NIF e um contacto de '
            'emergência. Estes dados são introduzidos pelo estúdio quando '
            'te inscreves.',
        // `bookings`, `attendance`, `usage`.
        'Atividade no estúdio: as tuas marcações, as presenças e faltas '
            'registadas pelo instrutor, e a contagem de utilizações da '
            'semana para o limite do teu plano.',
        // `subscriptions`, `paymentRecords`.
        'Plano e mensalidades: o plano que contrataste, o preço acordado, '
            'e o estado de cada mensalidade.',
        // `workoutSessions`, `loadHistory`, `planEntries`.
        'Treino: o plano de treino que o instrutor te prescreve, os '
            'treinos que fazes e as cargas que registas.',
        // Storage `avatars/`.
        'Fotografia de perfil, se escolheres ter uma.',
        // `assessments` — artigo 9.º.
        'Avaliações físicas — peso, altura, massa gorda, gordura '
            'visceral, pressão arterial e frequência cardíaca. Estes são '
            'dados de saúde e só são recolhidos se autorizares '
            'expressamente (ver abaixo).',
      ],
    ),
    (
      'Para que servem, e com que fundamento',
      [
        'A maior parte destes dados é tratada para **executar o contrato** '
            'entre ti e o estúdio: sem eles não é possível inscrever-te, '
            'deixar-te marcar treinos, controlar o limite do teu plano ou '
            'cobrar a mensalidade.',
        'Os registos de pagamento são também conservados por **obrigação '
            'legal** — a lei fiscal obriga o estúdio a guardar a '
            'contabilidade.',
        'As **avaliações físicas** são a exceção e têm fundamento '
            'próprio: o teu **consentimento explícito**, dado no ecrã de '
            'privacidade da app e revogável no mesmo sítio. Podes usar a '
            'app inteira — marcar aulas, treinar, pagar — sem autorizar '
            'avaliações físicas.',
      ],
    ),
    (
      'Quem tem acesso',
      [
        // `firestore.rules` — leitura de `members` por manager/instructor.
        'Dentro do estúdio: o Gestor e os instrutores. Nenhum outro aluno '
            'vê os teus dados.',
        // Vitrina: `tenants/{t}/public/` não tem dados pessoais.
        'Fora do estúdio: ninguém. A app tem um ecrã público com a morada, '
            'o horário e o mapa de aulas, mas esse ecrã não contém dados '
            'de pessoa nenhuma.',
        'Os dados são alojados na infraestrutura da Google (Firebase), em '
            'servidores na União Europeia, que atua como subcontratante do '
            'estúdio. Nada é vendido nem partilhado para publicidade.',
      ],
    ),
    (
      'Durante quanto tempo',
      [
        'Enquanto fores membro do estúdio, e depois disso enquanto for '
            'necessário para resolver qualquer questão pendente.',
        'Quando pedires o apagamento, os teus dados são eliminados — com '
            'uma exceção: os registos de pagamento ficam, sem o teu nome '
            'nem qualquer dado que te identifique, porque a lei obriga o '
            'estúdio a conservar a contabilidade.',
      ],
    ),
    (
      'Os teus direitos',
      [
        'Podes pedir uma **cópia** de tudo o que o estúdio tem sobre ti. '
            'Está na app, em "Os meus dados" — exporta um ficheiro, sem '
            'teres de pedir a ninguém.',
        'Podes pedir a **correção** do que estiver errado, e o **apagamento** '
            'dos teus dados. O apagamento pede-se ao estúdio, que confirma '
            'a tua identidade antes de o fazer — é uma ação sem volta, e '
            'não deve poder ser desencadeada por quem tenha apanhado o teu '
            'telemóvel destrancado.',
        'Podes **retirar** a autorização para as avaliações físicas a '
            'qualquer momento, no mesmo sítio onde a deste. As avaliações '
            'já feitas continuam guardadas até pedires que sejam apagadas.',
        'Podes ainda opor-te ao tratamento, pedir a sua limitação, e pedir '
            'os teus dados num formato que possas levar para outro lado.',
      ],
    ),
    (
      'Se achares que algo está mal',
      [
        'Fala primeiro com o estúdio $contacto — é quem responde pelos '
            'teus dados e quem os pode corrigir.',
        'Tens também o direito de apresentar reclamação à **Comissão '
            'Nacional de Proteção de Dados** (CNPD), a autoridade '
            'portuguesa de controlo, em www.cnpd.pt.',
      ],
    ),
    (
      'Alterações a esta política',
      [
        'Se o tratamento mudar — dados novos, finalidades novas, novos '
            'destinatários — esta política muda e a app volta a pedir-te '
            'que a leias e aceites. É por isso que ela tem um número de '
            'versão: o registo da tua aceitação guarda qual das versões '
            'te foi mostrada.',
      ],
    ),
  ];
}

class _Seccao extends StatelessWidget {
  const _Seccao({required this.titulo, required this.paragrafos});

  final String titulo;
  final List<String> paragrafos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: AppColors.red,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (final paragrafo in paragrafos)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TextoComDestaques(paragrafo),
          ),
      ],
    );
  }
}

/// Os `**assim**` do texto passam a negrito.
///
/// Uma dependência de markdown para negritar meia dúzia de expressões
/// seria pagar um pacote inteiro por isto — e escrever o texto já
/// partido em `TextSpan` tornava-o impossível de rever por quem não
/// programa, que é precisamente quem o vai rever.
class _TextoComDestaques extends StatelessWidget {
  const _TextoComDestaques(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: AppColors.mute, fontSize: 13, height: 1.6);
    final partes = texto.split('**');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < partes.length; i++)
            TextSpan(
              text: partes[i],
              style: i.isOdd
                  ? const TextStyle(
                      color: AppColors.bone,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
        ],
      ),
      style: base,
    );
  }
}
