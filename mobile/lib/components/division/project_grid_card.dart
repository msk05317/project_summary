// 사업부 상세 화면의 프로젝트 카드 (2열 그리드).
// 영문명 / 한글명 / 상태 / 진행률 / 별 토글.
// 좌측 색띠로 상태 표시, 활성(즐겨찾기) 시 파란 테두리.
import 'package:flutter/material.dart';
import '../../design/design.dart';

class ProjectGridCard extends StatelessWidget {
  final String englishName;     // "Powerbox"
  final String koreanName;      // "파워박스"
  final String status;          // "지연" / "주의" / "정상"
  final int progressPercent;    // 55
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
    final borderColor = isSelected
        ? const Color(0xFF156082)
        : AppColors.reportCardBorder;
    final borderWidth = isSelected ? 1.6 : 1.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: hasData ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              // 좌측 상태 색띠
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    bottomLeft: Radius.circular(11),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
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
                            '$progressPercent%',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
