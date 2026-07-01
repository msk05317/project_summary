// 사업부 상세 화면의 프로젝트 카드 (2열 그리드).
// 영문명 / 한글명 / 상태 / 진행률 / 별 토글.
// 좌측 색띠 + 흰 카드 모두 border-radius를 자연스럽게 따라간다.
import 'package:flutter/material.dart';
import '../../design/design.dart';

class ProjectGridCard extends StatelessWidget {
  final String englishName;
  final String koreanName;
  final String status;
  final int progressPercent;
  final bool isFavorite;
  final bool isSelected;
  final bool hasData;
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
    required this.onTap,
    required this.onToggleFavorite,
  });

  Color get _statusColor {
    if (!hasData) return const Color(0xFFB8BFCC);
    switch (status) {
      case '지연':
        return const Color(0xFFFF0000);
      case '주의':
        return const Color(0xFFE97132);
      case '정상':
      default:
        return const Color(0xFF196B24);
    }
  }

  @override
  Widget build(BuildContext context) {
    const double outerRadius = 20;
    const double stripeWidth = 6;

    final Color borderColor = isSelected
        ? const Color(0xFF156082)
        : const Color(0xFFE6EAF0);
    final double borderWidth = isSelected ? 1.6 : 1.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 4),
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
          onTap: hasData ? onTap : null,
          child: Stack(
            children: [
              // 왼쪽 색띠: 카드 radius를 그대로 따라가는 형태
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: stripeWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _statusColor),
                ),
              ),
              // 본문
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  stripeWidth + 12,
                  12,
                  12,
                  12,
                ),
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
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasData ? status : '데이터 없음',
                          style: AppText.caption.copyWith(
                            fontSize: 11,
                            color: const Color(0xFF7C8594),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          hasData ? '$progressPercent%' : '-',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
