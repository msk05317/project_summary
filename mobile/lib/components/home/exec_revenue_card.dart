// 경영진용 이번 달 매출 요약 카드.
//
// 지금까지 매출은 홈 → 사업부 → 프로젝트 3단계를 들어가야 볼 수 있었다.
// 임원이 앱을 열자마자 봐야 하는 숫자이므로 홈 최상단으로 끌어올린다.
//
// 표시 내용
//  - 이번 달 실적 매출 (크게)
//  - 계획 기준 예상 매출 + 달성률 게이지
//  - 출하 수량 계획 → 실적
//  - 자세한 내역(프로젝트별)은 카드를 눌러 '매출 상세' 화면에서 본다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../services/overview_service.dart';
import '../../utils/format.dart';

class ExecRevenueCard extends StatelessWidget {
  final OverviewSummary summary;
  final bool loading;
  final VoidCallback? onTap;

  const ExecRevenueCard({
    super.key,
    required this.summary,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _ExecSkeleton();

    if (!summary.loaded) {
      return _shell(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 18, color: AppColors.textMute),
            const SizedBox(width: 8),
            Expanded(
              child: Text('매출 현황을 불러오지 못했습니다',
                  style: AppText.body.copyWith(color: AppColors.textMute)),
            ),
          ],
        ),
      );
    }

    if (!summary.hasRevenue) {
      return _shell(
        child: Row(
          children: [
            const Icon(Icons.insights_outlined,
                size: 18, color: AppColors.textMute),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${Fmt.monthShort(summary.month)} 등록된 매출 계획이 없습니다',
                style: AppText.body.copyWith(color: AppColors.textMute),
              ),
            ),
          ],
        ),
      );
    }

    final rate = summary.achievement;
    final ratio = rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0);
    final ahead = rate != null && rate >= 100;
    final barColor = rate == null
        ? AppColors.statusGray
        : (rate >= 100
            ? AppColors.summaryNormal
            : (rate >= 80 ? AppColors.summaryInProgress : AppColors.summaryCaution));

    return _shell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${Fmt.monthShort(summary.month)} 매출',
                  style: AppText.h2),
              const SizedBox(width: 6),
              Text('실적 / 계획',
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
              const Spacer(),
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textMute),
            ],
          ),
          const SizedBox(height: 10),

          // 실적 금액 (크게) + 계획 대비
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.moneyShort(summary.revenue),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              Text('/ ${Fmt.moneyShort(summary.planRevenue)}',
                  style: AppText.body.copyWith(color: AppColors.textMute)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rate == null ? '-' : '달성 $rate%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: barColor,
                  ),
                ),
              ),
            ],
          ),
          // 축약값과 정확한 금액이 같으면(10만 미만) 같은 줄을 두 번 보여줄 이유가 없다.
          if (Fmt.money(summary.revenue) != Fmt.moneyShort(summary.revenue)) ...[
            const SizedBox(height: 4),
            Text(
              Fmt.money(summary.revenue),
              style: AppText.caption.copyWith(color: AppColors.textMute),
            ),
          ],

          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.statusGraySoft,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 10),

          // 수량 + 초과/미달 한 줄 요약
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '출하 (계획 → 실적)',
                  value: '${Fmt.qty(summary.qtyPlan)} → ${Fmt.qty(summary.qtyActual)}대',
                ),
              ),
              Container(width: 1, height: 26, color: AppColors.borderSoft),
              Expanded(
                child: _MiniStat(
                  label: ahead ? '계획 대비 초과' : '계획 대비 부족',
                  value: Fmt.moneyShort(
                      (summary.revenue - summary.planRevenue).abs()),
                  color: ahead ? AppColors.summaryNormal : AppColors.summaryCaution,
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  Widget _shell({required Widget child, VoidCallback? onTap}) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: box,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _MiniStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.caption.copyWith(color: AppColors.textMute),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(value,
            style: AppText.bodyStrong.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _ExecSkeleton extends StatelessWidget {
  const _ExecSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.statusGraySoft,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(90, 14),
          const SizedBox(height: 12),
          bar(170, 28),
          const SizedBox(height: 14),
          bar(double.infinity, 8),
        ],
      ),
    );
  }
}
