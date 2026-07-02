import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/calendar_event.dart';

class CalendarUpcomingCard extends StatelessWidget {
  final CalendarEvent event;
  final DateTime today;
  const CalendarUpcomingCard({
    super.key,
    required this.event,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final diff = event.diffDays(today);
    final ddayText = diff == 0
        ? 'D-day'
        : diff > 0
            ? 'D-$diff'
            : 'D+${-diff}';
    final ddayColor = diff <= 1
        ? const Color(0xFFE53935)
        : diff <= 3
            ? const Color(0xFFE97132)
            : const Color(0xFF7C8594);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: event.category.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.category.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.headerNavy,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${event.divisionLabel}-${event.projectLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF525A66)),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: ddayColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              ddayText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ddayColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
