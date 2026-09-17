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

  /// 실적이 들어온 마지막 날. '9/12 보고 기준' — 달성률이 낮아 보이는
  /// 이유가 여기 있다. 못 채운 게 아니라 아직 안 온 날이다.
  String _asOf(RevenueMonth r) {
    final p = r.asOf.split('-');
    if (p.length != 3) return '';
    return '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]} 보고 기준';
  }

  Widget _buildFromExcel(BuildContext context, RevenueMonth r) {
    // 계획이 아직 없으면 rate 가 null 이다. 0 으로 바꾸면 '못 채웠다' 가
    // 되는데, 실제로는 '아직 모른다' 다.
    final rate = r.rate;
    final hasActual = r.items.any((e) => e.actual > 0);
    // 보고서와 같은 묶음으로 보여준다 — 반도체 · 데이터 센터 · 우주항공 ·
    // 내부거래. 품목 스무 줄을 홈에 늘어놓으면 아무도 안 읽는다.
    // 묶음이 안 오는 옛 서버면 품목으로 떨어진다.
    final groups = r.lines;
    final List<_Line> rows = groups.isNotEmpty
        ? [
            for (final g in groups)
              _Line(g.short, g.actual, g.plan, g.key == 'internal')
          ]
        : () {
            final it = hasActual
                ? r.byActual.where((e) => e.actual > 0).toList()
                : (List<RevenueItem>.from(r.items)
                  ..sort((a, b) => b.plan.compareTo(a.plan)));
            return [for (final e in it) _Line(e.item, e.actual, e.plan, false)];
          }();
    final top = rows.take(6).toList();
    final restA = rows.skip(6).fold<int>(0, (a, b) => a + b.actual);
    final restP = rows.skip(6).fold<int>(0, (a, b) => a + b.plan);
    final restN = rows.length - top.length;

    Widget line(String name, int actual, int plan, Color bar) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong.copyWith(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Text(Fmt.moneyShort(actual),
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: plan <= 0 ? 0 : (actual / plan).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.statusGraySoft,
                valueColor: AlwaysStoppedAnimation<Color>(bar),
              ),
            ),
            const SizedBox(height: 3),
            Text('계획 ${Fmt.moneyShort(plan)}',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          ]),
        );

    return _shell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Text('${Fmt.monthShort(r.month)} 매출',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.h2),
          ),
          const Spacer(),
          if (_asOf(r).isNotEmpty)
            Text(_asOf(r),
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          if (onTap != null)
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textMute),
        ]),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(Fmt.moneyShort(r.actual),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: AppColors.textMain)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('나갔습니다',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: AppColors.textMute)),
            ),
          ],
        ),
        const SizedBox(height: 11),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppColors.statusGraySoft,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.summaryInProgress),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text('${Fmt.monthShort(r.month)} 계획 ${Fmt.moneyShort(r.plan)}',
              style: AppText.caption.copyWith(color: AppColors.textMute)),
          const Spacer(),
          Text(rate == null ? '-' : '$rate%',
              style: AppText.bodyStrong.copyWith(fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _MiniStat(
                  label: '남은 계획', value: Fmt.moneyShort(r.left))),
          Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: AppColors.borderSoft,
          ),
          Expanded(
              child: _MiniStat(
                  label: '연간 누적', value: Fmt.moneyShort(r.ytd))),
        ]),
        const Divider(height: 20, color: AppColors.borderSoft),
        if (!hasActual)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('아직 실적 보고가 올라오지 않았습니다',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          ),
        for (final e in top)
          line(e.name, e.actual, e.plan,
              e.dim ? AppColors.statusGray : AppColors.summaryInProgress),
        if (restN > 0)
          line('그 외 $restN개', restA, restP, AppColors.statusGray),
        const SizedBox(height: 6),
        Text(
            groups.isNotEmpty
                ? '총합 (내부거래 포함) · 품목 ${r.items.length}개'
                : '반도체사업부 전체 · ${r.items.length}개 품목',
            style: AppText.caption.copyWith(color: AppColors.textHint)),
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

/// 카드에 그릴 한 줄. 묶음이든 품목이든 모양은 같다.
class _Line {
  final String name;
  final int actual;
  final int plan;
  /// 내부거래처럼 '매출합계에 안 들어가는' 줄은 흐리게
  final bool dim;

  const _Line(this.name, this.actual, this.plan, this.dim);
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
