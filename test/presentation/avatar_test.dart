import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme/app_colors.dart';
import 'package:gym_saas/presentation/widgets/design_system.dart';
import 'package:gym_saas/presentation/widgets/person_avatar.dart';

/// Todos os avatares eram o mesmo gradiente vermelho da marca, o que
/// transformava a tira da turma numa fila de cartões iguais — e é
/// precisamente aí que o instrutor precisa de distinguir doze pessoas de
/// relance, a meio da aula.
void main() {
  group('cor por pessoa', () {
    test('a mesma pessoa tem sempre a mesma cor', () {
      // Um avatar que muda de cor entre sessões deixa de servir para
      // reconhecer alguém.
      expect(
          Avatar.colorsOf('Rita Ferreira'), Avatar.colorsOf('Rita Ferreira'));
    });

    test('ignora maiúsculas e espaços à volta', () {
      // "rita ferreira" e "Rita Ferreira " são a mesma pessoa escrita
      // por duas mãos diferentes.
      expect(Avatar.colorsOf('  RITA FERREIRA '),
          Avatar.colorsOf('Rita Ferreira'));
    });

    test('pessoas diferentes tendem a ter cores diferentes', () {
      // Não é garantido para todos os pares — são oito cores — mas numa
      // turma pequena tem de separar. Se isto falhar, a paleta ficou
      // demasiado curta ou a dispersão má.
      final cores = {
        for (final nome in [
          'Rita Ferreira',
          'João Martins',
          'Ana Costa',
          'Bruno Dias',
        ])
          Avatar.colorsOf(nome),
      };
      expect(cores.length, greaterThanOrEqualTo(3));
    });

    test('um nome vazio não rebenta', () {
      expect(Avatar.colorsOf(''), AppColors.avatarPalette.first);
      expect(Avatar.colorsOf('   '), AppColors.avatarPalette.first);
    });
  });

  group('PersonAvatar', () {
    // O avatar recebe o URL já feito — não vai buscá-lo ao Storage.
    // Ver `person_avatar.dart`: antes era um pedido de rede por pessoa.
    Widget host({String? photoUrl}) {
      return MaterialApp(
        home: Scaffold(
          body: PersonAvatar(name: 'Rita Ferreira', photoUrl: photoUrl),
        ),
      );
    }

    testWidgets('sem foto, mostra as iniciais', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('RF'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('um URL vazio conta como não ter foto', (tester) async {
      // O documento pode ter o campo a '' em vez de ausente; sem esta
      // guarda pedia-se uma imagem a um URL que não existe.
      await tester.pumpWidget(host(photoUrl: ''));
      await tester.pumpAndSettle();

      expect(find.text('RF'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('com foto, pede exatamente o URL que recebeu', (tester) async {
      const url = 'https://exemplo.test/avatar.jpg?alt=media&token=abc';
      await tester.pumpWidget(host(photoUrl: url));
      await tester.pump();

      // `cacheWidth` faz o `Image.network` embrulhar o provider num
      // `ResizeImage` — o URL está lá dentro.
      final image = tester.widget<Image>(find.byType(Image));
      final resized = image.image as ResizeImage;
      expect((resized.imageProvider as NetworkImage).url, url);
    });

    testWidgets('descodifica no tamanho em que é mostrado, não no do ficheiro',
        (tester) async {
      // A foto tem 160px de lado e o círculo 34. Sem isto, cinquenta
      // avatares são ~5 MB de bitmaps para desenhar cinquenta círculos
      // de um centímetro.
      await tester.pumpWidget(host(photoUrl: 'https://exemplo.test/a.jpg'));
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      final ratio = tester.view.devicePixelRatio;
      expect((image.image as ResizeImage).width, (34 * ratio).round());
    });

    testWidgets('enquanto a imagem não chega, as iniciais ficam no lugar',
        (tester) async {
      // Sem isto havia um buraco cinzento em cada linha até a imagem
      // resolver — e numa lista de cinquenta pessoas são cinquenta
      // buracos.
      await tester.pumpWidget(host(photoUrl: 'https://exemplo.test/a.jpg'));
      await tester.pump(); // sem `settle`: ainda não há frame nenhum

      expect(find.text('RF'), findsOneWidget);
    });

    testWidgets('se a imagem falhar, volta às iniciais', (tester) async {
      // No ambiente de teste um pedido de rede falha sempre, que é
      // exatamente o caso que isto quer cobrir: URL partido, ficheiro
      // apagado à mão, sem rede.
      await tester.pumpWidget(host(photoUrl: 'https://exemplo.test/a.jpg'));
      await tester.pumpAndSettle();

      expect(find.text('RF'), findsOneWidget);
    });
  });
}
