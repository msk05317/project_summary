import 'package:flutter/material.dart';

import '../../design/design.dart';

class DivisionProgressRow extends StatelessWidget {
  final String divisionLabel;
  final String primaryStatus;
  final int totalCount;
  final int normalCount;
  final int warningCount;
  final int delayedCount;
  final int progressPercent;
  final VoidCallback onTap;

  const DivisionProgressRow({
    super.key,
    required this.divisionLabel,
    required this.primaryStatus,
    required this.totalCount,
    required this.normalCount,
    required this.warningCount,
    required this.delayedCount,
    required this.progressPercent,
    required this.onTap,
  });

  Color get _dotColor {
    switch (primaryStatus) {
      case '지연':
        return const Color(0xFFFF0000);
      case '주의':
        return const Color(0xFFE97132);
      case '정상':
      default:
        return const Color(0xFF196B24);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: _dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    divisionLabel,
                    style: AppText.bodyStrong.copyWith(
                      fontSize: 14,
                      color: AppColors.headerNavy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '전체 $totalCount건 · 정상 $normalCount · 주의 $warningCount · 지연 $delayedCount',
                    style: AppText.caption.copyWith(
                      fontSize: 10,
                      color: const Color(0xFF7C8594),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressPercent / 100.0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFEEF1F5),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.headerNavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$progressPercent%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.headerNavy,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: Color(0xFF7C8594)),
          ],
        ),
      ),
    );
  }
}
