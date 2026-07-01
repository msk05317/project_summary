import 'package:flutter/material.dart';

import '../design/design.dart';
import '../components/immediate/priority_badge.dart';
import '../components/immediate/issue_card.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'report_detail_screen.dart';

enum _IssueFilter { all, delayed, warning }

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

  final List<_IssueMock> _issues = const [
    _IssueMock('i1', 'chamber', IssuePriority.critical, '지연', 'D-1',
        '반도체사업부', '챔버', '출하 지연', '6/20'),
    _IssueMock('i2', 'bloom', IssuePriority.high, '지연', 'D-1',
        '블룸', 'BL-002', '자재 미입고', '6/20'),
    _IssueMock('i3', 'arista', IssuePriority.high, '지연', 'D-2',
        '아리스타', 'AR-001', '일정 지연', '6/19'),
    _IssueMock('i4', 'automotive', IssuePriority.mid, '주의', 'D-3',
        '자동차', 'AT-003', '수율 이슈', '6/19'),
    _IssueMock('i5', 'powerbox', IssuePriority.mid, '지연', 'D-4',
        '반도체사업부', '파워박스', '부품 교체 지연', '6/18'),
    _IssueMock('i6', 'network', IssuePriority.mid, '주의', 'D-5',
        '네트워크', 'NW-002', '테스트 실패', '6/17'),
    _IssueMock('i7', 'healthcare', IssuePriority.low, '지연', 'D-6',
        '헬스케어', 'HC-001', '승인 절차 지연', '6/16'),
    _IssueMock('i8', 'mill', IssuePriority.low, '주의', 'D-7',
        '밀', 'WH-001', '재고 부족', '6/15'),
  ];

  List<_IssueMock> get _filteredByDivision {
    if (widget.divisionFilterLabel == null) return _issues;
    return _issues
        .where((e) => e.divisionLabel == widget.divisionFilterLabel)
        .toList();
  }

  List<_IssueMock> get _visible {
    var list = [..._filteredByDivision];

    switch (_filter) {
      case _IssueFilter.all:
        break;
      case _IssueFilter.delayed:
        list.retainWhere((e) => e.status == '지연');
        break;
      case _IssueFilter.warning:
        list.retainWhere((e) => e.status == '주의');
        break;
    }

    list.sort((a, b) {
      final ai = a.priority.index;
      final bi = b.priority.index;
      return _priorityDesc ? ai.compareTo(bi) : bi.compareTo(ai);
    });

    return list;
  }

  int get _totalCount => _filteredByDivision.length;
  int get _delayedCount =>
      _filteredByDivision.where((e) => e.status == '지연').length;
  int get _warningCount =>
      _filteredByDivision.where((e) => e.status == '주의').length;

  void _openReport(String projectKey) {
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
    final visible = _visible;

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
                          '지연 $_delayedCount건 · 주의 $_warningCount건',
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
                    '총 $_totalCount건 — 우선순위 높은 순으로 정렬',
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
                  _tab('전체 $_totalCount', _IssueFilter.all,
                      color: AppColors.headerNavy),
                  const SizedBox(width: 6),
                  _tab('지연 $_delayedCount', _IssueFilter.delayed,
                      color: const Color(0xFFFF0000)),
                  const SizedBox(width: 6),
                  _tab('주의 $_warningCount', _IssueFilter.warning,
                      color: const Color(0xFFE97132)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _priorityDesc = !_priorityDesc),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _priorityDesc ? '우선순위 순 (높음↑)' : '우선순위 순 (낮음↑)',
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
                    id: visible[i].id,
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
                if (i < visible.length - 1) const SizedBox(height: 10),
              ],
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('이전 이슈 로딩은 다음 단계입니다.')),
                  );
                },
                icon: const Icon(Icons.expand_more_rounded,
                    size: 18, color: Color(0xFF7C8594)),
                label: Text(
                  '이전 이슈 더 보기',
                  style: AppText.bodyStrong.copyWith(
                    fontSize: 13,
                    color: AppColors.headerNavy,
                  ),
                ),
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
          border:
              Border.all(color: selected ? color : color.withValues(alpha: 0.4)),
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

class _IssueMock {
  final String id;
  final String projectKey;
  final IssuePriority priority;
  final String status;
  final String dueText;
  final String divisionLabel;
  final String projectLabel;
  final String headline;
  final String dueDate;

  const _IssueMock(
    this.id,
    this.projectKey,
    this.priority,
    this.status,
    this.dueText,
    this.divisionLabel,
    this.projectLabel,
    this.headline,
    this.dueDate,
  );
}
