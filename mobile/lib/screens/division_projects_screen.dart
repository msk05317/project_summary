// 사업부 상세 화면 (디자인 A · 매출 우선).
//
// 첫 블록은 진행률(%)이 아니라 이 달의 매출이다.
// 경영진이 앱을 여는 순서가 "얼마 나갔나 → 왜 → 누구 때문에" 이기 때문에
// 화면도 그 순서로 내려간다.
//   1) 이번 달 매출 히어로 (사업부 합계)
//   2) 확인이 필요한 프로젝트 N건 (0건이면 숨김)
//   3) 프로젝트 — 매출 기여순 1열 리스트
//   4) 매출 계획이 없는 프로젝트는 접어둔다
//
// 데이터 소스
//  - DashboardService.fetchCards() : 상태(RED/ORANGE/GREEN), 마감일
//  - ProgressService.fetch()       : 진행률 / 모델 수
//  - OverviewService.fetch(divisionId:) : 월 매출·출하 (프로젝트별 + 합계)

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../models/dashboard.dart';
import '../services/dashboard_service.dart';
import '../services/progress_service.dart';
import '../services/favorites_service.dart';
import '../services/overview_service.dart';
import '../components/division/division_immediate_check.dart'
    show DivisionImmediateItem, ImmediatePriority;
