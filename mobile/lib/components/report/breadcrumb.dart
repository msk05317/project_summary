// ============================================================
// File: lib/components/report/breadcrumb.dart
// Section: Report / Breadcrumb
// Figma:  Report / Breadcrumb
// 역할:    화면 상단의 경로 표시 (예: 목록 › 반도체사업부 › 프레임)
// 토큰:    typo/caption, typo/captionStrong, color/textSub, color/textMain
// 사용처:  보고 상세 화면 헤더 바로 아래
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

// ------------------------------------------------------------
// 1) 한 항목 데이터 모델
// ------------------------------------------------------------
class BreadcrumbItem {
  // 표시할 라벨 (예: '목록', '반도체사업부', '프레임')
  final String label;

  // 클릭 시 동작 (마지막 항목은 보통 null — 현재 화면이므로)
  final VoidCallback? onTap;

  const BreadcrumbItem({
    required this.label,
    this.onTap,
  });
}

// ------------------------------------------------------------
// 2) 위젯 본체
// ------------------------------------------------------------
class Breadcrumb extends StatelessWidget {
  // 좌→우 순서대로 경로
  final List<BreadcrumbItem> items;

  const Breadcrumb({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      // 경로가 길어지면 가로 스크롤 (모바일에서 자주 발생)
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x2,
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _Crumb(
              item: items[i],
              isLast: i == items.length - 1,
            ),
            if (i != items.length - 1) ...[
              const SizedBox(width: AppSpacing.x2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textMute,
              ),
              const SizedBox(width: AppSpacing.x2),
            ],
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// 3) 내부 — 한 항목 위젯
// ------------------------------------------------------------
class _Crumb extends StatelessWidget {
  final BreadcrumbItem item;
  final bool isLast;

  const _Crumb({
    required this.item,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    // 마지막 항목: 현재 화면 → 굵게 + 진한 색
    // 그 외: 이동 가능 → 회색 + 탭 가능
    final style = isLast
        ? AppText.captionStrong.copyWith(color: AppColors.textMain)
        : AppText.caption.copyWith(color: AppColors.textSub);

    final label = Text(labelOrEmpty(item.label), style: style);

    if (isLast || item.onTap == null) {
      return label;
    }
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 2,
        ),
        child: label,
      ),
    );
  }
}

// 빈 라벨 들어와도 레이아웃 깨지지 않게 보호
String labelOrEmpty(String s) => s.isEmpty ? ' ' : s;
