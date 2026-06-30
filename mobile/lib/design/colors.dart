import 'package:flutter/material.dart';

/// 앱 전역 컬러 토큰
///
/// 사용 규칙:
/// - 새 위젯에서 Color(0xFF...) 하드코딩 금지
/// - 반드시 AppColors.xxx 사용
///
/// 매핑:
/// - status (RED/YELLOW/GREEN/GRAY) → 도메인 상태
/// - text/bg/border → 공통 UI
class AppColors {
  AppColors._();

  // ============================================================
  // Status (도메인용 — Tracker, Badge, Card border)
  // ============================================================
  static const Color statusRed    = Color(0xFFDC2626); // 지연/부족
  static const Color statusYellow = Color(0xFFF59E0B); // 진행 중
  static const Color statusGreen  = Color(0xFF10B981); // 완료
  static const Color statusGray   = Color(0xFFCBD5E1); // 미시작/N/A

  // Status 보조 (배경/살짝 톤)
  static const Color statusRedSoft    = Color(0xFFFEE2E2);
  static const Color statusYellowSoft = Color(0xFFFEF3C7);
  static const Color statusGreenSoft  = Color(0xFFD1FAE5);
  static const Color statusGraySoft   = Color(0xFFF1F5F9);

  // ============================================================
  // 배경 / 보더 / 텍스트
  // ============================================================
  // 배경
  static const Color bgPage = Color(0xFFF8FAFC);
  static const Color bgCard = Color(0xFFFFFFFF);

  // 보더
  static const Color borderDefault = Color(0xFFE5E7EB);
  static const Color borderSoft    = Color(0xFFECEFF3);

  // 텍스트
  static const Color textMain = Color(0xFF111827);
  static const Color textSub  = Color(0xFF4B5563);
  static const Color textMute = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);

  // ============================================================
  // 액션
  // ============================================================
  static const Color primary = Color(0xFF1E3A5F); // 헤더/주요 버튼
  static const Color accent  = Color(0xFF3B82F6); // 미리보기 버튼 등

  // ============================================================
  // Report 전용 보정 토큰 (Section: report colors v1)
  // 사용처: 보고 상세 화면
  // ============================================================

  // 페이지 배경 (보고/상세 화면 공통 배경)
  static const Color reportPageBg = Color(0xFFF5F7FA);

  // 프로젝트명(타이틀) 카드 배경
  static const Color reportTitleCardBg = Color(0xFFE8EEF5);

  // 일반 카드 배경 (현황, CEFEM 프레임 등)
  static const Color reportCardBg = Color(0xFFFFFFFF);

  // 카드 외곽선
  static const Color reportCardBorder = Color(0xFFE5E7EB);

  // 본문 텍스트 (셀, sub, bullet 등)
  static const Color reportBody = Color(0xFF6B7280);

  // 제목/강조 텍스트 (h2, h1 등 — 제목·본문 외 강조)
  static const Color reportHeading = Color(0xFF0E2841);

  // ============================================================
  // Home 화면 전용 보정 토큰 (Section: home colors v1)
  // 사용처: HomeHeader, SummaryCard, ImmediateCheckCard,
  //        SearchFilterRow, DivisionGridCard 등 홈 시안 컴포넌트
  // ============================================================

  // 상단 헤더 네이비 배경
  // - HomeHeader 배경, 상태바 톤 일치용
  static const Color headerNavy = Color(0xFF0E2841);

  // 오늘 날짜 강조 텍스트 색상
  // - "오늘은 6월 22일" 에서 날짜 부분에 적용
  static const Color todayBlue = Color(0xFF156082);

  // KPI 카드 내부 세로 구분선
  // - SummaryCard 의 4분할(진행중/정상/주의/지연) 사이 라인
  static const Color dividerSoft = Color(0xFFEEF1F5);

  // 즉시 확인 카드 배경
  // - 알림성 카드 (FEE2E2 옅은 레드)
  static const Color alertBg = Color(0xFFFEE2E2);

  // 즉시 확인 카드 보더
  // - alertBg 보다 살짝 진한 톤
  static const Color alertBorder = Color(0xFFFCA5A5);

  // ============================================================
  // SummaryCard 전용 KPI 컬러 (Section: summary kpi colors v1)
  // - 시안에서 KPI 4개 숫자 색상이 별도로 정의됨
  // - 기존 statusRed/statusYellow/statusGreen 톤과 다르므로
  //   별도 토큰으로 추가하여 다른 컴포넌트에 영향 없도록 분리
  // 사용처: SummaryCard 의 진행중/정상/주의/지연 숫자
  // ============================================================

  // 진행 중 — 차분한 블루톤
  static const Color summaryInProgress = Color(0xFF156082);

  // 정상 — 그린톤 (statusGreen 보다 어두움)
  static const Color summaryNormal = Color(0xFF196B24);

  // 주의 — 오렌지톤
  static const Color summaryCaution = Color(0xFFE97132);

  // 지연 — 강한 레드 (시안 강조용, statusRed 보다 채도 높음)
  static const Color summaryDelayed = Color(0xFFFF0000);

  // ============================================================
  // 헬퍼
  // ============================================================
  /// status 문자열 → Color
  static Color fromStatus(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'RED':    return statusRed;
      case 'YELLOW': return statusYellow;
      case 'GREEN':  return statusGreen;
      case 'GRAY':
      case 'BLACK':  return statusGray;
    }
    return statusGray;
  }
}
