/// Normaliza texto para pesquisa: minúsculas e sem acentos.
///
/// Em português isto não é um detalhe. Um Gestor que escreve "joao" à
/// pressa tem de encontrar o "João", e "Antonio" tem de encontrar o
/// "António" — quem procura raramente escreve os acentos, e quem se
/// inscreveu escreveu-os quase sempre.
///
/// Sem pacote externo: o alfabeto português cabe num mapa, e o `intl`
/// (já presente) não faz remoção de diacríticos. Cobre também ü/ä/ö e
/// ñ, comuns em nomes de estrangeiros inscritos num ginásio cá.
String searchNormalize(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString().trim();
}

/// `true` se [haystack] contém [needle], ignorando acentos e
/// maiúsculas. Consulta vazia devolve sempre `true` — quem não escreveu
/// nada não está a filtrar nada.
bool searchMatches(String haystack, String needle) {
  final query = searchNormalize(needle);
  if (query.isEmpty) return true;
  return searchNormalize(haystack).contains(query);
}

/// Qualquer um dos campos serve. Usado onde uma pessoa pode ser
/// procurada por nome OU por número de sócio, sem obrigar quem procura
/// a escolher antes qual dos dois vai escrever.
bool searchMatchesAny(Iterable<String?> fields, String needle) {
  final query = searchNormalize(needle);
  if (query.isEmpty) return true;
  return fields.any(
    (field) => field != null && searchNormalize(field).contains(query),
  );
}

const _diacritics = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};
