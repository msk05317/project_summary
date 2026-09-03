// 홈 화면 상단의 '전체 현황 요약' 카드 (시안 v2 + overflow fix).
//
// 변경 의도:
// - 시안 기준 KPI 4개 사이에 옅은 세로 구분선(#EEF1F5)이 들어가고,
//   각 숫자가 별도 컬러(블루/그린/오렌지/레드) 로 강조됨.
// - 우측 상단 보조 문구는 'HH:mm 기준' 까지 표시.
// - 좌측 상단 아이콘을 차트 형태로 교체.
// - 진행률 바 두께를 키우고, 진행 중 컬러(summaryInProgress)로 통일.
//
// Overflow fix (1.0px):
// - IntrinsicHeight 안에서 _KpiCell 의 텍스트 baseline 계산 + 라벨 높이 합산이
//   부모가 추정한 높이보다 미세하게 커서 BOTTOM OVERFLOWED BY 1.0 PIXELS 가 떴음.
// - 해결: KPI 행 자체에 고정 높이(_kpiRowHeight)를 부여하고,
//         각 셀 안에서 mainAxisSize.min + 약간의 여유 라인 높이로 안정화.

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../models/dashboard.dart';

class SummaryCard extends StatelessWidget {
  // 집계된 요약 데이터 (총수/진행중/정상/주의/지연/진행률).
  final DashboardSummary summary;

  // 우측 상단 보조 안내 텍스트.
  // - 예: '오늘 09:12 기준'
  // - null/빈 문자열이면 우측 영역을 비웁니다.
  final String? rightCaption;

  const SummaryCard({
    super.key,
    required this.summary,
    this.rightCaption,
  });

  // KPI 행의 고정 높이.
  // - 숫자(22) + gap(4) + 라벨(13) + 위/아래 여유 = 약 58px 면 1.0px 오버플로우가 안 남.
  static const double _kpiRowHeight = 60;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.reportCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ────────────────────────────────
          // 헤더: 좌측 타이틀 + 우측 보조 캡션
          // ────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: AppColors.reportHeading,
              ),
              const SizedBox(width: 6),
              Text(
                '전체 현황 요약',
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.reportHeading,
                ),
              ),
              const Spacer(),
              if ((rightCaption ?? '').isNotEmpty)
                Text(
                  rightCaption!,
                  style: AppText.caption.copyWith(
                    color: AppColors.reportBody,
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.x3),

          // ────────────────────────────────
          // KPI 4분할
          // - IntrinsicHeight 대신 고정 높이를 사용해 1.0px 오버플로우를 차단
          // - 칸 사이 1px 구분선(AppColors.dividerSoft)
          // - 각 숫자 색상은 SummaryCard 전용 토큰
          // ────────────────────────────────
          SizedBox(
            height: _kpiRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _KpiCell(
                    // 프로젝트 단위 집계에서는 첫 칸이 '전체'(집계 대상 프로젝트)
                    value: summary.byProject
                        ? summary.total
                        : summary.inProgress,
                    label: summary.byProject ? summary.unitLabel : '진행 중',
                    color: AppColors.summaryInProgress,
                  ),
                ),
                const _VDivider(),
                Expanded(
                  child: _KpiCell(
                    value: summary.normal,
                    label: '정상',
                    color: AppColors.summaryNormal,
                  ),
                ),
                const _VDivider(),
                Expanded(
                  child: _KpiCell(
                    value: summary.warning,
                    label: '주의',
                    color: AppColors.summaryCaution,
                  ),
                ),
                const _VDivider(),
                Expanded(
                  child: _KpiCell(
                    value: summary.delayed,
                    label: '지연',
                    color: AppColors.summaryDelayed,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.x4),

          // ────────────────────────────────
          // 진행률 라벨 + 퍼센트
          // - 데이터가 0건이면 '-' 로 표시 (의미: 데이터 없음)
          // - 1건 이상이면 N% 로 표시
          // ────────────────────────────────
          Builder(
            builder: (context) {
              final pct = summary.progressPercentOrNull;
              final hasData = pct != null;
              final clamped = (pct ?? 0).clamp(0, 100);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '전체 진행률',
                        style: AppText.caption
                            .copyWith(color: AppColors.reportBody),
                      ),
                      const Spacer(),
                      Text(
                        hasData ? '$clamped%' : '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: hasData
                              ? AppColors.summaryInProgress
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // 게이지
                  // - 데이터 없음이면 회색 트랙만 보임 (value=0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: hasData ? clamped / 100.0 : 0.0,
                      backgroundColor: AppColors.dividerSoft,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.summaryInProgress,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// 단일 KPI 셀 — 큰 숫자 + 라벨 세로 배치.
// - 부모가 고정 높이를 주므로 mainAxisSize.min + 중앙 정렬만 하면 됨.
// - 라인 높이(height) 를 살짝 키워 한국어 라벨에서도 base line 잘림 방지.
class _KpiCell extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _KpiCell({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.caption.copyWith(
            color: AppColors.reportBody,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

// KPI 칸 사이 세로 구분선.
// - 부모(SizedBox 고정 높이) 안에서 자연스럽게 늘어남.
class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.dividerSoft,
    );
  }
}
