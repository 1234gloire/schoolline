import 'package:flutter/material.dart';

/// Couleurs sémantiques (fond, surfaces, texte) — varient clair / sombre.
@immutable
class ExamSimPalette extends ThemeExtension<ExamSimPalette> {
  const ExamSimPalette({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.divider,
    required this.border,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color divider;
  final Color border;
  final Color shimmerBase;
  final Color shimmerHighlight;

  static const ExamSimPalette light = ExamSimPalette(
    background: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEEF1F8),
    textPrimary: Color(0xFF0D0D0D),
    textSecondary: Color(0xFF6B7280),
    textHint: Color(0xFFB0B8C8),
    divider: Color(0xFFE5E7EB),
    border: Color(0xFFD1D5DB),
    shimmerBase: Color(0xFFEEF1F8),
    shimmerHighlight: Color(0xFFF5F7FA),
  );

  static const ExamSimPalette dark = ExamSimPalette(
    background: Color(0xFF0B0D14),
    surface: Color(0xFF131620),
    surfaceVariant: Color(0xFF1C2030),
    textPrimary: Color(0xFFF3F4F6),
    textSecondary: Color(0xFF9CA3AF),
    textHint: Color(0xFF6B7280),
    divider: Color(0xFF2A3142),
    border: Color(0xFF3D4558),
    shimmerBase: Color(0xFF1A1F2E),
    shimmerHighlight: Color(0xFF232838),
  );

  @override
  ExamSimPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? divider,
    Color? border,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return ExamSimPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  ExamSimPalette lerp(ThemeExtension<ExamSimPalette>? other, double t) {
    if (other is! ExamSimPalette) return this;
    return ExamSimPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}

extension ExamSimPaletteX on BuildContext {
  ExamSimPalette get palette {
    return Theme.of(this).extension<ExamSimPalette>() ?? ExamSimPalette.light;
  }
}
