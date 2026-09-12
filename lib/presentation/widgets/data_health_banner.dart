import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/observability/data_health.dart';
import '../../core/theme/app_colors.dart';

/// O aviso de que a app não está a conseguir ler os dados.
///
/// Envolve a app inteira (ver `app.dart`) e aparece por cima de tudo
/// quando algum provider está em erro — ver [dataHealthProvider] para a
/// história de porque isto existe. Em resumo: a app tem 54 sítios que
/// tratam "falhou a carregar" e "está vazio" como a mesma coisa, e o
/// resultado é um estúdio que parece não ter nada lá dentro.
///
/// Três decisões que valem a pena registar:
///
/// - **Não tapa nada.** Fica no fundo, acima da barra de navegação, e
///   deixa a app utilizável. Quem está offline com a cache quente
///   continua a poder ver o que já tem — dizer-lhe que algo falhou não
///   é razão para lhe tirar a app das mãos.
/// - **Espera antes de aparecer.** Um erro que dura meio segundo
///   enquanto a rede hesita não é notícia; um aviso que pisca a cada
///   troca de ecrã ensina as pessoas a ignorá-lo. Só aparece se a falha
///   se aguentar.
/// - **Não diz qual provider falhou.** Isso é informação para quem
///   programa, e vai para os registos. Ao utilizador interessa o que
///   fazer.
class DataHealthBanner extends ConsumerStatefulWidget {
  const DataHealthBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DataHealthBanner> createState() => _DataHealthBannerState();
}

class _DataHealthBannerState extends ConsumerState<DataHealthBanner> {
  /// Quanto tempo uma falha tem de durar para valer um aviso.
  static const _espera = Duration(seconds: 4);

  bool _mostrar = false;
  bool _dispensado = false;
  Timer? _temporizador;

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  /// Reage à MUDANÇA de estado, não a cada reconstrução.
  ///
  /// A primeira versão agendava um `Future.delayed` dentro do `build`.
  /// Funcionava por acidente: cada reconstrução enquanto a falha durasse
  /// agendava mais um, e bastava uma delas chegar ao fim. Um temporizador
  /// que se cancela é o que se quer dizer.
  void _aoMudar(Set<String> falhas) {
    if (falhas.isEmpty) {
      _temporizador?.cancel();
      _temporizador = null;
      // Recuperar limpa também o "já vi": a próxima falha é notícia
      // nova, e merece ser dita.
      _dispensado = false;
      if (_mostrar) setState(() => _mostrar = false);
      return;
    }

    if (_mostrar || _dispensado || _temporizador != null) return;
    _temporizador = Timer(_espera, () {
      _temporizador = null;
      if (!mounted) return;
      if (ref.read(dataHealthProvider).isNotEmpty) {
        setState(() => _mostrar = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Set<String>>(
      dataHealthProvider,
      (anterior, atual) => _aoMudar(atual),
    );
    // O `listen` só dispara em MUDANÇAS. Se já houver falhas quando este
    // widget nasce — recarregar a página com a cache partida, por
    // exemplo — ninguém o avisaria.
    final falhasAgora = ref.watch(dataHealthProvider);
    if (falhasAgora.isNotEmpty && !_mostrar && !_dispensado) {
      _aoMudar(falhasAgora);
    }

    return Stack(
      children: [
        widget.child,
        if (_mostrar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.panel2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warn, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 18, color: AppColors.warn),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Não estamos a conseguir ler os teus dados. O que '
                          'vês pode estar incompleto.',
                          style: TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _mostrar = false;
                          // Não voltar a insistir sobre a MESMA falha.
                          // Quando os dados voltarem e tornarem a
                          // falhar, aí sim.
                          _dispensado = true;
                        }),
                        child: const Text(
                          'Ok',
                          style: TextStyle(fontSize: 12, color: AppColors.mute),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
