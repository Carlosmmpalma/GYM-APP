import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/admin_providers.dart';
import '../../application/providers/tenant_context_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/studio_info.dart';
import '../widgets/async_action_button.dart';
import '../widgets/design_system.dart';
import '../widgets/unsaved_changes_guard.dart';

/// O que a app mostra a quem ainda não tem conta.
///
/// ## Porque este ecrã existe
///
/// Isto esteve em configuração da build durante meia tarde. Funcionava, e
/// estava errado por uma razão que não se vê no código: mudar o telefone
/// do estúdio obrigava a um developer, uma build nova e uma revisão da
/// App Store. É o mesmo problema que o resto da app resolveu fase a fase
/// — tudo o que é negócio pertence a quem gere o negócio.
///
/// ## Porque é aqui que se avisa do que falta
///
/// A vitrina esconde o que está por preencher, em vez de mostrar espaços
/// em branco a um visitante. Isso é o comportamento certo lá e um
/// problema aqui: o que se esconde também se esquece. Por isso este ecrã
/// diz, em cima e sem rodeios, o que ainda falta — e destaca a política
/// de privacidade, que não é um campo como os outros: **sem ela não há
/// submissão possível** nas lojas, e a app trata dados de saúde, que
/// exigem consentimento informado.
class StudioInfoScreen extends ConsumerStatefulWidget {
  const StudioInfoScreen({super.key});

  @override
  ConsumerState<StudioInfoScreen> createState() => _StudioInfoScreenState();
}

