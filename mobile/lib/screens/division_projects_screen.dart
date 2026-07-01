// 사업부 상세 화면 (실데이터 v1).
// 데이터 소스: DashboardService.fetchCards()
// - 해당 사업부(division.id)에 속한 카드만 필터해서 사용
// - 요약 카드/즉시 확인/프로젝트 그리드 모두 실데이터에서 파생
// UI 구조는 기존 mock 버전 그대로 유지.

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../models/dashboard.dart';
import '../services/dashboard_service.dart';
import '../components/division/division_summary_card.dart';
import '../components/division/division_immediate_check.dart';
import '../components/division/project_grid_card.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'immediate_check_screen.dart';
import 'report_detail_screen.dart';

class DivisionProjectsScreen extends StatefulWidget {
  final Division division;

  const DivisionProjectsScreen({
    super.key,
    required this.division,
  });

  @override
  State<DivisionProjectsScreen> createState() =>
      _DivisionProjectsScreenState();
}

class _DivisionProjectsScreenState extends State<DivisionProjectsScreen> {
  final Set<String> _favoriteProjects = {};
  String? _selectedProjectId;
  String _projectQuery = '';

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

  int _weightOf(String status) {
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

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'RED':
        return '지연';
      case 'YELLOW':
      case 'ORANGE':
        return '주의';
      case 'GREEN':
        return '정상';
      default:
        return '정상';
    }
  }

  String _headlineOf(DashboardCard c) {
    if (c.headline.trim().isNotEmpty) return c.headline.trim();
    if (c.summaryBullets.isEmpty) return c.projectLabel;

    var text = c.summaryBullets.first;
    text = text.replaceAll(RegExp(r'[*_`>#]'), '');
    text = text.replaceAll(RegExp(r'__[A-Za-z0-9_]+__'), '');
    text = text.replaceAll(RegExp(r'\([^)]*\)'), '');
    for (final sep in ['→', '->', '∎']) {
      final idx = text.indexOf(sep);
      if (idx > 0 && idx < 30) {
        text = text.substring(0, idx);
        break;
      }
    }
    text = text.trim();
    text = text.replaceAll(RegExp(r'(이|가|을|를|은|는|의|에|로|와|과|도)$'), '');
    if (text.length > 20) {
      final cut = text.substring(0, 20);
      final space = cut.lastIndexOf(' ');
      text = space > 10 ? '${cut.substring(0, space)}…' : '$cut…';
    }
    return text.isEmpty ? c.projectLabel : text;
  }

  String _todayText() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dueTextFrom(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '-';
    try {
      final parts = isoDate.split('-');
      if (parts.length < 3) return '-';
      final due = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2].substring(0, 2)),
      );
      final today = DateTime.now();
      final t = DateTime(today.year, today.month, today.day);
      final diff = due.difference(t).inDays;
      if (diff == 0) return 'D-day';
      if (diff > 0) return 'D-$diff';
      return 'D+${-diff}';
    } catch (_) {
      return '-';
    }
  }

  ImmediatePriority _immPriorityOf(String status, String dueText) {
    final s = status.toUpperCase();
    if (s == 'RED' && (dueText == 'D-day' || dueText == 'D-1')) {
      return ImmediatePriority.high;
    }
    return ImmediatePriority.mid;
  }

  _DivisionData _computeData(List<DashboardCard> allCards) {
    final divisionCards =
        allCards.where((c) => c.divisionId == widget.division.id).toList();

    int red = 0, orange = 0, green = 0, other = 0;
    int weightSum = 0;

    for (final c in divisionCards) {
      final s = c.status.toUpperCase();
      weightSum += _weightOf(s);
      switch (s) {
        case 'RED':
          red++;
          break;
        case 'YELLOW':
        case 'ORANGE':
          orange++;
          break;
        case 'GREEN':
          green++;
          break;
        default:
          other++;
      }
    }

    final total = divisionCards.length;
    final progress = total == 0 ? 0 : (weightSum / total).round();

    // 즉시 확인: RED/ORANGE 카드 중 마감 임박 상위 3건
    final immCandidates = divisionCards
        .where((c) => c.status.toUpperCase() == 'RED' ||
            c.status.toUpperCase() == 'ORANGE')
        .toList();

    immCandidates.sort((a, b) {
      final da = a.dueDateMin ?? '9999-99-99';
      final db = b.dueDateMin ?? '9999-99-99';
      return da.compareTo(db);
    });

    final immediate = <DivisionImmediateItem>[];
    for (final c in immCandidates) {
      final due = _dueTextFrom(c.dueDateMin);
      final headline = _headlineOf(c);
      immediate.add(DivisionImmediateItem(
        priority: _immPriorityOf(c.status, due),
        dueText: due,
        headline: '${c.projectLabel} · $headline',
        status: _statusLabel(c.status),
      ));
    }

    // 프로젝트 카드 매핑
    // - Division 모델의 projects 리스트를 기준으로 하되,
    //   해당 project_key에 대응하는 dashboard 카드가 있으면 상태/진행률 반영
    final cardByKey = <String, DashboardCard>{};
    for (final c in divisionCards) {
      if (c.projectKey.isNotEmpty) {
        cardByKey[c.projectKey] = c;
      }
    }

    final projects = <_ProjectItem>[];
    for (final p in widget.division.projects) {
      final card = cardByKey[p.id];
      final hasData = card != null;
      final status = hasData ? _statusLabel(card.status) : '';
      final percent = hasData ? _weightOf(card.status) : 0;
      projects.add(_ProjectItem(
        id: p.id,
        englishName: _englishOf(p.id),
        koreanName: p.label,
        status: status,
        progressPercent: percent,
        hasData: hasData,
      ));
    }

    // 백엔드 카드에는 있지만 division.projects에는 없는 경우 보강
    for (final c in divisionCards) {
      if (c.projectKey.isEmpty) continue;
      final exists = projects.any((p) => p.id == c.projectKey);
      if (exists) continue;
      projects.add(_ProjectItem(
        id: c.projectKey,
        englishName: _englishOf(c.projectKey),
        koreanName: c.projectLabel,
        status: _statusLabel(c.status),
        progressPercent: _weightOf(c.status),
        hasData: true,
      ));
    }

    return _DivisionData(
      progressPercent: progress,
      progressDeltaPp: 2,
      delayed: red,
      warning: orange,
      normal: green + other,
      updatedAt: _todayText(),
      immediate: immediate,
      projects: projects,
    );
  }

  // project_key → 영문 라벨.
  // 자동 변환이 어색한 특수 케이스는 명시적 매핑을 우선 사용.
  static const Map<String, String> _englishOverrides = {
    'tolon': 'Torlon',
    'eos_chamber': 'EOS Chamber',
    'faraday_4t': 'Faraday 4T',
    'hrva_plate': 'Hrva Plate',
    'plating_cell': 'Plating Cell',
    'major_module': 'Major Module',
    'powerbox': 'Powerbox',
    'chamber': 'Chamber',
    'enclosure': 'Enclosure',
    'frame': 'Frame',
    'cup': 'CUP',
  };

  String _englishOf(String key) {
    if (key.isEmpty) return '';
    final override = _englishOverrides[key];
    if (override != null) return override;
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');
  }

  List<_ProjectItem> _sortProjects(List<_ProjectItem> input) {
    final list = [...input];
    list.sort((a, b) {
      final aFav = _favoriteProjects.contains(a.id);
      final bFav = _favoriteProjects.contains(b.id);
      if (aFav != bFav) return aFav ? -1 : 1;
      if (a.hasData != b.hasData) return a.hasData ? -1 : 1;
      return a.progressPercent.compareTo(b.progressPercent);
    });
    return list;
  }

  List<_ProjectItem> _visibleProjects(List<_ProjectItem> sorted) {
    final q = _projectQuery.trim().toLowerCase();
    if (q.isEmpty) return sorted;
    final trimmed = _projectQuery.trim();
    return sorted.where((p) {
      return p.englishName.toLowerCase().contains(q) ||
          p.koreanName.contains(trimmed) ||
          p.status.contains(trimmed);
    }).toList();
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favoriteProjects.contains(id)) {
        _favoriteProjects.remove(id);
      } else {
        _favoriteProjects.add(id);
      }
    });
  }

  Future<void> _openProject(String projectKey) async {
    await Navigator.of(context).push(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('캘린더 화면은 준비 중입니다.')),
        );
        break;
      case AppNavTab.settings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정 화면은 준비 중입니다.')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortLabel =
        widget.division.badgeShortLabel ?? widget.division.label;

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.division.label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.star_rounded,
                color: Color(0xFFF4B63D), size: 18),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '목록 > ${widget.division.label}',
              style: AppText.caption.copyWith(
                fontSize: 11,
                color: const Color(0xFF7C8594),
              ),
            ),
          ),
        ),
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
                  '데이터를 불러오지 못했어요.\n${snap.error ?? ''}',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                ),
              ),
            );
          }

          final data = _computeData(snap.data!);
          final sortedProjects = _sortProjects(data.projects);
          final visibleProjects = _visibleProjects(sortedProjects);

          return SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  DivisionSummaryCard(
                    divisionLabel: widget.division.label,
                    updatedAt: data.updatedAt,
                    progressPercent: data.progressPercent,
                    progressDeltaPp: data.progressDeltaPp,
                    projectCount: data.projects.length,
                    delayedCount: data.delayed,
                    warningCount: data.warning,
                    normalCount: data.normal,
                  ),
                  const SizedBox(height: 16),
                  if (data.immediate.isNotEmpty) ...[
                    DivisionImmediateCheckSection(
                      divisionShortLabel: shortLabel,
                      items: data.immediate,
                      onTapSeeAll: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImmediateCheckScreen(
                              divisionFilterLabel: widget.division.label,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined,
                          size: 16, color: Color(0xFF7C8594)),
                      const SizedBox(width: 6),
                      Text(
                        '프로젝트',
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 14,
                          color: AppColors.headerNavy,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _projectQuery.trim().isEmpty
                            ? '총 ${sortedProjects.length}건'
                            : '${visibleProjects.length}/${sortedProjects.length}건',
                        style: AppText.caption.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF7C8594),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SearchFilterRow(
                    value: _projectQuery,
                    onChanged: (v) {
                      setState(() {
                        _projectQuery = v;
                      });
                    },
                    onTapFilter: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('프로젝트 필터는 준비 중입니다.')),
                      );
                    },
                    hintText: '프로젝트 검색',
                  ),
                  const SizedBox(height: 12),
                  if (visibleProjects.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      alignment: Alignment.center,
                      child: Text(
                        _projectQuery.trim().isEmpty
                            ? '이 사업부에 프로젝트가 없어요'
                            : '검색 결과가 없어요',
                        style: AppText.caption.copyWith(
                          fontSize: 12,
                          color: const Color(0xFF7C8594),
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visibleProjects.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 88,
                      ),
                      itemBuilder: (context, i) {
                        final p = visibleProjects[i];
                        return ProjectGridCard(
                          englishName: p.englishName,
                          koreanName: p.koreanName,
                          status: p.status,
                          progressPercent: p.progressPercent,
                          isFavorite: _favoriteProjects.contains(p.id),
                          isSelected: _selectedProjectId == p.id,
                          hasData: p.hasData,
                          onTap: () async {
                            setState(() {
                              _selectedProjectId = p.id;
                            });
                            await _openProject(p.id);
                            if (!mounted) return;
                            setState(() {
                              _selectedProjectId = null;
                            });
                          },
                          onToggleFavorite: () => _toggleFavorite(p.id),
                        );
                      },
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
            current: AppNavTab.list,
            onChanged: _handleBottomNav,
          ),
        ],
      ),
    );
  }
}

class _DivisionData {
  final int progressPercent;
  final int progressDeltaPp;
  final int delayed;
  final int warning;
  final int normal;
  final String updatedAt;
  final List<DivisionImmediateItem> immediate;
  final List<_ProjectItem> projects;

  _DivisionData({
    required this.progressPercent,
    required this.progressDeltaPp,
    required this.delayed,
    required this.warning,
    required this.normal,
    required this.updatedAt,
    required this.immediate,
    required this.projects,
  });
}

class _ProjectItem {
  final String id;
  final String englishName;
  final String koreanName;
  final String status;
  final int progressPercent;
  final bool hasData;

  const _ProjectItem({
    required this.id,
    required this.englishName,
    required this.koreanName,
    required this.status,
    required this.progressPercent,
    required this.hasData,
  });
}
