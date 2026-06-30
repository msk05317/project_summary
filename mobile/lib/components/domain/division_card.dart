// ============================================================
// File: lib/components/division_card.dart
// Purpose: 사업부 1개를 대표하는 카드 (HOME 화면용)
// 사용처: HOME 사업부 진행현황 리스트
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../base/status_badge.dart';

class DivisionCard extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final String label;       // '블룸', '반도체사업부' ...
  final String status;      // 'RED' / 'YELLOW' / 'GREEN' / 'GRAY'
  final String? subtitle;   // 예: '지연 2 · 임박 0'
  final VoidCallback? onTap;

  const DivisionCard({
    super.key,
    required this.label,
    required this.status,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(AppSpacing.rLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.rLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.rLg),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            children: [
              // ------------------------------------------------
              // 좌측: 사업부명 + 부가설명
              // ------------------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.h2),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.x1),
                      Text(subtitle!, style: AppText.caption),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x3),

              // ------------------------------------------------
              // 우측: 상태 배지
              // ------------------------------------------------
              StatusBadge(status: status),
            ],
          ),
        ),
      ),
    );
  }
}
