import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../services/divisions_service.dart';
import '../services/dashboard_service.dart';
import '../services/favorites_service.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/division_grid_card.dart';
import '../models/dashboard.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_projects_screen.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class DivisionSelectScreen extends StatefulWidget {
  const DivisionSelectScreen({super.key});

  @override
  State<DivisionSelectScreen> createState() => _DivisionSelectScreenState();
}

class _DivisionSelectScreenState extends State<DivisionSelectScreen> {
  late Future<List<Division>> _divisionsFuture;
  late Future<List<DashboardCard>> _dashboardFuture;
  Set<String> _favoriteDivisions = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _divisionsFuture = DivisionsService.fetchAll();
    _dashboardFuture = DashboardService.fetchCards();
    _loadFavorites();
  }

  // 즐겨찾기는 홈 화면과 같은 저장소를 써야 한다.
  // (예전에는 이 화면만 메모리 Set 이라 ★를 눌러도 저장되지 않았고
  //  홈과 값이 달라 보였다)
  Future<void> _loadFavorites() async {
    final saved = await FavoritesService.loadAllDivisions();
    if (!mounted) return;
    setState(() => _favoriteDivisions = saved);
  }

  DivisionStatus _statusOf(String divisionId, List<DashboardCard> cards) {
    return computeDivisionStatus(divisionId, cards);
  }

  Future<void> _toggleFavorite(String id) async {
    await FavoritesService.toggleDivision(id);
    await _loadFavorites();
  }

  bool _matchDivision(Division d, String q) {
    if (q.trim().isEmpty) return true;
    final query = q.trim();
    return d.label.contains(query) ||
        (d.badgeShortLabel?.contains(query) ?? false) ||
        d.projects.any((p) => p.label.contains(query));
  }

  void _openDivision(Division division) {
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
        break;
      case AppNavTab.calendar:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CalendarScreen(),
          ),
        );
        break;
      case AppNavTab.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
        titleSpacing: 16,
        automaticallyImplyLeading: false,
        title: const Text(
          '목록',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() {
                _divisionsFuture = DivisionsService.fetchAll();
                _dashboardFuture = DashboardService.fetchCards();
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([_divisionsFuture, _dashboardFuture]),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final results = snap.data ?? [];
            final all = results.isNotEmpty
                ? results[0] as List<Division>
                : const <Division>[];
            final cards = results.length > 1
                ? results[1] as List<DashboardCard>
                : const <DashboardCard>[];
            final filtered =
                all.where((d) => _matchDivision(d, _query)).toList();

            final favorites = filtered
                .where((d) => _favoriteDivisions.contains(d.id))
                .toList();
            final others = filtered
                .where((d) => !_favoriteDivisions.contains(d.id))
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_copy_outlined,
                        size: 18, color: Color(0xFF7C8594)),
                    const SizedBox(width: 6),
                    Text(
                      '전체 사업부',
                      style: AppText.bodyStrong.copyWith(
                        fontSize: 15,
                        color: AppColors.headerNavy,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _query.trim().isEmpty
                          ? '${all.length}개'
                          : '${filtered.length}/${all.length}개',
                      style: AppText.caption.copyWith(
                        fontSize: 12,
                        color: const Color(0xFF7C8594),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SearchFilterRow(
                  value: _query,
                  onChanged: (v) {
                    setState(() {
                      _query = v;
                    });
                  },
                  onTapFilter: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사업부 필터는 준비 중입니다.')),
                    );
                  },
                  hintText: '사업부명 검색',
                ),
                const SizedBox(height: 16),
                if (favorites.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 18, color: Color(0xFFF4B63D)),
                      const SizedBox(width: 4),
                      Text(
                        '즐겨찾기',
                        style: AppText.bodyStrong.copyWith(
                          fontSize: 13,
                          color: AppColors.reportHeading,
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
                        '${favorites.length}개',
                        style: AppText.caption.copyWith(
                          color: AppColors.reportBody,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: favorites.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 104,
                    ),
                    itemBuilder: (context, i) {
                      final d = favorites[i];
                      return DivisionGridCard(
                        divisionId: d.id,
                        label: d.label,
                        projectCount: d.projects.length,
                        status: _statusOf(d.id, cards),
                        isFavorite: true,
                        onTap: () => _openDivision(d),
                        onToggleFavorite: () => _toggleFavorite(d.id),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
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
                      '${others.length}개',
                      style: AppText.caption.copyWith(
                        color: AppColors.reportBody,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: others.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 104,
                  ),
                  itemBuilder: (context, i) {
                    final d = others[i];
                    return DivisionGridCard(
                      divisionId: d.id,
                      label: d.label,
                      projectCount: d.projects.length,
                      status: _statusOf(d.id, cards),
                      isFavorite: false,
                      onTap: () => _openDivision(d),
                      onToggleFavorite: () => _toggleFavorite(d.id),
                    );
                  },
                ),
              ],
            );
          },
        ),
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
