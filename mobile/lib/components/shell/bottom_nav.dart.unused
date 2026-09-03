// ============================================================
// File: lib/components/shell/bottom_nav.dart
// Section: App shell / Bottom nav
// Figma:  Bottom Nav / 4tab
// Tokens: color/primary, color/textMute
// 사용처: 모든 화면 하단
// ============================================================
import 'package:flutter/material.dart';
import '../../design/design.dart';

enum AppNavTab { home, list, calendar, settings }

class AppBottomNav extends StatelessWidget {
  final AppNavTab current;
  final ValueChanged<AppNavTab> onChanged;

  const AppBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: AppNavTab.values.indexOf(current),
      onTap: (i) => onChanged(AppNavTab.values[i]),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMute,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
        BottomNavigationBarItem(icon: Icon(Icons.view_list_outlined), label: '목록'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: '캘린더'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '설정'),
      ],
    );
  }
}
