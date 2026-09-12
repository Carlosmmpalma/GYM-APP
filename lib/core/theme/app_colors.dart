import 'package:flutter/material.dart';

/// Fase 10 — os tokens de cor do mockup (`Functional/nxt-studio-screens.html`,
/// bloco `:root`), um-para-um. Até aqui a app não tinha tokens nenhuns: o
/// tema era uma única linha (`ThemeData(colorSchemeSeed: Colors.red)`),
/// clara, e cada ecrã usava `Colors.green`/`Colors.orange` à mão quando
/// precisava de cor — é por isso que a app "funciona mas não se parece com
/// o produto".
///
/// Os nomes seguem deliberadamente os do CSS (`void`, `panel`, `bone`,
/// `mute`, `dim`) em vez de nomes Material (`surface`, `onSurface`): quando
/// alguém comparar o ecrã com o mockup lado a lado, o token que procura no
/// CSS tem o mesmo nome aqui. O mapeamento para o `ColorScheme` do Material
/// é feito em `app_theme.dart`, num sítio só.
abstract final class AppColors {
  /// `--void` — fundo da app.
  static const void_ = Color(0xFF0B0B0C);

  /// `--panel` — fundo de card.
  static const panel = Color(0xFF17171A);

  /// `--panel2` — fundo de input, `IconBox`, chip.
  static const panel2 = Color(0xFF1F1F23);

  /// `--red` — cor de marca (ações primárias, destaques, tab ativa).
  static const red = Color(0xFFE11D2E);

  /// `--red-deep` — só usado no gradiente do avatar.
  static const redDeep = Color(0xFF7A0F1C);

  /// `--bone` — texto principal (não branco puro).
  static const bone = Color(0xFFF3F1EC);

  /// `--mute` — texto secundário.
  static const mute = Color(0xFF8B8B93);

  /// `--dim` — texto terciário/desativado, bordas de radio/checkbox.
  static const dim = Color(0xFF5B5B61);

  /// `--ok` — estado positivo (pago, em dia, ativo).
  static const ok = Color(0xFF22C55E);

  /// `--warn` — estado de aviso (em atraso, por aprovar).
  static const warn = Color(0xFFF5A524);

  /// Borda subtil dos cards — `rgba(255,255,255,.05)` no mockup.
  /// As cores dos avatares, quando a pessoa não tem foto.
  ///
  /// Todos os avatares eram o mesmo gradiente vermelho da marca, o que
  /// transformava a tira da turma numa fila de cartões iguais — e é
  /// precisamente aí que o instrutor precisa de distinguir doze pessoas
  /// de relance, a meio da aula.
  ///
  /// Escolhidas escuras o suficiente para o texto branco se ler por
  /// cima, e afastadas do vermelho da marca: no resto da app o vermelho
  /// quer dizer "ação" ou "atenção", e um avatar não é nem uma coisa
  /// nem outra.
  static const avatarPalette = <(Color, Color)>[
    (Color(0xFF2563EB), Color(0xFF1E3A8A)), // azul
    (Color(0xFF7C3AED), Color(0xFF4C1D95)), // violeta
    (Color(0xFF0891B2), Color(0xFF155E75)), // ciano
    (Color(0xFF059669), Color(0xFF065F46)), // verde
    (Color(0xFFD97706), Color(0xFF92400E)), // âmbar
    (Color(0xFFDB2777), Color(0xFF831843)), // rosa
    (Color(0xFF4F46E5), Color(0xFF312E81)), // índigo
    (Color(0xFF65A30D), Color(0xFF3F6212)), // lima
  ];

  static const cardBorder = Color(0x0DFFFFFF);

  /// Borda de input — `rgba(255,255,255,.08)`.
  static const inputBorder = Color(0x14FFFFFF);

  /// Fundo dos pills/tabs inativos — `rgba(255,255,255,.05)`.
  static const subtleFill = Color(0x0DFFFFFF);

  /// Fundo do `bar-track` — `rgba(255,255,255,.06)`.
  static const trackFill = Color(0x0FFFFFFF);

  /// Os pills do mockup usam a cor de estado a 10% sobre o fundo escuro
  /// (`rgba(34,197,94,.1)` etc.). Centralizado aqui para nenhum ecrã
  /// inventar a sua própria opacidade.
  static Color statusFill(Color statusColor) =>
      statusColor.withValues(alpha: 0.1);
}
