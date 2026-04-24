import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Couleurs primaires — bleu marine profond (identité ExamSim)
  static const Color primary = Color(0xFF0A1172);
  static const Color primaryDark = Color(0xFF060B4F);
  static const Color primaryLight = Color(0xFF1E2FA0);

  // Accent — jaune/or (boutons CTA, badges actifs)
  static const Color accent = Color(0xFFF5B731);
  static const Color accentDark = Color(0xFFD99A10);
  static const Color accentLight = Color(0xFFFDD46A);

  // Fond et surfaces
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFEEF1F8);

  // Textes
  static const Color textPrimary = Color(0xFF0D0D0D);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFFB0B8C8);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnAccent = Color(0xFF0A1172);

  // Statuts épreuves
  static const Color statusOpen = Color(0xFF22C55E);       // Ouverte
  static const Color statusActive = Color(0xFFF5B731);     // En cours
  static const Color statusLocked = Color(0xFF6B7280);     // Verrouillée
  static const Color statusDone = Color(0xFF3B82F6);       // Terminée
  static const Color statusCorrecting = Color(0xFFF97316); // Correction en cours
  static const Color statusPublished = Color(0xFF8B5CF6);  // Résultats publiés

  // Matières (couleurs distinctives)
  static const Color mathColor = Color(0xFF3B82F6);
  static const Color physicsColor = Color(0xFF8B5CF6);
  static const Color svtColor = Color(0xFF22C55E);
  static const Color frenchColor = Color(0xFFF97316);
  static const Color philoColor = Color(0xFFEC4899);
  static const Color historyColor = Color(0xFF14B8A6);
  static const Color chemistryColor = Color(0xFFEF4444);

  // Feedback
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Dividers et bordures
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFD1D5DB);

  // Overlay
  static const Color overlay = Color(0x80000000);
  static const Color shimmerBase = Color(0xFFEEF1F8);
  static const Color shimmerHighlight = Color(0xFFF5F7FA);

  // Gradient principal (fond écran login)
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF060B4F), Color(0xFF0A1172), Color(0xFF1E2FA0)],
    stops: [0.0, 0.5, 1.0],
  );

  // Gradient accent
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5B731), Color(0xFFFFD166)],
  );
}
