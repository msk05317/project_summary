// 홈 화면 '전체 사업부' 그리드에 들어가는 카드 1칸.
//
// 정리 의도 (v4):
// - 예전 카드는 상단에 '● 비어 있음' 텍스트가 먼저 오고 사업부명이 그 아래였다.
//   12칸 중 10칸이 '비어 있음' 이라 화면 전체가 회색 문구로 덮여, 정작 스캔해야 할
//   사업부명이 뒤로 밀렸다.
// - 그래서 순서를 뒤집었다. 사업부명(가장 크게) → 프로젝트 수 → 상태 pill(가장 작게).
// - 상태 pill 은 지연/임박/진행 중일 때만 색 배경을 준다. '비어 있음' 은 조용한 회색 글자로만.
// - 한글이 잘려 보이던 height:1.0 을 1.15~1.2 로 풀고, 별 히트박스가 줄 높이를
//   밀어올리던 문제(패딩 10)를 고정 크기 30dp 로 바꿨다.
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

  bool get _quiet => status == DivisionStatus.empty;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.reportCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1) 사업부명 + 즐겨찾기
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.headerNavy,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  // 카드 전체 onTap 과 붙어 있어 아이콘 크기만큼만 잡으면 오탭이 잦다.
                  // 패딩 대신 고정 30dp 박스로 잡아 줄 높이를 흔들지 않는다.
                  GestureDetector(
                    onTap: onToggleFavorite,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 17,
                        color: isFavorite
                            ? const Color(0xFFF4B63D)
                            : const Color(0xFFCED4DE),
                      ),
                    ),
                  ),
                ],
              ),

              // 2) 프로젝트 수
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Text(
                  projectCount == 0 ? '등록된 프로젝트 없음' : '프로젝트 $projectCount개',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    fontSize: 11.5,
                    color: const Color(0xFF98A1B0),
                    height: 1.2,
                  ),
                ),
              ),

              const Spacer(),

              // 3) 상태 — 눈에 걸려야 하는 것만 색을 쓴다
              if (projectCount > 0) _statusPill(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill() {
    final c = _statusColor(status);
    final text = Text(
      _statusLabel(status),
      style: AppText.caption.copyWith(
        fontSize: 11.5,
        fontWeight: _quiet ? FontWeight.w500 : FontWeight.w700,
        color: _quiet ? const Color(0xFF98A1B0) : c,
        height: 1.1,
      ),
    );

    // '비어 있음' 은 배경 없이 조용하게. 나머지는 색 pill 로 눈에 걸리게.
    if (_quiet) return text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          text,
        ],
      ),
    );
  }

  static String _statusLabel(DivisionStatus s) {
    switch (s) {
      case DivisionStatus.delayed: return '지연';
      case DivisionStatus.warning: return '임박';
      case DivisionStatus.active:  return '진행 중';
      case DivisionStatus.empty:   return '진행 데이터 없음';
    }
  }

  static Color _statusColor(DivisionStatus s) {
    switch (s) {
      case DivisionStatus.delayed: return const Color(0xFFE23D3D);
      case DivisionStatus.warning: return const Color(0xFFE8A339);
      case DivisionStatus.active:  return const Color(0xFF156082);
      case DivisionStatus.empty:   return const Color(0xFF98A1B0);
    }
  }
}
