// ============================================================
// File: lib/components/status_badge.dart
// Purpose: 상태(RED/YELLOW/GREEN/GRAY) + D±N 일자 배지
// 사용처: 카드 헤더 우측, 사업부 카드 상단
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

class StatusBadge extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final String status;   // 'RED' | 'YELLOW' | 'GREEN' | 'GRAY'
  final String? label;   // 예: 'D+3', 'RISK', '지연 2'

  const StatusBadge({
    super.key,
    required this.status,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fromStatus(status);
    final text = (label == null || label!.isEmpty) ? status : label!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x3,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.rXl),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
