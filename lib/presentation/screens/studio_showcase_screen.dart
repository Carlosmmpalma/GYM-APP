import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/tenant_context_providers.dart';
import '../../core/config/tenant_app_config.dart';
import '../../domain/entities/studio_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/public_schedule.dart';
import '../widgets/design_system.dart';
import '../widgets/privacy_policy_link.dart';
import 'login_screen.dart';

const _diasDaSemana = <int, String>{
  1: 'Segunda',
  2: 'Terça',
  3: 'Quarta',
  4: 'Quinta',
  5: 'Sexta',
  6: 'Sábado',
  7: 'Domingo',
};

/// A porta de entrada da app, para quem ainda não tem conta.
///
/// ## Porque existe
///
/// Até aqui a app abria diretamente no formulário de login. Quem a
/// instalasse antes de se inscrever não conseguia saber nada — nem onde
/// fica o estúdio, nem a que horas abre, nem que aulas dá. Um formulário
/// de password é uma porta fechada com um cadeado e sem placa.
///
/// Serve também quem revê a app na App Store: abre-a, vê um campo de
/// password que não sabe preencher, e não tem como avaliar o que ali
/// está. Não é garantido que rejeitem por isso, mas o remédio é barato e
/// vale por si.
///
/// ## De onde vem o que se vê
///
/// De dois sítios diferentes, por razões diferentes:
///
/// - **Morada, contactos, horário e política de privacidade** vêm de
///   `tenants/{t}/public/info` ([StudioInfo]), escrito pelo Gestor em
///   Gestão › Informação pública.
/// - **O mapa de aulas** vem de `tenants/{t}/public/schedule`, derivado
///   das séries ativas pelo cron diário — escrito à mão desatualizava-se
///   na primeira semana, e um horário público errado manda pessoas ao
///   ginásio à hora errada.
///
/// Os dois lêem-se sem sessão, que é a condição de existir este ecrã.
///
/// ## O que fazer quando falta
///
/// Nada aqui é obrigatório aparecer. Um campo por preencher esconde-se
/// em vez de desenhar um espaço em branco; quem avisa que falta é o ecrã
/// de gestão, ao Gestor, e não o utilizador. Um mapa de aulas vazio, ou
/// que não é reescrito há mais de uma semana, também não aparece: mais
/// vale não anunciar horário nenhum do que anunciar um que já não é
/// verdade.
class StudioShowcaseScreen extends ConsumerWidget {
  const StudioShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(tenantAppConfigProvider);
    // Do servidor, não da build: o Gestor muda a morada do ginásio em
    // Gestão › Informação pública, sem esperar por uma versão nova da
    // app. `null` enquanto carrega, e o ecrã esconde o que não sabe.
    final info = ref.watch(studioInfoProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                _Marca(config: config),
                const SizedBox(height: 24),
                _BotaoMembro(),
                const SizedBox(height: 28),
                const _Aulas(),
                if (info != null) ...[
                  const SizedBox(height: 24),
                  _Horario(info: info),
                  const SizedBox(height: 24),
                  _Contactos(info: info),
                ],
                const SizedBox(height: 28),
                const PrivacyPolicyLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.config});

  final TenantAppConfig config;

  @override
  Widget build(BuildContext context) {
    final logo = config.logoAsset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logo != null)
          Image.asset(
            logo,
            height: 72,
            errorBuilder: (context, error, stack) => Text(
              config.displayName ?? '',
              style: AppTheme.display(fontSize: 26),
            ),
          )
        else
          Text(config.displayName ?? '', style: AppTheme.display(fontSize: 26)),
        const SizedBox(height: 22),
        Text(
          'TREINA AO\nTEU RITMO',
          style: AppTheme.display(fontSize: 30, height: 1.15),
        ),
        const SizedBox(height: 10),
        const Text(
          'Aulas de grupo, treino livre e acompanhamento. '
          'O acesso à app é criado pelo estúdio quando te inscreves.',
          style: TextStyle(color: AppColors.mute, height: 1.5),
        ),
      ],
    );
  }
}

