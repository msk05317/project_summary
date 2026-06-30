// 홈 화면 상단 헤더 컴포넌트 (시안 v2 — 네이비 헤더 통합형).
//
// 변경 의도:
// - 기존: 흰 배경 위에 로고/아이콘/인사말이 떠 있어 시안과 톤이 달랐음.
// - 시안: 상단 네이비(#0E2841) 헤더 블록 안에 로고/아이콘/인사말/오늘 날짜가
//        모두 들어가 있고, 본문 카드들과 시각적으로 분리됨.
//
// 이 컴포넌트가 책임지는 영역:
//   1) 상태바 영역까지 네이비로 채우기 (SafeArea)
//   2) 좌측 'OneView' 로고 + 우측 알림/검색 아이콘
//   3) "안녕하세요" 인사말 (로그인 도입 전: 사용자명 없이 고정 문구)
//   4) "오늘은 {todayLabel} 입니다" — 날짜 부분만 강조 컬러
//
// 책임지지 않는 영역:
//   - todayLabel 포맷 ('6월 22일' 같은 문자열은 호출 화면에서 생성)
//   - 알림/검색 아이콘 실제 동작 (콜백만 노출)
//
// 호출 예:
//   HomeHeader(
//     todayLabel: '6월 22일',
//     onTapNotification: () { ... },
//     onTapSearch: () { ... },
//   )

import 'package:flutter/material.dart';

import '../../design/design.dart';

class HomeHeader extends StatelessWidget {
  // 오늘 날짜 라벨. 예: '6월 22일'
  // - HomeScreen 에서 DateTime → 문자열 변환 후 전달
  // - 빈 문자열일 경우 "오늘은 입니다" 가 되지 않도록 build() 에서 가드
  final String todayLabel;

  // 알림 아이콘 콜백. null 이면 InkWell 자체는 동작하지만 아무 일도 안 함.
  final VoidCallback? onTapNotification;

  // 검색 아이콘 콜백.
  final VoidCallback? onTapSearch;

  const HomeHeader({
    super.key,
    required this.todayLabel,
    this.onTapNotification,
    this.onTapSearch,
  });

  @override
  Widget build(BuildContext context) {
    // 헤더 전체 배경: 시안에서 가장 눈에 띄는 식별 요소.
    // - AppColors.headerNavy 는 0단계에서 새로 추가된 토큰 (#0E2841).
    final navy = AppColors.headerNavy;

    return Container(
      width: double.infinity,
      color: navy,
      // 상단 노치/상태바 영역까지 네이비로 칠해지도록 SafeArea 는 top:false 로 두고,
      // 대신 MediaQuery.padding.top 만큼 위쪽 패딩을 직접 줍니다.
      // (이렇게 하면 상태바 컬러가 헤더와 자연스럽게 이어집니다)
      padding: EdgeInsets.fromLTRB(
        AppSpacing.x4,
        MediaQuery.of(context).padding.top + AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─────────────────────────────────────────────
          // 1행: 로고 + 우측 액션 아이콘
          // ─────────────────────────────────────────────
          Row(
            children: [
              // 'OneView' 로고는 시안 기준 흰색 + 굵은 weight
              const Text(
                'OneView',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),

              // 알림 아이콘 — 네이비 배경 위라서 모든 아이콘은 흰색 계열
              IconButton(
                onPressed: onTapNotification,
                icon: const Icon(Icons.notifications_none_rounded),
                color: Colors.white,
                splashRadius: 22,
              ),

              // 검색 아이콘
              IconButton(
                onPressed: onTapSearch,
                icon: const Icon(Icons.search_rounded),
                color: Colors.white,
                splashRadius: 22,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.x3),

          // ─────────────────────────────────────────────
          // 2행: 인사말
          // - 로그인 전이라 사용자명 없이 '안녕하세요' 만 표시
          // - 추후 로그인 도입 시 userName prop 추가 예정
          // ─────────────────────────────────────────────
          const Text(
            '안녕하세요',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 4),

          // ─────────────────────────────────────────────
          // 3행: 오늘 날짜 안내
          // - "오늘은 {todayLabel} 입니다" 형태
          // - 날짜 부분만 강조 컬러(AppColors.todayBlue, #156082)로 분리
          // - RichText 로 inline span 컬러 적용
          // ─────────────────────────────────────────────
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white70, // 본문 톤은 옅게
                height: 1.3,
              ),
              children: [
                const TextSpan(text: '오늘은 '),
                TextSpan(
                  text: todayLabel.isEmpty ? '오늘' : todayLabel,
                  style: TextStyle(
                    color: AppColors.todayBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const TextSpan(text: ' 입니다'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
