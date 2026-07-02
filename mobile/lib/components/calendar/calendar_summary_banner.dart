import 'package:flutter/material.dart';
import '../../design/design.dart';

class CalendarSummaryBanner extends StatelessWidget {
  final int pendingCount;
  final int doneCount;
  final List<String> categoryLabels;
  const CalendarSummaryBanner({
    super.key,
    required this.pendingCount,
    required this.doneCount,
    required this.categoryLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '이번 주 마감 관리',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C8594),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5E5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'D-7 이내',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE53935),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '미확인 $pendingCount건 · 완료 $doneCount건',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.headerNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            categoryLabels.join(' · '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF7C8594)),
          ),
        ],
      ),
    );
  }
}
