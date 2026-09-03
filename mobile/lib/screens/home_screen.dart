import 'dart:async';
// 앱의 첫 화면(홈).
// 시안 기준 상단부터 다음 순서로 구성합니다.
//  1) 상단 헤더 (HomeHeader)         — 로고, 알림/검색, 인사말, 오늘 날짜
//  2) 전체 현황 요약 (SummaryCard)    — /dashboard 카드로부터 KPI 계산
//  3) (다음 단계 예정) 즉시 확인 카드
//  4) 즐겨찾기 프로젝트 가로 스크롤
//  5) 전체 사업부 그리드
//  6) 하단 LLM 입력바 (BottomPromptBar)
//  7) 하단 4탭 네비 (AppBottomNav) — 첫 탭 '홈'
//
// 이번 단계에서 새로 들어간 것:
//  - /dashboard 호출 + KPI 계산
//  - SummaryCard 배치
//  - 하단 네비 첫 탭을 '홈' 으로 변경

import 'package:flutter/material.dart';
import 'notifications_screen.dart';

import '../components/components.dart';
import '../design/design.dart';
import '../models/division.dart';
import '../models/dashboard.dart';
import '../services/divisions_service.dart';
import '../services/favorites_service.dart';
import '../services/dashboard_service.dart';
import '../services/progress_service.dart';
import '../services/overview_service.dart';
import 'division_projects_screen.dart';
import 'overall_status_screen.dart';
import 'immediate_check_screen.dart';
import 'calendar_screen.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'project_overview_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _autoRefreshTimer;

  void _setupAutoRefresh() {
    _autoRefreshTimer?.cancel();
    final min = SettingsService.instance.autoRefreshMinutes.value;
    if (min <= 0) return;
    _autoRefreshTimer = Timer.periodic(Duration(minutes: min), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }


  // 사업부 목록 비동기 결과.
  late Future<List<Division>> _divisionsFuture;

  // 즐겨찾기 프로젝트 카드들의 비동기 결과.

  // 대시보드 카드 비동기 결과 (KPI 계산에 사용).
  late Future<List<DashboardCard>> _dashboardFuture;

  // 프로젝트별 진행률 요약 (모델 실데이터 기준).
  late Future<ProgressSummary> _progressFuture;

  // 경영 요약(이번 달 매출/출하) — 홈 최상단 카드용
  late Future<OverviewSummary> _overviewFuture;

  // 헤더 돋보기로 여는 검색 패널
  bool _searchOpen = false;

  // 사업부 필터
  _DivFilter _divFilter = _DivFilter.all;
  bool _favoritesOnly = false;

  bool get _filterActive =>
      _divFilter != _DivFilter.all || _favoritesOnly;

  /// 검색어 외 추가 필터(상태/즐겨찾기) 통과 여부.
  bool _passesFilter(Division d, DivisionStatus status) {
    if (_favoritesOnly && !_favDivisions.contains(d.id)) return false;
    switch (_divFilter) {
      case _DivFilter.all:
        return true;
      case _DivFilter.active:
        return status != DivisionStatus.empty;
      case _DivFilter.empty:
        return status == DivisionStatus.empty;
    }
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var f = _divFilter;
        var fav = _favoritesOnly;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget option(String label, bool selected, VoidCallback onTap) {
              return InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: AppText.body)),
                      if (selected)
                        const Icon(Icons.check,
                            size: 20, color: AppColors.summaryInProgress),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.borderDefault,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('사업부 필터', style: AppText.h2),
                    ),
                    const SizedBox(height: 6),
                    option('전체', f == _DivFilter.all,
                        () => setSheet(() => f = _DivFilter.all)),
                    option('진행 중인 사업부만', f == _DivFilter.active,
                        () => setSheet(() => f = _DivFilter.active)),
                    option('비어 있는 사업부만', f == _DivFilter.empty,
                        () => setSheet(() => f = _DivFilter.empty)),
                    const Divider(height: 1, color: AppColors.borderSoft),
                    option('즐겨찾기(★)만 보기', fav,
                        () => setSheet(() => fav = !fav)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setSheet(() {
                                  f = _DivFilter.all;
                                  fav = false;
                                });
                              },
                              child: const Text('초기화'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _divFilter = f;
                                  _favoritesOnly = fav;
                                });
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('적용'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 현재 선택된 하단 네비 탭. 첫 탭이 '홈'.
  AppNavTab _currentTab = AppNavTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAutoRefresh();
    SettingsService.instance.autoRefreshMinutes.addListener(_setupAutoRefresh);
    // 화면 진입 시 즉시 모든 데이터를 받아옵니다.
    _divisionsFuture = DivisionsService.fetchAll();
    _dashboardFuture = DashboardService.fetchCards();
    _progressFuture = ProgressService.fetch();
    _overviewFuture = OverviewService.fetch();
    _loadFavDivisions();

  }

  // 화면 전체 새로고침.
  Future<void> _refresh() async {
    setState(() {
      _divisionsFuture = DivisionsService.fetchAll();
        _dashboardFuture = DashboardService.fetchCards();
        _progressFuture = ProgressService.fetch();
        _overviewFuture = OverviewService.fetch();
    });
    _loadFavDivisions(); // 사업부 즐겨찾기 Set 로딩
    await Future.wait(
        [_divisionsFuture, _dashboardFuture, _progressFuture, _overviewFuture]);
  }

  // 오늘 날짜를 한국식 표기로 변환합니다.
  String get _todayLabel {
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일';
  }

  // ============================================================
  // 사업부 즐겨찾기 (Section: division favorites v1)
  // - 시안에서 DivisionGridCard 우측 상단 ★ 토글이 추가됨
  // - SharedPreferences 기반 FavoritesService 의 division 메서드를 사용
  // - 로컬 Set 으로 보관해 리렌더링을 최소화
  // ============================================================
  Set<String> _favDivisions = <String>{};

  // ============================================================
  // 검색어 (Section: home search v1)
  // - 시안의 '사업부명 / 프로젝트 검색' 입력에 대응.
  // - 빈 문자열이면 필터링 없음.
  // - 즐겨찾기 / 사업부 그리드 양쪽에 동일하게 적용.
  // ============================================================
  String _query = '';

  // 사업부/프로젝트 검색 매칭.
  // - 사업부 라벨, 또는 사업부에 포함된 프로젝트 라벨/키 중 하나라도 매칭되면 true.
  // - 대소문자 무시.
  bool _matchDivisionByQuery(Division d, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    if (d.label.toLowerCase().contains(needle)) return true;
    for (final p in d.projects) {
      if (p.label.toLowerCase().contains(needle)) return true;
      if (p.id.toLowerCase().contains(needle)) return true;
    }
    return false;
  }


  // 앱 진입 시 1회, 그리고 새로고침 시마다 호출.
  Future<void> _loadFavDivisions() async {
    final s = await FavoritesService.loadAllDivisions();
    if (!mounted) return;
    setState(() {
      _favDivisions = s;
    });
  }

  // 사업부 즐겨찾기 토글 핸들러.
  // - 카드의 별 아이콘에서 호출됨.
  // - 토글 후 로컬 Set 만 갱신해서 다시 setState — 카드 리렌더링 최소화.
  Future<void> _toggleDivisionFavorite(String divisionId) async {
    final nowFav = await FavoritesService.toggleDivision(divisionId);
    if (!mounted) return;
    setState(() {
      if (nowFav) {
        _favDivisions = {..._favDivisions, divisionId};
      } else {
        _favDivisions = {..._favDivisions}..remove(divisionId);
      }
    });
  }

  // 사업부 활성 상태 판정.
  // - 시안 규칙: 사업부 안 프로젝트 중 RED/YELLOW 가 1개라도 있으면 "진행 중".
  //              전부 GRAY/BLACK/null 이면 "대기".
  // - GREEN(완료)만 있는 경우는 일단 "대기"로 둡니다(시안의 회색 톤과 일치).
  // - 데이터 소스는 /dashboard 응답 (DashboardCard 리스트).
  //   각 카드의 division_id 가 일치하는 카드 중 status 가 RED/YELLOW 면 활성.
  DivisionStatus _divisionStatus(String divisionId, List<DashboardCard> cards) {
    return computeDivisionStatus(divisionId, cards);
  }

  // 즉시 확인 1줄용 핵심 내용 추출.
  //
  // 목표:
  // - [project_name] · 핵심 내용
  // - 너무 raw 하거나 placeholder 같은 문자열이면 null 반환
  String? _toImmediateHeadline(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // placeholder/마크다운 제거
    text = text.replaceAll(RegExp(r'__[^_]+__'), ' ');
    text = text.replaceAll(RegExp(r'[`*_#>]+'), ' ');
    text = text.replaceAll(RegExp(r'\[(.*?)\]'), ' ');

    // 앞쪽 번호/불릿 제거 (반복 적용: '1) ', '1. ', '- ', '• ', '· ')
    while (true) {
      final before = text;
      text = text.replaceFirst(
          RegExp(r'^(?:\d+[\)\.]\s*|[-•·]\s*)'), '');
      if (text == before) break;
    }

    // 화살표 이후 제거
    text = text.split(RegExp(r'->|→')).first;

    // 괄호 시작 전까지만
    text = text.split(RegExp(r'[\(\[]')).first;

    // 공백 정리
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;

    // 너무 짧은 코드성 텍스트 제거 (YFP, ABC123, A1B 등 영문/숫자만 짧게)
    if (text.length <= 4) return null;
    if (RegExp(r'^[A-Za-z0-9_-]{1,8}\$').hasMatch(text)) return null;

    // 앞 3~5어절만 사용 (최대 ~12자)
    final words = text.split(' ');
    var headline = '';
    for (final w in words) {
      final next = headline.isEmpty ? w : '$headline $w';
      if (next.length > 12) break;
      headline = next;
    }
    if (headline.isEmpty && words.isNotEmpty) {
      final first = words.first;
      headline = first.length > 12
          ? '${first.substring(0, 12)}…'
          : first;
    }

    // 한국어 조사 제거 (마지막 어절 끝)
    headline = headline.replaceAll(
        RegExp(r'(이|가|을|를|은|는|의|에|로|와|과|도)\$'), '');
    headline = headline.trim();

    // 앞뒤 구두점 정리
    headline = headline.replaceAll(
        RegExp(r'^[,.;:\-\s]+|[,.;:\-\s]+\$'), '');

    if (headline.isEmpty) return null;
    if (headline.length <= 2) return null;
    return headline;
  }





  // 즉시 확인 2줄용 상세 요약 추출.
  //
  // 목표:
  // - 핵심 내용 상세 요약
  // - 너무 길면 20자 컷
  // - 깨진 placeholder는 제거
  String? _toImmediateDetail(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // placeholder __XXX__ 제거
    text = text.replaceAll(RegExp(r'__[^_]+__'), ' ');

    // 마크다운/특수 기호 제거: * _ # > `
    text = text.replaceAll(RegExp(r'[`*_#>]+'), ' ');

    // 대괄호 [...] 제거 (내용은 살릴 수도 있지만 일단 제거)
    text = text.replaceAll(RegExp(r'\[(.*?)\]'), ' ');

    // 앞쪽 번호/불릿 제거: '1) ', '1. ', '- ', '• ', '· '
    text = text.replaceFirst(
        RegExp(r'^(?:\d+[\)\.]\s*|[-•·]\s*)'), '');

    // 화살표 '->', '→' 이후는 잘라냄 (꼬리표성 텍스트 제거)
    text = text.split(RegExp(r'->|→')).first;

    // 공백 정리
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;

    // 너무 짧은 코드성 텍스트 ('YFP', '1) YFP' 등) 제거
    if (text.length <= 4) return null;
    if (RegExp(r'^[A-Z0-9_-]{1,8}$').hasMatch(text)) return null;

    // 길이 제한 25자, 단어 경계에서 자연스럽게 자르기
    const maxLen = 25;
    if (text.length > maxLen) {
      var cut = text.substring(0, maxLen);
      final lastSpace = cut.lastIndexOf(' ');
      if (lastSpace >= 12) {
        cut = cut.substring(0, lastSpace);
      }
      text = '${cut.trimRight()}…';
    }

    // 앞뒤 구두점 정리
    text = text.replaceAll(RegExp(r'^[,.;:\-\s]+|[,.;:\-\s]+$'), '');

    return text.isEmpty ? null : text;
  }




  // ============================================================
  // 즉시 확인 (Section: immediate check v1)
  // - 추천 규칙(확정): status == 'RED' 이고 dueDateMin 이 존재하는 카드 중
  //                   마감 임박 순으로 최대 3개.
  // - dueDateMin 없는 RED 카드는 제외.
  // - 항목 1줄에 표시할 헤드라인은 summary_bullets[0] 의 짧은 앞부분 사용.
  // ============================================================

  // 즉시 확인 후보 카드 추출.
  // - now 는 D-day 계산 기준 시간 (테스트 편의를 위해 파라미터로 주입).
  List<ImmediateCheckItem> _buildImmediateItems(
    List<DashboardCard> cards, {
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    // 시각 영향 제거: 자정 기준으로만 D-day 계산.
    final today = DateTime(base.year, base.month, base.day);

    // 1) RED + dueDateMin 파싱 가능 카드만 추림
    final candidates = <_RankedCard>[];
    for (final c in cards) {
      if (c.status.toUpperCase() != 'RED') continue;
      final dueRaw = c.dueDateMin;
      if (dueRaw == null || dueRaw.isEmpty) continue;
      final due = DateTime.tryParse(dueRaw);
      if (due == null) continue;
      final dueDay = DateTime(due.year, due.month, due.day);
      final diffDays = dueDay.difference(today).inDays;
      candidates.add(_RankedCard(card: c, diffDays: diffDays));
    }

    // 1.5) 같은 프로젝트 중복 제거 (projectKey 기준, 가장 마감 가까운 것만 유지)
    final seenKeys = <String>{};
    candidates.removeWhere((rc) {
      final key = rc.card.projectKey.isNotEmpty 
          ? rc.card.projectKey 
          : rc.card.projectLabel;
      if (seenKeys.contains(key)) return true;
      seenKeys.add(key);
      return false;
    });

    // 2) 마감이 가까운 순 정렬 (이미 지난 것 = 음수가 가장 앞으로 옴)
    // 정렬 규칙 (시안 v3):
    // - 7일 이상 지난 항목은 제외 (오래된 RED 카드 노출 방지)
    // - 미래/오늘(diffDays >= 0) 항목을 먼저, 가까운 순으로
    // - 그 다음 과거(diffDays < 0) 항목을 최근 지난 순으로
    candidates.removeWhere((c) => c.diffDays < -30);
    candidates.sort((a, b) {
      final aFuture = a.diffDays >= 0 ? 0 : 1;
      final bFuture = b.diffDays >= 0 ? 0 : 1;
      if (aFuture != bFuture) return aFuture.compareTo(bFuture);
      return a.diffDays.abs().compareTo(b.diffDays.abs());
    });

    // 3) 상위 3개만
    final top = candidates.take(3).toList();

    // 4) 모델 변환
    return top.map((rc) {
      final diff = rc.diffDays;
      // D-day 텍스트 ('D-1', 'D+2', 'D-day')
      final dueText = diff == 0
          ? 'D-day'
          : (diff > 0 ? 'D-$diff' : 'D+${-diff}');

      // 톤 결정
      // - diff <= 1     : urgent
      // - 2 <= diff <= 3: warn
      // - else          : info
      ImmediateCheckTone tone;
      if (diff <= 1) {
        tone = ImmediateCheckTone.urgent;
      } else if (diff <= 3) {
        tone = ImmediateCheckTone.warn;
      } else {
        tone = ImmediateCheckTone.info;
      }

      // 헤드라인: summary_bullets[0] 을 짧게 정제.
      // - placeholder 류(__PRODUCT__, __SOMETHING__) 제거
      // - 마크다운/특수문자 제거 (* # >)
      // - 양 끝 공백 정리
      // - 결과가 비거나 너무 깨졌으면 null (= 프로젝트명만 표시)
      // - 20자 컷
      String? headline;
      String? detail;

      if (rc.card.summaryBullets.isNotEmpty || rc.card.headline.trim().isNotEmpty) {
        // headline: 백엔드 headline 필드 우선, 없으면 summaryBullets[0] 사용
        final rawHeadline = rc.card.headline.trim().isNotEmpty
            ? rc.card.headline
            : (rc.card.summaryBullets.isNotEmpty
                ? rc.card.summaryBullets.first
                : '');
        final rawDetail = rc.card.summaryBullets.isNotEmpty
            ? rc.card.summaryBullets.first
            : '';

        if (rawHeadline.isNotEmpty) {
          headline = _toImmediateHeadline(rawHeadline);
        }
        if (rawDetail.isNotEmpty) {
          detail = _toImmediateDetail(rawDetail);
        }

        // headline/detail 중복 제거 (한 쪽이 다른 쪽의 부분집합이면 detail 숨김)
        if (headline != null && detail != null) {
          final h = headline.replaceAll('…', '').trim();
          final d = detail.replaceAll('…', '').trim();
          if (h.isNotEmpty && (d.startsWith(h) || h.startsWith(d))) {
            detail = null;
          }
        }
      }

      return ImmediateCheckItem(
        projectKey: rc.card.projectKey,
        projectLabel: rc.card.projectLabel,
        headline: headline,
        detail: detail,
        dueText: dueText,
        tone: tone,
        status: rc.card.status,
      );
    }).toList();
  }

  // 프로젝트 카드 클릭 시 보고 상세 화면으로 진입.
  void _openProject(String projectKey) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(projectKey: projectKey, projectName: ''),
      ),
    );
  }

  // 사업부 카드 클릭 시 사업부 내 프로젝트 목록 화면으로 진입.
  void _openImmediateCheck({String? divisionLabel}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImmediateCheckScreen(
          divisionFilterLabel: divisionLabel,
        ),
      ),
    );
  }

  void _openOverallStatus() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const OverallStatusScreen(),
      ),
    );
  }

  Future<void> _openDivision(Division division) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DivisionProjectsScreen(division: division),
      ),
    );
    // 목록 화면에서 즐겨찾기 상태가 바뀌었을 수 있으니 재로드
    await _loadFavDivisions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    HomeHeader(
                      todayLabel: _todayLabel,
                      onTapNotification: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                      onTapSearch: () {
                        setState(() {
                          _searchOpen = !_searchOpen;
                          if (!_searchOpen) _query = '';
                        });
                      },
                    ),

                    // 헤더 돋보기로 여는 검색 패널.
                    // 사업부뿐 아니라 프로젝트까지 바로 찾아 들어갈 수 있게 한다.
                    if (_searchOpen)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.x4,
                          AppSpacing.x2,
                          AppSpacing.x4,
                          AppSpacing.x2,
                        ),
                        child: _HomeSearchPanel(
                          query: _query,
                          divisionsFuture: _divisionsFuture,
                          onChanged: (v) => setState(() => _query = v),
                          onClose: () => setState(() {
                            _searchOpen = false;
                            _query = '';
                          }),
                          onTapDivision: _openDivision,
                          onTapProject: (key) => _openProject(key),
                        ),
                      ),

                    // 전체 현황 요약 (KPI)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x4,
                        AppSpacing.x1,
                        AppSpacing.x4,
                        AppSpacing.x3,
                      ),
                      child: _SummarySection(
                        future: _dashboardFuture,
                        divisionsFuture: _divisionsFuture,
                        progressFuture: _progressFuture,
                        onTap: _openOverallStatus,
                      ),
                    ),

                    // 이번 달 매출 (경영진이 가장 먼저 봐야 하는 숫자)
                    // - 기존에는 홈 → 사업부 → 프로젝트 3단계를 들어가야 볼 수 있었음
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x4,
                        0,
                        AppSpacing.x4,
                        AppSpacing.x3,
                      ),
                      child: FutureBuilder<OverviewSummary>(
                        future: _overviewFuture,
                        builder: (context, snap) {
                          return ExecRevenueCard(
                            summary: snap.data ?? OverviewSummary.empty,
                            loading:
                                snap.connectionState == ConnectionState.waiting,
                            onTap: _openOverallStatus,
                          );
                        },
                      ),
                    ),

                    // 즉시 확인 섹션 (시안 v2 신규)
                    // - SummaryCard 아래, 즐겨찾기 위에 배치
                    // - 데이터 소스: _dashboardFuture (SummaryCard 가 쓰던 Future 재사용)
                    // - 항목 추출 로직: _HomeScreenState._buildImmediateItems
                    // - 항목 탭: 보고 상세 화면으로 이동
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.x4,
                        0,
                        AppSpacing.x4,
                        AppSpacing.x3,
                      ),
                      child: _ImmediateCheckSection(
                        future: _dashboardFuture,
                        buildItems: _buildImmediateItems,
                        onTapItem: (item) => _openProject(item.projectKey),
                        onTapShowAll: () => _openImmediateCheck(),
                      ),
                    ),

                    _DivisionsSection(
                      future: _divisionsFuture,
                      onTapItem: _openDivision,
                      dashboardFuture: _dashboardFuture,
                      favoriteDivisionIds: _favDivisions,
                      divisionStatus: _divisionStatus,
                      onToggleFavorite: _toggleDivisionFavorite,
                      // 검색/필터 (시안 v2 신규)
                      query: _query,
                      matchDivision: _matchDivisionByQuery,
                      onChangedQuery: (v) => setState(() => _query = v),
                      onTapFilter: _openFilterSheet,
                      passesFilter: _passesFilter,
                      filterActive: _filterActive,
                      onClearFilter: () => setState(() {
                        _divFilter = _DivFilter.all;
                        _favoritesOnly = false;
                      }),
                      // 즐겨찾기 종속 prop (시안 v2 신규)
                    ),
                  ],
                ),
              ),
            ),

            // 하단 LLM 입력바 (UI 만)
            BottomPromptBar(
              onSubmit: (text) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(initialQuestion: text),
                  ),
                );
              },
            ),

            // 하단 글로벌 네비 (첫 탭 '홈')
            AppBottomNav(
              current: _currentTab,
              onChanged: (tab) {
                if (tab != AppNavTab.settings) setState(() => _currentTab = tab);
                switch (tab) {
                  case AppNavTab.home:
                    break;
                  case AppNavTab.list:
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DivisionSelectScreen(),
                      ),
                    ).then((_) {
                      if (!mounted) return;
                      setState(() => _currentTab = AppNavTab.home);
                    });
                    break;
                  case AppNavTab.calendar:
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CalendarScreen(),
                      ),
                    ).then((_) {
                      if (!mounted) return;
                      setState(() => _currentTab = AppNavTab.home);
                    });
                    break;
                  case AppNavTab.settings:

                    Navigator.of(context).push(

                      MaterialPageRoute(

                        builder: (_) => const SettingsScreen(),

                      ),

                    );

                    break;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

}

