import 'package:flutter/material.dart';

import '../../core/observability/error_reporting.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';
import '../../core/theme/app_theme.dart';

/// Fase 10 — os componentes do mockup (`Functional/nxt-studio-screens.html`)
/// como widgets reutilizáveis. Até aqui cada ecrã montava o seu próprio
/// `Card`/`Chip` Material e escolhia cores à mão (`Colors.green`,
/// `Colors.orange`), o que garantia que dois ecrãs com o mesmo conceito
/// ("em atraso") nunca ficassem exatamente iguais.
///
/// Um ficheiro só, e não um por widget: são componentes pequenos, sempre
/// usados em conjunto, e tê-los à vista uns dos outros é o que evita
/// acrescentar o décimo-primeiro quando um dos dez já servia.

/// Estado semântico partilhado pelos pills. Mapeia para as classes
/// `pill-ok` / `pill-warn` / `pill-red` / `pill-mute` do mockup.
enum PillTone { ok, warn, danger, neutral }

extension on PillTone {
  Color get color => switch (this) {
        PillTone.ok => AppColors.ok,
        PillTone.warn => AppColors.warn,
        PillTone.danger => AppColors.red,
        PillTone.neutral => AppColors.mute,
      };
}

/// `.pill` — etiqueta compacta de estado. Fundo é sempre a cor do estado
/// a 10%, como no CSS; nunca a cor cheia (ilegível em texto pequeno).
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.statusFill(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// `.card` — o contentor base de quase tudo no mockup. Existe além do
/// `Card` do Material porque o `padding` interno (12) faz parte da
/// definição visual: sem isto, cada ecrã escolhia o seu.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.gradient = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// O card de destaque do "Início" do Aluno usa um gradiente subtil
  /// (`linear-gradient(135deg,#1B1114,var(--panel))`) — é o único sítio
  /// do mockup onde isso acontece.
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient ? null : AppColors.panel,
        gradient: gradient
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B1114), AppColors.panel],
              )
            : null,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: content,
    );
  }
}

/// `.icon-box` — quadrado arredondado com um ícone vermelho, à esquerda
/// das linhas de lista.
class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.size = 34});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: AppColors.red, size: size * 0.45),
    );
  }
}

/// `.avatar` — círculo com gradiente vermelho e as iniciais do nome.
/// Substitui a ausência de fotos de perfil (fora de âmbito desde a Fase 5).
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 34});

  final String name;
  final double size;

  /// Primeira letra do primeiro e do último nome ("Rita Ferreira" → "RF").
  /// Um nome só devolve uma inicial; vazio devolve "?" em vez de rebentar.
  static String initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Um leitor de ecrã lia "RF". As iniciais são uma abreviatura
      // visual — para quem ouve, o que interessa é o nome.
      label: name,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.red, AppColors.redDeep],
            ),
          ),
          // O círculo tem tamanho fixo; com o texto do sistema em 200%
          // as iniciais transbordavam-no. `FittedBox` encolhe-as para
          // caber, em vez de as deixar sair do círculo — é decoração,
          // não conteúdo a ler.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initialsOf(name),
              style: AppTheme.display(
                fontSize: size * 0.34,
                color: Colors.white,
              ).copyWith(fontStyle: FontStyle.normal),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.slash` — a barra vermelha inclinada por baixo dos títulos de ecrã.
/// É o elemento de marca mais repetido do mockup (aparece em TODOS os
/// cabeçalhos).
class SlashDivider extends StatelessWidget {
  const SlashDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _SlashClipper(),
      child: Container(
        height: 3,
        width: 48,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            stops: [0, 0.4, 0.4],
            colors: [AppColors.red, AppColors.red, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _SlashClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // `clip-path: polygon(0 0, 100% 0, 92% 100%, 0 100%)`.
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.92, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// `.s-head` — cabeçalho de ecrã: título display + subtítulo opcional +
/// slash. Usado DENTRO do corpo dos ecrãs que no mockup não têm AppBar
/// (a maioria); os que navegam com "voltar" continuam a usar `AppBar`,
/// que o tema já estiliza.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AppTheme.display(fontSize: 20),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          ],
          const SizedBox(height: 9),
          const SlashDivider(),
        ],
      ),
    );
  }
}

/// `.tabs` — separadores em forma de pill, vermelho quando ativo. O
/// mockup usa isto para modalidades ("Hyrox | Pilates | PT | Livre"),
/// dias da semana e tipo de utilizador.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            GestureDetector(
              onTap: () => onSelected(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color:
                      i == selectedIndex ? AppColors.red : AppColors.subtleFill,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i == selectedIndex ? Colors.white : AppColors.mute,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.stat-num` + `.stat-label` — o par usado nos dashboards (Visão global
/// do Gestor, Início do Instrutor).
class StatNumber extends StatelessWidget {
  const StatNumber({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTheme.display(fontSize: 22, color: AppColors.red)),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.mute, fontSize: 11),
        ),
      ],
    );
  }
}

