import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Um ecrã real, com as medidas que o Flutter vê.
///
/// ## Porque isto existe
///
/// Os testes de widget corriam todos no ecrã por omissão do
/// `flutter_test`: 800×600, sem recortes, com o texto à escala 1.0. Não
/// é nenhum telemóvel. É mais largo do que qualquer iPhone e mais baixo
/// do que todos — ou seja, o tamanho em que um `Row` demasiado cheio
/// cabe e uma `Column` demasiado alta não estoura.
///
/// Um `RenderFlex overflowed` não é um detalhe estético: o Flutter
/// desenha as barras amarelas e pretas por cima do conteúdo, e o que
/// ficou de fora deixa de ser tocável. Um botão "Confirmar" empurrado
/// para fora do ecrã é uma funcionalidade que não existe naquele
/// telefone.
///
/// O framework já sabe detetar isto — reporta um `FlutterError` que faz
/// o teste falhar. O que faltava era pôr os ecrãs em tamanhos onde isso
/// acontece.
///
/// ## As medidas
///
/// `largura`/`altura` são pontos lógicos (o que o Flutter chama
/// `Size`), não pixels. `topo`/`fundo` são a área segura — a barra de
/// estado e o entalhe em cima, o indicador de gestos em baixo — e é por
/// isso que um iPhone com entalhe tem MENOS espaço útil do que a altura
/// sugere.
///
/// `escalaTexto` é o tamanho de letra do sistema. Não é um extra: é a
/// definição de acessibilidade mais usada que existe, e a que mais
/// parte layouts. No Android, "Enorme" é 1.3. No iOS, os tamanhos de
/// acessibilidade chegam a 2.0 e além.
class Dispositivo {
  const Dispositivo(
    this.nome, {
    required this.largura,
    required this.altura,
    this.dpr = 3.0,
    this.topo = 0,
    this.fundo = 0,
    this.escalaTexto = 1.0,
    this.teclado = 0,
  });

  final String nome;
  final double largura;
  final double altura;
  final double dpr;
  final double topo;
  final double fundo;
  final double escalaTexto;

  /// Altura do teclado, em pontos. Entra como `viewInsets`, que é o que
  /// o `Scaffold` usa para encolher o corpo — não como `padding`.
  ///
  /// Um teclado num iPhone SE tira 291 dos 667 pontos: o ecrã fica com
  /// 56% da altura, e é com o teclado aberto que se preenche um
  /// formulário. Um ecrã que só cabe com o teclado fechado é um ecrã
  /// que não cabe.
  final double teclado;

  @override
  String toString() => nome;
}

