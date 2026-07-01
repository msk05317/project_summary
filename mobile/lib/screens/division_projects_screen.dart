// 사업부 상세 화면 (시안 v3).
// 구성: 헤더 → 브레드크럼 → 요약 카드 → 즉시확인 → 프로젝트 검색/그리드
//      → 하단 LLM 입력바 → 하단 4탭 네비
// 현재는 mock 데이터로 UI 우선 완성, 백엔드 연결은 다음 단계.

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../components/division/division_summary_card.dart';
import '../components/division/division_immediate_check.dart';
import '../components/division/project_grid_card.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_select_screen.dart' show DivisionSelectScreen;
import 'report_detail_screen.dart';
import 'immediate_check_screen.dart';

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
  // 임시 즐겨찾기 상태 (백엔드 연결 전까지 로컬만 유지)
  final Set<String> _favoriteProjects = {'major_module'};

  // 마지막으로 선택(탭)한 프로젝트. 파란 테두리 표시용.
  String? _selectedProjectId;

  // 검색어
  String _projectQuery = '';

  // Mock 데이터 (백엔드 스펙 확정 전까지)
  late final _MockData _mock = _buildMock();

  _MockData _buildMock() {
    return _MockData(
      progressPercent: 68,
      progressDeltaPp: 2,
      delayed: 1,
      warning: 1,
      normal: 5,
      updatedAt: '2026-06-22 09:41',
      immediate: [
        DivisionImmediateItem(
          priority: ImmediatePriority.high,
          dueText: 'D-1',
          headline: '챔버 · 출하 지연',
          status: '지연',
        ),
        DivisionImmediateItem(
          priority: ImmediatePriority.mid,
          dueText: 'D-4',
          headline: '파워박스 · 부품 교체 지연',
          status: '지연',
        ),
        DivisionImmediateItem(
          priority: ImmediatePriority.mid,
          dueText: 'D-6',
          headline: '메이저모듈 · 일정 재확인',
          status: '주의',
        ),
        // 4번째가 있어도 즉시확인 UI는 최대 3건만 노출,
        // 우측 상단 건수는 전체(items.length) 유지
        DivisionImmediateItem(
          priority: ImmediatePriority.mid,
          dueText: 'D-8',
          headline: '엔클로저 · 일정 확인 필요',
          status: '주의',
        ),
      ],
      projects: const [
        _MockProject('Powerbox', '파워박스', '지연', 55),
        _MockProject('Frame', '프레임', '주의', 64),
        _MockProject('Major Module', '메이저모듈', '정상', 80, id: 'major_module'),
        _MockProject('Chamber', '챔버', '지연', 42),
        _MockProject('Enclosure', '엔클로저', '정상', 72),
        _MockProject('Hrva Plate', '하바플레이트', '정상', 78),
        _MockProject('CUP', 'CUP', '정상', 85),
      ],
    );
  }

  List<_MockProject> get _sortedProjects {
    final list = [..._mock.projects];
    list.sort((a, b) {
      final aFav = _favoriteProjects.contains(a.id);
      final bFav = _favoriteProjects.contains(b.id);

      if (aFav != bFav) {
        return aFav ? -1 : 1; // 즐겨찾기 먼저
      }

      return a.progressPercent.compareTo(b.progressPercent); // 낮은 % 먼저
    });
    return list;
  }

  List<_MockProject> get _visibleProjects {
    final q = _projectQuery.trim().toLowerCase();
    if (q.isEmpty) return _sortedProjects;

    return _sortedProjects.where((p) {
      return p.englishName.toLowerCase().contains(q) ||
          p.koreanName.contains(_projectQuery.trim()) ||
          p.status.contains(_projectQuery.trim());
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('새로고침은 다음 단계에서 연결합니다.')),
              );
            },
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
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            // 1) 요약 카드
            DivisionSummaryCard(
              divisionLabel: widget.division.label,
              updatedAt: _mock.updatedAt,
              progressPercent: _mock.progressPercent,
              progressDeltaPp: _mock.progressDeltaPp,
              projectCount: _mock.projects.length,
              delayedCount: _mock.delayed,
              warningCount: _mock.warning,
              normalCount: _mock.normal,
            ),
            const SizedBox(height: 16),

            // 2) 이 사업부 즉시 확인
            DivisionImmediateCheckSection(
              divisionShortLabel: shortLabel,
              items: _mock.immediate,
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

            // 3) 프로젝트 헤더
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
                      ? '총 ${_sortedProjects.length}건'
                      : '${_visibleProjects.length}/${_sortedProjects.length}건',
                  style: AppText.caption.copyWith(
                    fontSize: 11,
                    color: const Color(0xFF7C8594),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 4) 검색바 + 필터
            SearchFilterRow(
              value: _projectQuery,
              onChanged: (value) {
                setState(() {
                  _projectQuery = value;
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

            // 5) 프로젝트 그리드 (2열)
            if (_visibleProjects.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                child: Text(
                  '검색 결과가 없어요',
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
                itemCount: _visibleProjects.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 88,
                ),
                itemBuilder: (context, i) {
                  final p = _visibleProjects[i];
                  return ProjectGridCard(
                    englishName: p.englishName,
                    koreanName: p.koreanName,
                    status: p.status,
                    progressPercent: p.progressPercent,
                    isFavorite: _favoriteProjects.contains(p.id),
                    isSelected: _selectedProjectId == p.id,
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

// ===== Mock 데이터 (백엔드 연결 시 제거) =====
class _MockData {
  final int progressPercent;
  final int progressDeltaPp;
  final int delayed;
  final int warning;
  final int normal;
  final String updatedAt;
  final List<DivisionImmediateItem> immediate;
  final List<_MockProject> projects;

  _MockData({
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

class _MockProject {
  final String englishName;
  final String koreanName;
  final String status;
  final int progressPercent;
  final String id;

  const _MockProject(
    this.englishName,
    this.koreanName,
    this.status,
    this.progressPercent, {
    String? id,
  }) : id = id ?? koreanName;
}
