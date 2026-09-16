// 홈 첫 장 — '이번 달' 한 카드.
//
// 예전 홈은 '전체 현황'(지연·임박·보류·PO 대기 타일 4개 + 전체 진행률)과
// '이번 달 매출' 카드가 따로 있었다. 숫자가 일곱 개 널려 있는데 서로
// 무슨 관계인지가 없어서, 임원이 열면 어디를 봐야 할지 모른다.
//
// 이 카드는 한 달을 이렇게 읽는다.
//
//   이번 달 계획이 얼마고 지금 얼마 왔나        → 매출 / 달성률
//   끝난 주까지만 보면 계획을 지켰나            → 지금까지
//   남은 주에 얼마가 걸려 있나                  → 남은 N주
//   그걸 막고 있는 게 몇 건인가                 → 막힌 것 (지연 + 이슈)
//
// 월 달성률 35% 만 크게 띄우면 '큰일났다' 로 읽힌다. 아직 3주가 남았고
// 그 3주 계획이 분모에 들어 있어서다. 끝난 주만 놓고 보면 96% 다.
// 그래서 두 숫자를 같은 카드 안에 나란히 둔다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../services/home_alerts_service.dart';
import '../../services/overview_service.dart';
import '../../utils/format.dart';

class MonthOverviewCard extends StatelessWidget {
  final OverviewSummary summary;
  final HomeAlerts alerts;
  final bool loading;

  /// 매출 자리를 누르면 프로젝트별 내역으로
  final VoidCallback? onTapRevenue;

  /// '막힌 것' 을 누르면 그 목록으로
  final VoidCallback? onTapBlocked;

  const MonthOverviewCard({
    super.key,
    required this.summary,
    required this.alerts,
    this.loading = false,
    this.onTapRevenue,
    this.onTapBlocked,
  });