/// Os ecrãs onde esta app vai mesmo correr.
///
/// A lista é deliberadamente curta. Cada entrada multiplica o número de
/// testes por todos os ecrãs, e uma matriz que demora demasiado é uma
/// matriz que se deixa de correr. Cada uma está aqui por representar um
/// canto diferente do espaço, não por ser um telemóvel popular:
///
/// * o mais **estreito** que ainda se vende;
/// * o mais **baixo** (deitado), onde as colunas estouram;
/// * o mais **largo** (tablet), onde as linhas ficam esticadas;
/// * o de **texto grande**, que é onde a maioria dos problemas reais
///   aparece e que quase nunca é testado.
const dispositivos = <Dispositivo>[
  // O mais estreito que a App Store ainda aceita. O iPhone SE tem botão
  // físico, por isso não tem indicador de gestos em baixo — mas tem 20
  // pontos de barra de estado.
  Dispositivo(
    'iPhone SE · 375×667',
    largura: 375,
    altura: 667,
    dpr: 2,
    topo: 20,
  ),
  // Android barato, ainda muito comum. Mais estreito que qualquer
  // iPhone atual e com uma densidade mais baixa.
  Dispositivo(
    'Android pequeno · 360×640',
    largura: 360,
    altura: 640,
    dpr: 2,
    topo: 24,
  ),
  // O caso normal em iOS, com entalhe e indicador de gestos: 93 pontos
  // dos 852 desaparecem antes de qualquer conteúdo.
  Dispositivo(
    'iPhone 15 · 393×852',
    largura: 393,
    altura: 852,
    topo: 59,
    fundo: 34,
  ),
  // Android moderno, com furo na câmara e barra de gestos.
  Dispositivo(
    'Pixel 7 · 412×915',
    largura: 412,
    altura: 915,
    dpr: 2.625,
    topo: 24,
    fundo: 24,
  ),
  // Deitado. A app NÃO tranca a orientação — o `Info.plist` declara
  // landscape nas duas direções e o Android não declara nada — por isso
  // isto é um ecrã real, e um revisor da App Store roda o telefone.
  // 390 pontos de altura menos o teclado não deixam quase nada.
  Dispositivo(
    'iPhone deitado · 852×393',
    largura: 852,
    altura: 393,
    topo: 0,
    fundo: 21,
  ),
  // Tablet. A app é submetida como universal, por isso tem de se
  // aguentar aqui — mesmo que ninguém treine com um iPad na mão.
  Dispositivo(
    'iPad · 744×1133',
    largura: 744,
    altura: 1133,
    dpr: 2,
    topo: 24,
    fundo: 20,
  ),
  // Texto grande no ecrã mais pequeno: o pior caso realista, e o mais
  // provável de acontecer a um sócio mais velho. 1.3 é o "Enorme" do
  // Android.
  Dispositivo(
    'Android pequeno · texto 1.3×',
    largura: 360,
    altura: 640,
    dpr: 2,
    topo: 24,
    escalaTexto: 1.3,
  ),
  // Acessibilidade a sério no iOS. Não é um caso de bordo inventado —
  // é uma definição que o utilizador escolhe no sistema, e a app não
  // pode partir por causa dela.
  Dispositivo(
    'iPhone SE · texto 2.0×',
    largura: 375,
    altura: 667,
    dpr: 2,
    topo: 20,
    escalaTexto: 2.0,
  ),
  // O teclado aberto, que é o estado NORMAL de qualquer formulário e o
  // mais fácil de esquecer — no emulador testa-se com o rato, e o
  // teclado nunca aparece.
  Dispositivo(
    'iPhone SE · teclado aberto',
    largura: 375,
    altura: 667,
    dpr: 2,
    topo: 20,
    teclado: 291,
  ),
];

/// Põe o `WidgetTester` a fingir [d], e desfaz no fim do teste.
///
/// Tem de ser chamado ANTES do `pumpWidget`: o `MediaQuery` nasce da
/// view no primeiro build, e mudá-la a meio não reconstrói o que já foi
/// medido.
void aplicarDispositivo(WidgetTester tester, Dispositivo d) {
  tester.view.devicePixelRatio = d.dpr;
  tester.view.physicalSize = Size(d.largura * d.dpr, d.altura * d.dpr);

  // `ViewPadding` é em pixels físicos — o `MediaQueryData.fromView`
  // divide pelo `devicePixelRatio`. Passar pontos aqui dava recortes
  // duas ou três vezes maiores do que a realidade, e o teste falharia
  // por um ecrã que não existe.
  final recorte = FakeViewPadding(top: d.topo * d.dpr, bottom: d.fundo * d.dpr);
  tester.view.viewPadding = recorte;
  tester.view.padding = recorte;

  // `viewInsets` e não `padding`: são coisas diferentes e o `Scaffold`
  // só reage à primeira. Pôr o teclado em `padding` dava um ecrã com
  // uma margem estranha em baixo e nenhuma das consequências reais.
  tester.view.viewInsets = FakeViewPadding(bottom: d.teclado * d.dpr);

  tester.platformDispatcher.textScaleFactorTestValue = d.escalaTexto;

  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Deixa o ecrã assentar sem exigir que TODAS as animações parem.
///
/// `pumpAndSettle` rebenta com "timed out" em qualquer ecrã que tenha um
/// `CircularProgressIndicator` à espera de dados — e um indicador de
/// progresso indeterminado nunca para. Aqui isso não é uma falha: um
/// ecrã em carregamento também tem de caber no telemóvel, e é
/// exatamente esse estado que mais vezes escapa aos testes.
Future<void> assentar(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  } on FlutterError {
    // Animação perpétua. Damos alguns fotogramas e seguimos: o layout
    // já foi calculado, e é o layout que estamos a medir.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}
