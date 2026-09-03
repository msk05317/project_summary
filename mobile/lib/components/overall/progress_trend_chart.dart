import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/design.dart';

class ProgressTrendPoint {
  final String label;
  final double value;
  const ProgressTrendPoint(this.label, this.value);
}

class ProgressTrendChart extends StatelessWidget {
  final List<ProgressTrendPoint> points;

  const ProgressTrendChart({
    super.key,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            '추이 데이터가 없습니다',
            style: AppText.caption.copyWith(color: AppColors.textMute),
          ),
        ),
      );
    }

    // 진행률은 0~100 고정축.
    // 예전에는 데이터 범위에 맞춰 축을 확대해서 78%→80% 변화가 급등처럼
    // 보였다. 경영 보고 차트에서 기울기 과장은 가장 피해야 할 오독이다.
    const double effectiveMinY = 0;
    const double effectiveMaxY = 100;

    final spots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].value));
    }

    final lastIndex = points.length - 1;
    final lastValue = points.last.value;

    return SizedBox(
      height: 180,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: LineChart(
            LineChartData(
              minX: -0.35,
              maxX: (points.length - 1).toDouble() + 0.35,
              minY: effectiveMinY,
              maxY: effectiveMaxY,
              clipData: const FlClipData.none(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: AppColors.dividerSoft,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 25,
                    reservedSize: 30,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${v.toInt()}',
                        style: AppText.caption.copyWith(
                          color: AppColors.textMute,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
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
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      // 데이터 인덱스에 정확히 매칭되는 정수 x에서만 라벨 표시.
                      // (minX/maxX를 -0.35 / +0.35로 확장했기 때문에
                      //  fl_chart가 여유 공간에도 라벨을 그리려 시도함)
                      if ((value - value.roundToDouble()).abs() > 0.001) {
                        return const SizedBox.shrink();
                      }
                      final i = value.round();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          points[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            color: const Color(0xFF7C8594),
                            fontWeight: i == lastIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.28,
                  barWidth: 2.5,
                  color: AppColors.headerNavy,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) {
                      final isLast = index == lastIndex;
                      return FlDotCirclePainter(
                        radius: isLast ? 5 : 3,
                        color: Colors.white,
                        strokeWidth: isLast ? 3 : 2,
                        strokeColor: AppColors.headerNavy,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.headerNavy.withValues(alpha: 0.06),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      return LineTooltipItem(
                        '${s.y.toStringAsFixed(0)}%',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      );
                    }).toList();
                  },
                  getTooltipColor: (_) => AppColors.headerNavy,
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: lastValue,
                    color: AppColors.headerNavy.withValues(alpha: 0.25),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(right: 4, bottom: 2),
                      style: TextStyle(
                        color: AppColors.headerNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                      labelResolver: (_) => '${lastValue.toStringAsFixed(0)}%',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