class _BotaoMembro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      ),
      child: const Text('Já sou membro — entrar'),
    );
  }
}

class _Aulas extends ConsumerWidget {
  const _Aulas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicScheduleProvider);
    final schedule = async.valueOrNull;

    // Em silêncio quando não há nada de confiança para dizer: o resto do
    // ecrã (morada, contactos, horário) continua a valer por si, e um
    // bloco de erro sobre um horário não ajuda quem só quer saber onde
    // fica o ginásio.
    if (schedule == null ||
        schedule.isEmpty ||
        schedule.isStale(DateTime.now())) {
      return const SizedBox.shrink();
    }

    final porDia = <int, List<PublicScheduleEntry>>{};
    for (final entry in schedule.entries) {
      porDia.putIfAbsent(entry.dayOfWeek, () => []).add(entry);
    }
    final dias = porDia.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Mapa de aulas'),
        const SizedBox(height: 8),
        PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final dia in dias) ...[
                if (dia != dias.first) const SizedBox(height: 14),
                Text(
                  _diasDaSemana[dia] ?? '',
                  style: const TextStyle(
                    color: AppColors.bone,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                for (final entry in porDia[dia]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            entry.startTime,
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          '${entry.durationMinutes} min',
                          style: const TextStyle(
                            color: AppColors.dim,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Horario extends StatelessWidget {
  const _Horario({required this.info});

  final StudioInfo info;

  @override
  Widget build(BuildContext context) {
    final linhas = info.visibleHours;
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Horário'),
        const SizedBox(height: 8),
        PanelCard(
          child: Column(
            children: [
              for (final linha in linhas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // Os dois `Flexible` não são decoração. Um horário
                  // real de um estúdio com pausa de almoço escreve-se
                  // "07:00 – 13:00, 16:00 – 21:30", e ao lado de
                  // "Segunda a sexta" isso passa a largura de qualquer
                  // telemóvel — 226 px a mais num iPhone SE, e 141 a
                  // mais num iPad. Sem eles, os dois `Text` pediam a
                  // largura que quisessem e o `spaceBetween` não tinha
                  // nada para distribuir.
                  //
                  // Este é o primeiro ecrã que alguém vê, incluindo
                  // quem faz a revisão na App Store.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // `Expanded` e não `Flexible`: com `Flexible` a
                      // caixa encolhe até ao texto e o
                      // `mainAxisAlignment` volta a decidir onde ela
                      // fica, o que torna o alinhamento dependente do
                      // comprimento do conteúdo. Aqui cada lado fica
                      // com metade, sempre, e o `textAlign` manda
                      // dentro da sua metade.
                      Expanded(
                        child: Text(
                          linha.days,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          linha.hours,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Contactos extends StatelessWidget {
  const _Contactos({required this.info});

  final StudioInfo info;

  @override
  Widget build(BuildContext context) {
    final linhas = <Widget>[
      if (temValorReal(info.address))
        _Linha(
          icon: Icons.place_outlined,
          texto: info.address,
          onTap: temValorReal(info.mapsUrl)
              ? () => abrirLigacaoExterna(context, info.mapsUrl)
              : null,
          accao: temValorReal(info.mapsUrl) ? 'Como chegar' : null,
        ),
      if (temValorReal(info.phone))
        _Linha(
          icon: Icons.call_outlined,
          texto: info.phone,
          onTap: () => abrirLigacaoExterna(
              context, 'tel:${info.phone.replaceAll(' ', '')}'),
        ),
      if (temValorReal(info.email))
        _Linha(
          icon: Icons.mail_outline,
          texto: info.email,
          onTap: () => abrirLigacaoExterna(context, 'mailto:${info.email}'),
        ),
    ];
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Onde estamos'),
        const SizedBox(height: 8),
        PanelCard(child: Column(children: linhas)),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.icon,
    required this.texto,
    this.onTap,
    this.accao,
  });

  final IconData icon;
  final String texto;
  final VoidCallback? onTap;
  final String? accao;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.mute),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(texto, style: const TextStyle(fontSize: 12)),
                  if (accao != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        accao!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