// 전체 현황 요약 섹션.
// /dashboard 응답을 받아 DashboardSummary 로 집계 후 SummaryCard 에 전달합니다.
class _SummarySection extends StatelessWidget {
  final Future<List<DashboardCard>> future;
  final Future<List<Division>> divisionsFuture;
  final Future<ProgressSummary> progressFuture;
  final VoidCallback onTap;

  const _SummarySection({
    required this.future,
    required this.divisionsFuture,
    required this.progressFuture,
    required this.onTap,
  });

  /// 사업부 단위 요약 집계.
  /// - 전체 = 등록된 사업부 수
  /// - 상태(지연/주의/정상)는 사업부 안 프로젝트의 최악 상태 기준
  ///   (진행률 데이터가 하나도 없는 사업부는 상태 분류에서 제외)
  /// - 전체 진행률은 집계 대상 모델 가중 평균
  DashboardSummary _summarize(
    List<Division> divisions,
    List<DashboardCard> cards,
    ProgressSummary progress,
  ) {
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

    final worstByKey = <String, String>{};
    for (final c in cards) {
      if (c.projectKey.isEmpty) continue;
      final cur = worstByKey[c.projectKey];
      if (cur == null || rank(c.status) > rank(cur)) {
        worstByKey[c.projectKey] = c.status;
      }
    }

    // 전체 사업부의 프로젝트 목록 (진행률 가중 평균용)
    final keys = <String>{};
    for (final d in divisions) {
      for (final p in d.projects) {
        if (p.id.isNotEmpty) keys.add(p.id);
      }
    }
    keys.addAll(worstByKey.keys);

    // ── 사업부 단위 집계 ──
    // 전체 = 등록된 사업부 수, 상태는 사업부 안 프로젝트 중 최악 기준
    var delayed = 0, warning = 0, normal = 0, noData = 0;
    for (final d in divisions) {
      final pKeys = d.projects
          .map((p) => p.id)
          .where((id) => id.isNotEmpty)
          .toList();
      final hasData = pKeys.any((k) => progress.of(k)?.hasData ?? false);
      if (!hasData) {
        noData++;
        continue;
      }
      var worst = 1;
      for (final k in pKeys) {
        final st = worstByKey[k];
        if (st == null) continue;
        final r = rank(st);
        if (r > worst) worst = r;
      }
      if (worst == 3) {
        delayed++;
      } else if (worst == 2) {
        warning++;
      } else {
        normal++;
      }
    }

    return DashboardSummary.fromDivisions(
      delayed: delayed,
      warning: warning,
      normal: normal,
      noData: noData,
      progress: progress.weightedFor(keys),
    );
  }
  // SummaryCard 우측 상단 캡션 포맷터.
  // - "오늘 09:07 기준" 형태로 두 자리 패딩.
  String _formatSummaryCaption(DateTime now) {
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '오늘 $hh:$mm 기준';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DashboardCard>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Text(
            '대시보드를 불러오지 못했어요.\n${snapshot.error}',
            style: AppText.caption.copyWith(color: AppColors.reportBody),
          );
        }

