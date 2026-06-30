// ============================================================
// File: lib/components/report/report_tab_bar.dart
// Section: Report / Tab bar
// Figma:  Report / TabBar (보고 / 생산 / 입고 / 출하)
// 역할:    보고 상세 화면 상단의 4개 탭
// 주의:    아이콘 대신 asset 이미지 사용
// 사용처:  보고 상세 화면 — Breadcrumb 아래
// ============================================================

import 'package:flutter/material.dart';
import '../../design/design.dart';

// ------------------------------------------------------------
// 탭 종류
// ------------------------------------------------------------
enum ReportTab { report, production, inbound, outbound }

// ------------------------------------------------------------
// 각 탭에 들어갈 asset 정보
// ------------------------------------------------------------
class ReportTabAsset {
  final ReportTab tab;
  final String label;

  // 비활성 상태 이미지
  final String inactiveAssetPath;

  // 활성 상태 이미지
  final String activeAssetPath;

  const ReportTabAsset({
    required this.tab,
    required this.label,
    required this.inactiveAssetPath,
    required this.activeAssetPath,
  });
}

// ------------------------------------------------------------
// ReportTabBar 본체
// ------------------------------------------------------------
class ReportTabBar extends StatelessWidget {
  final ReportTab current;
  final ValueChanged<ReportTab> onChanged;

  const ReportTabBar({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // ========================================================
    // 실제 파일명/경로는 네 asset 정리한 뒤 여기만 바꾸면 됨
    // ========================================================
    const tabs = [
      ReportTabAsset(
        tab: ReportTab.report,
        label: '보고',
        inactiveAssetPath: 'assets/icons/report/report_off.png',
        activeAssetPath: 'assets/icons/report/report_on.png',
      ),
      ReportTabAsset(
        tab: ReportTab.production,
        label: '생산',
        inactiveAssetPath: 'assets/icons/report/production_off.png',
        activeAssetPath: 'assets/icons/report/production_on.png',
      ),
      ReportTabAsset(
        tab: ReportTab.inbound,
        label: '입고',
        inactiveAssetPath: 'assets/icons/report/inbound_off.png',
        activeAssetPath: 'assets/icons/report/inbound_on.png',
      ),
      ReportTabAsset(
        tab: ReportTab.outbound,
        label: '출하',
        inactiveAssetPath: 'assets/icons/report/outbound_off.png',
        activeAssetPath: 'assets/icons/report/outbound_on.png',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderSoft,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: tabs
            .map(
              (item) => Expanded(
                child: _ReportTabItem(
                  item: item,
                  isActive: current == item.tab,
                  onTap: () => onChanged(item.tab),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ------------------------------------------------------------
// 내부 탭 아이템
// ------------------------------------------------------------
class _ReportTabItem extends StatelessWidget {
  final ReportTabAsset item;
  final bool isActive;
  final VoidCallback onTap;

  const _ReportTabItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary;
    const inactiveColor = AppColors.textMute;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 탭 이미지 (asset)
            SizedBox(
              width: 28,
              height: 28,
              child: FittedBox(
                // png 안의 그림 크기가 서로 달라도 28x28 박스에 꽉 차게 맞춥니다.
                fit: BoxFit.contain,
                child: Image.asset(
                  isActive ? item.activeAssetPath : item.inactiveAssetPath,
                  errorBuilder: (context, error, stackTrace) {
                    // 아이콘 파일이 없을 때를 대비한 placeholder
                    return Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),

            // 탭 라벨
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
