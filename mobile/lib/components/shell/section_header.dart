// ============================================================
// File: lib/components/shell/section_header.dart
// Section: App shell / Section header
// Figma:  Section Header
// Tokens: typo/h2, space/x3
// 사용처: 카드 그룹 위 타이틀
// ============================================================
import 'package:flutter/material.dart';
import '../../design/design.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.x3,
        horizontal: AppSpacing.x1,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.h2)),
          ?trailing,
        ],
      ),
    );
  }
}