/// `.bar-track` + `.bar-fill` — a barra "1/2 sessões esta semana" (UC08).
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    // `limit` 0 nunca deve chegar aqui (um serviço ilimitado não mostra
    // barra), mas dividir por zero seria um crash — não vale a pena
    // arriscar num widget de apresentação.
    final fraction = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 5,
        backgroundColor: AppColors.trackFill,
        valueColor: const AlwaysStoppedAnimation(AppColors.red),
      ),
    );
  }
}

/// `.banner` — aviso destacado (sugestão por aprovar, password
/// temporária, conta inativa).
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.text,
    this.title,
    this.tone = PillTone.warn,
    this.icon = Icons.warning_amber_outlined,
  });

  final String text;
  final String? title;
  final PillTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = tone.color;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusFill(color),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.bone,
                    fontSize: 12,
                    height: 1.4,
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

/// `.field-block` — par etiqueta/valor usado nas fichas (detalhe da
/// avaliação, ficha de utilizador).
class FieldBlock extends StatelessWidget {
  const FieldBlock({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.dim, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.bone,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Fase 10 — estado vazio que EXPLICA em vez de constatar. A app tinha
/// ~20 listas vazias com uma frase seca ("Ainda não existe nenhum
/// plano."), o que deixa quem abre o ecrã pela primeira vez sem saber
/// o que aquilo é, porque está vazio, nem o que fazer a seguir — foi a
/// queixa concreta ("difícil perceber o que devo fazer").
///
/// Três partes, todas opcionais menos o título: o que é isto
/// ([message]), o que fazer a seguir ([actionLabel]/[onAction]), e um
/// pré-requisito quando o ecrã depende de outro estar preenchido
/// primeiro ([prerequisite]) — ex.: não dá para criar um Plano sem
/// existir um Serviço.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.prerequisite,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? prerequisite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.dim),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.display(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mute,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (prerequisite != null) ...[
              const SizedBox(height: 16),
              AppBanner(
                text: prerequisite!,
                icon: Icons.info_outline,
                tone: PillTone.neutral,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fase 10 — o par do [EmptyState] para quando a leitura FALHA.
///
/// A app tinha ~49 sítios com `Text(userFacingError(error, fallback: 'Erro. Tenta outra vez.'))`: o `toString()` de
/// uma exceção do SDK, cru, no meio do ecrã. Foi assim que o bug do
/// treino livre chegou ao utilizador — como
/// `[cloud_firestore/permission-denied] ... Null value error for 'get'
/// @ L393`. Isso é informação para quem escreve o código, não para quem
/// usa a app: não diz o que aconteceu nem o que fazer a seguir.
///
/// Aqui a mensagem humana fica em cima, com [onRetry] quando há forma
/// de tentar outra vez, e o detalhe técnico só aparece se o utilizador
/// o abrir — continua acessível para um print de ecrã de suporte, sem
/// ser a primeira coisa que se lê.
class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    required this.error,
    this.message = 'Não foi possível carregar esta informação.',
    this.onRetry,
    this.compact = false,
  });

  final Object error;

  /// A frase por omissão, para quando o erro não é um dos que sabemos
  /// traduzir. Se `describeFirebaseError` reconhecer o código, ganha a
  /// dele: dizer "sem ligação à Internet" é acionável, "não foi possível
  /// carregar" não é.
  final String message;
  final VoidCallback? onRetry;

  /// Versão de uma linha, para quando isto vive dentro de um formulário
  /// (um dropdown que não carregou) em vez de ocupar o ecrã todo.
  final bool compact;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

/// Tem estado só para uma coisa: reportar o erro UMA vez.
///
/// Todo o erro que o utilizador chega a ver passa por aqui, o que faz
/// deste o sítio certo para o registar — em vez de espalhar chamadas de
/// telemetria por cada `catch`. Num `StatelessWidget` seria reportado a
/// cada rebuild, e um ecrã que reconstrói dez vezes daria dez ocorrências
/// do mesmo erro.
class _ErrorStateState extends State<ErrorState> {
  @override
  void initState() {
    super.initState();
    reportHandledError(widget.error, StackTrace.current,
        context: widget.message);
  }

  @override
  void didUpdateWidget(ErrorState oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Erro diferente no mesmo sítio = ocorrência nova.
    if (oldWidget.error != widget.error) {
      reportHandledError(widget.error, StackTrace.current,
          context: widget.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final message = widget.message;
    final compact = widget.compact;
    final onRetry = widget.onRetry;

    final humanMessage = describeFirebaseError(error) ?? message;
    final isOffline = _codeIsOffline(error);

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isOffline ? Icons.wifi_off : Icons.error_outline,
            size: 16,
            color: AppColors.warn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              humanMessage,
              style: const TextStyle(color: AppColors.mute, fontSize: 12),
            ),
          ),
        ],
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline ? Icons.wifi_off : Icons.cloud_off_outlined,
              size: 40,
              color: AppColors.dim,
            ),
            const SizedBox(height: 14),
            Text(
              // Um problema de rede não é "algo correu mal" — não correu
              // nada mal, só não há ligação. Dizer o contrário faz a
              // pessoa procurar um problema que não existe.
              isOffline ? 'Sem ligação' : 'Algo correu mal',
              textAlign: TextAlign.center,
              style: AppTheme.display(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              humanMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mute,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tentar outra vez'),
              ),
            ],
            const SizedBox(height: 18),
            Theme(
              // O `ExpansionTile` desenha divisórias por omissão, que
              // aqui só sujavam o bloco.
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text(
                  'Detalhe técnico',
                  style: TextStyle(color: AppColors.dim, fontSize: 11),
                ),
                children: [
                  SelectableText(
                    '$error',
                    style: const TextStyle(
                      color: AppColors.dim,
                      fontSize: 11,
                      height: 1.4,
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

/// Fase 11 — a caixa de pesquisa das listas de gestão.
///
/// Existe como componente e não como `TextField` copiado em cada ecrã
/// por causa dos detalhes que se perdem na cópia: o botão de limpar que
/// só aparece quando há texto, a altura consistente, e sobretudo a
/// pesquisa sem acentos (ver `searchNormalize`) — se cada ecrã fizesse
/// o seu `contains`, metade acertava nos acentos e a outra metade não.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        // `setState` só para o ícone de limpar aparecer/desaparecer.
        setState(() {});
        widget.onChanged(value);
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Limpar',
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        isDense: true,
      ),
    );
  }
}

/// Uma linha de filtros de escolha única. O primeiro é sempre o
/// "sem filtro" (`null`), porque uma lista que abre já filtrada esconde
/// coisas sem o utilizador ter pedido.
///
/// Cada opção traz a sua contagem: ver "Em atraso (3)" antes de tocar
/// evita o filtro que abre vazio, e responde de relance à pergunta que
/// levou a pessoa ao ecrã.
class FilterChipsRow<T> extends StatelessWidget {
  const FilterChipsRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allLabel = 'Todos',
    this.allCount,
  });