        final cards = snapshot.data ?? const <DashboardCard>[];

        return FutureBuilder<List<Division>>(
          future: divisionsFuture,
          builder: (context, divSnap) {
            return FutureBuilder<ProgressSummary>(
              future: progressFuture,
              builder: (context, progSnap) {
                final divisions = divSnap.data ?? const <Division>[];
                final progress = progSnap.data ?? ProgressSummary.empty;
                final summary = divisions.isEmpty && progress.projects.isEmpty
                    ? DashboardSummary.fromCards(cards)
                    : _summarize(divisions, cards, progress);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: SummaryCard(
                      summary: summary,
                      rightCaption: _formatSummaryCaption(DateTime.now()),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}


// 홈 화면의 '전체 사업부' 섹션.
//
// 변경 의도 (시안 v2):
// - 카드마다 좌측 상단에 상태점(진행 중/대기) 표시
// - 카드마다 우측 상단에 즐겨찾기 별 토글
//
// 이를 위해 _DivisionsSection 이 추가로 받는 정보:
//  - dashboardFuture       : 사업부 status 계산용 /dashboard 카드 목록
//  - favoriteDivisionIds   : 현재 즐겨찾기된 사업부 id 집합
//  - divisionStatus        : (divisionId, cards) → 4단계 상태 판정 함수
//                            (HomeScreen 의 _isDivisionActive 위임)
//  - onToggleFavorite      : (divisionId) → 즐겨찾기 토글 콜백
//
// 사업부 status 계산은 _dashboardFuture 와 _divisionsFuture 두 결과가 모두
// 필요한데, 둘을 동시에 기다리기 위해 GridView 영역에 dashboardFuture 의
// FutureBuilder 를 한 겹 더 둡니다.
// (네트워크는 SummaryCard 가 이미 같은 Future 를 소비 중이므로 중복 호출 없음)
class _DivisionsSection extends StatelessWidget {
  final Future<List<Division>> future;
  final void Function(Division item) onTapItem;

  final Future<List<DashboardCard>> dashboardFuture;
  final Set<String> favoriteDivisionIds;
  final DivisionStatus Function(String divisionId, List<DashboardCard> cards) divisionStatus;
  final void Function(String divisionId) onToggleFavorite;

  // 검색/필터
  final String query;
  final bool Function(Division d, String q) matchDivision;
  final VoidCallback onTapFilter;
  final ValueChanged<String> onChangedQuery;

  // 상태/즐겨찾기 필터
  final bool Function(Division d, DivisionStatus status) passesFilter;
  final bool filterActive;
  final VoidCallback onClearFilter;

  const _DivisionsSection({
    required this.future,
    required this.onTapItem,
    required this.dashboardFuture,
    required this.favoriteDivisionIds,
    required this.divisionStatus,
    required this.onToggleFavorite,
    required this.query,
    required this.matchDivision,
    required this.onTapFilter,
    required this.onChangedQuery,
    required this.passesFilter,
    required this.filterActive,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x4,
        AppSpacing.x2,
        AppSpacing.x4,
        AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더: 📋 전체 사업부 + 우측 총개수
          FutureBuilder<List<Division>>(
            future: future,
            builder: (context, snap) {
              final total = (snap.data ?? const <Division>[]).length;
              return Row(
                children: [
                  Text(
                    '📋 ',
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.reportHeading,
                    ),
                  ),
                  Text(
                    '전체 사업부',
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.reportHeading,
                    ),
                  ),
                  const Spacer(),
                  if (snap.connectionState != ConnectionState.waiting)
                    Text(
                      '$total개',
                      style: AppText.caption.copyWith(
                        color: AppColors.reportBody,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.x2),

          // 검색바 + 필터
          SearchFilterRow(
            value: query,
            onChanged: onChangedQuery,
            onTapFilter: onTapFilter,
            hintText: '사업부명 검색',
          ),
          const SizedBox(height: AppSpacing.x3),

          // 즐겨찾기 사업부 서브섹션 (시안 v3 - 사업부 단위 즐겨찾기)
          // - 사업부 카드의 ★ 토글로 등록된 favoriteDivisionIds 사용
          // - 0개일 때 섹션 통째로 숨김
          FutureBuilder<List<Division>>(
            future: future,
            builder: (context, snap) {
              final all = snap.data ?? const <Division>[];

              return FutureBuilder<List<DashboardCard>>(
                future: dashboardFuture,
                builder: (context, cardSnap) {
                  final cards = cardSnap.data ?? const <DashboardCard>[];
                  final favs = all
                      .where((d) => favoriteDivisionIds.contains(d.id))
                      .where((d) => matchDivision(d, query))
                      .where((d) =>
                          passesFilter(d, divisionStatus(d.id, cards)))
                      .toList();

                  if (favs.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 서브헤더: ★ 즐겨찾기 N개
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '즐겨찾기',
                            style: AppText.bodyStrong.copyWith(
                              color: AppColors.reportHeading,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              color: AppColors.dividerSoft,
                            ),
                          ),
                          Text(
                            '${favs.length}개',
                            style: AppText.caption.copyWith(
                              color: AppColors.reportBody,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 104,
                        ),
                        itemCount: favs.length,
                        itemBuilder: (context, index) {
                          final d = favs[index];
                          return DivisionGridCard(
                            divisionId: d.id,
                            label: d.label,
                            projectCount: d.projects.length,
                            status: divisionStatus(d.id, cards),
                            isFavorite: true,
                            onTap: () => onTapItem(d),
                            onToggleFavorite: () => onToggleFavorite(d.id),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.x3),
                    ],
                  );
                },
              );
            },
          ),

          // '전체' 서브헤더 + 검색 후 사업부 개수
          FutureBuilder<List<Division>>(
            future: future,
            builder: (context, snap) {
              final all = snap.data ?? const <Division>[];
              return FutureBuilder<List<DashboardCard>>(
                future: dashboardFuture,
                builder: (context, cardSnap) {
              final cards = cardSnap.data ?? const <DashboardCard>[];
              final filtered = all
                  .where((d) => matchDivision(d, query))
                  .where((d) => passesFilter(d, divisionStatus(d.id, cards)))
                  .toList();
              final allCount = all.length;
              final shownCount = filtered.length;

              return Row(
                children: [
                  Text(
                    '전체',
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.reportHeading,
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: AppColors.dividerSoft,
                    ),
                  ),
                  Text(
                    (query.isEmpty && !filterActive)
                        ? '$allCount개'
                        : '$shownCount/$allCount개',
                    style: AppText.caption.copyWith(
                      color: AppColors.reportBody,
                    ),
                  ),
                ],
              );
                },
              );
            },
          ),

          // 필터가 걸려 있으면 한 줄로 알려주고, 눌러서 바로 해제한다.
          if (filterActive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: onClearFilter,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.summaryInProgress
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_alt_rounded,
                            size: 13,
                            color: AppColors.summaryInProgress),
                        const SizedBox(width: 4),
                        Text('필터 적용 중',
                            style: AppText.caption.copyWith(
                              color: AppColors.summaryInProgress,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(width: 8),
                        Text('해제',
                            style: AppText.caption.copyWith(
                              color: AppColors.summaryInProgress,
                              decoration: TextDecoration.underline,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.x2),

          // 사업부 그리드 (검색어 필터링 + status 매핑)
          FutureBuilder<List<Division>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Text(
                  '사업부 정보를 불러오지 못했어요.\n${snapshot.error}',
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                );
              }

              final allItems = snapshot.data ?? const <Division>[];

              if (allItems.isEmpty) {
                return Text(
                  '등록된 사업부가 없습니다.',
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                );
              }
              return FutureBuilder<List<DashboardCard>>(
                future: dashboardFuture,
                builder: (context, cardSnap) {
                  final cards = cardSnap.data ?? const <DashboardCard>[];
                  final items = allItems
                      .where((d) => matchDivision(d, query))
                      .where((d) =>
                          passesFilter(d, divisionStatus(d.id, cards)))
                      .toList();

                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        query.isEmpty
                            ? '조건에 맞는 사업부가 없습니다.'
                            : '"$query" 에 해당하는 사업부/프로젝트가 없습니다.',
                        style: AppText.caption.copyWith(
                          color: AppColors.reportBody,
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      // 시안 v3: 카드 간격 축소
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      // 시안 v3: 카드 높이를 80px로 고정 (시안 절대 크기 169x80 기준)
                      mainAxisExtent: 104,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final d = items[index];
                      return DivisionGridCard(
                        divisionId: d.id,
                        label: d.label,
                        projectCount: d.projects.length,
                        status: divisionStatus(d.id, cards),
                        isFavorite: favoriteDivisionIds.contains(d.id),
                        onTap: () => onTapItem(d),
                        onToggleFavorite: () => onToggleFavorite(d.id),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
// 즉시 확인 정렬 보조용. card + 마감까지 남은 일수(diff) 묶음.
class _RankedCard {
  final DashboardCard card;
  final int diffDays;
  _RankedCard({required this.card, required this.diffDays});
}

// 즉시 확인 섹션.
// - _dashboardFuture 결과를 받아 ImmediateCheckCard 로 변환해 그립니다.
// - 후보 항목이 0개이면 카드 자체를 그리지 않습니다 (시안: 빨간 카드가 화면에 떠 있어선 안 됨).
// - 변환 로직은 HomeScreen 의 _buildImmediateItems 를 그대로 위임받습니다.
class _ImmediateCheckSection extends StatelessWidget {
  // SummaryCard 가 쓰던 동일한 Future. 재사용해 추가 네트워크 호출 없음.
  final Future<List<DashboardCard>> future;

  // DashboardCard 리스트 → ImmediateCheckItem 리스트 변환 함수.
  // - 시그니처: (cards) => List<ImmediateCheckItem>
  final List<ImmediateCheckItem> Function(List<DashboardCard> cards) buildItems;

  // 항목 탭 콜백.
  final void Function(ImmediateCheckItem item) onTapItem;

  // '모두 보기' 탭 콜백.
  final VoidCallback? onTapShowAll;

  const _ImmediateCheckSection({
    required this.future,
    required this.buildItems,
    required this.onTapItem,
    this.onTapShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DashboardCard>>(
      future: future,
      builder: (context, snap) {
        // 로딩 / 에러 / 0건을 반드시 구분해서 보여준다.
        // 예전에는 셋 다 SizedBox.shrink() 라, 조회가 실패해도 화면상으로는
        // '지연 없음' 과 똑같이 보였다 (경영 판단이 걸린 정보라 위험).
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ImmediateNotice(
            icon: Icons.hourglass_empty,
            text: '지연·마감임박 항목 확인 중...',
          );
        }

        if (snap.hasError) {
          return const _ImmediateNotice(
            icon: Icons.error_outline,
            text: '지연 현황을 불러오지 못했습니다',
            color: AppColors.statusRed,
          );
        }

        final cards = snap.data ?? const <DashboardCard>[];
        final items = buildItems(cards);

        if (items.isEmpty) {
          return const _ImmediateNotice(
            icon: Icons.check_circle_outline,
            text: '지연·마감임박 항목이 없습니다',
            color: AppColors.summaryNormal,
          );
        }

        return ImmediateCheckCard(
          items: items,
          onTapItem: onTapItem,
          onTapShowAll: onTapShowAll,
        );
      },
    );
  }
}

// 즉시 확인 섹션의 로딩/에러/0건 안내 한 줄.
class _ImmediateNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _ImmediateNotice({
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMute;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppText.body.copyWith(color: c)),
          ),
        ],
      ),
    );
  }
}

// 사업부 필터 종류. 필터 시트에서 고른다.
enum _DivFilter { all, active, empty }

// 헤더 돋보기로 여는 검색 패널.
// - 사업부명뿐 아니라 프로젝트명/키까지 한 번에 찾는다.
// - 결과를 바로 눌러 해당 화면으로 들어간다.
class _HomeSearchPanel extends StatefulWidget {
  final String query;
  final Future<List<Division>> divisionsFuture;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final void Function(Division division) onTapDivision;
  final void Function(String projectKey) onTapProject;

  const _HomeSearchPanel({
    required this.query,
    required this.divisionsFuture,
    required this.onChanged,
    required this.onClose,
    required this.onTapDivision,
    required this.onTapProject,
  });

  @override
  State<_HomeSearchPanel> createState() => _HomeSearchPanelState();
}

class _HomeSearchPanelState extends State<_HomeSearchPanel> {
  late final TextEditingController _c =
      TextEditingController(text: widget.query);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query.trim().toLowerCase();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: AppColors.textMute),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    style: AppText.body,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '사업부 · 프로젝트 검색',
                      hintStyle:
                          AppText.body.copyWith(color: AppColors.textMute),
                    ),
                    onChanged: (v) {
                      setState(() {});
                      widget.onChanged(v);
                    },
                  ),
                ),
                if (_c.text.isNotEmpty)
                  IconButton(
                    tooltip: '지우기',
                    icon: const Icon(Icons.cancel,
                        size: 18, color: AppColors.textMute),
                    onPressed: () {
                      _c.clear();
                      setState(() {});
                      widget.onChanged('');
                    },
                  ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          if (q.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.borderSoft),
            FutureBuilder<List<Division>>(
              future: widget.divisionsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final all = snap.data ?? const <Division>[];

                final divHits = all
                    .where((d) => d.label.toLowerCase().contains(q))
                    .toList();

                final projHits = <_ProjHit>[];
                for (final d in all) {
                  for (final p in d.projects) {
                    if (p.label.toLowerCase().contains(q) ||
                        p.id.toLowerCase().contains(q)) {
                      projHits.add(_ProjHit(d, p));
                    }
                  }
                }

                if (divHits.isEmpty && projHits.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    child: Text(
                      '"${widget.query}" 검색 결과가 없습니다.',
                      style:
                          AppText.caption.copyWith(color: AppColors.reportBody),
                    ),
                  );
                }

                final rows = <Widget>[];

                if (divHits.isNotEmpty) {
                  rows.add(_sectionLabel('사업부 ${divHits.length}'));
                  for (final d in divHits.take(6)) {
                    rows.add(_row(
                      icon: Icons.apartment_rounded,
                      title: d.label,
                      sub: '프로젝트 ${d.projects.length}개',
                      onTap: () {
                        widget.onClose();
                        widget.onTapDivision(d);
                      },
                    ));
                  }
                }

                if (projHits.isNotEmpty) {
                  rows.add(_sectionLabel('프로젝트 ${projHits.length}'));
                  for (final h in projHits.take(8)) {
                    rows.add(_row(
                      icon: Icons.description_outlined,
                      title: h.project.label,
                      sub: h.division.label,
                      onTap: () {
                        widget.onClose();
                        widget.onTapProject(h.project.id);
                      },
                    ));
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          color: AppColors.textMute,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.summaryInProgress),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text(sub,
                      style:
                          AppText.caption.copyWith(color: AppColors.reportBody),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textMute),
          ],
        ),
      ),
    );
  }
}

// 검색 결과에서 '어느 사업부의 어느 프로젝트' 인지 같이 들고 다닌다.
class _ProjHit {
  final Division division;
  final DivisionProjectRef project;
  const _ProjHit(this.division, this.project);
}