class _StudioInfoScreenState extends ConsumerState<StudioInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _mapsUrl = TextEditingController();
  final _policyUrl = TextEditingController();

  /// Sete linhas fixas, uma por dia da semana agrupável. O Gestor deixa
  /// em branco as que não usa — é mais rápido do que um botão de
  /// "acrescentar linha" para uma lista que quase nunca passa de três.
  final _hours = List.generate(
    4,
    (_) => (days: TextEditingController(), hours: TextEditingController()),
  );

  bool _loaded = false;

  /// O que estava guardado quando o ecrã abriu.
  ///
  /// É contra isto que se decide se há alterações por gravar — e não
  /// contra uma flag ligada pelo `onChanged` do `Form`. O ecrã carrega
  /// os valores para os campos, e isso dispara o `onChanged` tal como se
  /// alguém estivesse a escrever: com uma flag, abrir o ecrã e sair
  /// perguntava "tens alterações por gravar" sobre alterações que não
  /// existiam. O docstring do `UnsavedChangesGuard` até avisa disto.
  StudioInfo _guardado = const StudioInfo();

  @override
  void dispose() {
    for (final c in [_address, _phone, _email, _mapsUrl, _policyUrl]) {
      c.dispose();
    }
    for (final linha in _hours) {
      linha.days.dispose();
      linha.hours.dispose();
    }
    super.dispose();
  }

  /// O que está nos campos agora.
  StudioInfo _noFormulario() => StudioInfo(
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        mapsUrl: _mapsUrl.text.trim(),
        privacyPolicyUrl: _policyUrl.text.trim(),
        openingHours: [
          for (final linha in _hours)
            OpeningHours(
              days: linha.days.text.trim(),
              hours: linha.hours.text.trim(),
            ),
        ],
      );

  /// Há alterações por gravar?
  ///
  /// Compara com o formulário tal como ficou depois de carregado — e não
  /// com o que veio do servidor. A diferença importa: ao abrir vazio, o
  /// ecrã SUGERE "Segunda a sexta / Sábado / Domingo" nas linhas de
  /// horário. Essa sugestão é uma alteração que nós fizemos, não o
  /// utilizador, e contá-la fazia o ecrã perguntar "tens alterações por
  /// gravar" a quem abriu e saiu sem tocar em nada.
  bool _haAlteracoes() => _noFormulario() != _guardado;

  void _preencher(StudioInfo info) {
    _address.text = info.address;
    _phone.text = info.phone;
    _email.text = info.email;
    _mapsUrl.text = info.mapsUrl;
    _policyUrl.text = info.privacyPolicyUrl;
    for (var i = 0; i < _hours.length; i++) {
      final linha = i < info.openingHours.length ? info.openingHours[i] : null;
      _hours[i].days.text = linha?.days ?? '';
      _hours[i].hours.text = linha?.hours ?? '';
    }
    // Sugestão para quem começa do zero: o horário de um ginásio quase
    // sempre se escreve nestas três linhas.
    if (info.openingHours.isEmpty) {
      _hours[0].days.text = 'Segunda a sexta';
      _hours[1].days.text = 'Sábado';
      _hours[2].days.text = 'Domingo';
    }
    // Só agora, com as sugestões já lá: é este o estado a partir do qual
    // se mede o que o utilizador mudou.
    _guardado = _noFormulario();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Sem try/catch nem estado de ocupado: quem trata dos dois é o
    // `AsyncActionButton`, que desativa enquanto corre e dá o visto no
    // fim. O erro sobe e ele mostra-o.
    await ref.read(studioAdminRepositoryProvider).updateStudioInfo(
          StudioInfo(
            address: _address.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            mapsUrl: _mapsUrl.text.trim(),
            privacyPolicyUrl: _policyUrl.text.trim(),
            openingHours: [
              for (final linha in _hours)
                OpeningHours(
                  days: linha.days.text.trim(),
                  hours: linha.hours.text.trim(),
                ),
            ],
          ),
        );
    ref.invalidate(studioInfoProvider);
    if (!mounted) return;
    // O que está no formulário passa a ser o que está guardado — senão
    // o ecrã continuava a dizer que havia alterações depois de as ter
    // gravado.
    setState(() => _guardado = _noFormulario());
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(studioInfoProvider);

    // Preenche uma vez, quando os dados chegam. Voltar a preencher a
    // cada reconstrução apagava o que o Gestor estivesse a escrever.
    final info = async.valueOrNull;
    if (info != null && !_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _preencher(info));
      });
    }

    return UnsavedChangesGuard(
      hasChanges: _haAlteracoes,
      child: Scaffold(
        appBar: AppBar(title: const Text('Informação pública')),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(studioInfoProvider),
          ),
          data: (info) => Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Isto é o que a app mostra a quem ainda não tem conta — '
                  'quem a instala antes de se inscrever, e quem a revê na '
                  'App Store. O que deixares em branco simplesmente não '
                  'aparece.',
                  style: TextStyle(color: AppColors.mute, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (info.missing.isNotEmpty) ...[
                  AppBanner(
                    title: 'Falta preencher',
                    text: info.missing.join(' · '),
                    // `warn` e não `danger`: nada do que falta aqui
                    // impede a app de funcionar — o que não estiver
                    // preenchido simplesmente não aparece na vitrina.
                    //
                    // Já foi `danger` quando faltasse a política de
                    // privacidade, e ficou desalinhado quando a política
                    // passou a viver dentro da app: o aviso ficava
                    // vermelho por causa de um campo que já nem sequer
                    // listava. Um alarme sobre uma coisa que não se
                    // nomeia é pior do que nenhum.
                    tone: PillTone.warn,
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _policyUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Política de privacidade publicada',
                    hintText: 'https://…',
                    // Deixou de ser obrigatória aqui quando a política
                    // passou a viver dentro da app. Dizer "obrigatória"
                    // mandava o Gestor à procura de uma coisa que já
                    // tem.
                    helperText: 'Opcional. A app já traz uma política, e é '
                        'essa que conta para o consentimento. Preenche isto '
                        'se a publicares também num site — a ficha da App '
                        'Store pede um endereço.',
                    helperMaxLines: 4,
                  ),
                  validator: _validarUrl,
                ),
                const SizedBox(height: 14),
                const SectionLabel('Onde estamos'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Morada',
                    hintText: 'Rua, número, código postal, cidade',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _mapsUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Ligação para o mapa',
                    hintText: 'https://maps.app.goo.gl/…',
                    helperText: 'Opcional. Dá o botão "Como chegar".',
                    helperMaxLines: 2,
                  ),
                  validator: _validarUrl,
                ),
                const SizedBox(height: 18),
                const SectionLabel('Horário de funcionamento'),
                const SizedBox(height: 4),
                const Text(
                  'Escreve como se lê num cartaz. Deixa em branco as '
                  'linhas que não usares.',
                  style: TextStyle(color: AppColors.dim, fontSize: 11),
                ),
                const SizedBox(height: 8),
                for (final linha in _hours)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: linha.days,
                            decoration: const InputDecoration(
                              hintText: 'Segunda a sexta',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: linha.hours,
                            decoration: const InputDecoration(
                              hintText: '07:00 – 22:00',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // O "A guardar…" e o visto de "guardado" vivem no
                // botão — ver `AsyncActionButton`. O SnackBar de
                // "Informação pública atualizada" saiu com eles: aqui o
                // resultado vê-se no próprio formulário, que fica com o
                // que foi gravado.
                AsyncActionButton(
                  label: 'Guardar',
                  expand: true,
                  onPressed: _guardar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Um endereço sem esquema abre uma página em branco no telemóvel, e o
  /// Gestor nunca saberia porquê — o botão simplesmente não faz nada.
  String? _validarUrl(String? value) {
    final texto = (value ?? '').trim();
    if (texto.isEmpty) return null;
    final uri = Uri.tryParse(texto);
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
      return 'Tem de começar por https:// e ter um domínio.';
    }
    return null;
  }
}
