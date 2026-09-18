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
import '../../services/revenue_service.dart';
import '../../utils/format.dart';

class ExecRevenueCard extends StatelessWidget {
  final OverviewSummary summary;

  /// 엑셀에서 받은 사업부 매출. 올린 적이 있으면 이걸 그린다.
  ///
  /// 모델 판가 × 수량은 추정이다 — 하바플레이트 55종 중 52종이 3,400 으로
  /// 일괄 입력돼 있어서 9월이 18만 달러 부풀어 있었다. 확정 금액은 일일보고
  /// 에 있다. 아직 한 번도 안 올렸으면 예전처럼 모델에서 계산한다.
  final RevenueMonth? revenue;

  final bool loading;
  final VoidCallback? onTap;

  const ExecRevenueCard({
    super.key,
    required this.summary,
    this.revenue,
    this.loading = false,
    this.onTap,
  });

  /// 이 숫자에 무엇이 들어 있는지 한 줄로. '반도체 7개 프로젝트' 면 충분하다.
  /// 무엇이 안 들어갔는지(주차 계획 미등록)까지 적으면 카드가 변명처럼 읽힌다.
  String _coverage() {
    const names = {
      'semiconductor': '반도체',
      'automotive': '자동차',
      'ess': 'ESS',
      'bloom': '블룸',
      'network': '네트워크',
      'pcb': 'PCB',
    };
    final inn = <String>{};
    var n = 0;
    for (final p in summary.items) {
      final d = names[p.divisionId] ?? (p.divisionId ?? '');
      if (d.isEmpty) continue;
      if (p.planRevenue > 0 || p.revenue > 0) {
        inn.add(d);
        n++;
      }
    }
    if (inn.isEmpty) return '';
    return '${inn.join(' · ')} $n개 프로젝트';
  }

  /// 홈에서는 사업부 통 매출 하나만 본다. 어디서 나왔는지는 눌러서
  /// '매출 상세' 에서 본다 — 카드에 묶음을 늘어놓으면 홈이 길어진다.
  Widget _buildFromExcel(BuildContext context, RevenueMonth r) {
    // 짝은 타겟이다. 예상은 관리자 화면과 부서별 달성률에서만 쓴다 —
    // 예상은 지금 그렇게 될 것 같은 값이고, 타겟은 그렇게 만들기로 한 값이다.
    final rate = r.targetRate;
    final est = r.hasTarget;
    return _shell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${Fmt.monthShort(r.month)} 매출',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.h2),
          ),
          if (onTap != null) ...[
            Text('상세 보기',
                textAlign: TextAlign.right,
                style: AppText.caption.copyWith(color: AppColors.textMute)),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMute),
          ],
        ]),
        const SizedBox(height: 8),
        Text(est ? '실적 / 타겟' : '실적',
            style: AppText.caption.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 3),
        // Spacer 는 flex 1 의 Expanded 다. 옆의 Flexible 도 flex 1 이라
        // 남은 폭이 셋으로 똑같이 나뉘었고, 카드가 넓은데도 실적이 1/3 만
        // 받아 '$67…' 로 잘렸다. 왼쪽 묶음을 Expanded 하나로 감싸고,
        // 그 안에서는 실적이 제 폭을 먼저 가져간다 — 헤드라인 숫자가
        // 잘리면 카드를 볼 이유가 없다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(Fmt.moneyShort(r.actual),
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: AppColors.textMain)),
                  if (est) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('/ ${Fmt.moneyShort(r.target)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(
                              fontSize: 16, color: AppColors.textMute)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 예상을 아직 안 넣은 달은 달성률을 지어내지 않는다.
            Text(est ? (rate == null ? '-' : '$rate%') : '타겟 미등록',
                style: est
                    ? AppText.bodyStrong.copyWith(fontSize: 15)
                    : AppText.caption.copyWith(color: AppColors.textHint)),
          ],
        ),
        const SizedBox(height: 11),
        // 예상이 없다고 막대를 빼면 카드가 접혔다 펴졌다 한다.
        // 빈 막대로 두면 '아직 안 넣었다' 가 그대로 보인다.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (!est || rate == null) ? 0.0 : (rate / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppColors.statusGraySoft,
            valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.summaryInProgress),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _MiniStat(
                  label: '남은 타겟',
                  value: est ? Fmt.moneyShort(r.targetLeft) : '—')),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: AppColors.borderSoft,
          ),
          Expanded(
              child: _MiniStat(label: '연간 누적', value: Fmt.moneyShort(r.ytd))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _ExecSkeleton();

    // 엑셀을 한 번이라도 올렸으면 그 값이 맞다.
    final r = revenue;
    if (r != null && r.loaded && r.hasData) {
      return _buildFromExcel(context, r);
    }

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
          if (_coverage().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_coverage(),
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
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
              // 구분선에 글자가 붙지 않게 양옆으로 띄운다.
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.borderSoft,
              ),
              Expanded(
                // '계획 대비 부족 $750만' 이라고 적었는데, 그 $751만 중
                // $735만은 아직 안 온 3주치 계획이었다. 못 채운 게 아니라
                // 아직 안 온 것이라 부족이라고 부를 수 없다.
                child: summary.hasWeekSplit && summary.openWeeks > 0
                    ? _MiniStat(
                        label: '남은 ${summary.openWeeks}주 계획',
                        value: Fmt.moneyShort(summary.openPlanRevenue),
                      )
                    : _MiniStat(
                        label: ahead ? '계획 대비 초과' : '계획 대비 부족',
                        value: Fmt.moneyShort(
                            (summary.revenue - summary.planRevenue).abs()),
                        color: ahead
                            ? AppColors.summaryNormal
                            : AppColors.summaryCaution,
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
