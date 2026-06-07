import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    print('🟡 _load 시작');
    setState(() {
      loading = true;
      error = null;
    });
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

      setState(() {
        cards = fetchedCards;
        projects = fetchedProjects;
        loading = false;
      });
    } catch (e) {
      print('🔴 _load 오류: $e');
      setState(() {
        error = e.toString();
        loading = false;
      });
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

  // 카드 탭 시 적절한 상세 화면으로 이동
  void _navigateToDetail(ProductCard card) {
    if (card.projectKey != null && card.projectKey!.isNotEmpty) {
      // project_key 있으면 부서별 상세
      // 라벨은 projects에서 찾기 (없으면 product명 사용)
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
      // 매핑 실패한 경우 fallback
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('사업부 진행현황'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _buildError()
              : (cards.isEmpty && projects.isEmpty)
                  ? const Center(child: Text('데이터가 없습니다'))
                  : _buildContent(),
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
            ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    // status별 카드 그룹화
    final redCards = cards.where((c) => c.status == 'RED').toList();
    final blueCards = cards.where((c) => c.status == 'BLUE').toList();
    final blackCards = cards.where((c) => c.status == 'BLACK').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ========== 부서별 보기 (가로 스크롤) ==========
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

          // ========== 신호등 카드 그룹 ==========
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
              // 좌측 상태 원
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              // 본문
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
              // 우측 화살표
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}