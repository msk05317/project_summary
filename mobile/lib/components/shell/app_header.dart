// ============================================================
// File: lib/components/shell/app_header.dart
// Section: App shell / Top header
// Figma:  Header / Default
// Tokens: color/primary, typo/h1
// 사용처: 모든 화면 상단
// ============================================================
import 'package:flutter/material.dart';
import '../../design/design.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBack;
  final List<Widget> actions;

  const AppHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      automaticallyImplyLeading: showBack,
      title: Text(
        title,
        style: AppText.h2.copyWith(color: Colors.white),
      ),
      actions: actions,
    );
  }
}