  /// `(valor, rótulo, contagem)`.
  final List<(T, String, int)> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final String allLabel;
  final int? allCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              allCount == null ? allLabel : '$allLabel ($allCount)',
            ),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final (value, label, count) in options) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('$label ($count)'),
              selected: selected == value,
              // Tocar no que já está escolhido desliga o filtro — é o
              // que se espera de uma linha de chips, e poupa a viagem
              // até ao "Todos".
              onSelected: (isSelected) =>
                  onSelected(isSelected && selected != value ? value : null),
            ),
          ],
        ],
      ),
    );
  }
}

bool _codeIsOffline(Object error) {
  final text = '$error';
  return text.contains('unavailable') ||
      text.contains('deadline-exceeded') ||
      text.contains('network-request-failed');
}

/// `.t-eyebrow` — o rótulo de secção em maiúsculas pequenas que separa
/// blocos dentro de um ecrã ("Próxima marcação", "Treino livre").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.mute,
        fontSize: 11,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Rótulo de um campo obrigatório.
///
/// Antes disto, o único sinal de que um campo era preciso era a
/// mensagem "Obrigatório" que aparecia **depois** de carregar em
/// gravar — e, quando a validação vivia só no servidor, nem isso: vinha
/// um erro genérico. Num formulário em que a maior parte dos campos é
/// opcional (criar utilizador, criar série), saber quais é que contam
/// antes de começar a escrever poupa a viagem inteira.
///
/// Convenção da app: asterisco no fim do rótulo, e uma linha a
/// explicá-lo uma vez por formulário ([RequiredFieldsHint]).
String requiredLabel(String label) => '$label *';

/// A legenda do asterisco. Uma vez por formulário, no topo — sem isto o
/// símbolo pressupõe que toda a gente conhece a convenção.
class RequiredFieldsHint extends StatelessWidget {
  const RequiredFieldsHint({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Text(
        'Os campos com * são obrigatórios.',
        style: TextStyle(color: AppColors.dim, fontSize: 11),
      ),
    );
  }
}
