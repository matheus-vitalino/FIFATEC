import 'package:flutter/material.dart';

class AppColors {
  // Primárias
  static const Color primary = Color(0xFF1B5E20);       // Verde escuro
  static const Color primaryLight = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF003300);
  static const Color accent = Color(0xFFFFD600);         // Amarelo ouro
  static const Color accentLight = Color(0xFFFFFF52);

  // Fundo
  static const Color background = Color(0xFF0F1923);     // Azul quase preto
  static const Color surface = Color(0xFF1A2634);
  static const Color surfaceLight = Color(0xFF243447);
  static const Color card = Color(0xFF1E2D3D);

  // Texto
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0BEC5);
  static const Color textHint = Color(0xFF607D8B);

  // Status
  static const Color win = Color(0xFF4CAF50);
  static const Color loss = Color(0xFFE53935);
  static const Color draw = Color(0xFFFF9800);
  static const Color goal = Color(0xFFFFD600);

  // Gradientes
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0F1923), Color(0xFF1A2634)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1E2D3D), Color(0xFF243447)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFFD600), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}