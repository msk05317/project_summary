import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/dashboard.dart';
import '../services/dashboard_service.dart';
import '../components/immediate/priority_badge.dart';
import '../components/immediate/issue_card.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'report_detail_screen.dart';

enum _IssueFilter { all, delayed, warning }

// 카드 → 화면에서 보여줄 이슈 데이터로 변환한 결과.
class _Issue {
  final String projectKey;
  final IssuePriority priority;
  final String status;
  final String dueText;
  final String divisionLabel;
  final String projectLabel;
  final String headline;
  final String dueDate;
  final int diffDays;

  const _Issue({
    required this.projectKey,
    required this.priority,
    required this.status,
    required this.dueText,
    required this.divisionLabel,
    required this.projectLabel,
    required this.headline,
    required this.dueDate,
    required this.diffDays,
  });
}

class ImmediateCheckScreen extends StatefulWidget {
  final String? divisionFilterLabel;

  const ImmediateCheckScreen({
    super.key,
    this.divisionFilterLabel,
  });

  @override
  State<ImmediateCheckScreen> createState() => _ImmediateCheckScreenState();
}

class _ImmediateCheckScreenState extends State<ImmediateCheckScreen> {
  _IssueFilter _filter = _IssueFilter.all;
  bool _priorityDesc = true;

  late Future<List<DashboardCard>> _future;

