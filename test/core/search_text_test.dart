import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/utils/search_text.dart';

/// Fase 11 — a pesquisa das listas de gestão.
///
/// Em português, ignorar acentos não é polimento: quem procura escreve
/// "joao" à pressa, quem se inscreveu escreveu "João".
void main() {
  group('searchNormalize', () {
    test('tira acentos e passa a minúsculas', () {
      expect(searchNormalize('João'), 'joao');
      expect(searchNormalize('ANTÓNIO'), 'antonio');
      expect(searchNormalize('Conceição'), 'conceicao');
    });

    test('deixa passar texto sem acentos', () {
      expect(searchNormalize('Rita'), 'rita');
    });

    test('apara espaços das pontas', () {
      expect(searchNormalize('  Rita  '), 'rita');
    });
  });

  group('searchMatches', () {
    test('encontra sem acentos escritos', () {
      expect(searchMatches('João Pedro', 'joao'), isTrue);
      expect(searchMatches('António', 'antonio'), isTrue);
    });

    test('encontra com acentos escritos, em texto sem eles', () {
      expect(searchMatches('Joao Pedro', 'joão'), isTrue);
    });

    test('é uma pesquisa parcial, não do início', () {
      expect(searchMatches('Rita Ferreira', 'ferr'), isTrue);
    });

    test('consulta vazia devolve tudo — não filtrar não é filtrar a zero', () {
      expect(searchMatches('Rita', ''), isTrue);
      expect(searchMatches('Rita', '   '), isTrue);
    });

    test('não inventa correspondências', () {
      expect(searchMatches('Rita Ferreira', 'joao'), isFalse);
    });
  });

  group('searchMatchesAny', () {
    test('basta um campo corresponder', () {
      // O caso real: procurar uma pessoa pelo nome OU pelo nº de sócio,
      // sem ter de decidir antes qual dos dois se vai escrever.
      expect(searchMatchesAny(['Rita Ferreira', '000142'], '142'), isTrue);
      expect(searchMatchesAny(['Rita Ferreira', '000142'], 'rita'), isTrue);
    });

    test('campos nulos não rebentam', () {
      expect(searchMatchesAny(['Rita', null], 'rita'), isTrue);
      expect(searchMatchesAny([null, null], 'rita'), isFalse);
    });

    test('nenhum campo corresponde', () {
      expect(searchMatchesAny(['Rita', '000142'], 'joao'), isFalse);
    });
  });
}
