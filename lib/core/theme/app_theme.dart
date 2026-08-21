import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Fase 10 — o tema escuro do mockup, a substituir a única linha que a app
/// teve das Fases 0-9 (`ThemeData(colorSchemeSeed: Colors.red,
/// useMaterial3: true)` — Material 3 CLARO por omissão).
///
/// Tipografia: o mockup usa Oswald (display — itálico, maiúsculas, títulos
/// e números) e Inter (corpo). Os `.ttf` que o HTML referencia (`fonts/`)
/// não vieram com o ficheiro, por isso vêm do `google_fonts` em vez de
/// assets locais. Consequência a saber: o pacote descarrega e cacheia as
/// fontes no primeiro arranque — sem rede, o Flutter cai para a fonte do
/// sistema e a app continua utilizável, só perde o carácter tipográfico.
/// Se isso for inaceitável para o produto final, a alternativa é obter os
/// `.ttf` e passá-los para `assets/fonts/` + `pubspec.yaml`, sem mexer em
/// mais nada além deste ficheiro.
abstract final class AppTheme {
  /// O "display" do mockup: Oswald, itálico, maiúsculas, com letter-spacing
  /// ligeiro. Usado em títulos de ecrã, números de estatística e cargas.
  /// Exposto porque nem tudo o que precisa deste estilo é um `TextTheme`
  /// slot (ex.: o "60 kg" vermelho dentro de uma linha de exercício).
  static TextStyle display({
    required double fontSize,
    Color color = AppColors.bone,
    FontWeight fontWeight = FontWeight.w600,
    // O mockup aperta a entrelinha nos títulos grandes de duas linhas
    // (`line-height:1.15`); nos tamanhos pequenos deixa a de origem.
    double? height,
  }) {
    return GoogleFonts.oswald(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.4,
      height: height,
    );
  }

  static ThemeData get dark {
    // `ColorScheme.dark` explícito em vez de `fromSeed`: o mockup define
    // cores concretas, e deixar o Material derivá-las de uma seed daria
    // tons aproximados que nunca baterão certo numa comparação lado a lado.
    const colorScheme = ColorScheme.dark(
      primary: AppColors.red,
      onPrimary: Colors.white,
      secondary: AppColors.red,
      onSecondary: Colors.white,
      surface: AppColors.panel,
      onSurface: AppColors.bone,
      surfaceContainerHighest: AppColors.panel2,
      error: AppColors.red,
      onError: Colors.white,
      outline: AppColors.dim,
    );

    final baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: AppColors.bone, displayColor: AppColors.bone);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.void_,
      canvasColor: AppColors.void_,
      textTheme: baseTextTheme.copyWith(
        // Títulos de ecrã e de secção herdam o "display" do mockup; o
        // resto fica Inter (corpo), como no CSS.
        titleLarge: display(fontSize: 18),
        titleMedium: display(fontSize: 15),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: AppColors.mute),
        labelSmall: baseTextTheme.labelSmall?.copyWith(color: AppColors.mute),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.void_,
        foregroundColor: AppColors.bone,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display(fontSize: 18),
      ),
      cardTheme: CardThemeData(
        color: AppColors.panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.bone,
        iconColor: AppColors.mute,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.cardBorder),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.panel2,
        labelStyle: const TextStyle(color: AppColors.mute),
        hintStyle: const TextStyle(color: AppColors.dim),
        helperStyle: const TextStyle(color: AppColors.dim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.bone,
          backgroundColor: AppColors.panel2,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.red),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF101012),
        indicatorColor: AppColors.statusFill(AppColors.red),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w600 : null,
            color: states.contains(WidgetState.selected)
                ? AppColors.red
                : AppColors.dim,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.red
                : AppColors.dim,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.panel2,
        contentTextStyle: TextStyle(color: AppColors.bone),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.panel2,
        side: BorderSide.none,
        labelStyle: const TextStyle(color: AppColors.bone, fontSize: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.red,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.red
              : AppColors.dim,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.red
              : AppColors.dim,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.red
              : Colors.transparent,
        ),
        side: const BorderSide(color: AppColors.dim, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}