  @override
  void initState() {
    super.initState();
    _future = DashboardService.fetchCards();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = DashboardService.fetchCards();
    });
    await _future;
  }

  // 카드 상태 → 우선순위 등급.
  // RED + 임박(D-1 이하) → critical
  // RED → high
  // ORANGE → mid
  // YELLOW → low
  IssuePriority _priorityOf(String status, int diffDays) {
    final s = status.toUpperCase();
    if (s == 'RED') {
      if (diffDays <= 1) return IssuePriority.critical;
      return IssuePriority.high;
    }
    if (s == 'ORANGE') return IssuePriority.mid;
    return IssuePriority.low;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'RED':
        return '지연';
      case 'ORANGE':
      case 'YELLOW':
        return '주의';
      default:
        return '정상';
    }
  }

  String _dueText(int diffDays) {
    if (diffDays == 0) return 'D-day';
    if (diffDays > 0) return 'D-$diffDays';
    return 'D+${-diffDays}';
  }

  String _dueDateShort(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    // yyyy-MM-dd → M/d
    try {
      final parts = isoDate.split('-');
      if (parts.length < 3) return isoDate;
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2].substring(0, 2));
      return '$m/$d';
    } catch (_) {
      return isoDate;
    }
  }

  String _headlineOf(DashboardCard c) {
    // 백엔드 headline이 대부분 빈 문자열이라 summary_bullets[0]에서 뽑기.
    if (c.headline.trim().isNotEmpty) return c.headline.trim();
    if (c.summaryBullets.isEmpty) return '';

    var text = c.summaryBullets.first;

    // 마크다운/특수문자 제거
    text = text.replaceAll(RegExp(r'[*_`>#]'), '');
    // placeholder(__X__) 제거
    text = text.replaceAll(RegExp(r'__[A-Za-z0-9_]+__'), '');
    // 괄호 안 날짜/부가정보 제거: (06-19) 등
    text = text.replaceAll(RegExp(r'\([^)]*\)'), '');
    // 화살표/이후 잘라내기
    for (final sep in ['→', '->', '∎', '·']) {
      final idx = text.indexOf(sep);
      if (idx > 0 && idx < 30) {
        text = text.substring(0, idx);
        break;
      }
    }
    text = text.trim();

    // 조사 정리
    text = text.replaceAll(RegExp(r'(이|가|을|를|은|는|의|에|로|와|과|도)$'), '');

    // 길이 컷
    if (text.length > 20) {
      final cut = text.substring(0, 20);
      final space = cut.lastIndexOf(' ');
      text = space > 10 ? '${cut.substring(0, space)}…' : '$cut…';
    }

    return text;
  }

  List<_Issue> _buildIssues(List<DashboardCard> cards) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final result = <_Issue>[];
    for (final c in cards) {
      final s = c.status.toUpperCase();
      // 지연/주의 카드만 즉시 확인 대상
      if (s != 'RED' && s != 'ORANGE' && s != 'YELLOW') continue;

      final dueRaw = c.dueDateMin;
      DateTime? dueDate;
      int diffDays = 999;
      if (dueRaw != null && dueRaw.isNotEmpty) {
        try {
          final parts = dueRaw.split('-');
          if (parts.length >= 3) {
            dueDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2].substring(0, 2)),
            );
            diffDays = dueDate.difference(todayDate).inDays;
          }
        } catch (_) {}
      }

      final headline = _headlineOf(c);

      result.add(_Issue(
        projectKey: c.projectKey,
        priority: _priorityOf(s, diffDays),
        status: _statusLabel(s),
        dueText: dueDate == null ? '-' : _dueText(diffDays),
        divisionLabel: c.divisionLabel,
        projectLabel: c.projectLabel,
        headline: headline.isEmpty ? c.projectLabel : headline,
        dueDate: _dueDateShort(dueRaw),
        diffDays: diffDays,
      ));
    }

    return result;
  }

  List<_Issue> _filteredByDivision(List<_Issue> all) {
    if (widget.divisionFilterLabel == null) return all;
    return all.where((e) => e.divisionLabel == widget.divisionFilterLabel).toList();
  }

  List<_Issue> _applyTabAndSort(List<_Issue> list) {
    final result = [...list];

    switch (_filter) {
      case _IssueFilter.all:
        break;
      case _IssueFilter.delayed:
        result.retainWhere((e) => e.status == '지연');
        break;
      case _IssueFilter.warning:
        result.retainWhere((e) => e.status == '주의');
        break;
    }

    result.sort((a, b) {
      final ai = a.priority.index;
      final bi = b.priority.index;
      if (ai != bi) {
        return _priorityDesc ? ai.compareTo(bi) : bi.compareTo(ai);
      }
      // 같은 우선순위: 임박한 것 먼저
      return a.diffDays.compareTo(b.diffDays);
    });

    return result;
  }

  void _openReport(String projectKey) {
    if (projectKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결된 프로젝트가 없습니다.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(projectKey: projectKey),
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
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 28, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '즉시 확인',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<DashboardCard>>(
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
                  '이슈를 불러오지 못했어요.\n${snap.error ?? ''}',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                ),
              ),
            );
          }

          final all = _buildIssues(snap.data!);
          final scoped = _filteredByDivision(all);
          final visible = _applyTabAndSort(scoped);

          final totalCount = scoped.length;
          final delayedCount =
              scoped.where((e) => e.status == '지연').length;
          final warningCount =
              scoped.where((e) => e.status == '주의').length;

          return SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error,
                                color: Color(0xFFFF0000), size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '지연 $delayedCount건 · 주의 $warningCount건',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.headerNavy,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '총 $totalCount건 — 우선순위 높은 순으로 정렬',
                          style: AppText.caption.copyWith(
                            fontSize: 11,
                            color: const Color(0xFF7C8594),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _tab('전체 $totalCount', _IssueFilter.all,
                            color: AppColors.headerNavy),
                        const SizedBox(width: 6),
                        _tab('지연 $delayedCount', _IssueFilter.delayed,
                            color: const Color(0xFFFF0000)),
                        const SizedBox(width: 6),
                        _tab('주의 $warningCount', _IssueFilter.warning,
                            color: const Color(0xFFE97132)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        onTap: () => setState(
                            () => _priorityDesc = !_priorityDesc),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _priorityDesc
                                    ? '우선순위 순 (높음↑)'
                                    : '우선순위 순 (낮음↑)',
                                style: AppText.caption.copyWith(
                                  fontSize: 11,
                                  color: AppColors.headerNavy,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Icon(
                                _priorityDesc
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 14,
                                color: AppColors.headerNavy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (visible.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      alignment: Alignment.center,
                      child: Text(
                        '해당하는 이슈가 없어요',
                        style: AppText.caption.copyWith(
                          fontSize: 12,
                          color: const Color(0xFF7C8594),
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < visible.length; i++) ...[
                      IssueCard(
                        data: IssueCardData(
                          id: visible[i].projectKey,
                          projectKey: visible[i].projectKey,
                          priority: visible[i].priority,
                          status: visible[i].status,
                          dueText: visible[i].dueText,
                          divisionLabel: visible[i].divisionLabel,
                          projectLabel: visible[i].projectLabel,
                          headline: visible[i].headline,
                          dueDate: visible[i].dueDate,
                          onTap: () => _openReport(visible[i].projectKey),
                        ),
                      ),
                      if (i < visible.length - 1)
                        const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 12),
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

  Widget _tab(String label, _IssueFilter value, {required Color color}) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
