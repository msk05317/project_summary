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
import '../services/progress_service.dart';
import '../services/favorites_service.dart';
import '../components/division/division_summary_card.dart';
import '../components/division/division_immediate_check.dart';
import '../components/division/project_grid_card.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'immediate_check_screen.dart';
import 'project_overview_screen.dart';
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
  _ProjectSort _sort = _ProjectSort.progressDesc;
  bool _favoritesOnly = false;


  late Future<List<DashboardCard>> _future;

  /// 진행률 요약 (백엔드 /projects-progress-summary)
  ProgressSummary _progress = ProgressSummary.empty;

  @override
  void initState() {
    super.initState();
    _future = DashboardService.fetchCards();
    _loadFavorites();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final summary = await ProgressService.fetch();
    if (!mounted) return;
    setState(() => _progress = summary);
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
    await Future.wait([_future, _loadProgress()]);
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

    final projects = <_ProjectItem>[];
    for (final p in widget.division.projects) {
      final card = cardByKey[p.id];
      final int? percent = avgProgressOf(p.id);
      // '데이터 있음' = 진행률이 산출되는 프로젝트 (모델만 있고 입력이 없으면 미등록)
      final hasData = _progress.of(p.id)?.hasData ?? false;
      final status = hasData && card != null ? _statusLabel(card.status) : '';
      projects.add(_ProjectItem(
        id: p.id,
        englishName: _englishOf(p.id),
        koreanName: p.label,
        status: status,
        progressPercent: percent,
        hasData: hasData,
        modelsTotal: _progress.of(p.id)?.modelsTotal ?? 0,
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
        progressPercent: avgProgressOf(c.projectKey),
        hasData: _progress.of(c.projectKey)?.hasData ?? false,
        modelsTotal: _progress.of(c.projectKey)?.modelsTotal ?? 0,
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
      if (a.hasData != b.hasData) return a.hasData ? -1 : 1;

      final ap = a.progressPercent;
      final bp = b.progressPercent;
      switch (_sort) {
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
                    noDataCount: data.noData,
                    basisText: data.scoredModels > 0
                        ? '집계 모델 ${data.scoredModels}개'
                        : null,
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
                        mainAxisExtent: 112,
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
                          modelsTotal: p.modelsTotal,
                          onTap: () async {
                            setState(() {
                              _selectedProjectId = p.id;
                            });
                            await _openProject(p.id, p.koreanName);
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

  const _ProjectItem({
    required this.id,
    required this.englishName,
    required this.koreanName,
    required this.status,
    required this.progressPercent,
    required this.hasData,
    this.modelsTotal = 0,
  });
}
