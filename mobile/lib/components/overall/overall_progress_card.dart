import 'package:flutter/material.dart';

import '../../design/design.dart';

class OverallProgressCard extends StatelessWidget {
  final int progressPercent;
  final int deltaVsYesterday;
  final int deltaVsAverage;
  final int totalCount;
  final int normalCount;
  final int warningCount;
  final int delayedCount;

  const OverallProgressCard({
    super.key,
    required this.progressPercent,
    required this.deltaVsYesterday,
    required this.deltaVsAverage,
    required this.totalCount,
    required this.normalCount,
    required this.warningCount,
    required this.delayedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.reportCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_chart_outlined_rounded,
                  size: 16, color: Color(0xFF7C8594)),
              const SizedBox(width: 6),
              Text(
                '전체 진행률',
                style: AppText.bodyStrong.copyWith(
                  fontSize: 13,
                  color: AppColors.headerNavy,
                ),
              ),
              const Spacer(),
              Text(
                '어제 대비',
                style: AppText.caption.copyWith(
                  fontSize: 10,
                  color: const Color(0xFF7C8594),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$progressPercent',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: AppColors.headerNavy,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.headerNavy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DeltaBadge(delta: deltaVsYesterday),
                    const SizedBox(height: 2),
                    Text(
                      '전주 평균 ${deltaVsAverage >= 0 ? '+' : ''}$deltaVsAverage%',
                      style: AppText.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7C8594),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _kpi('전체', totalCount, AppColors.headerNavy),
              _kpi('정상', normalCount, const Color(0xFF196B24)),
              _kpi('주의', warningCount, const Color(0xFFE97132)),
              _kpi('지연', delayedCount, const Color(0xFFFF0000)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppText.caption.copyWith(
              fontSize: 11,
              color: const Color(0xFF7C8594),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  final int delta;
  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final positive = delta >= 0;
    final color =
        positive ? const Color(0xFF196B24) : const Color(0xFFFF0000);
    final icon = positive ? Icons.arrow_drop_up : Icons.arrow_drop_down;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        Text(
          '${delta.abs()}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
