import 'package:flutter/material.dart';

class AppColors {
  // ─── Identidade FIFATEC: Midnight Navy + Electric Lime ─────────────────────
  static const Color primary = Color(0xFFB8FF3A);       // Electric Lime
  static const Color primaryLight = Color(0xFFD4FF7A);  // Lime claro (hover/shine)
  static const Color primaryDark = Color(0xFF6FAF0E);   // Field Green

  static const Color accent = Color(0xFF9ADE20);        // Kick Green
  static const Color accentLight = Color(0xFFCCF56B);   // Lime suave
  static const Color accentDark = Color(0xFF3D6B05);    // Pitch Dark
  static const Color accentGold = Color(0xFFFFD166);    // Mantido para troféus/ouro

  // ─── Fundo ─────────────────────────────────────────────────────────────────
  static const Color background = Color(0xFF0D1B2A);    // Midnight Navy
  static const Color surface = Color(0xFF1A2E45);       // Deep Steel
  static const Color surfaceLight = Color(0xFF2B4A6B);  // Atlantic
  static const Color card = Color(0xFF162336);          // Entre Navy e Steel
  static const Color cardElevated = Color(0xFF1E3450);  // Steel elevado
  static const Color border = Color(0xFF2B4A6B);        // Atlantic como borda

  // ─── Texto ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);   // White
  static const Color textSecondary = Color(0xFFE8F0F7); // Ice
  static const Color textHint = Color(0xFFA3B5C8);      // Silver Mist

  // ─── Status ────────────────────────────────────────────────────────────────
  static const Color win = Color(0xFFB8FF3A);           // Electric Lime
  static const Color loss = Color(0xFFFF5A6A);          // Mantido
  static const Color draw = Color(0xFFFFD166);          // Mantido
  static const Color goal = Color(0xFFD4FF7A);          // Lime claro

  // ─── Gradientes ────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFB8FF3A), Color(0xFF6FAF0E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF9ADE20), Color(0xFF3D6B05)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF1A2E45), Color(0xFF0D1B2A), Color(0xFF070F18)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1E3450), Color(0xFF162336)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFB8FF3A), Color(0xFF3D6A94)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD166), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
