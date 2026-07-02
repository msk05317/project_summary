import 'package:flutter/material.dart';
import '../../models/calendar_event.dart';

class CalendarCategoryFilter extends StatelessWidget {
  final Set<CalendarCategory> selected;
  final ValueChanged<CalendarCategory> onToggle;
  const CalendarCategoryFilter({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      CalendarCategory.shipping,
      CalendarCategory.receiving,
      CalendarCategory.report,
      CalendarCategory.approval,
    ];
    return Row(
      children: items.map((c) {
        final on = selected.contains(c);
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: InkWell(
            onTap: () => onToggle(c),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: on ? c.color : const Color(0xFFC5CAD3),
                      width: 1.5,
                    ),
                    color: on ? c.color : Colors.white,
                  ),
                  child: on
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 5),
                Text(
                  c.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF525A66),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
