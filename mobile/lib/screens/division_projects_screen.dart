// 사업부 → 프로젝트 목록 화면.
// HomeScreen 의 사업부 카드를 탭했을 때 진입합니다.
// 이 화면에서는 해당 사업부의 프로젝트들을 나열하고,
// 프로젝트를 탭하면 ReportDetailScreen 으로 이동합니다.

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import 'report_detail_screen.dart';

class DivisionProjectsScreen extends StatelessWidget {
  // 진입 시 받은 사업부 객체.
  // 사업부 라벨/배지/프로젝트 리스트를 그대로 사용합니다.
  final Division division;

  const DivisionProjectsScreen({
    super.key,
    required this.division,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,

      // 상단 헤더 — 네이비 톤은 ReportDetailScreen 과 통일.
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E2841),
        foregroundColor: Colors.white,
        title: Text(
          division.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.x4),
          itemCount: division.projects.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final p = division.projects[index];
            return _ProjectRow(
              label: p.label,
              onTap: () {
                // 프로젝트 클릭 시 보고 상세로 진입.
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportDetailScreen(projectKey: p.id),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// 단일 프로젝트 행.
// 단순 텍스트 + 화살표 형태로 시작하고, 추후 status 배지 등을 추가할 수 있습니다.
class _ProjectRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ProjectRow({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.reportCardBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.reportHeading,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
