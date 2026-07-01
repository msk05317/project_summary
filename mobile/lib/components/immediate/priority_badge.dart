import 'package:flutter/material.dart';

enum IssuePriority { critical, high, mid, low }

extension IssuePriorityUi on IssuePriority {
  String get label {
    switch (this) {
      case IssuePriority.critical:
        return '최우선';
      case IssuePriority.high:
        return '높음';
      case IssuePriority.mid:
        return '중간';
      case IssuePriority.low:
        return '낮음';
    }
  }

  Color get color {
    switch (this) {
      case IssuePriority.critical:
        return const Color(0xFFFF0000);
      case IssuePriority.high:
        return const Color(0xFFE97132);
      case IssuePriority.mid:
        return const Color(0xFF156082);
      case IssuePriority.low:
        return const Color(0xFF196B24);
    }
  }
}

class PriorityBadge extends StatelessWidget {
  final IssuePriority priority;
  const PriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    return _FilledBadge(text: priority.label, color: priority.color);
  }
}

class StatusOutlineBadge extends StatelessWidget {
  final String status;
  const StatusOutlineBadge({super.key, required this.status});

  Color get _color {
    switch (status) {
      case '지연':
        return const Color(0xFFFF0000);
      case '주의':
        return const Color(0xFFE97132);
      default:
        return const Color(0xFF7C8594);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

class CriticalImpactBadge extends StatelessWidget {
  const CriticalImpactBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return _FilledBadge(
      text: '활성화 영향',
      color: const Color(0xFFFF0000),
      icon: Icons.warning_amber_rounded,
    );
  }
}

class _FilledBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const _FilledBadge({
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
