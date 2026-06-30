// ============================================================
// File: lib/components/base/base_card.dart
// Section: Base / Card
// Figma:  Card / Base
// Tokens: bg/card, border/default, radius/lg
// 사용처: 모든 카드 (Division, Project, Issue, Summary, Product)
// ============================================================
import 'package:flutter/material.dart';
import '../../design/design.dart';

class BaseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  const BaseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.x4),
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.borderDefault),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}
