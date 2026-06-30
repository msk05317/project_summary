// ============================================================
// File: lib/components/home/issue_card.dart
// Section: Home / Urgent issue card
// Figma:  Home / Issue
// 역할:    즉시 확인이 필요한 이슈 목록 카드 (빨간 톤)
// 토큰:    bg/card, border/default, radius/lg, color/status*
// 사용처:  HomeScreen 세 번째 블록
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';
import '../base/base_card.dart';

// ------------------------------------------------------------
// 1) 한 줄 데이터 모델
// ------------------------------------------------------------
class IssueEntry {
  // 좌측 색 점 컬러 (red / yellow / green / gray 등)
  final Color dotColor;

  // 본문 (예: '물류 — 자재 미입고')
  final String text;

  // 우측 강조 (예: 'D-1', '-8% (전일대비)')
  final String? trailing;

  // 우측 강조 컬러 (기본은 red)
  final Color? trailingColor;

  const IssueEntry({
    required this.dotColor,
    required this.text,
    this.trailing,
    this.trailingColor,
  });
}

// ------------------------------------------------------------
// 2) 카드 본체
// ------------------------------------------------------------
class IssueCard extends StatelessWidget {
  final List<IssueEntry> entries;

  // '모두 보기' 클릭 핸들러
  final VoidCallback? onTapMore;

  const IssueCard({
    super.key,
    required this.entries,
    this.onTapMore,
  });

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      // 살짝 빨간 톤이 들어가도록 border 강조
      borderColor: AppColors.statusRedSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============================================
          // (1) 헤더: 🚨 즉시 확인 ──── 모두 보기 →
          // ============================================
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.statusRedSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  '🚨 즉시 확인',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.statusRed,
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onTapMore,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '모두 보기',
                        style: AppText.captionStrong.copyWith(
                          color: AppColors.statusRed,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppColors.statusRed,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.x3),

          // ============================================
          // (2) 이슈 항목 리스트
          // ============================================
          for (int i = 0; i < entries.length; i++) ...[
            _IssueRow(entry: entries[i]),
            if (i != entries.length - 1)
              const Divider(
                height: AppSpacing.x4,
                color: AppColors.borderSoft,
              ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 3) 한 줄 위젯 (내부 전용)
// ------------------------------------------------------------
class _IssueRow extends StatelessWidget {
  final IssueEntry entry;
  const _IssueRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 좌측 컬러 점
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: entry.dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.x2),

        // 본문
        Expanded(
          child: Text(
            entry.text,
            style: AppText.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // 우측 강조 라벨
        if (entry.trailing != null && entry.trailing!.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.x2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.statusRedSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              entry.trailing!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: entry.trailingColor ?? AppColors.statusRed,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
