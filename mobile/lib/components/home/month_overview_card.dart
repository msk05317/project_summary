// 홈 첫 장 — "이번 달 매출 맞나".
//
// 홈 화면을 세 번 고쳤는데 세 번 다 빗나갔다. 배치가 나빠서가 아니라
// 이 화면이 무슨 질문에 답하는지를 안 정한 채로 카드만 늘어놨기 때문이다.
// 숫자가 일곱 개 있어도 보고 나서 할 말이 없으면 그 화면은 실패다.
//
// 경영진이 이 앱을 여는 이유는 하나다 — 이번 달 매출을 맞출 수 있나.
// 그래서 이 카드는 카드 묶음이 아니라 '문장 하나 + 그 근거' 다.
//
//   9월
//   $1108만                          이대로면 · 계획의 96%
//   실적 $400만 · 남은 3주 계획 $735만 · 마감 2주 96% 달성
//
//   남은 $735만 중 $506만이 문제 걸린 프로젝트에 있습니다
//     파워박스 $216만 · 메이저모듈 $198만 · 하바플레이트 $88.3만
//
// 마지막 블록이 이 앱에 계속 없던 연결성이다. '막힌 것 15건' 은 경영진에게
// 아무 뜻이 없고, '남은 매출의 69%가 거기 있다' 는 뜻이 있다.
//
// 판정은 하지 않는다. '모자랍니다', '계획대로입니다' 같은 말도, 빨강·주황도
// 쓰지 않는다. 96% 를 매달 빨갛게 칠하면 두 달 만에 아무도 안 본다. 그리고
// 아직 3주가 남은 추정을 확정처럼 말하면 앱이 아는 것보다 더 확신하는 것이다.
// 보는 사람이 '아 이렇구나' 하면 그걸로 됐다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../services/home_alerts_service.dart';
import '../../services/overview_service.dart';
import '../../utils/format.dart';

/// 위험 금액이 걸린 프로젝트 한 줄
class _AtRisk {
  final String key;
  final String label;
  final int money;
  final int blocked;

  const _AtRisk(this.key, this.label, this.money, this.blocked);
}

class MonthOverviewCard extends StatelessWidget {
  final OverviewSummary summary;
  final HomeAlerts alerts;
  final bool loading;

  /// 매출 자리를 누르면 프로젝트별 내역으로
  final VoidCallback? onTapRevenue;

  /// 위험 블록을 누르면 문제 목록으로
  final VoidCallback? onTapBlocked;

  /// 위험 프로젝트 한 줄을 누르면 그 프로젝트로
  final void Function(String projectKey)? onTapProject;

  const MonthOverviewCard({
    super.key,
    required this.summary,
    required this.alerts,
    this.loading = false,
    this.onTapRevenue,
    this.onTapBlocked,
    this.onTapProject,
  });

  // ── 위험 금액 ────────────────────────────────────────────────
  //
  // 문제가 걸린 프로젝트가 이번 달에 아직 들고 있는 돈. 끝난 주차의 돈은
  // 이미 나갔으므로 위험하지 않다 — 남은 주차의 계획만 센다.
  List<_AtRisk> _atRisk() {
    if (!alerts.loaded || !summary.loaded) return const [];
    final open = summary.openByProject;
    final labels = {for (final p in summary.items) p.key: p.label};
    final out = <_AtRisk>[];
    for (final p in alerts.byProject) {
      if (p.blocked <= 0) continue;
      final money = open[p.key] ?? 0;
      if (money <= 0) continue; // 금액이 안 잡힌 곳은 아래 한 줄로 따로 말한다
      out.add(_AtRisk(p.key, labels[p.key] ?? p.label, money, p.blocked));
    }
    out.sort((a, b) => b.money.compareTo(a.money));
    return out;
  }

