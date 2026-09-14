// 자동차사업부 목록 1행. 고객사 줄과 제품 줄이 같은 카드를 쓴다.
//
// 반도체의 ProjectRevenueRow 와 같은 뼈대다 — 점 · 이름 · 금액 / 보조금액,
// 게이지, 아래 메타 두 개와 오른쪽 한 마디.
// 자동차라서 달라지는 건 들어가는 말뿐이다.
//   진행률 → 매출 비중, 출하 → 계약 물량, 그리고 원가 초과는 빨간 글씨로.
import 'package:flutter/material.dart';

import '../../design/design.dart';

class AutomotiveRowCard extends StatelessWidget {
  final Color dotColor;
  final String name;
  final String? badge;      // '기아 EV3' 같은 꼬리표. 없으면 안 그린다
  final String value;       // '1,047.0억'
  final String subValue;    // '/ 156.3만대'
  final double ratio;       // 게이지 0~1
  final Color barColor;
  final String meta1;
  final String meta2;
  final String trailing;    // '비중 39%' | '원가율 138%'
  final Color? trailingColor; // 빨간색이면 경고
  final bool? isFavorite;   // null 이면 별을 안 그린다 (제품 줄)
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;

  const AutomotiveRowCard({
    super.key,
    required this.dotColor,
    required this.name,
    this.badge,
    required this.value,
    required this.subValue,
    required this.ratio,
    required this.barColor,
    required this.meta1,
    required this.meta2,
    required this.trailing,
    this.trailingColor,
    this.isFavorite,
    this.isSelected = false,
    required this.onTap,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.headerNavy : const Color(0xFFE6EAF0),
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                // 이름 묶음이 남는 폭을 다 먹어야 금액이 카드 오른쪽 끝에 붙는다.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.headerNavy,
                          ),
                        ),
                      ),
                      if (badge != null && badge!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.statusGraySoft,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badge!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSub,
                            ),
                          ),
                        ),
                      ],
                      if (isFavorite != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onToggleFavorite,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(
                              isFavorite!
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 16,
                              color: isFavorite!
                                  ? const Color(0xFFF4B63D)
                                  : const Color(0xFFC5CAD3),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
                if (subValue.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    subValue,
                    style: AppText.caption.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.dividerSoft,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    meta1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMute,
                    ),
                  ),
                ),
                if (meta2.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      meta2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  trailing,
                  style: AppText.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: trailingColor ?? AppColors.textHint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
