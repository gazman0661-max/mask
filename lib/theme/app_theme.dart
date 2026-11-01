import 'package:flutter/material.dart';

/// Marka paleti (ikonla aynı): koyu bordo zemin, altın vurgular, fildişi taş,
/// ceviz ahşap ıstaka, bordo çuha masa.
class AppColors {
  static const bg = Color(0xFF3A0B19);
  static const bgTop = Color(0xFF5B1528);
  static const surface = Color(0xFF4A0F21);
  static const surfaceLight = Color(0xFF6A1B33);
  static const gold = Color(0xFFE3B24E);
  static const goldLight = Color(0xFFF0C25A);
  static const felt = Color(0xFF7A1E38);
  static const feltDark = Color(0xFF4F1022);
  static const wood = Color(0xFF8A5A33);
  static const woodDark = Color(0xFF4B2A15);
  static const woodLight = Color(0xFFA77347);
  static const tileCream = Color(0xFFFBF6EA);
  static const tileEdge = Color(0xFFC9BE9F);
  static const tileYellow = Color(0xFFE19B00);
  static const tileBlue = Color(0xFF1E6BD0);
  static const tileBlack = Color(0xFF1B1B22);
  static const tileRed = Color(0xFFD0342C);
  static const teal = Color(0xFF7A1E38);
  static const tealDark = Color(0xFF5B1528);
  static const wine = Color(0xFF7A1E38);
  static const wineDark = Color(0xFF4F1022);
  static const orange = Color(0xFFF08A1C);
  static const orangeDark = Color(0xFFB85E08);
  static const green = Color(0xFF3FBF3F);
  static const greenDark = Color(0xFF1F7A25);
  static const blueBtn = Color(0xFF1E8FD0);
  static const blueBtnDark = Color(0xFF0F5E93);
  static const navy = Color(0xFF4A0F21);
  static const good = Color(0xFF47C46B);
  static const bad = Color(0xFFE5604F);

  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bg],
  );
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
            primary: AppColors.gold, surface: AppColors.surface),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}
