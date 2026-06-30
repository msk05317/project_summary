// ============================================================
// File: lib/components/tracker_row.dart
// Purpose: 4단계 흐름(원자재/입고/생산/납기)을 가로로 묶음
// 사용처: ProductBlock 내부
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';
import 'tracker_step.dart';

class TrackerStepData {
  final String label;
  final String status;
  final double percent;
  final String? fraction;
  final String? detail;

  const TrackerStepData({
    required this.label,
    required this.status,
    required this.percent,
    this.fraction,
    this.detail,
  });
}

class TrackerRow extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final List<TrackerStepData> steps; // 보통 길이 4
  final bool compact;

  const TrackerRow({
    super.key,
    required this.steps,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: TrackerStep(
              label: steps[i].label,
              status: steps[i].status,
              percent: steps[i].percent,
              fraction: steps[i].fraction,
              detail: steps[i].detail,
              compact: compact,
            ),
          ),
          if (i != steps.length - 1)
            // 단계 사이 연결선
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 9),
                height: 2,
                color: AppColors.borderDefault,
              ),
            ),
        ],
      ],
    );
  }
}
