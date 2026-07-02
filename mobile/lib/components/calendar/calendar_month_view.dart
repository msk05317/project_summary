import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../../models/calendar_event.dart';

class CalendarMonthView extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  const CalendarMonthView({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.events,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((leading + daysInMonth) / 7).ceil() * 7;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF0), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${month.year}년 ${month.month}월',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.headerNavy,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onPrev,
                child: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF7C8594)),
              ),
              InkWell(
                onTap: onNext,
                child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF7C8594)),
              ),
              const Spacer(),
              InkWell(
                onTap: onToday,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE6EAF0), width: 1),
                  ),
                  child: const Text(
                    '오늘',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF525A66),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              _Weekday('일', Color(0xFFE53935)),
              _Weekday('월', Color(0xFF7C8594)),
              _Weekday('화', Color(0xFF7C8594)),
              _Weekday('수', Color(0xFF7C8594)),
              _Weekday('목', Color(0xFF7C8594)),
              _Weekday('금', Color(0xFF7C8594)),
              _Weekday('토', Color(0xFF1E88E5)),
            ],
          ),
          const SizedBox(height: 6),
          ...List.generate((totalCells / 7).ceil(), (row) {
            return Row(
              children: List.generate(7, (col) {
                final index = row * 7 + col;
                final dayNum = index - leading + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 42));
                }
                final d = DateTime(month.year, month.month, dayNum);
                final isToday = _same(d, today);
                final isSelected = _same(d, selected);
                final dayEvents = events.where((e) => _same(e.date, d)).toList();

                Color textColor;
                if (col == 0) {
                  textColor = const Color(0xFFE53935);
                } else if (col == 6) {
                  textColor = const Color(0xFF1E88E5);
                } else {
                  textColor = AppColors.headerNavy;
                }

                return Expanded(
                  child: InkWell(
                    onTap: () => onSelect(d),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 42,
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0E2841) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday && !isSelected
                            ? Border.all(color: const Color(0xFF1E88E5), width: 1.4)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dayEvents.take(2).map((e) => Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : e.category.color,
                                shape: BoxShape.circle,
                              ),
                            )).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '색점 = 일정 유형',
              style: TextStyle(fontSize: 10, color: Color(0xFFB0B7C1)),
            ),
          ),
        ],
      ),
    );
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Weekday extends StatelessWidget {
  final String label;
  final Color color;
  const _Weekday(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
