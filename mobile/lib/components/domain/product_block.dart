// ============================================================
// File: lib/components/product_block.dart
// Purpose: 제품 1개 단위 블록 (제품명 + TrackerRow)
// 사용처: 블룸 카드 안 제품별 진행 현황
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';
import 'tracker_row.dart';

class ProductBlock extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final String name;                  // 'YFP', 'KPE CORVA' ...
  final List<TrackerStepData> steps;  // 4 steps
  final bool compact;

  const ProductBlock({
    super.key,
    required this.name,
    required this.steps,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppSpacing.rMd),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------------
          // 제품 타이틀
          // ------------------------------------------------------------
          Text(name, style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.x2),

          // ------------------------------------------------------------
          // 4단계 tracker
          // ------------------------------------------------------------
          TrackerRow(steps: steps, compact: compact),
        ],
      ),
    );
  }
}
