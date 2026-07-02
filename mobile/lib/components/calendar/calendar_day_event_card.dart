import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/calendar_event.dart';

class CalendarDayEventCard extends StatelessWidget {
  final CalendarEvent event;
  final ValueChanged<bool> onToggleDone;
  final VoidCallback? onTap;
  const CalendarDayEventCard({
    super.key,
    required this.event,
    required this.onToggleDone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF0), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: event.category.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                        InkWell(
                          onTap: () => onToggleDone(!event.isDone),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: event.isDone ? const Color(0xFFE8F5E9) : const Color(0xFFF6F8FB),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: event.isDone ? const Color(0xFF43A047) : const Color(0xFFC5CAD3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  event.isDone ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 12,
                                  color: event.isDone ? const Color(0xFF43A047) : const Color(0xFF7C8594),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  event.isDone ? '완료' : '미확인',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: event.isDone ? const Color(0xFF43A047) : const Color(0xFF7C8594),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headerNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${event.divisionLabel} · ${event.projectLabel}${event.time != null ? " · ${event.time}" : ""}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7C8594)),
                    ),
                  ],
                ),
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