import '../components/division/division_revenue_hero.dart';
import '../components/division/division_attention_banner.dart';
import '../components/division/project_revenue_row.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'immediate_check_screen.dart';
import 'project_overview_screen.dart';
import 'revenue_detail_screen.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';

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
  Set<String> _favoriteProjects = {};
  bool _isDivisionFavorite = false;
  String? _selectedProjectId;
  String _projectQuery = '';

  // 프로젝트 목록 필터/정렬
  _ProjectStatusFilter _statusFilter = _ProjectStatusFilter.all;
  _ProjectSort _sort = _ProjectSort.revenueDesc;
  bool _favoritesOnly = false;

  /// 매출 계획이 없는 프로젝트 그룹 펼침 여부
  bool _showNoPlan = false;

  late Future<List<DashboardCard>> _future;

  /// 진행률 요약 (백엔드 /projects-progress-summary)
  ProgressSummary _progress = ProgressSummary.empty;

  /// 이 사업부의 월 매출/출하 (백엔드 /overview?division_id=)
  OverviewSummary _overview = OverviewSummary.empty;
  bool _overviewLoading = true;

  @override
  void initState() {
    super.initState();
    _future = DashboardService.fetchCards();
    _loadFavorites();
    _loadProgress();
    _loadOverview();
  }

  Future<void> _loadProgress() async {
    final summary = await ProgressService.fetch();
    if (!mounted) return;
    setState(() => _progress = summary);
  }

  Future<void> _loadOverview() async {
    if (mounted) setState(() => _overviewLoading = true);
    final s = await OverviewService.fetch(divisionId: widget.division.id);
    if (!mounted) return;
    setState(() {
      _overview = s;
      _overviewLoading = false;
    });
  }

  /// 이번 달 남은 영업일(오늘 포함, 주말 제외). 공휴일은 반영하지 않는다.
  int _businessDaysLeft() {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month + 1, 0).day;
    var n = 0;
    for (var d = now.day; d <= last; d++) {
      final wd = DateTime(now.year, now.month, d).weekday;
      if (wd <= DateTime.friday) n++;
    }
    return n;
  }

  /// 오늘이 속한 ISO 주차 라벨 ('W36').
  String _weekLabel() {
    final now = DateTime.now();
    final thursday = now.add(Duration(days: 4 - now.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(jan1).inDays) / 7).floor() + 1;
    return 'W$week';
  }

  Future<void> _loadFavorites() async {
    final projs = await FavoritesService.loadAll();
    final isDivFav = await FavoritesService.isDivisionFavorite(widget.division.id);
    if (!mounted) return;
    setState(() {
      _favoriteProjects = projs;
      _isDivisionFavorite = isDivFav;
    });
  }

  Future<void> _toggleDivisionFavorite() async {
    final nowFav = await FavoritesService.toggleDivision(widget.division.id);
    if (!mounted) return;
    setState(() {
      _isDivisionFavorite = nowFav;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _future = DashboardService.fetchCards();
    });
    await Future.wait([_future, _loadProgress(), _loadOverview()]);
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

    // 프로젝트별 최악 상태 (지연 > 주의 > 정상) — 현황 카운트는 프로젝트 단위
    final worstStatusByKey = <String, String>{};
    int rank(String s) {
      switch (s.toUpperCase()) {
        case 'RED':
          return 3;
        case 'YELLOW':
        case 'ORANGE':
          return 2;
        default:
          return 1;
      }
    }
    for (final c in divisionCards) {
      if (c.projectKey.isEmpty) continue;
      final cur = worstStatusByKey[c.projectKey];
      if (cur == null || rank(c.status) > rank(cur)) {
        worstStatusByKey[c.projectKey] = c.status;
      }
    }

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
    final cardsByKey = <String, List<DashboardCard>>{};
    for (final c in divisionCards) {
      if (c.projectKey.isNotEmpty) {
        cardsByKey.putIfAbsent(c.projectKey, () => []).add(c);
      }
    }
    // 진행률은 모델 실데이터(/projects-progress-summary) 기준.
    // 데이터가 없으면 null → 카드에 '-' 표시하고 평균에서도 제외.
    int? avgProgressOf(String key) => _progress.of(key)?.progress;
    final cardByKey = <String, DashboardCard>{};
    for (final e in cardsByKey.entries) {
      cardByKey[e.key] = e.value.first;
    }

    // 매출/출하는 /overview 응답을 프로젝트 키로 붙인다.
    final revByKey = <String, OverviewProject>{
      for (final o in _overview.items) o.key: o,
    };

    final projects = <_ProjectItem>[];
    for (final p in widget.division.projects) {
      final card = cardByKey[p.id];
      final int? percent = avgProgressOf(p.id);
      // '데이터 있음' = 진행률이 산출되는 프로젝트 (모델만 있고 입력이 없으면 미등록)
      final hasData = _progress.of(p.id)?.hasData ?? false;
      final status = hasData && card != null ? _statusLabel(card.status) : '';
      final rev = revByKey[p.id];
      projects.add(_ProjectItem(
        id: p.id,
        englishName: _englishOf(p.id),
        koreanName: p.label,
        status: status,
        progressPercent: percent,
        hasData: hasData,
        modelsTotal: _progress.of(p.id)?.modelsTotal ?? 0,
        revenue: rev?.revenue ?? 0,
        planRevenue: rev?.planRevenue ?? 0,
        qtyPlan: rev?.qtyPlan ?? 0,
        qtyActual: rev?.qtyActual ?? 0,
      ));
    }

    // 백엔드 카드에는 있지만 division.projects에는 없는 경우 보강
    for (final c in divisionCards) {
      if (c.projectKey.isEmpty) continue;
      final exists = projects.any((p) => p.id == c.projectKey);
      if (exists) continue;
      final rev = revByKey[c.projectKey];
      projects.add(_ProjectItem(
        id: c.projectKey,
        englishName: _englishOf(c.projectKey),
        koreanName: c.projectLabel,
        status: _statusLabel(c.status),
        progressPercent: avgProgressOf(c.projectKey),
        hasData: _progress.of(c.projectKey)?.hasData ?? false,
        modelsTotal: _progress.of(c.projectKey)?.modelsTotal ?? 0,
        revenue: rev?.revenue ?? 0,
        planRevenue: rev?.planRevenue ?? 0,
        qtyPlan: rev?.qtyPlan ?? 0,
        qtyActual: rev?.qtyActual ?? 0,
      ));
    }

    // ── 사업부 전체 진행률: 집계 대상 '모델' 가중 평균
    final keys = projects.map((p) => p.id);
    final scoredModels = _progress.scoredModelsFor(keys);
    final int? progress = _progress.weightedFor(keys);

    // ── 현황 카운트: 프로젝트 단위 (지연 + 주의 + 정상 + 미등록 = 전체)
    int red = 0, orange = 0, green = 0, noData = 0;
    for (final p in projects) {
      if (!p.hasData) {
        noData++;
        continue;
      }
      switch ((worstStatusByKey[p.id] ?? 'GREEN').toUpperCase()) {
        case 'RED':
          red++;
          break;
        case 'YELLOW':
        case 'ORANGE':
          orange++;
          break;
        default:
          green++;
      }
    }

    return _DivisionData(
      progressPercent: progress,
      progressDeltaPp: null, // 전월 데이터가 없으므로 표시하지 않음
      delayed: red,
      warning: orange,
      normal: green,
      noData: noData,
      scoredModels: scoredModels,
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
    'spacex': 'CURIE (Space X)',
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
      // 즐겨찾기 먼저, 그다음 데이터 있는 프로젝트, 그 안에서 선택한 정렬
      final aFav = _favoriteProjects.contains(a.id);
      final bFav = _favoriteProjects.contains(b.id);
      if (aFav != bFav) return aFav ? -1 : 1;
      if (a.hasRevenue != b.hasRevenue) return a.hasRevenue ? -1 : 1;
      if (a.hasData != b.hasData) return a.hasData ? -1 : 1;

      final ap = a.progressPercent;
      final bp = b.progressPercent;
      switch (_sort) {
        case _ProjectSort.revenueDesc:
          // 매출 기여는 '실적'이 아니라 '이 달에 걸린 금액'(계획)이 기준이다.
          // 실적순으로 두면 아직 안 나간 큰 건이 맨 아래로 밀린다.
          if (a.planRevenue != b.planRevenue) {
            return b.planRevenue.compareTo(a.planRevenue);
          }
          if (a.revenue != b.revenue) return b.revenue.compareTo(a.revenue);
          break;
        case _ProjectSort.achievementAsc:
          final ar = a.planRevenue <= 0 ? 1000.0 : a.revenue * 100 / a.planRevenue;
          final br = b.planRevenue <= 0 ? 1000.0 : b.revenue * 100 / b.planRevenue;
          if (ar != br) return ar.compareTo(br);
          break;
        case _ProjectSort.progressDesc:
          if (ap != bp) return (bp ?? -1).compareTo(ap ?? -1);
          break;
        case _ProjectSort.progressAsc:
          if (ap != bp) return (ap ?? 999).compareTo(bp ?? 999);
          break;
        case _ProjectSort.name:
          break;
      }
      return a.koreanName.compareTo(b.koreanName);
    });
    return list;
  }

  bool _matchesStatusFilter(_ProjectItem p) {
    switch (_statusFilter) {
      case _ProjectStatusFilter.all:
        return true;
      case _ProjectStatusFilter.normal:
        return p.hasData && p.status == '정상';
      case _ProjectStatusFilter.warning:
        return p.hasData && p.status == '주의';
      case _ProjectStatusFilter.delayed:
        return p.hasData && p.status == '지연';
      case _ProjectStatusFilter.noData:
        return !p.hasData;
    }
  }

  List<_ProjectItem> _visibleProjects(List<_ProjectItem> sorted) {
    final q = _projectQuery.trim().toLowerCase();
    final trimmed = _projectQuery.trim();
    return sorted.where((p) {
      if (!_matchesStatusFilter(p)) return false;
      if (_favoritesOnly && !_favoriteProjects.contains(p.id)) return false;
      if (q.isEmpty) return true;
      return p.englishName.toLowerCase().contains(q) ||
          p.koreanName.contains(trimmed) ||
          p.status.contains(trimmed);
    }).toList();
  }

  // 프로젝트 목록 필터 시트 (상태 / 정렬 / 즐겨찾기)
  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void update(VoidCallback fn) {
              setSheetState(fn);
              setState(fn);
            }

            Widget chip(String label, bool selected, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.headerNavy : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? AppColors.headerNavy
                          : const Color(0xFFD1D5DB),
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

            Widget section(String title, List<Widget> children) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.bodyStrong.copyWith(
                          fontSize: 13, color: AppColors.headerNavy)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: children),
                  const SizedBox(height: 16),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(sheetContext).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('프로젝트 필터',
                          style: AppText.bodyStrong
                              .copyWith(fontSize: 15, color: AppColors.headerNavy)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => update(() {
                          _statusFilter = _ProjectStatusFilter.all;
                          _sort = _ProjectSort.progressDesc;
                          _favoritesOnly = false;
                        }),
                        child: const Text('초기화',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  section('상태', [
                    for (final f in _ProjectStatusFilter.values)
                      chip(f.label, _statusFilter == f,
                          () => update(() => _statusFilter = f)),
                  ]),
                  section('정렬', [
                    for (final v in _ProjectSort.values)
                      chip(v.label, _sort == v, () => update(() => _sort = v)),
                  ]),
                  section('보기', [
                    chip('즐겨찾기만', _favoritesOnly,
                        () => update(() => _favoritesOnly = !_favoritesOnly)),
                  ]),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.headerNavy),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleFavorite(String id) async {
    final nowFav = await FavoritesService.toggle(id);
    if (!mounted) return;
    setState(() {
      if (nowFav) {
        _favoriteProjects = {..._favoriteProjects, id};
      } else {
        _favoriteProjects = {..._favoriteProjects}..remove(id);
      }
    });
  }

  /// 행 탭 → 선택 표시 → 상세 진입 → 복귀 시 선택 해제.
  Future<void> _tapProject(String projectKey, String projectName) async {
    setState(() => _selectedProjectId = projectKey);
    await _openProject(projectKey, projectName);
    if (!mounted) return;
    setState(() => _selectedProjectId = null);
  }

  Future<void> _openProject(String projectKey, String projectName) async {
    // 모델 데이터 로드
    // 모델 데이터 로드 (사용하지 않음)

    // 모델 있든 없든 프로젝트 현황 화면으로 이동
    if (!mounted) return;

    // 모델 있든 없든 프로젝트 현황 화면으로 이동
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(
          projectKey: projectKey,
          projectName: projectName,
        ),
      ),
    );
    // 상세에서 돌아오면 즐겨찾기 상태 재로드
    await _loadFavorites();
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
          const SnackBar(content: Text('설정 화면은 준비 중입니다.')),
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
            GestureDetector(
              onTap: _toggleDivisionFavorite,
              child: Icon(
                _isDivisionFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isDivisionFavorite ? const Color(0xFFF4B63D) : const Color(0xFFB0B0B0),
                size: 20,
              ),
            ),
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
          // 매출이 걸린 프로젝트가 본문, 나머지는 접힌 그룹.
          final withRevenue =
              visibleProjects.where((p) => p.hasRevenue).toList();
          final noRevenue =
              visibleProjects.where((p) => !p.hasRevenue).toList();

          return SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  DivisionRevenueHero(
                    month: _overview.month,
                    revenue: _overview.revenue,
                    planRevenue: _overview.planRevenue,
                    qtyPlan: _overview.qtyPlan,
                    qtyActual: _overview.qtyActual,
                    weekLabel: _weekLabel(),
                    businessDaysLeft: _businessDaysLeft(),
                    loading: _overviewLoading && !_overview.loaded,
                    loaded: _overview.loaded,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RevenueDetailScreen(
                            divisionId: widget.division.id,
                            divisionLabel: widget.division.label,
                          ),
                        ),
                      );
                    },
                  ),
                  if (data.delayed + data.warning > 0) ...[
                    const SizedBox(height: 10),
                    DivisionAttentionBanner(
                      count: data.delayed + data.warning,
                      severe: data.delayed > 0,
                      headline: data.immediate.isEmpty
                          ? null
                          : data.immediate.first.headline,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImmediateCheckScreen(
                              divisionFilterLabel: widget.division.label,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 18),

                  // ── 프로젝트 (매출 기여순)
                  Row(
                    children: [
                      Text(
                        '프로젝트',
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 14,
                          color: AppColors.headerNavy,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_sort.label} · ${visibleProjects.length}건',
                        style: AppText.caption.copyWith(
                          fontSize: 11.5,
                          color: AppColors.textHint,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _openFilterSheet,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Text(
                              '정렬',
                              style: AppText.caption.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.todayBlue,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 16, color: AppColors.todayBlue),
                          ],
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
                    onTapFilter: _openFilterSheet,
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
                  else ...[
                    for (final p in withRevenue) ...[
                      ProjectRevenueRow(
                        koreanName: p.koreanName,
                        status: p.status,
                        revenue: p.revenue,
                        planRevenue: p.planRevenue,
                        qtyPlan: p.qtyPlan,
                        qtyActual: p.qtyActual,
                        modelsTotal: p.modelsTotal,
                        progressPercent: p.progressPercent,
                        isFavorite: _favoriteProjects.contains(p.id),
                        isSelected: _selectedProjectId == p.id,
                        onTap: () => _tapProject(p.id, p.koreanName),
                        onToggleFavorite: () => _toggleFavorite(p.id),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 매출 계획이 없는 프로젝트는 기본으로 접어둔다.
                    // 첫 화면에서 읽어야 할 줄 수를 줄이는 게 목적이라
                    // 지우지는 않고 한 줄로만 남긴다.
                    if (noRevenue.isNotEmpty) ...[
                      InkWell(
                        onTap: () =>
                            setState(() => _showNoPlan = !_showNoPlan),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppColors.statusGraySoft,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '매출 계획 없는 프로젝트',
                                style: AppText.captionStrong.copyWith(
                                  fontSize: 12.5,
                                  color: AppColors.textMute,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${noRevenue.length}건',
                                style: AppText.captionStrong.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textHint,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _showNoPlan
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.chevron_right,
                                size: 18,
                                color: const Color(0xFFC5CAD3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 검색 중에는 접힌 그룹도 펼쳐야 결과가 보인다.
                      if (_showNoPlan || _projectQuery.trim().isNotEmpty)
                        for (final p in noRevenue) ...[
                          const SizedBox(height: 8),
                          ProjectPlainRow(
                            koreanName: p.koreanName,
                            modelsTotal: p.modelsTotal,
                            progressPercent: p.progressPercent,
                            isFavorite: _favoriteProjects.contains(p.id),
                            onTap: () => _tapProject(p.id, p.koreanName),
                            onToggleFavorite: () => _toggleFavorite(p.id),
                          ),
                        ],
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomPromptBar(
              onSubmit: (text) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(initialQuestion: text),
                  ),
                );
              },
            ),
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
  final int? progressPercent;
  final int? progressDeltaPp;
  final int delayed;
  final int warning;
  final int normal;
  final int noData;
  final int scoredModels;
  final String updatedAt;
  final List<DivisionImmediateItem> immediate;
  final List<_ProjectItem> projects;

  _DivisionData({
    required this.progressPercent,
    required this.progressDeltaPp,
    required this.delayed,
    required this.warning,
    required this.normal,
    required this.noData,
    required this.scoredModels,
    required this.updatedAt,
    required this.immediate,
    required this.projects,
  });
}

enum _ProjectStatusFilter {
  all('전체'),
  normal('정상'),
  warning('주의'),
  delayed('지연'),
  noData('미등록');

  final String label;
  const _ProjectStatusFilter(this.label);
}

enum _ProjectSort {
  revenueDesc('매출 기여순'),
  achievementAsc('달성률 낮은순'),
  progressDesc('진행률 높은순'),
  progressAsc('진행률 낮은순'),
  name('이름순');

  final String label;
  const _ProjectSort(this.label);
}

class _ProjectItem {
  final String id;
  final String englishName;
  final String koreanName;
  final String status;
  final int? progressPercent;
  final bool hasData;
  final int modelsTotal;
  final int revenue;
  final int planRevenue;
  final int qtyPlan;
  final int qtyActual;

  const _ProjectItem({
    required this.id,
    required this.englishName,
    required this.koreanName,
    required this.status,
    required this.progressPercent,
    required this.hasData,
    this.modelsTotal = 0,
    this.revenue = 0,
    this.planRevenue = 0,
    this.qtyPlan = 0,
    this.qtyActual = 0,
  });

  /// 이번 달 매출 계획이나 실적이 잡혀 있는가.
  /// 없으면 리스트 본문이 아니라 접힌 그룹으로 내린다.
  bool get hasRevenue => planRevenue > 0 || revenue > 0;
}
