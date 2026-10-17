import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Marka rengi — yeni uygulamada sadece bunu değiştirmen yeterli.
/// (Share Extension butonundaki renk ayrıca native kodda tanımlı.)
const Color kBrandColor = Color(0xFFFF6B35);

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kBrandColor,
      brightness: brightness,
    ).copyWith(
      // Material'ın seed algoritması marka rengini koyulaştırır;
      // primary'yi canlı marka renginde sabitliyoruz.
      primary: kBrandColor,
      onPrimary: Colors.white,
    );

    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    // Başlık: Plus Jakarta Sans, gövde: Inter.
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        textStyle: base.textTheme.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        textStyle: base.textTheme.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        textStyle: base.textTheme.titleLarge,
        fontWeight: FontWeight.w600,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }
}
