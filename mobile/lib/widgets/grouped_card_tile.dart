import 'package:flutter/material.dart';
import '../models/product_card.dart';

/// 모델 단위 그룹 카드 위젯
/// - 헤더: 신호등 색 dot + 모델명 + 부서 배지
/// - 본문: 이슈마다 색 dot + headline
class GroupedCardTile extends StatelessWidget {
  final GroupedCard group;
  final void Function(GroupedCard group, GroupedIssue issue)? onIssueTap;
  final void Function(GroupedCard group)? onGroupTap;

  const GroupedCardTile({
    super.key,
    required this.group,
    this.onGroupTap,
    this.onIssueTap,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'RED':
        return const Color(0xFFE53935);
      case 'BLUE':
        return const Color(0xFF1E88E5);
      default:
        return const Color(0xFF424242);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _statusColor(group.status);
    final badge = group.projectBadge ?? group.projectLabel ?? '미분류';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: cardColor, width: 5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onGroupTap == null ? null : () => onGroupTap!(group),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== 헤더: 모델명 + 배지 =====
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cardColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      group.model.isEmpty ? '(이름 없음)' : group.model,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BadgeChip(label: badge),
                ],
              ),
              // ===== 본문: 이슈 리스트 =====
              if (group.issues.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...group.issues.map((it) {
                  final dotColor = _statusColor(it.status);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onIssueTap == null
                        ? null
                        : () => onIssueTap!(group, it),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              it.headline,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF374151),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  const _BadgeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A5F),
        ),
      ),
    );
  }
}
