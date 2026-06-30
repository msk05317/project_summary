// 홈 화면 상단의 '즐겨찾기 프로젝트' 가로 스크롤 카드 한 칸.
// 별표(★) 아이콘 + 프로젝트명 + 소속 사업부명을 보여줍니다.
// status 값에 따라 별 색이 자동으로 결정됩니다.

import 'package:flutter/material.dart';

import '../../design/design.dart';

class FavoriteProjectChip extends StatelessWidget {
  // 프로젝트 이름 (예: '프레임')
  final String label;

  // 소속 사업부 이름 (예: '반도체사업부'). 비어 있으면 노출하지 않습니다.
  final String? divisionLabel;

  // 백엔드 상태 코드.
  // 'RED' / 'YELLOW' / 'GREEN' / 'GRAY' / 'BLUE' / 'BLACK' 중 하나.
  // AppColors.fromStatus 로 별 색으로 변환합니다.
  final String? status;

  // 카드 탭 콜백. 보통 ReportDetailScreen 으로 이동시키는 데 사용합니다.
  final VoidCallback? onTap;

  const FavoriteProjectChip({
    super.key,
    required this.label,
    this.divisionLabel,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 상태 → 별 색 매핑.
    // status 가 비어 있으면 'GRAY' 로 폴백합니다.
    final tone = AppColors.fromStatus(status ?? 'GRAY');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        // 카드 폭은 디자인 시안 기준으로 고정.
        width: 180,
        padding: const EdgeInsets.all(AppSpacing.x3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.reportCardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 별표 + 프로젝트명 (이름은 한 줄로 잘라서 표시)
            Row(
              children: [
                Icon(Icons.star_rounded, size: 16, color: tone),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.reportHeading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 하단: 사업부명 (있을 때만)
            if ((divisionLabel ?? '').isNotEmpty)
              Text(
                divisionLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.reportBody),
              ),
          ],
        ),
      ),
    );
  }
}
