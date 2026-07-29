// 홈 화면 '전체 사업부' 그리드에 들어가는 카드 1칸 (시안 v3 — 컴팩트 마감).
//
// 변경 의도:
// - 시안 카드가 지금보다 더 납작하고 정보 밀도가 높음.
// - 패딩 / 폰트 / 행간 / 별 크기 / 점 크기를 한 단계씩 줄여 한 화면에 더 많은 카드가 보이게.
// - 좌측 상단 상태 점 + 상태 텍스트, 우측 상단 즐겨찾기 별, 본문 사업부명 + 프로젝트 수.
//
// 책임 분리:
// - 이 위젯은 표시 + 별 토글 콜백 노출만 담당.
// - 사업부 상태 계산은 호출 측(HomeScreen)에서.

import 'package:flutter/material.dart';
import '../../design/colors.dart';
import '../../design/typography.dart';
import '../../models/dashboard.dart';

class DivisionGridCard extends StatelessWidget {
  const DivisionGridCard({
    super.key,
    required this.divisionId,
    required this.label,
    required this.projectCount,
    required this.status,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final String divisionId;
  final String label;
  final int projectCount;
  final DivisionStatus status;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.reportCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(status),
                    style: AppText.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusTextColor(status),
                    ),
                  ),
                  const Spacer(),
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
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStrong.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.headerNavy, // 시안 v3: 더 진한 색
                  height: 1.0,
                ),
              ),
              Text(
                '프로젝트 $projectCount개',
                style: AppText.caption.copyWith(
                  fontSize: 11,
                  color: const Color(0xFF9AA3B2),
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  static String _statusLabel(DivisionStatus s) {
    switch (s) {
      case DivisionStatus.delayed: return '지연';
      case DivisionStatus.warning: return '임박';
      case DivisionStatus.active:  return '진행 중';
      case DivisionStatus.empty:   return '비어 있음';
    }
  }

  static Color _statusColor(DivisionStatus s) {
    switch (s) {
      case DivisionStatus.delayed: return const Color(0xFFE23D3D);
      case DivisionStatus.warning: return const Color(0xFFE8A339);
      case DivisionStatus.active:  return const Color(0xFF156082);
      case DivisionStatus.empty:   return const Color(0xFFB8BFCC);
    }
  }

  static Color _statusTextColor(DivisionStatus s) {
    switch (s) {
      case DivisionStatus.delayed: return const Color(0xFFE23D3D);
      case DivisionStatus.warning: return const Color(0xFFE8A339);
      case DivisionStatus.active:  return const Color(0xFF156082);
      case DivisionStatus.empty:   return const Color(0xFF7C8594);
    }
  }
}

