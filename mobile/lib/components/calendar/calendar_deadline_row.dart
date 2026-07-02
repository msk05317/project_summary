import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/calendar_event.dart';

class CalendarDeadlineRow extends StatelessWidget {
  final CalendarEvent event;
  final DateTime today;
  const CalendarDeadlineRow({
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
    final dateText = '${event.date.month}/${event.date.day}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: event.category.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.category.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: event.category.color,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${event.divisionLabel} · ${event.projectLabel}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7C8594)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.headerNavy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF525A66),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ddayColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ddayText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ddayColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
