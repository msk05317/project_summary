// ============================================================
// File: lib/components/report/status_summary_row.dart
// Section: Report / Status summary
// Figma:  Report / 현황 카드 (★ 총 42개 모델 중 양산 2종, 진행중 40종)
// 역할:    보고 상세 화면의 "현황" 한 줄 + 그것을 감싸는 카드
// 토큰:    bg/card, border/default, radius/lg, typo/h2, typo/body, color/status*
// 사용처:  보고 상세 화면 — ReportTitleCard 다음
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../base/base_card.dart';

// ------------------------------------------------------------
// 1) 별 마커 + 본문 한 줄 (재사용 가능)
// ------------------------------------------------------------
class StatusSummaryRow extends StatelessWidget {
  // 본문 텍스트 (예: '총 42개 모델 중 양산 2종, 진행중 40종')
  final String text;

  // 상태값 — 별 색을 결정
  // 'RED' | 'YELLOW' | 'GREEN' | 'GRAY' (기본 GRAY)
  final String status;

  // 별 표시 여부 (false 면 그냥 텍스트만)
  final bool showStar;

  const StatusSummaryRow({
    super.key,
    required this.text,
    this.status = 'GRAY',
    this.showStar = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fromStatus(status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStar) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.star_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
        ],
        Expanded(
          child: Text(
            text,
            style: AppText.bodyStrong.copyWith(color: AppColors.reportHeading),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 2) "현황" 카드 — 헤더 + StatusSummaryRow 한 묶음
//    보고 상세 화면에서 그대로 쓰는 형태
// ------------------------------------------------------------
class StatusSummaryCard extends StatelessWidget {
  // 카드 헤더 (기본값 '현황')
  final String heading;

  // 본문 텍스트
  final String text;

  // 별 색 결정용 상태
  final String status;

  const StatusSummaryCard({
    super.key,
    this.heading = '현황',
    required this.text,
    this.status = 'GRAY',
  });

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      borderColor: AppColors.reportCardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============================================
          // 헤더 — 예: 현황
          // ============================================
          Text(heading, style: AppText.h2.copyWith(color: AppColors.reportHeading)),

          const SizedBox(height: AppSpacing.x3),

          // 헤더 아래 얇은 구분선
          Container(
            height: 1,
            color: AppColors.borderSoft,
          ),

          const SizedBox(height: AppSpacing.x3),

          // ============================================
          // 본문 — 별 + 텍스트
          // ============================================
          StatusSummaryRow(
            text: text,
            status: status,
          ),
        ],
      ),
    );
  }
}