  /// 문제는 있는데 금액이 0 인 프로젝트 수.
  /// ESS(SDI·FLUENCE·EPC POWER)는 판가가 등록돼 있지 않아 매출이 $0 이다.
  /// 그걸 '위험 없음' 으로 보여주면 거짓말이 된다.
  int _unpricedCount() {
    if (!alerts.loaded || !summary.loaded) return 0;
    final open = summary.openByProject;
    return alerts.byProject
        .where((p) => p.blocked > 0 && (open[p.key] ?? 0) <= 0)
        .length;
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
          padding: EdgeInsets.symmetric(vertical: 44),
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

    return _shell(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _verdict(context),
        const Divider(height: 1, color: AppColors.borderSoft),
        _riskBlock(context),
      ]),
    );
  }

  // ── 결론 ──────────────────────────────────────────────────────
  Widget _verdict(BuildContext context) {
    final mon = Fmt.monthShort(summary.month);

    if (!summary.hasRevenue) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mon, style: AppText.h2),
          const SizedBox(height: 6),
          Text('$mon 등록된 매출 계획이 없습니다',
              style: AppText.body.copyWith(color: AppColors.textMute)),
        ]),
      );
    }

    final fc = summary.forecast;
    final fcRate = summary.forecastRate;
    final closed = summary.monthClosed;

    // 색으로 판정하지 않는다. 96% 를 주황으로 칠하면 '뭔가 잘못됐다' 로
    // 읽히는데, 3주 남은 추정에 그렇게 말할 근거가 없다.
    const tone = AppColors.textMain;

    // 예상을 낼 수 없으면(월초) 실적/계획만 말한다.
    final head = fc == null
        ? Fmt.moneyShort(summary.revenue)
        : Fmt.moneyShort(fc);
    // 숫자 옆에 그 숫자가 무엇인지만 붙인다.
    final tag = fc == null
        ? (summary.achievement == null
            ? '실적'
            : '실적 · 계획의 ${summary.achievement}%')
        : (closed
            ? '마감 · 계획의 $fcRate%'
            : '이대로면 · 계획의 $fcRate%');
    final ratio = ((fcRate ?? summary.achievement ?? 0) / 100).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTapRevenue,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(mon, style: AppText.h2),
            const Spacer(),
            if (onTapRevenue != null)
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textMute),
          ]),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(head,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w800,
                        color: tone,
                        height: 1.1)),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textMute)),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.statusGraySoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.summaryInProgress),
            ),
          ),
          const SizedBox(height: 8),
          Text(_basis(),
              style: AppText.caption.copyWith(color: AppColors.textHint)),
        ]),
      ),
    );
  }

  /// 예상이 어디서 나왔는지 한 줄. 근거 없는 숫자는 경영진이 안 믿는다.
  String _basis() {
    final bits = <String>[
      '실적 ${Fmt.moneyShort(summary.revenue)}',
      if (summary.hasWeekSplit && summary.openWeeks > 0)
        '남은 ${summary.openWeeks}주 계획 ${Fmt.moneyShort(summary.openPlanRevenue)}',
    ];
    final line = bits.join(' · ');
    final r = summary.closedAchievement;
    if (r == null || summary.closedWeeks <= 0 || summary.monthClosed) {
      return line;
    }
    return '$line · 마감 ${summary.closedWeeks}주 $r% 달성';
  }

  // ── 무엇이 그걸 막고 있나 ──────────────────────────────────────
  Widget _riskBlock(BuildContext context) {
    if (!alerts.loaded) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(children: [
          Icon(Icons.error_outline, size: 16, color: AppColors.statusRed),
          SizedBox(width: 6),
          Text('막힌 것을 불러오지 못했습니다',
              style: TextStyle(fontSize: 13, color: AppColors.statusRed)),
        ]),
      );
    }
    if (alerts.blocked == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Text('지연·이슈로 잡힌 건 없습니다',
            style: TextStyle(fontSize: 13, color: AppColors.textMute)),
      );
    }

    final risk = _atRisk();
    final money = risk.fold<int>(0, (a, b) => a + b.money);
    final open = summary.openPlanRevenue;
    final share = open > 0 ? (money * 100 / open).round() : null;
    final unpriced = _unpricedCount();
    final rows = risk.take(3).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: onTapBlocked,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(
                  // 건수가 아니라 금액으로 말한다. '15건' 은 경영진에게
                  // 아무 뜻이 없고, '남은 매출의 69%' 는 뜻이 있다.
                  money > 0 && share != null
                      ? '남은 ${Fmt.moneyShort(open)} 중 '
                          '${Fmt.moneyShort(money)}($share%)이 '
                          '지연·이슈가 있는 프로젝트에 있습니다'
                      : '지연·이슈 ${alerts.blocked}건',
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.chevron_right,
                  size: 18, color: AppColors.statusGray),
            ),
          ]),
        ),
      ),
      for (final r in rows) _riskRow(r),
      if (risk.length > rows.length || unpriced > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
          child: Text(
              [
                if (risk.length > rows.length) '외 ${risk.length - rows.length}곳',
                if (unpriced > 0) '판가 미등록 $unpriced곳은 금액이 잡히지 않습니다',
              ].join(' · '),
              style: AppText.caption.copyWith(color: AppColors.textHint)),
        ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _riskRow(_AtRisk r) {
    return InkWell(
      onTap: onTapProject == null ? null : () => onTapProject!(r.key),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Row(children: [
          Expanded(
            child: Text(r.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain)),
          ),
          const SizedBox(width: 8),
          Text(Fmt.moneyShort(r.money),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain)),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text('${r.blocked}건',
                textAlign: TextAlign.right,
                style: AppText.caption.copyWith(color: AppColors.textMute)),
          ),
        ]),
      ),
    );
  }
}
