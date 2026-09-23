import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/firebase_error_text.dart';

/// Um botão que corre uma ação assíncrona **uma vez**.
///
/// ## O problema que isto resolve
///
/// A app tinha 23 ficheiros a chamar uma Cloud Function a partir de um
/// botão sem nada que impedisse o segundo toque. Entre o toque e a
/// resposta — que numa rede fraca são segundos — o botão continuava a
/// parecer que não tinha feito nada, porque de facto não mudava nada.
/// Tocar outra vez é a reação certa de qualquer pessoa.
///
/// Não é estética. `start_workout_button` chamava `startSession` sem
/// guarda nenhuma: dois toques criavam **dois treinos** para a mesma
/// pessoa, e o segundo ficava aberto para sempre porque só um é que o
/// ecrã mostra. O mesmo padrão existia em enviar notificações, apagar
/// itens do catálogo e registar pagamentos.
///
/// ## Porque um widget e não uma guarda em cada sítio
///
/// A guarda em si são três linhas: um `bool`, um `setState` à entrada e
/// outro no `finally`. Escrevê-la 23 vezes dá 23 oportunidades de
/// esquecer o `finally` (e deixar o botão morto para sempre), e o 24.º
/// sítio nasceria outra vez desprotegido.
///
/// Aqui está num sítio só, e inclui as duas coisas que mais se esquecem:
/// o `finally` e o `mounted` antes do `setState` — um ecrã que se fecha
/// enquanto a chamada corre não pode reconstruir o que já não existe.
///
/// ## O que mostra enquanto corre, e depois
///
/// O ícone dá lugar a um indicador de progresso e o botão desativa-se.
/// Não é um ecrã bloqueado nem um diálogo por cima: o trabalho está
/// onde o toque foi dado, que é onde a pessoa está a olhar.
///
/// Quando acaba bem, o ícone passa a um visto durante um segundo e
/// meio. É a confirmação **no sítio da ação**, e é o que permite não
/// mostrar um SnackBar por cima de uma coisa que já se vê.
///
/// A app tinha 134 SnackBars, dos quais uns 59 eram confirmações. Boa
/// parte anunciava o que o ecrã já mostrava — a linha mudou, o cartão
/// atualizou-se — e um aviso a dizer o que está à frente dos olhos é
/// ruído que ensina a ignorar os avisos que importam.
///
/// Os que continuam a fazer sentido são os que dizem alguma coisa que
/// NÃO se vê: uma escrita que ficou em fila por falta de rede, ou uma
/// confirmação depois de o ecrã ter fechado.
enum AsyncButtonKind { filled, outlined, text }

class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = AsyncButtonKind.filled,
    this.expand = false,
    this.enabled = true,
    this.onError,
  });

  final String label;

  /// `null` desativa o botão por outras razões que não a ação a correr
  /// (por exemplo, um formulário ainda incompleto).
  final Future<void> Function()? onPressed;

  final IconData? icon;
  final AsyncButtonKind kind;

  /// Ocupa a largura toda. O caso dos botões de submissão no fim de um
  /// formulário.
  final bool expand;

  final bool enabled;

  /// O que fazer quando a ação lança.
  ///
  /// Por omissão, mostra a mensagem traduzida onde o botão está. Quem
  /// tiver um sítio melhor para o erro — um banner no formulário, por
  /// exemplo — passa o seu.
  final void Function(Object erro)? onError;

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool _aCorrer = false;
  bool _feito = false;
  Timer? _limparFeito;

  @override
  void dispose() {
    _limparFeito?.cancel();
    super.dispose();
  }

  Future<void> _correr() async {
    final accao = widget.onPressed;
    // A segunda guarda, além do `onPressed: null`: entre o toque e o
    // `setState` há um fotograma, e um toque duplo rápido cabe lá
    // dentro.
    if (accao == null || _aCorrer) return;

    setState(() {
      _aCorrer = true;
      _feito = false;
    });
    _limparFeito?.cancel();
    try {
      await accao();
      if (!mounted) return;
      setState(() => _feito = true);
      // Um visto permanente deixaria de significar "acabou agora" e
      // passaria a fazer parte do botão.
      _limparFeito = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _feito = false);
      });
    } catch (erro) {
      if (!mounted) return;
      if (widget.onError != null) {
        widget.onError!(erro);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userFacingError(
              erro,
              fallback: 'Não foi possível concluir. Tenta outra vez.',
            )),
          ),
        );
      }
    } finally {
      // Sem isto, um ecrã fechado a meio da chamada rebentava com
      // "setState() called after dispose()".
      if (mounted) setState(() => _aCorrer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activo = widget.enabled && widget.onPressed != null && !_aCorrer;
    final onPressed = activo ? _correr : null;

    // O indicador tem o tamanho do ícone (ou do texto, quando não há
    // ícone) para o botão não mudar de largura a meio — um botão que
    // encolhe sob o dedo parece que se moveu.
    final Widget? conteudo;
    if (_aCorrer) {
      conteudo = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.bone,
        ),
      );
    } else if (_feito) {
      conteudo = const Icon(Icons.check, size: 18);
    } else {
      conteudo = widget.icon == null ? null : Icon(widget.icon, size: 18);
    }

    final rotulo = Text(widget.label);

    final Widget botao = switch (widget.kind) {
      AsyncButtonKind.filled => conteudo == null
          ? FilledButton(onPressed: onPressed, child: rotulo)
          : FilledButton.icon(
              onPressed: onPressed, icon: conteudo, label: rotulo),
      AsyncButtonKind.outlined => conteudo == null
          ? OutlinedButton(onPressed: onPressed, child: rotulo)
          : OutlinedButton.icon(
              onPressed: onPressed, icon: conteudo, label: rotulo),
      AsyncButtonKind.text => conteudo == null
          ? TextButton(onPressed: onPressed, child: rotulo)
          : TextButton.icon(
              onPressed: onPressed, icon: conteudo, label: rotulo),
    };

    return widget.expand
        ? SizedBox(width: double.infinity, child: botao)
        : botao;
  }
}
