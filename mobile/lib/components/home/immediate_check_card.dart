// 홈 화면의 '즉시 확인' 카드 (시안 v3 — 2줄형 본문).
//
// 반영 사항:
// 1) '모두 보기 →'를 항상 빨간색으로 표시
// 2) 각 항목을 2줄 구조로 렌더링
//    - 1줄: [프로젝트명] · 핵심 내용
//    - 2줄: 핵심 내용 상세 요약
//
// 책임:
// - 이 파일은 오직 표시만 담당합니다.
// - headline / detail 텍스트를 어떻게 만들지는 HomeScreen 쪽에서 결정합니다.

import 'package:flutter/material.dart';

import '../../design/design.dart';

enum ImmediateCheckTone { urgent, warn, info }

class ImmediateCheckItem {
  // 라우팅용 프로젝트 키
  final String projectKey;

  // 예: '블룸'
  final String projectLabel;

  // 1줄의 핵심 키워드. 예: '자재 미입고'
  final String? headline;

  // 2줄의 상세 요약. 예: '핵심 자재 2종 미입고 — 입고 예정일 미정'
  final String? detail;

  // 우측 배지 텍스트. 예: 'D-1'
  final String dueText;

  // 배지 톤
  final ImmediateCheckTone tone;

  // 상태 문자열
  final String status;

  const ImmediateCheckItem({
    required this.projectKey,
    required this.dueText,
    required this.tone,
    required this.status,
    required this.projectLabel,
    this.headline,
    this.detail,
  });
}

class ImmediateCheckCard extends StatelessWidget {
  final List<ImmediateCheckItem> items;
  final void Function(ImmediateCheckItem item)? onTapItem;
  final VoidCallback? onTapShowAll;

  const ImmediateCheckCard({
    super.key,
    required this.items,
    this.onTapItem,
    this.onTapShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.alertBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 헤더만 연한 빨강
            Container(
              width: double.infinity,
              color: AppColors.alertBg,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.statusRed,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '즉시 확인',
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.statusRed,
                    ),
                  ),
                  const Spacer(),

                  // 시안 요구: 모두 보기와 화살표 모두 빨간색
                  InkWell(
                    onTap: onTapShowAll,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        '모두 보기 →',
                        style: AppText.caption.copyWith(
                          color: AppColors.statusRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 본문은 흰색
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              child: Column(
                children: List.generate(items.length, (i) {
                  final item = items[i];
                  final isLast = i == items.length - 1;
                  return _ImmediateRow(
                    item: item,
                    onTap: onTapItem == null ? null : () => onTapItem!(item),
                    showDivider: !isLast,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImmediateRow extends StatelessWidget {
  final ImmediateCheckItem item;
  final VoidCallback? onTap;
  final bool showDivider;

  const _ImmediateRow({
    required this.item,
    required this.onTap,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    Color dotColor;
    switch (item.tone) {
      case ImmediateCheckTone.urgent:
        dotColor = AppColors.statusRed;
        break;
      case ImmediateCheckTone.warn:
        dotColor = AppColors.summaryCaution;
        break;
      case ImmediateCheckTone.info:
        dotColor = AppColors.textMute;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 좌측 점
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 가운데 2줄 텍스트
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1줄: [프로젝트명] · 핵심 내용
                      RichText(
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.reportHeading,
                            height: 1.25,
                          ),
                          children: [
                            TextSpan(
                              text: item.projectLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if ((item.headline ?? '').isNotEmpty) ...[
                              TextSpan(
                                text: ' · ',
                                style: TextStyle(
                                  color: AppColors.textMute,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: item.headline!,
                                style: TextStyle(
                                  color: AppColors.reportBody,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // 2줄: 핵심 내용 상세 요약
                      if ((item.detail ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textMute,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 우측 배지 + chevron
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DueBadge(text: item.dueText, tone: item.tone),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textMute,
                    ),
                  ],
                ),
              ],
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  height: 1,
                  color: AppColors.dividerSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  final String text;
  final ImmediateCheckTone tone;

  const _DueBadge({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tone) {
      case ImmediateCheckTone.urgent:
        bg = AppColors.statusRedSoft;
        fg = AppColors.statusRed;
        break;
      case ImmediateCheckTone.warn:
        bg = AppColors.statusYellowSoft;
        fg = AppColors.summaryCaution;
        break;
      case ImmediateCheckTone.info:
        bg = AppColors.dividerSoft;
        fg = AppColors.reportHeading;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
