import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../base/deadline_pill.dart';

class IssueSubLine {
  final String text;
  final String marker;

  const IssueSubLine({
    required this.text,
    this.marker = '·',
  });
}

class IssueBlock extends StatelessWidget {
  final String headline;
  final String status;
  final bool showStar;
  final List<IssueSubLine> subs;

  // 마감 배지 (선택)
  // deadlineText 예: 'D+6 (06/18)'
  // deadlineTone 으로 색을 따로 지정. 안 주면 DeadlineTone.normal.
  final String? deadlineText;
  final DeadlineTone deadlineTone;

  const IssueBlock({
    super.key,
    required this.headline,
    required this.status,
    this.showStar = false,
    this.subs = const [],
    this.deadlineText,
    this.deadlineTone = DeadlineTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = AppColors.fromStatus(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤드라인 한 줄: ★ + 본문 + (옵션) 마감 배지
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showStar) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: starColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                headline,
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.reportHeading,
                ),
              ),
            ),
            if (deadlineText != null && deadlineText!.isNotEmpty) ...[
              const SizedBox(width: 8),
              DeadlinePill(
                text: deadlineText!,
                tone: deadlineTone,
              ),
            ],
          ],
        ),

        if (subs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x2),
          for (final sub in subs)
            Padding(
              padding: const EdgeInsets.only(
                left: 22,
                top: 2,
                bottom: 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub.marker,
                    style: AppText.body.copyWith(
                      color: AppColors.reportBody,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sub.text,
                      style: AppText.body.copyWith(
                        color: AppColors.reportBody,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
