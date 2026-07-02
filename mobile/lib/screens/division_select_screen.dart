import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/division.dart';
import '../services/divisions_service.dart';
import '../components/home/search_filter_row.dart';
import '../components/home/division_grid_card.dart';
import '../components/home/bottom_prompt_bar.dart';
import '../components/home/app_bottom_nav.dart';
import 'division_projects_screen.dart';
import 'calendar_screen.dart';

class DivisionSelectScreen extends StatefulWidget {
  const DivisionSelectScreen({super.key});

  @override
  State<DivisionSelectScreen> createState() => _DivisionSelectScreenState();
}

class _DivisionSelectScreenState extends State<DivisionSelectScreen> {
  late Future<List<Division>> _divisionsFuture;
  final Set<String> _favoriteDivisions = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _divisionsFuture = DivisionsService.fetchAll();
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favoriteDivisions.contains(id)) {
        _favoriteDivisions.remove(id);
      } else {
        _favoriteDivisions.add(id);
      }
    });
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
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<Division>>(
          future: _divisionsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data ?? const <Division>[];
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
                      mainAxisExtent: 92,
                    ),
                    itemBuilder: (context, i) {
                      final d = favorites[i];
                      return DivisionGridCard(
                        divisionId: d.id,
                        label: d.label,
                        projectCount: d.projects.length,
                        isActive: true,
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
                    mainAxisExtent: 92,
                  ),
                  itemBuilder: (context, i) {
                    final d = others[i];
                    return DivisionGridCard(
                      divisionId: d.id,
                      label: d.label,
                      projectCount: d.projects.length,
                      isActive: true,
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
