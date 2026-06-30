// ============================================================
// File: lib/components/base/deadline_pill.dart
// Section: Base / Deadline pill
// Figma:  Pill / Deadline
// Tokens: color/status*
// 사용처: D-1, D-3 등 기한 표시 (Issue/Project 카드)
// ============================================================
import 'package:flutter/material.dart';
import '../../design/design.dart';

enum DeadlineTone { normal, warn, over }

class DeadlinePill extends StatelessWidget {
  final String text;          // 'D-1', 'D-3', 'D+2'
  final DeadlineTone tone;    // 색조

  const DeadlinePill({
    super.key,
    required this.text,
    this.tone = DeadlineTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tone) {
      case DeadlineTone.over:
        bg = AppColors.statusRedSoft;
        fg = AppColors.statusRed;
        break;
      case DeadlineTone.warn:
        bg = AppColors.statusYellowSoft;
        fg = AppColors.statusYellow;
        break;
      case DeadlineTone.normal:
        bg = AppColors.statusGraySoft;
        fg = AppColors.textSub;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
