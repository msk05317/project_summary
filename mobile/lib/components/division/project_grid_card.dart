// 사업부 상세 화면의 프로젝트 카드 (2열 그리드).
// 영문명 / 한글명 / 상태 / 진행률 / 별 토글.
// 좌측 색띠 + 흰 카드 모두 border-radius를 자연스럽게 따라간다.
import 'package:flutter/material.dart';
import '../../design/design.dart';

class ProjectGridCard extends StatelessWidget {
  final String englishName;
  final String koreanName;
  final String status;
  final int? progressPercent;
  final bool isFavorite;
  final bool isSelected;
  final bool hasData;
  // 등록된 모델 수. 데이터가 없을 때 왜 없는지 구분해 보여주기 위해 사용.
  final int modelsTotal;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const ProjectGridCard({
    super.key,
    required this.englishName,
    required this.koreanName,
    required this.status,
    required this.progressPercent,
    required this.isFavorite,
    required this.isSelected,
    this.hasData = true,
    this.modelsTotal = 0,
    required this.onTap,
    required this.onToggleFavorite,
  });

  // 진행률 강조색: 지연/주의는 경고색, 그 외에는 브랜드 네이비 한 가지로 통일해
  // 카드가 신호등처럼 알록달록해지지 않게 한다.
  Color get _accent {
    if (!hasData) return const Color(0xFFC5CAD3);
    switch (status) {
      case '지연':
        return const Color(0xFFDC2626);
      case '주의':
        return const Color(0xFFD97706);
      default:
        return AppColors.headerNavy;
    }
  }

  @override
  Widget build(BuildContext context) {
    const double outerRadius = 16;

    final Color borderColor = isSelected
        ? const Color(0xFF156082)
        : const Color(0xFFE6EAF0);
    final double borderWidth = isSelected ? 1.6 : 1.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(outerRadius),
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            englishName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              fontSize: 10,
                              color: const Color(0xFF7C8594),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onToggleFavorite,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              isFavorite
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 16,
                              color: isFavorite
                                  ? const Color(0xFFF4B63D)
                                  : const Color(0xFFC5CAD3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      koreanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headerNavy,
                      ),
                    ),
                    if (hasData) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '진행률',
                            style: AppText.caption.copyWith(
                              fontSize: 10,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$progressPercent%',
                            style: TextStyle(
                              fontSize: 18,
                              height: 1.0,
                              fontWeight: FontWeight.w800,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: ((progressPercent ?? 0) / 100).clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFFEDF0F5),
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                    ] else
                      Text(
                        modelsTotal > 0
                            ? '모델 $modelsTotal종 · 진행률 미입력'
                            : '등록된 모델 없음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontSize: 11,
                          color: const Color(0xFFA8AFBB),
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
