// 주차별 매출 현황.
//
// 예전에는 6컬럼 표를 '세로 스크롤 안의 가로 스크롤'로 보여줬다.
// 모바일에서 임원이 좌우로 밀며 자릿수를 세야 해서 스캔이 불가능했다.
//
// 지금 구성
//  1) 이번 달 실적 / 계획 기준 예상 / 달성률  (한눈에)
//  2) 주차별 계획 vs 실적 막대그래프          (추세를 형태로)
//  3) '표로 보기' 를 눌렀을 때만 상세 표      (필요할 때만)
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/weekly_revenue.dart';
import '../utils/format.dart';

class WeeklyRevenueCard extends StatefulWidget {
  final WeeklyRevenue rev;
  const WeeklyRevenueCard({super.key, required this.rev});

  @override
  State<WeeklyRevenueCard> createState() => _WeeklyRevenueCardState();
}

class _WeeklyRevenueCardState extends State<WeeklyRevenueCard> {
  bool _showTable = false;

  WeeklyRevenue get rev => widget.rev;

  int _weekActual(String w) =>
      (rev.mass.weeks[w]?.revenue ?? 0) + (rev.dev.weeks[w]?.revenue ?? 0);

  int _weekPlan(String w) =>
      (rev.mass.weeks[w]?.planRevenue ?? 0) + (rev.dev.weeks[w]?.planRevenue ?? 0);

  @override
  Widget build(BuildContext context) {
    final rate = rev.achievement;
    final rateColor = rate == null
        ? AppColors.textMute
        : (rate >= 100
            ? AppColors.summaryNormal
            : (rate >= 80 ? AppColors.summaryInProgress : AppColors.summaryCaution));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('주차별 매출', style: AppText.h2),
              const SizedBox(width: 6),
              Text(Fmt.monthShort(rev.month),
                  style: AppText.caption.copyWith(color: AppColors.textMute)),
            ],
          ),
          const SizedBox(height: 12),

          // 1) 이번 달 요약
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  label: '실적 매출',
                  value: Fmt.moneyShort(rev.combinedRevenue),
                  color: AppColors.summaryNormal,
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.borderSoft),
              Expanded(
                child: _Kpi(
                  label: '계획 기준 예상',
                  value: Fmt.moneyShort(rev.combinedPlanRevenue),
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.borderSoft),
              Expanded(
                child: _Kpi(
                  label: '달성률',
                  value: rate == null ? '-' : '$rate%',
                  color: rateColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2) 주차별 계획 vs 실적
          if (rev.weeks.isNotEmpty) _buildChart(),

          const SizedBox(height: 8),
          Row(
            children: [
              _legend(AppColors.statusGray, '계획'),
              const SizedBox(width: 12),
              _legend(AppColors.summaryNormal, '실적'),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _showTable = !_showTable),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_showTable ? '표 닫기' : '표로 보기',
                          style: AppText.caption
                              .copyWith(color: AppColors.summaryInProgress)),
                      Icon(
                        _showTable ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: AppColors.summaryInProgress,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 3) 상세 표 (요청 시)
          if (_showTable) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                border: TableBorder.all(color: AppColors.borderDefault),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  _row(const [
                    '주차',
                    '양산 계획/실적',
                    '양산 매출',
                    '개발 계획/실적',
                    '개발 매출',
                    '주차 합계'
                  ], header: true),
                  ...rev.weeks.map(_weekRow),
                  _totalRow(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart() {
    final maxV = rev.weeks
        .map((w) => _weekPlan(w) > _weekActual(w) ? _weekPlan(w) : _weekActual(w))
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (maxV <= 0) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text('이 달 매출 데이터가 없습니다',
              style: AppText.caption.copyWith(color: AppColors.textMute)),
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxV * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final w = rev.weeks[group.x.toInt()];
                final isPlan = rodIndex == 0;
                return BarTooltipItem(
                  '$w ${isPlan ? '계획' : '실적'}\n${Fmt.money(rod.toY.round())}',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxV / 2,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.dividerSoft,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= rev.weeks.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      rev.weeks[i],
                      style: AppText.caption.copyWith(
                        color: AppColors.textMute,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < rev.weeks.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: _weekPlan(rev.weeks[i]).toDouble(),
                    color: AppColors.statusGray,
                    width: 10,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3)),
                  ),
                  BarChartRodData(
                    toY: _weekActual(rev.weeks[i]).toDouble(),
                    color: AppColors.summaryNormal,
                    width: 10,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: AppText.caption.copyWith(color: AppColors.textMute)),
      ],
    );
  }

  TableRow _weekRow(String w) {
    final m = rev.mass.weeks[w];
    final d = rev.dev.weeks[w];
    final sum = (m?.revenue ?? 0) + (d?.revenue ?? 0);
    return _row([
      w,
      '${m?.plan ?? 0} / ${m?.actual ?? 0}',
      Fmt.money(m?.revenue ?? 0),
      '${d?.plan ?? 0} / ${d?.actual ?? 0}',
      Fmt.money(d?.revenue ?? 0),
      Fmt.money(sum),
    ], revenueRow: true);
  }

  TableRow _totalRow() {
    final mRev = rev.mass.total.revenue ?? 0;
    final dRev = rev.dev.total.revenue ?? 0;
    return _row([
      '합계',
      '${rev.mass.total.plan} / ${rev.mass.total.actual}',
      Fmt.money(mRev),
      '${rev.dev.total.plan} / ${rev.dev.total.actual}',
      Fmt.money(dRev),
      Fmt.money(mRev + dRev),
    ], total: true, revenueRow: true);
  }

  TableRow _row(List<String> cells,
      {bool header = false, bool total = false, bool revenueRow = false}) {
    return TableRow(
      decoration: BoxDecoration(
          color: header
              ? AppColors.bgPage
              : total
                  ? AppColors.statusGraySoft
                  : null),
      children: cells.asMap().entries.map((e) {
        final i = e.key;
        Color? color;
        if (!header && revenueRow) {
          if (i == 2) color = AppColors.summaryInProgress;
          if (i == 4) color = AppColors.summaryCaution;
          if (i == 5) color = AppColors.summaryNormal;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Text(
            e.value,
            textAlign: i == 0 ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  (header || total || i == 0) ? FontWeight.w700 : FontWeight.w400,
              color: color ?? AppColors.textMain,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Kpi({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.caption.copyWith(color: AppColors.textMute),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textMain,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
