// ============================================================
// File: lib/components/tracker_step.dart
// Purpose: 4단계 흐름의 한 단계 (원자재/입고/생산/납기) 표시
// 사용처: TrackerRow 내부
// 모드:
//   - compact: dot + label + percent
//   - full:    compact + fraction + detail
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

class TrackerStep extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final String label;      // '원자재', '입고', '생산', '납기'
  final String status;     // 'RED'/'YELLOW'/'GREEN'/'GRAY'
  final double percent;    // 0.0 ~ 100.0
  final String? fraction;  // 예: '108 / 640'
  final String? detail;    // 예: '잔량 532'
  final bool compact;      // true: 사업부 첫 화면, false: 카드 상세

  const TrackerStep({
    super.key,
    required this.label,
    required this.status,
    required this.percent,
    this.fraction,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fromStatus(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // dot
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppText.captionStrong),
        const SizedBox(height: 2),
        Text(
          '${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color == AppColors.statusGray
                ? AppColors.textMute
                : color,
          ),
        ),
        if (!compact && fraction != null && fraction!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(fraction!, style: AppText.caption),
        ],
        if (!compact && detail != null && detail!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(detail!, style: AppText.caption, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}