  /// 이 숫자에 무엇이 들어 있는지 한 줄로 밝힌다.
  /// '전체 사업부 매출' 로 읽히면 안 된다 — 주차 계획이 올라온 프로젝트만이다.
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
    final out = <String>{};
    var n = 0;
    for (final p in summary.items) {
      final d = names[p.divisionId] ?? (p.divisionId ?? '');
      if (d.isEmpty) continue;
      if (p.planRevenue > 0 || p.revenue > 0) {
        inn.add(d);
        n++;
      } else if (p.modelsTotal > 0) {
        out.add(d);
      }
    }
    if (inn.isEmpty) return '';
    var t = '${inn.join(' · ')} $n개 프로젝트';
    final miss = out.difference(inn);
    if (miss.isNotEmpty) t += ' · ${miss.join('·')}는 주차 계획 미등록';
    return t;
  }

  Widget _shell({required Widget child}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _shell(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 34),
          child: Center(
            child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    // 못 받아왔을 때 0 을 그리면 '계획이 없다' 와 똑같이 보인다.
    // 경영 판단이 걸린 숫자라 모르는 건 모른다고 말해야 한다.
    if (!summary.loaded) {
      return _shell(
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: Row(children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.textMute),
            SizedBox(width: 8),
            Text('이번 달 현황을 불러오지 못했습니다',
                style: TextStyle(fontSize: 13, color: AppColors.textMute)),
          ]),
        ),
      );
    }

    final rate = summary.achievement;
    final ratio = rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0);
    final barColor = rate == null
        ? AppColors.statusGray
        : (rate >= 100
            ? AppColors.summaryNormal
            : (rate >= 80
                ? AppColors.summaryInProgress
                : AppColors.summaryCaution));

    return _shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: summary.hasRevenue ? onTapRevenue : null,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(Fmt.monthShort(summary.month), style: AppText.h2),
                    const SizedBox(width: 6),
                    Text(_headline(),
                        style: AppText.caption
                            .copyWith(color: AppColors.textMute)),
                    const Spacer(),
                    if (summary.hasRevenue && onTapRevenue != null)
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.textMute),
                  ]),
                  if (!summary.hasRevenue) ...[
                    const SizedBox(height: 10),
                    Text('${Fmt.monthShort(summary.month)} 등록된 매출 계획이 없습니다',
                        style:
                            AppText.body.copyWith(color: AppColors.textMute)),
                  ] else ...[
                    const SizedBox(height: 10),
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
                              height: 1.1),
                        ),
                        const SizedBox(width: 8),
                        Text('/ ${Fmt.moneyShort(summary.planRevenue)}',
                            style: AppText.body
                                .copyWith(color: AppColors.textMute)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: barColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(rate == null ? '-' : '달성 $rate%',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: barColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: AppColors.statusGraySoft,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                    if (_coverage().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_coverage(),
                          style: AppText.caption
                              .copyWith(color: AppColors.textHint)),
                    ],
                  ],
                ]),
          ),
        ),

        // 끝난 주 / 남은 주
        if (summary.hasRevenue && summary.hasWeekSplit) ...[
          const Divider(height: 1, color: AppColors.borderSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _closedSide()),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: AppColors.borderSoft,
                  ),
                  Expanded(child: _openSide()),
                ],
              ),
            ),
          ),
        ],

        // 막힌 것 — 지연 + 이슈
        const Divider(height: 1, color: AppColors.borderSoft),
        _blockedRow(),
      ]),
    );
  }

  /// 제목 옆 한 줄. '남은 주' 가 있으면 그게 제일 쓸모 있는 맥락이다.
  String _headline() {
    if (!summary.hasWeekSplit) return '실적 / 계획';
    if (summary.openWeeks <= 0) return '이번 달 마감';
    return '${summary.openWeeks}주 남음';
  }

  Widget _closedSide() {
    final pct = summary.closedAchievement;
    final good = pct != null && pct >= 95;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('지금까지 · ${summary.closedWeeks}주 마감',
          style: AppText.caption.copyWith(color: AppColors.textMute)),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(pct == null ? '-' : '$pct%',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: good
                      ? AppColors.summaryNormal
                      : AppColors.summaryCaution)),
          const SizedBox(width: 5),
          Text('계획 대비',
              style: AppText.caption.copyWith(color: AppColors.textHint)),
        ],
      ),
      const SizedBox(height: 2),
      Text(
          '출하 ${Fmt.qty(summary.closedQtyActual)} / '
          '${Fmt.qty(summary.closedQtyPlan)}대',
          style: AppText.caption.copyWith(color: AppColors.textMute)),
    ]);
  }

  Widget _openSide() {
    final share = summary.openShare;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(summary.openWeeks > 0 ? '남은 ${summary.openWeeks}주' : '남은 주 없음',
          style: AppText.caption.copyWith(color: AppColors.textMute)),
      const SizedBox(height: 4),
      Text(Fmt.moneyShort(summary.openPlanRevenue),
          style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.textMain)),
      const SizedBox(height: 2),
      Text(
          '${Fmt.qty(summary.openQtyPlan)}대'
          '${share == null ? '' : ' · 월 계획의 $share%'}',
          style: AppText.caption.copyWith(color: AppColors.textMute)),
    ]);
  }

  /// 매출을 막고 있는 것. 지연(일정이 밀림) + 이슈(적어 둔 문제).
  /// 임박은 아직 늦지 않았으니 여기 없다 — 모델 목록의 '임박' 칩에서 본다.
  Widget _blockedRow() {
    if (!alerts.loaded) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Icon(Icons.error_outline, size: 16, color: AppColors.statusRed),
          SizedBox(width: 6),
          Text('막힌 것을 불러오지 못했습니다',
              style: TextStyle(fontSize: 13, color: AppColors.statusRed)),
        ]),
      );
    }
    final n = alerts.blocked;
    if (n == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          Icon(Icons.check_circle_outline,
              size: 16, color: AppColors.summaryNormal),
          SizedBox(width: 6),
          Text('막힌 것 없음',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.summaryNormal)),
        ]),
      );
    }
    final bits = <String>[];
    if (alerts.delayed > 0) bits.add('지연 ${alerts.delayed}');
    if (alerts.issue > 0) bits.add('이슈 ${alerts.issue}');
    return InkWell(
      onTap: onTapBlocked,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          const Icon(Icons.report_problem_outlined,
              size: 16, color: AppColors.statusRed),
          const SizedBox(width: 6),
          const Text('막힌 것',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.statusRedSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.statusRed)),
          ),
          const Spacer(),
          Text(bits.join(' · '),
              style: AppText.caption.copyWith(color: AppColors.textMute)),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.statusGray),
        ]),
      ),
    );
  }
}
