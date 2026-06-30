// ============================================================
// File: lib/components/issue_item.dart
// Purpose: 이슈사항의 한 항목 (bullet / sub / group_note / photo)
// 사용처: 카드 상세 화면 이슈사항 섹션
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

enum IssueItemKind { bullet, sub, groupNote, photo }

class IssueItem extends StatelessWidget {
  // ----------------------------------------------------------
  // Props
  // ----------------------------------------------------------
  final IssueItemKind kind;
  final String text;
  final String? photoUrl;
  final String? dueDate; // 'D+3' 등 배지

  const IssueItem({
    super.key,
    required this.kind,
    required this.text,
    this.photoUrl,
    this.dueDate,
  });

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      // ----------------------------------------------------
      // sub: 묶음 제목 ('1) CORVA KPE')
      // ----------------------------------------------------
      case IssueItemKind.sub:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.x2),
          child: Text(text, style: AppText.bodyStrong),
        );

      // ----------------------------------------------------
      // group_note: 보조 안내 (들여쓰기 + 화살표)
      // ----------------------------------------------------
      case IssueItemKind.groupNote:
        return Padding(
          padding: const EdgeInsets.only(left: AppSpacing.x4, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('↪ ', style: AppText.caption),
              Expanded(child: Text(text, style: AppText.caption)),
            ],
          ),
        );

      // ----------------------------------------------------
      // photo: 첨부 이미지
      // ----------------------------------------------------
      case IssueItemKind.photo:
        if (photoUrl == null || photoUrl!.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.rSm),
            child: Image.network(photoUrl!, fit: BoxFit.cover),
          ),
        );

      // ----------------------------------------------------
      // bullet: 일반 항목
      // ----------------------------------------------------
      case IssueItemKind.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: AppText.body),
              Expanded(child: Text(text, style: AppText.body)),
              if (dueDate != null && dueDate!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.x2),
                Text(dueDate!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.statusRed)),
              ],
            ],
          ),
        );
    }
  }
}
