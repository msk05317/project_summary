// '확인이 필요한 프로젝트 N건' 한 줄 배너.
//
// 매출(상시 정보)과 예외(오늘 볼 것)는 층을 나눈다.
// 매출 히어로 바로 아래에 한 줄로만 두고, 상세는 즉시 확인 화면에서 본다.
// 0건이면 화면에서 아예 빠진다 (호출하는 쪽에서 판단).
import 'package:flutter/material.dart';

import '../../design/design.dart';

class DivisionAttentionBanner extends StatelessWidget {
  final int count;
  final String? headline; // 가장 급한 1건 요약. 없으면 생략.
  final bool severe;      // 지연이 하나라도 있으면 레드 톤
  final VoidCallback? onTap;

  const DivisionAttentionBanner({
    super.key,
    required this.count,
    this.headline,
    this.severe = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = severe ? AppColors.statusRed : AppColors.summaryCaution;
    final bg = severe ? const Color(0xFFFEF2F2) : const Color(0xFFFDEDE4);
    final border = severe ? const Color(0xFFFCA5A5) : const Color(0xFFF3C6AE);

    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.priority_high_rounded, size: 15, color: tone),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '확인이 필요한 프로젝트 $count건',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: severe
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF9A3412),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (headline != null && headline!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    headline!.trim(),
                    style: AppText.caption.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textSub,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: tone),
        ],
      ),
    );

    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: box,
    );
  }
}
