import 'package:flutter/material.dart';
import '../../design/design.dart';

/// 보고 상세 화면 상단의 프로젝트명 카드
/// - 디자인 기준: 카드 전체 배경이 #E8EEF5 이어야 함
/// - title: 예) 프레임
/// - subtitle: 예) 보고일자: 2026-06-22 · 25주차
/// - trailing: 우측에 아이콘/배지 등을 붙이고 싶을 때 사용
class ReportTitleCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const ReportTitleCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 카드가 가로 전체를 채우도록 설정
      width: double.infinity,

      // 카드 내부 여백
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x4,
      ),

      decoration: BoxDecoration(
        // [핵심]
        // 프로젝트명 영역 전체 배경색
        color: const Color(0xFFE8EEF5),

        // 둥근 모서리
        borderRadius: BorderRadius.circular(16),

        // 카드 외곽선
        border: Border.all(
          color: AppColors.reportCardBorder,
          width: 1,
        ),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 좌측: 제목 + 부제
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 프로젝트명
                Text(
                  title,
                  style: AppText.h2.copyWith(
                    color: AppColors.reportHeading,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                // subtitle 이 있을 때만 표시
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.x2),

                  Text(
                    subtitle!,
                    style: AppText.caption.copyWith(
                      color: AppColors.reportBody,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 우측 trailing 위젯이 있으면 표시
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.x3),
            trailing!,
          ],
        ],
      ),
    );
  }
}
