import 'package:flutter/material.dart';
import '../models/product_card.dart';

/// 모델 단위 그룹 카드 위젯
/// - 헤더: 신호등 색 dot + 모델명 + 부서 배지
/// - 본문: 이슈마다 색 dot + headline
class GroupedCardTile extends StatefulWidget {
  final GroupedCard group;
  final void Function(GroupedCard group, GroupedIssue issue)? onIssueTap;
  final void Function(GroupedCard group)? onGroupTap;

  const GroupedCardTile({
    super.key,
    required this.group,
    this.onGroupTap,
    this.onIssueTap,
  });

  @override
  State<GroupedCardTile> createState() => _GroupedCardTileState();
}

class _GroupedCardTileState extends State<GroupedCardTile> {
  bool _expanded = false;
  static const int _kCollapsedMax = 3;

  // 줄 끝 보조 날짜 제거: (06-17), ( 6/17 ), (6-17) 등
  String _cleanTail(String s) {
    return s
        .replaceAll(RegExp(r'\s*\(\s*\d{1,2}[-/]\d{1,2}\s*\)\s*$'), '')
        .replaceAll(RegExp(r'\s*\(\s*0?\d{1,2}-0?\d{1,2}\s*\)\s*$'), '')
        .trimRight();
  }

  GroupedCard get group => widget.group;

  /// bullets를 렌더링하되, ↪ (그룹 메모)가 있으면
  /// 그 그룹 메모와 직전의 bullet 항목들을 노란 박스로 묶어 표시.
  Widget _buildBulletsWithGroup(List<String> bullets, Color cardColor) {
    // 그룹 단위로 분할: ↪ 가 나오면 그 직전까지의 bullet들과 함께 한 그룹
    final List<List<String>> groups = [];
    final List<String> standalone = [];
    List<String> currentGroup = [];

    for (final b in bullets) {
      if (b.startsWith('↪')) {
        // 그룹 메모 → 현재 누적된 bullets와 함께 그룹 마감
        currentGroup.add(b);
        groups.add(List.of(currentGroup));
        currentGroup = [];
      } else {
        currentGroup.add(b);
      }
    }
    // 남은 항목은 그룹 메모 없는 단독 bullets
    if (currentGroup.isNotEmpty) {
      standalone.addAll(currentGroup);
    }

    final children = <Widget>[];

    // 1) 그룹 박스들
    for (final g in groups) {
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB), // 옅은 노란 배경
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: const Color(0xFFF59E0B), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: g.map((b) {
            final isGroupNote = b.startsWith('↪');
            return Padding(
              padding: EdgeInsets.only(
                top: 3, bottom: 3,
                left: isGroupNote ? 4 : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isGroupNote) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: cardColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      b,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isGroupNote
                            ? const Color(0xFF92400E)
                            : const Color(0xFF374151),
                        fontStyle:
                            isGroupNote ? FontStyle.italic : FontStyle.normal,
                        fontWeight:
                            isGroupNote ? FontWeight.w600 : FontWeight.normal,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ));
    }

    // 2) 그룹에 속하지 않은 단독 bullets
    for (final b in standalone) {
      children.add(Padding(
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
                  color: cardColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                b,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF374151),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'RED':
        return const Color(0xFFE53935);
      case 'ORANGE':
        return const Color(0xFFEF6C00);
      case 'BLUE':
        return const Color(0xFF1E88E5);
      case 'GRAY':
        return const Color(0xFFBDBDBD);
      default:
        return const Color(0xFF424242);
    }
  }

  String? _ddayLabel(String? due) {
    if (due == null || due.isEmpty) return null;
    try {
      final parts = due.split('-');
      if (parts.length != 3) return null;
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final today = DateTime.now();
      final t0 = DateTime(today.year, today.month, today.day);
      final diff = d.difference(t0).inDays;
      if (diff == 0) return 'D-DAY';
      if (diff > 0) return 'D-$diff';
      return 'D+${-diff}'; // 지연
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _statusColor(group.status);
    final dday = _ddayLabel(group.dueDate);
    final badge = dday ?? '';

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
        onTap: widget.onGroupTap == null ? null : () => widget.onGroupTap!(group),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== 헤더: 모델명 + 배지 =====
              Row(
                children: [
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
                  if (badge.isNotEmpty)
                    _BadgeChip(label: badge, color: cardColor, emphasize: dday != null),
                ],
              ),
              // ===== 본문: 진행 중 항목 (bullets 우선, 없으면 issues 폴백) =====
              if (group.bullets.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildBulletsWithGroup(
                  _expanded
                      ? group.bullets.map(_cleanTail).toList()
                      : group.bullets.take(_kCollapsedMax).map(_cleanTail).toList(),
                  cardColor,
                ),
                if (group.bullets.length > _kCollapsedMax)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF1E3A5F),
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded
                            ? '▴ 접기'
                            : '▾ 더 보기 (${group.bullets.length - _kCollapsedMax}건)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ] else if (group.issues.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...group.issues.map((it) {
                  final dotColor = _statusColor(it.status);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onIssueTap == null
                        ? null
                        : () => widget.onIssueTap!(group, it),
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
                              _cleanTail(it.headline),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
  final Color? color;
  final bool emphasize;
  const _BadgeChip({required this.label, this.color, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1E3A5F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasize ? c : c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: emphasize ? Colors.white : c,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
