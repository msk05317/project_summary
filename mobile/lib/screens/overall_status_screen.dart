import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../components/overall/overall_progress_card.dart';
import '../components/overall/status_distribution_bar.dart';
import '../components/overall/progress_trend_chart.dart';
import '../components/overall/division_progress_row.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_projects_screen.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;

enum _Period { today, week, month }

enum _DivisionFilter { all, normal, warning, delayed }

class OverallStatusScreen extends StatefulWidget {
  const OverallStatusScreen({super.key});

  @override
  State<OverallStatusScreen> createState() => _OverallStatusScreenState();
}

class _OverallStatusScreenState extends State<OverallStatusScreen> {
  _Period _period = _Period.week;
  _DivisionFilter _filter = _DivisionFilter.all;

  final List<_DivisionMock> _divisions = const [
    _DivisionMock('semiconductor', '반도체사업부', 7, 5, 1, 1, 68, '주의'),
    _DivisionMock('automotive', '자동차', 4, 2, 1, 1, 52, '지연'),
    _DivisionMock('bloom', '블룸', 3, 1, 1, 1, 47, '지연'),
    _DivisionMock('arista', '아리스타', 3, 2, 1, 0, 55, '주의'),
    _DivisionMock('network', '네트워크', 3, 2, 1, 0, 71, '주의'),
    _DivisionMock('system', '시스템', 2, 1, 1, 0, 66, '주의'),
    _DivisionMock('pcb', 'PCB', 3, 2, 1, 0, 63, '주의'),
    _DivisionMock('automation', '자동화', 3, 3, 0, 0, 80, '정상'),
    _DivisionMock('mill', '밀', 2, 1, 1, 0, 58, '주의'),
    _DivisionMock('healthcare', '헬스케어', 3, 2, 1, 0, 49, '주의'),
    _DivisionMock('ess', 'ESS', 2, 2, 0, 0, 74, '정상'),
    _DivisionMock('heavy', '중공업', 2, 2, 0, 0, 70, '정상'),
  ];

  List<_DivisionMock> get _visibleDivisions {
    final list = [..._divisions];
    switch (_filter) {
      case _DivisionFilter.all:
        list.sort((a, b) {
          if (b.delayed != a.delayed) {
            return b.delayed.compareTo(a.delayed);
          }
          if (b.warning != a.warning) {
            return b.warning.compareTo(a.warning);
          }
          return a.progressPercent.compareTo(b.progressPercent);
        });
        break;
      case _DivisionFilter.normal:
        list.retainWhere((d) => d.primaryStatus == '정상');
        break;
      case _DivisionFilter.warning:
        list.retainWhere((d) => d.primaryStatus == '주의');
        break;
      case _DivisionFilter.delayed:
        list.retainWhere((d) => d.primaryStatus == '지연');
        break;
    }
    return list;
  }

  void _openDivision(_DivisionMock d) {
    final division = Division(
      id: d.id,
      label: d.label,
      order: 0,
      projects: const [],
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DivisionProjectsScreen(division: division),
      ),
    );
  }

  void _handleBottomNav(AppNavTab tab) {
    switch (tab) {
      case AppNavTab.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case AppNavTab.list:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const DivisionSelectScreen(),
          ),
        );
        break;
      case AppNavTab.calendar:
      case AppNavTab.settings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('준비 중입니다.')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.headerNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '전체 현황',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('새로고침은 다음 단계에서 연결합니다.')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Row(
              children: [
                _periodChip('오늘', _Period.today),
                const SizedBox(width: 6),
                _periodChip('이번 주', _Period.week),
                const SizedBox(width: 6),
                _periodChip('이번 달', _Period.month),
                const Spacer(),
                Text(
                  '기준: 2026-06-22',
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    color: const Color(0xFF7C8594),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const OverallProgressCard(
              progressPercent: 64,
              deltaVsYesterday: 2,
              deltaVsAverage: 6,
              totalCount: 37,
              normalCount: 24,
              warningCount: 9,
              delayedCount: 4,
            ),
            const SizedBox(height: 12),
            const StatusDistributionBar(
              normalCount: 24,
              warningCount: 9,
              delayedCount: 4,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.reportCardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '진행률 추이 (최근 7일)',
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 13,
                          color: AppColors.headerNavy,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF196B24).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '이번 주 +6%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF196B24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const ProgressTrendChart(
                    points: [
                      ProgressTrendPoint('6/16', 58),
                      ProgressTrendPoint('6/17', 59),
                      ProgressTrendPoint('6/18', 60),
                      ProgressTrendPoint('6/19', 61),
                      ProgressTrendPoint('6/20', 62),
                      ProgressTrendPoint('6/21', 63),
                      ProgressTrendPoint('6/22', 64),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '사업부별 진행 현황',
                  style: AppText.bodyStrong.copyWith(
                    fontSize: 14,
                    color: AppColors.headerNavy,
                  ),
                ),
                const Spacer(),
                Text(
                  '지연 많은 순',
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    color: const Color(0xFF7C8594),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _filterChip('전체', _DivisionFilter.all),
                const SizedBox(width: 6),
                _filterChip('정상', _DivisionFilter.normal),
                const SizedBox(width: 6),
                _filterChip('주의', _DivisionFilter.warning),
                const SizedBox(width: 6),
                _filterChip('지연', _DivisionFilter.delayed),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.reportCardBorder),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _visibleDivisions.length; i++) ...[
                    DivisionProgressRow(
                      divisionLabel: _visibleDivisions[i].label,
                      primaryStatus: _visibleDivisions[i].primaryStatus,
                      totalCount: _visibleDivisions[i].total,
                      normalCount: _visibleDivisions[i].normal,
                      warningCount: _visibleDivisions[i].warning,
                      delayedCount: _visibleDivisions[i].delayed,
                      progressPercent: _visibleDivisions[i].progressPercent,
                      onTap: () => _openDivision(_visibleDivisions[i]),
                    ),
                    if (i < _visibleDivisions.length - 1)
                      const Divider(
                          height: 1, color: Color(0xFFEEF1F5), thickness: 1),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomPromptBar(),
          AppBottomNav(
            current: AppNavTab.home,
            onChanged: _handleBottomNav,
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, _Period value) {
    final selected = _period == value;
    return InkWell(
      onTap: () => setState(() => _period = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.headerNavy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.headerNavy : AppColors.reportCardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.reportBody,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, _DivisionFilter value) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.headerNavy : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.headerNavy : AppColors.reportCardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.reportBody,
          ),
        ),
      ),
    );
  }
}

class _DivisionMock {
  final String id;
  final String label;
  final int total;
  final int normal;
  final int warning;
  final int delayed;
  final int progressPercent;
  final String primaryStatus;

  const _DivisionMock(
    this.id,
    this.label,
    this.total,
    this.normal,
    this.warning,
    this.delayed,
    this.progressPercent,
    this.primaryStatus,
  );
}
