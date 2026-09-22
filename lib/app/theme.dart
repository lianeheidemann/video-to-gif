import 'package:flutter/material.dart';

import '../core/models/size_estimate.dart';

const _seed = Color(0xFFC9A8FF);
const _darkBackground = Color(0xFF101014);
const _darkCard = Color(0xFF1A191F);

/// Monta o ThemeData do app para o modo claro ou escuro.
///
/// A partir da cor semente [_seed], gera um ColorScheme via Material 3 e,
/// no modo escuro, substitui as cores de superfície por tons próprios
/// (mais neutros que os gerados automaticamente).
ThemeData buildTheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  // No escuro, troca as superfícies geradas pelo ColorScheme.fromSeed por
  // tons neutros definidos à mão, mantendo a cor primária.
  final scheme = brightness == Brightness.dark
      ? base.copyWith(
          primary: _seed,
          surface: _darkBackground,
          surfaceContainerLow: _darkCard,
          surfaceContainer: _darkCard,
          surfaceContainerHigh: const Color(0xFF211F28),
          surfaceContainerHighest: const Color(0xFF26232D),
        )
      : base;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? _darkBackground
        : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: brightness == Brightness.dark
          ? _darkCard
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selectedColor: brightness == Brightness.dark
          ? const Color(0xFF5D4D72)
          : scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    dividerColor: scheme.outlineVariant.withValues(alpha: 0.45),
  );
}

/// Cor associada a cada faixa de peso, usada no painel de estimativa.
Color verdictColor(SizeVerdict verdict, ColorScheme scheme) {
  return switch (verdict) {
    SizeVerdict.light => const Color(0xFF58C78C),
    SizeVerdict.good => const Color(0xFFB8B36A),
    SizeVerdict.heavy => const Color(0xFFE6A15D),
    SizeVerdict.tooHeavy => const Color(0xFFE57373),
  };
}
