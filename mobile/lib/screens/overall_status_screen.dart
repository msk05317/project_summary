import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../models/dashboard.dart';
import '../services/dashboard_service.dart';
import '../services/divisions_service.dart';
import '../components/overall/overall_progress_card.dart';
import '../components/overall/status_distribution_bar.dart';
import '../components/overall/division_progress_row.dart';
import '../components/overall/progress_trend_chart.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_projects_screen.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'calendar_screen.dart';

enum _Period { today, week, month }

enum _DivisionFilter { all, normal, warning, delayed }

// 사업부별 집계 결과.
class _DivisionAgg {
  final Division division;
  final int total;
  final int normal;
  final int warning;
  final int delayed;
  final int inProgress;
  final int progressPercent;
  final String primaryStatus;

  const _DivisionAgg({
    required this.division,
    required this.total,
    required this.normal,
    required this.warning,
    required this.delayed,
    required this.inProgress,
    required this.progressPercent,
    required this.primaryStatus,
  });
}

class OverallStatusScreen extends StatefulWidget {
  const OverallStatusScreen({super.key});

  @override
  State<OverallStatusScreen> createState() => _OverallStatusScreenState();
}

class _OverallStatusScreenState extends State<OverallStatusScreen> {
  _Period _period = _Period.week;
  _DivisionFilter _filter = _DivisionFilter.all;

  late Future<_LoadedData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoadedData> _load() async {
    final results = await Future.wait([
      DashboardService.fetchCards(),
      DivisionsService.fetchAll(),
    ]);
    return _LoadedData(
      cards: results[0] as List<DashboardCard>,
      divisions: results[1] as List<Division>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  // 상태별 진행률 가중치 (mock 기반 근사)
  // 실제 진행률 필드가 백엔드에 생기면 이 로직 교체 예정
  int _progressWeight(String status) {
    switch (status.toUpperCase()) {
      case 'GREEN':
        return 100;
      case 'BLUE':
      case 'GRAY':
      case 'BLACK':
        return 80;
      case 'YELLOW':
      case 'ORANGE':
        return 50;
      case 'RED':
        return 20;
      default:
        return 60;
    }
  }

  List<_DivisionAgg> _aggregateByDivision(
    List<Division> divisions,
    List<DashboardCard> cards,
  ) {
    final byId = <String, List<DashboardCard>>{};
    for (final c in cards) {
      byId.putIfAbsent(c.divisionId, () => []).add(c);
    }

    final result = <_DivisionAgg>[];
    for (final d in divisions) {
      final divCards = byId[d.id] ?? const <DashboardCard>[];

      int normal = 0, warning = 0, delayed = 0, inProgress = 0;
      int weightSum = 0;

      for (final c in divCards) {
        final s = c.status.toUpperCase();
        weightSum += _progressWeight(s);
        switch (s) {
          case 'GREEN':
            normal++;
            break;
          case 'YELLOW':
          case 'ORANGE':
            warning++;
            break;
          case 'RED':
            delayed++;
            break;
          default:
            inProgress++;
        }
      }

      final total = divCards.length;
      final progressPercent =
          total == 0 ? 0 : (weightSum / total).round();

      String primary;
      if (delayed > 0) {
        primary = '지연';
      } else if (warning > 0) {
        primary = '주의';
      } else {
        primary = '정상';
      }

      result.add(_DivisionAgg(
        division: d,
        total: total,
        normal: normal + inProgress,
        warning: warning,
        delayed: delayed,
        inProgress: inProgress,
        progressPercent: progressPercent,
        primaryStatus: primary,
      ));
    }

    return result;
  }

  List<_DivisionAgg> _filterAndSort(List<_DivisionAgg> aggs) {
    final list = [...aggs];

    switch (_filter) {
      case _DivisionFilter.all:
        list.sort((a, b) {
          if (b.delayed != a.delayed) return b.delayed.compareTo(a.delayed);
          if (b.warning != a.warning) return b.warning.compareTo(a.warning);
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

  void _openDivision(Division d) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DivisionProjectsScreen(division: d),
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CalendarScreen(),
          ),
        );
        break;
      case AppNavTab.settings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('준비 중입니다.')),
        );
        break;
    }
  }

String _periodLabel() {
    switch (_period) {
      case _Period.today:
        return '최근 7일';
      case _Period.week:
        return '최근 4주';
      case _Period.month:
        return '최근 6개월';
    }
  }

