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
  final double minY;
  final double maxY;

  const ProgressTrendChart({
    super.key,
    required this.points,
    this.minY = 40,
    this.maxY = 80,
  });

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].value));
    }

    final lastIndex = points.length - 1;
    final lastValue = points.isEmpty ? 0.0 : points.last.value;

    return SizedBox(
      height: 160,
      child: Padding(
        padding: const EdgeInsets.only(top: 20, right: 24, bottom: 4),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 4,
              getDrawingHorizontalLine: (v) => FlLine(
                color: const Color(0xFFEEF1F5),
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
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
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
                      TextStyle(
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
