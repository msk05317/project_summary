// 앱 글로벌 하단 네비게이션 바.
// 시안 순서: 홈 → 목록 → 캘린더 → 설정
// 라우팅 자체는 이 컴포넌트가 하지 않고, onChanged 콜백을 통해
// 상위 화면이 결정합니다 (관심사 분리).

import 'package:flutter/material.dart';

import '../../design/design.dart';

// 하단 네비게이션 탭 종류.
// 화면 라우팅/현재 활성 탭 표시에 모두 사용합니다.
enum AppNavTab { home, list, calendar, settings }

class AppBottomNav extends StatelessWidget {
  // 현재 활성 탭.
  final AppNavTab current;

  // 탭 선택 시 상위 화면에 변경 사실을 알리는 콜백.
  final ValueChanged<AppNavTab> onChanged;

  const AppBottomNav({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.x2,
        16,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: '홈',
              active: current == AppNavTab.home,
              onTap: () => onChanged(AppNavTab.home),
            ),
            _NavItem(
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard_rounded,
              label: '목록',
              active: current == AppNavTab.list,
              onTap: () => onChanged(AppNavTab.list),
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded,
              label: '캘린더',
              active: current == AppNavTab.calendar,
              onTap: () => onChanged(AppNavTab.calendar),
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: '설정',
              active: current == AppNavTab.settings,
              onTap: () => onChanged(AppNavTab.settings),
            ),
          ],
        ),
      ),
    );
  }
}

// 단일 탭 아이콘 + 라벨을 표시하는 내부 위젯.
// 외부에 노출되지 않으므로 private(_) 으로 둡니다.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 활성/비활성 색은 디자인 토큰에서 가져와 일관성을 유지합니다.
    // 시안 v3: 활성 탭은 헤더와 동일한 네이비(#0E2841)
    final activeColor = AppColors.headerNavy;
    final inactiveColor = AppColors.reportBody;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? activeIcon : icon,
                size: 22,
                color: active ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