    String _todayText() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<ProgressTrendPoint> _trendPoints(int todayPercent) {
    // 백엔드 히스토리 API가 아직 없어 오늘 값을 기준으로 근사치를 생성.
    // 기간 탭에 따라 표시 단위와 범위가 바뀌도록 구성.
    final now = DateTime.now();
    final points = <ProgressTrendPoint>[];

    switch (_period) {
      case _Period.today:
        // 최근 7일 (일 단위)
        for (int i = 6; i >= 0; i--) {
          final day = now.subtract(Duration(days: i));
          final label = '${day.month}/${day.day}';
          final value = i == 0
              ? todayPercent.toDouble()
              : (todayPercent - i - (i % 2 == 0 ? 1 : 0)).toDouble();
          points.add(ProgressTrendPoint(
              label, value.clamp(0, 100).toDouble()));
        }
        break;

      case _Period.week:
        // 최근 4주 (주 단위)
        for (int i = 3; i >= 0; i--) {
          final day = now.subtract(Duration(days: i * 7));
          final label = '${day.month}/${day.day}';
          final value = i == 0
              ? todayPercent.toDouble()
              : (todayPercent - (i * 3) - (i % 2 == 0 ? 2 : 0)).toDouble();
          points.add(ProgressTrendPoint(
              label, value.clamp(0, 100).toDouble()));
        }
        break;

      case _Period.month:
        // 최근 6개월 (월 단위)
        for (int i = 5; i >= 0; i--) {
          final base = DateTime(now.year, now.month - i, 1);
          final label = '${base.month}월';
          final value = i == 0
              ? todayPercent.toDouble()
              : (todayPercent - (i * 5) - (i % 2 == 0 ? 2 : 0)).toDouble();
          points.add(ProgressTrendPoint(
              label, value.clamp(0, 100).toDouble()));
        }
        break;
    }

    return points;
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
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_LoadedData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '데이터를 불러오지 못했어요.\n${snap.error ?? ''}',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                ),
              ),
            );
          }

          final data = snap.data!;
          final summary = DashboardSummary.fromCards(data.cards);
          final aggs = _aggregateByDivision(data.divisions, data.cards);
          final visible = _filterAndSort(aggs);
          final trendPoints = _trendPoints(summary.progressPercent);

          return SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
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
                        '기준: ${_todayText()}',
                        style: AppText.caption.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF7C8594),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OverallProgressCard(
                    progressPercent: summary.progressPercent,
                    deltaVsYesterday: 2,
                    deltaVsAverage: 6,
                    totalCount: summary.total,
                    normalCount: summary.normal + summary.inProgress,
                    warningCount: summary.warning,
                    delayedCount: summary.delayed,
                  ),
                  const SizedBox(height: 12),
                  StatusDistributionBar(
                    normalCount: summary.normal + summary.inProgress,
                    warningCount: summary.warning,
                    delayedCount: summary.delayed,
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
                              '진행률 추이 (${_periodLabel()})',
                              style: AppText.bodyStrong.copyWith(
                                fontSize: 13,
                                color: AppColors.headerNavy,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF196B24)
                                    .withValues(alpha: 0.1),
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
                        ProgressTrendChart(points: trendPoints),
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
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              '해당 상태의 사업부가 없어요',
                              style: AppText.caption.copyWith(
                                fontSize: 12,
                                color: const Color(0xFF7C8594),
                              ),
                            ),
                          )
                        else
                          for (int i = 0; i < visible.length; i++) ...[
                            DivisionProgressRow(
                              divisionLabel: visible[i].division.label,
                              primaryStatus: visible[i].primaryStatus,
                              totalCount: visible[i].total,
                              normalCount: visible[i].normal,
                              warningCount: visible[i].warning,
                              delayedCount: visible[i].delayed,
                              progressPercent: visible[i].progressPercent,
                              onTap: () => _openDivision(visible[i].division),
                            ),
                            if (i < visible.length - 1)
                              const Divider(
                                  height: 1,
                                  color: Color(0xFFEEF1F5),
                                  thickness: 1),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

class _LoadedData {
  final List<DashboardCard> cards;
  final List<Division> divisions;

  const _LoadedData({required this.cards, required this.divisions});
}
