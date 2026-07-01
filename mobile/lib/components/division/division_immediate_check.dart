// 사업부 상세 화면의 "이 사업부 즉시 확인" 섹션.
// 빨간 테두리 박스 안에 우선순위 배지 + 지연 배지 + D-day + 한줄 텍스트.
import 'package:flutter/material.dart';
import '../../design/design.dart';

enum ImmediatePriority { high, mid }

class DivisionImmediateItem {
  final ImmediatePriority priority;
  final String dueText;     // "D-1"
  final String headline;    // "챔버 · 출하 지연"
  final String? detail;      // "전월부터 정체"
  final String status;      // "지연" / "주의"
  final VoidCallback? onTap;

  DivisionImmediateItem({
    required this.priority,
    required this.dueText,
    required this.headline,
    this.detail,
    required this.status,
    this.onTap,
  });
}

class DivisionImmediateCheckSection extends StatelessWidget {
  final String divisionShortLabel;   // "반도체"
  final List<DivisionImmediateItem> items;
  final VoidCallback onTapSeeAll;

  const DivisionImmediateCheckSection({
    super.key,
    required this.divisionShortLabel,
    required this.items,
    required this.onTapSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error, color: Color(0xFFFF0000), size: 16),
            const SizedBox(width: 6),
            Text(
              '이 사업부 즉시 확인',
              style: AppText.bodyStrong.copyWith(
                fontSize: 14,
                color: AppColors.headerNavy,
              ),
            ),
            const Spacer(),
            Text(
              '${items.length}건',
              style: AppText.caption.copyWith(
                fontSize: 12,
                color: const Color(0xFFFF0000),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF0000), width: 1.2),
          ),
          child: Column(
            children: [
              for (int i = 0; i < visibleItems.length; i++) ...[
                _ImmediateRow(item: visibleItems[i]),
                if (i < visibleItems.length - 1)
                  const Divider(height: 14, color: Color(0xFFEEF1F5)),
              ],
              const SizedBox(height: 8),
              InkWell(
                onTap: onTapSeeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$divisionShortLabel 이슈 모두 보기',
                        style: AppText.caption.copyWith(
                          fontSize: 12,
                          color: const Color(0xFFFF0000),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 14, color: Color(0xFFFF0000)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImmediateRow extends StatelessWidget {
  final DivisionImmediateItem item;
  const _ImmediateRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final priorityColor = item.priority == ImmediatePriority.high
        ? const Color(0xFFFF0000)
        : const Color(0xFFE97132);
    final priorityLabel =
        item.priority == ImmediatePriority.high ? '최우선' : '중간';

    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(text: priorityLabel, color: priorityColor),
                const SizedBox(width: 6),
                _Badge(
                  text: item.status,
                  color: const Color(0xFF7C8594),
                  filled: false,
                ),
                const Spacer(),
                Text(
                  item.dueText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: priorityColor,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right,
                    size: 14, color: Color(0xFF7C8594)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.headline,
              style: AppText.bodyStrong.copyWith(
                fontSize: 13,
                color: AppColors.headerNavy,
              ),
            ),
            if (item.detail != null && item.detail!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.detail!,
                style: AppText.caption.copyWith(
                  fontSize: 11,
                  color: const Color(0xFF7C8594),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const _Badge({required this.text, required this.color, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}
