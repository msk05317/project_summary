import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../models/product_card.dart';
import '../services/api_client.dart';
import 'project_detail_screen.dart';
import 'product_detail_screen.dart';
import 'division_select_screen.dart';
import '../widgets/grouped_card_tile.dart';

class DashboardScreen extends StatefulWidget {
  final String? divisionKey;
  final String? divisionLabel;
  const DashboardScreen({super.key, this.divisionKey, this.divisionLabel});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiClient _api = ApiClient();
  List<ProductCard> cards = [];
  List<GroupedCard> groupedCards = [];
  List<Map<String, dynamic>> projects = [];
  bool loading = true;
  String? error;

  // ✨ Level 2 상태
  Timer? _autoRefreshTimer;
  DateTime? _lastRefreshAt;
  String _lastDataFingerprint = '';
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      _load(silent: true);
    });
  }

  String _makeFingerprint(List<ProductCard> list) {
    final parts = list.map((c) {
      return [
        c.projectKey ?? '',
        c.product,
        c.status,
        c.headline,
        c.reportDate,
        c.docId,
      ].join('|');
    }).toList()
      ..sort();
    return parts.join('||');
  }

  String? _latestReportDate() {
    final dates = cards
        .map((c) => c.reportDate)
        .where((d) => d.isNotEmpty)
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  String _formatReportDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final weekday = weekdays[dt.weekday - 1];
      return '보고 기준: ${dt.month}/${dt.day} ($weekday)';
    } catch (_) {
      return '보고 기준: $iso';
    }
  }

  String _formatRefreshTime(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[dt.weekday - 1];
    final isAm = dt.hour < 12;
    final ampm = isAm ? '오전' : '오후';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '새로고침: ${dt.month}/${dt.day} ($weekday) $ampm $hour12:$minute';
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      print('🟡 _load 시작');
      setState(() {
        loading = true;
        error = null;
      });
    } else {
      print('🟡 _load (silent) 자동 새로고침');
    }

    try {
      final divKey = widget.divisionKey;
      final results = await Future.wait([
        _api.fetchDashboardData(),
        (divKey != null && divKey.isNotEmpty)
            ? _api.fetchDivisionProjects(divKey)
            : _api.fetchProjects(),
      ]);
      final fetchedData = results[0] as DashboardData;
      final fetchedCards = fetchedData.cards;
      final fetchedGrouped = fetchedData.groupedCards;
      final fetchedProjects = results[1] as List<Map<String, dynamic>>;

      print('🟢 카드 받음: ${fetchedCards.length}개');
      print('🟢 프로젝트 받음: ${fetchedProjects.length}개');
      if (fetchedCards.isNotEmpty) {
        print('🟢 첫 카드: ${fetchedCards.first.product} / ${fetchedCards.first.projectKey}');
      }

      if (!mounted) return;

      final newFingerprint = _makeFingerprint(fetchedCards);
      final hasNewData = _loadedOnce &&
          _lastDataFingerprint.isNotEmpty &&
          _lastDataFingerprint != newFingerprint;

      setState(() {
        cards = fetchedCards;
        groupedCards = fetchedGrouped;
        projects = fetchedProjects;
        loading = false;
        error = null;
        _lastRefreshAt = DateTime.now();
        _lastDataFingerprint = newFingerprint;
        _loadedOnce = true;
      });

      if (hasNewData && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('새 데이터가 업데이트되었습니다.'),
                ],
              ),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.blueAccent,
            ),
          );
      }
    } catch (e) {
      print('🔴 _load 오류: $e');
      if (!mounted) return;

      if (!silent) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RED':
        return Colors.red;
      case 'ORANGE':
        return Colors.orange.shade700;
      case 'BLUE':
        return Colors.blue;
      case 'BLACK':
        return Colors.grey.shade800;
      case 'GRAY':
        return Colors.grey.shade400;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'RED':
        return '즉시 확인';
      case 'ORANGE':
        return '임박';
      case 'BLUE':
        return '진행 중';
      case 'BLACK':
        return '정상';
      case 'GRAY':
        return '내용 없음';
      default:
        return '';
    }
  }

  void _navigateToDetail(ProductCard card) {
    if (card.projectKey != null && card.projectKey!.isNotEmpty) {
      final matched = projects.firstWhere(
        (p) => p['key'] == card.projectKey,
        orElse: () => <String, dynamic>{},
      );
      final label = (matched['label']?.toString().isNotEmpty ?? false)
          ? matched['label'].toString()
          : card.product;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            projectKey: card.projectKey!,
            projectLabel: label,
            status: card.status,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            docId: card.docId,
            productName: card.product,
          ),
        ),
      );
    }
  }

  void _navigateToProject(Map<String, dynamic> project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          projectKey: project['key']?.toString() ?? '',
          projectLabel: project['label']?.toString() ?? '',
          status: project['status']?.toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestReport = _latestReportDate();

    return PopScope(
      canPop: widget.divisionKey == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (widget.divisionKey != null) {
          await AppSettings.instance.setLastDivisionKey(null);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const DivisionSelectScreen(),
            ),
          );
        }
      },
      child: Scaffold(
      appBar: AppBar(
        toolbarHeight: 88,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 2,
        leading: widget.divisionKey != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '사업부 선택',
                onPressed: () async {
                  await AppSettings.instance.setLastDivisionKey(null);
                  if (!mounted) return;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const DivisionSelectScreen(),
                    ),
                  );
                },
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.divisionLabel ?? '사업부 진행현황',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            if (latestReport != null)
              Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _formatReportDate(latestReport),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            if (_lastRefreshAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(
                  children: [
                    const Icon(Icons.refresh,
                        size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      _formatRefreshTime(_lastRefreshAt!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          // ✨ 글자 크기 버튼 (AppSettings 변경 시 자동 rebuild)
          AnimatedBuilder(
            animation: AppSettings.instance,
            builder: (context, _) {
              return PopupMenuButton<double>(
                tooltip: '글자 크기',
                icon: const Icon(Icons.text_fields, color: Colors.white),
                initialValue: AppSettings.instance.fontScale,
                onSelected: (value) async {
                  await AppSettings.instance.setFontScale(value);
                  if (!mounted) return;

                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                            '글자 크기: ${AppSettings.instance.labelFor(value)}'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 0.9, child: Text('작게')),
                  PopupMenuItem(value: 1.0, child: Text('기본')),
                  PopupMenuItem(value: 1.15, child: Text('크게')),
                  PopupMenuItem(value: 1.3, child: Text('아주 크게')),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '새로고침',
            onPressed: () => _load(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? _buildError()
                : (cards.isEmpty && projects.isEmpty)
                    ? _buildEmpty()
                    : _buildContent(),
      ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('데이터가 없습니다',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('당겨서 새로고침',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text('오류: $error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => _load(), child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // 사업부 필터: widget.divisionKey 가 있으면 해당 사업부 카드만
    final divKey = widget.divisionKey;

    final filteredGrouped = (divKey == null || divKey.isEmpty)
        ? groupedCards
        : groupedCards.where((g) => g.divisionId == divKey).toList();
    final filteredCards = (divKey == null || divKey.isEmpty)
        ? cards
        : cards.where((c) => c.divisionId == divKey).toList();
    final filteredProjects = (divKey == null || divKey.isEmpty)
        ? projects
        : projects.where((p) => (p['division_id']?.toString() ?? '') == divKey).toList();

    // GroupedCard 기준으로 분류 (백엔드가 grouped 응답을 주면 우선 사용)
    final useGrouped = groupedCards.isNotEmpty;
    final redGroups = filteredGrouped.where((g) => g.status == 'RED').toList();
    final orangeGroups = filteredGrouped.where((g) => g.status == 'ORANGE').toList();
    final blueGroups = filteredGrouped.where((g) => g.status == 'BLUE').toList();
    final blackGroups = filteredGrouped.where((g) => g.status == 'BLACK').toList();

    // flat 폴백용
    final redCards = filteredCards.where((c) => c.status == 'RED').toList();
    final orangeCards = filteredCards.where((c) => c.status == 'ORANGE').toList();
    final blueCards = filteredCards.where((c) => c.status == 'BLUE').toList();
    final blackCards = filteredCards.where((c) => c.status == 'BLACK').toList();

    // 내용 없는 프로젝트 (회색 칩에서 추출)
    final grayProjects = filteredProjects.where((p) =>
        (p['has_content'] == false) || (p['status']?.toString() == 'GRAY')).toList();

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          12, 12, 12,
          12,
        ),
        children: [
          if (filteredProjects.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text('🏢 부서별 보기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filteredProjects.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final p = filteredProjects[idx];
                  final status = p['status']?.toString() ?? 'BLACK';
                  final color = _statusColor(status);
                  return InkWell(
                    onTap: () => _navigateToProject(p),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration:
                                BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            p['label']?.toString() ?? '',
                            style: TextStyle(
                                color: color, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (useGrouped) ...[
            if (redGroups.isEmpty && orangeGroups.isEmpty && blueGroups.isEmpty && blackGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        '${widget.divisionLabel ?? '해당 사업부'}에\n등록된 보고가 없습니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (redGroups.isNotEmpty || orangeGroups.isNotEmpty || blueGroups.isNotEmpty || blackGroups.isNotEmpty)
              _buildCeoKpiBar(redGroups, orangeGroups, blueGroups, blackGroups),
              _buildGroupedStatusSection('🔴 즉시 확인', redGroups),
            if (orangeGroups.isNotEmpty)
              _buildGroupedStatusSection('🟠 임박', orangeGroups),
            if (blueGroups.isNotEmpty)
              _buildGroupedStatusSection('🔵 진행 중', blueGroups),
            if (blackGroups.isNotEmpty)
              _buildGroupedStatusSection('⚫ 정상', blackGroups),
          ] else ...[
            if (redCards.isNotEmpty)
              _buildStatusGroup('🔴 즉시 확인', redCards, 'RED'),
            if (orangeCards.isNotEmpty)
              _buildStatusGroup('🟠 임박', orangeCards, 'ORANGE'),
            if (blueCards.isNotEmpty)
              _buildStatusGroup('🔵 진행 중', blueCards, 'BLUE'),
            if (blackCards.isNotEmpty)
              _buildStatusGroup('⚫ 정상', blackCards, 'BLACK'),
          ],
          // ⚪ 내용 없음 — 부서 진입 시에만 표시
          if (grayProjects.isNotEmpty && (widget.divisionKey != null && widget.divisionKey!.isNotEmpty)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text('⚪ 내용 없음 (${grayProjects.length}건)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            ...grayProjects.map((p) => Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              color: Colors.grey.shade50,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
              child: ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  p['label']?.toString() ?? '',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                ),
                subtitle: Text(
                  '아직 입력된 내용이 없습니다',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${p['label']}: 아직 입력된 내용이 없습니다'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            )),
          ],
        ],
      ),
    );
  }

  // ===== 사장님용 KPI 한 줄 =====
  int _countByStatus(List<GroupedCard> cards, String status) {
    return cards.where((c) => c.status == status).length;
  }

  Widget _buildCeoKpiBar(
    List<GroupedCard> red,
    List<GroupedCard> orange,
    List<GroupedCard> blue,
    List<GroupedCard> black,
  ) {
    final all = [...red, ...orange, ...blue, ...black];
    final delayed = _countByStatus(all, 'RED');
    final imminent = _countByStatus(all, 'ORANGE');
    final normal = _countByStatus(all, 'BLUE') + _countByStatus(all, 'BLACK');

    Widget chip(Color dot, Color text, String label, int n) {
      return Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '$label $n',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          chip(const Color(0xFFE53935), const Color(0xFFB91C1C), '지연', delayed),
          chip(const Color(0xFFEF6C00), const Color(0xFFB45309), '임박', imminent),
          chip(const Color(0xFF10B981), const Color(0xFF374151), '정상', normal),
        ],
      ),
    );
  }

  Widget _buildGroupedStatusSection(String title, List<GroupedCard> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('$title (${list.length}건)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
        ...list.map((g) => GroupedCardTile(
              group: g,
              onGroupTap: _onGroupTap,
              onIssueTap: _onIssueTap,
              compact: true,
            )),
        const SizedBox(height: 8),
      ],
    );
  }

  void _onGroupTap(GroupedCard g) {
    if (g.projectId != null && g.projectId!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            projectKey: g.projectId!,
            projectLabel: g.projectLabel ?? g.model,
          ),
        ),
      );
    } else if (g.issues.isNotEmpty) {
      _onIssueTap(g, g.issues.first);
    }
  }

  void _onIssueTap(GroupedCard g, GroupedIssue it) {
    final card = ProductCard(
      docId: it.docId,
      product: g.model,
      status: it.status,
      headline: it.headline,
      reportDate: g.reportDate,
      reportFamily: g.reportFamily,
      projectKey: g.projectId,
    );
    _navigateToDetail(card);
  }

  Widget _buildStatusGroup(String title, List<ProductCard> list, String status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('$title (${list.length}건)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
        ...list.map((c) => _buildCard(c)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCard(ProductCard card) {
    final color = _statusColor(card.status);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: () => _navigateToDetail(card),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.product,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (card.reportFamily.isNotEmpty &&
                            card.reportFamily != 'default')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(card.reportFamily,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.black54)),
                          ),
                      ],
                    ),
                    if (card.headline.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          card.headline,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
