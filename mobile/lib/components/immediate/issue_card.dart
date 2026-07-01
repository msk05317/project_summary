import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'priority_badge.dart';

class IssueCardData {
  final String id;
  final String projectKey;
  final IssuePriority priority;
  final String status;
  final String dueText;
  final String divisionLabel;
  final String projectLabel;
  final String headline;
  final String dueDate;
  final VoidCallback? onTap;

  const IssueCardData({
    required this.id,
    required this.projectKey,
    required this.priority,
    required this.status,
    required this.dueText,
    required this.divisionLabel,
    required this.projectLabel,
    required this.headline,
    required this.dueDate,
    this.onTap,
  });
}

class IssueCard extends StatelessWidget {
  final IssueCardData data;
  const IssueCard({super.key, required this.data});

  Color get _stripeColor {
    if (data.priority == IssuePriority.critical) {
      return const Color(0xFFFF0000);
    }
    switch (data.status) {
      case '지연':
        return const Color(0xFFFF0000);
      case '주의':
        return const Color(0xFFE97132);
      default:
        return const Color(0xFF7C8594);
    }
  }

  Color get _dueColor {
    switch (data.status) {
      case '지연':
        return const Color(0xFFFF0000);
      case '주의':
        return const Color(0xFFE97132);
      default:
        return AppColors.headerNavy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.reportCardBorder;
    const borderWidth = 1.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: _stripeColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(11),
                      bottomLeft: Radius.circular(11),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  PriorityBadge(priority: data.priority),
                                  StatusOutlineBadge(status: data.status),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              data.dueText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _dueColor,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${data.divisionLabel} · ${data.projectLabel}',
                          style: AppText.bodyStrong.copyWith(
                            fontSize: 16,
                            color: AppColors.headerNavy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.headline,
                          style: AppText.caption.copyWith(
                            fontSize: 14,
                            color: AppColors.headerNavy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.event_outlined,
                                size: 12, color: Color(0xFF9AA3B2)),
                            const SizedBox(width: 4),
                            Text(
                              '완료일 ${data.dueDate}',
                              style: AppText.caption.copyWith(
                                fontSize: 11,
                                color: const Color(0xFF9AA3B2),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.chevron_right_rounded,
                                size: 18, color: Color(0xFF9AA3B2)),
                          ],
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
