import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_settings.dart';
import '../models/product_card.dart';
import '../services/api_client.dart';
import 'project_detail_screen.dart';
import 'product_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiClient _api = ApiClient();
  List<ProductCard> cards = [];
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
      final results = await Future.wait([
        _api.fetchDashboard(),
        _api.fetchProjects(),
      ]);
      final fetchedCards = results[0] as List<ProductCard>;
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
      case 'BLUE':
        return Colors.blue;
      case 'BLACK':
        return Colors.grey.shade800;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'RED':
        return '즉시 확인';
      case 'BLUE':
        return '진행 중';
      case 'BLACK':
        return '정상';
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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 88,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '사업부 진행현황',
              style: TextStyle(
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
          // ✨ 글자 크기 버튼 추가
          PopupMenuButton<double>(
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
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '새로고침',
            onPressed: () => _load(),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _buildError()
              : (cards.isEmpty && projects.isEmpty)
                  ? _buildEmpty()
                  : _buildContent(),
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
    final redCards = cards.where((c) => c.status == 'RED').toList();
    final blueCards = cards.where((c) => c.status == 'BLUE').toList();
    final blackCards = cards.where((c) => c.status == 'BLACK').toList();

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (projects.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text('🏢 부서별 보기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: projects.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final p = projects[idx];
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
          if (redCards.isNotEmpty)
            _buildStatusGroup('🔴 즉시 확인', redCards, 'RED'),
          if (blueCards.isNotEmpty)
            _buildStatusGroup('🔵 진행 중', blueCards, 'BLUE'),
          if (blackCards.isNotEmpty)
            _buildStatusGroup('⚫ 정상', blackCards, 'BLACK'),
        ],
      ),
    );
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
