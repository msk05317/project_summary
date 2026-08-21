import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../design/typography.dart';
import 'model_list_screen.dart';
import 'model_cost_list_screen.dart';

class ProjectOverviewScreen extends StatefulWidget {
  final String projectKey;
  final String projectName;
  const ProjectOverviewScreen({super.key, required this.projectKey, required this.projectName});

  @override
  State<ProjectOverviewScreen> createState() => _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends State<ProjectOverviewScreen> {
  late Future<Map<String, dynamic>> _modelsFuture;
  late Future<Map<String, dynamic>> _planFuture;
  late Future<List<Map<String, String>>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _modelsFuture = _fetchModels();
    _planFuture = _fetchWeeklyPlan();
    _summaryFuture = _fetchIssuesSummary();
  }

  Future<Map<String, dynamic>> _fetchModels() async {
    final res = await http
        .get(Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}/models/detail'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<Map<String, dynamic>> _fetchWeeklyPlan() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}/weekly-plan'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return {'has_plan': false};
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return {'has_plan': false};
    }
  }

  Future<List<Map<String, String>>> _fetchIssuesSummary() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}/issues/summary'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const [];
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      final items = (d['items'] as List? ?? const []);
      return items
          .whereType<Map<String, dynamic>>()
          .map((e) => {
                'model': (e['model'] ?? '').toString(),
                'summary': (e['summary'] ?? '').toString(),
              })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.projectName, style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _modelsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('로드 실패: ${snap.error}'));
          }
          final data = snap.data ?? {};
          final models = (data['models'] as List? ?? []).cast<Map<String, dynamic>>();
          if (models.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 모델 없음 안내 카드
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text(
                        '등록된 모델이 없습니다',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'admin v2에서 모델을 추가하면 여기서 확인할 수 있습니다.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 현황 텍스트 (있으면 표시)
                _buildStatusNote((data['status_note'] ?? '').toString()),
                // 주차별 계획 (있으면 표시)
                _buildWeeklyPlanSection(),
              ],
            );
          }

          final total = models.length;
          final avgProgress = total > 0
              ? (models.fold<int>(0, (s, m) {
                      final po = (m['po_qty'] as num?)?.toInt() ?? 0;
                      final sh = (m['shipped_qty'] as num?)?.toInt() ?? 0;
                      return s + (po > 0 ? ((sh * 100) / po).round() : 0);
                    }) / total).round()
              : 0;
          final delayed = models.where((m) => m['status'] == '지연').length;
          final watched = models.where((m) => m['status'] == '주의').length;

          final byGroup = <String, List<Map<String, dynamic>>>{'양산': [], '개발': []};
          for (final m in models) {
            final g = m['group'] == '개발' ? '개발' : '양산';
            byGroup[g]!.add(m);
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _modelsFuture = _fetchModels();
                _planFuture = _fetchWeeklyPlan();
                _summaryFuture = _fetchIssuesSummary();
              });
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 헤더 카드
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('전체 진행률', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 6),
                      Text('$avgProgress%',
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF0F2C59))),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: avgProgress / 100,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFF3F4F6),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F2C59)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── KPI 3열
                Row(children: [
                  _kpi('전체 모델', '$total개', const Color(0xFF0F2C59)),
                  const SizedBox(width: 8),
                  _kpi('지연', '$delayed개', const Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  _kpi('주의', '$watched개', const Color(0xFFD97706)),
                ]),
                const SizedBox(height: 12),
                // ── 주요 이슈 / 리스크
                _buildIssueSection(models),
                _buildStatusNote((data['status_note'] ?? '').toString()),
                // ── 주차별 계획 (엑셀 → PNG, 탭하면 확대)
                _buildWeeklyPlanSection(),
                // ── 상세로 이동
                const Padding(
                  padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
                  child: Text('상세로 이동',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
                ),
                ...['양산', '개발'].map((g) => _groupCard(g, byGroup[g]!)),
                _costCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ]),
      ),
    );
  }

  Widget _buildIssueSection(List<Map<String, dynamic>> models) {
    // issues 텍스트가 실제로 있는 모델만 추출
    final withIssues = models
        .where((m) => (m['issues'] ?? '').toString().trim().isNotEmpty)
        .toList();
    // 이슈 라인 총 개수 (모델별 여러 줄 가능)
    final totalLines = withIssues.fold<int>(
        0,
        (s, m) =>
            s +
            (m['issues'] ?? '')
                .toString()
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .length);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('주요 이슈 / 리스크',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$totalLines',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626))),
            ),
          ]),
          const SizedBox(height: 10),
          // ── AI 모델별 요약 (같은 모델은 한 묶음)
          FutureBuilder<List<Map<String, String>>>(
            future: _summaryFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                );
              }
              final items = snap.data ?? const [];
              // 같은 모델명끼리 합치기
              final groups = <String, List<String>>{};
              for (final it in items) {
                final mk = (it['model'] ?? '').trim();
                if (mk.isEmpty) continue;
                final ls = (it['summary'] ?? '')
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty)
                    .toList();
                groups.putIfAbsent(mk, () => []).addAll(ls);
              }
              if (groups.isEmpty) {
                return const Text('이슈가 없습니다',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in groups.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280))),
                          const SizedBox(height: 4),
                          for (final line in e.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Icon(Icons.circle,
                                        size: 5, color: Color(0xFFDC2626)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(line.trim(),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.45,
                                            color: Color(0xFF374151))),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildStatusNote(String note) {
    if (note.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('현황', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF374151))),
        ],
      ),
    );
  }

  Widget _buildWeeklyPlanSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _planFuture,
      builder: (context, snap) {
        final plan = snap.data ?? {};
        final hasPlan = plan['has_plan'] == true && (plan['url'] ?? '').toString().isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('주차별 계획',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              else if (!hasPlan)
                const Text('등록된 주차별 계획이 없습니다',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))
              else
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.black87,
                        pageBuilder: (_, __, ___) => _ZoomableImageScreen(
                          imageUrl: '$kApiBaseUrl${plan['url']}',
                          title: plan['file_name'] ?? '주차별 계획',
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '$kApiBaseUrl${plan['url']}',
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Text('이미지 로드 실패',
                          style: TextStyle(color: Color(0xFFDC2626))),
                    ),
                  ),
                ),
              if (hasPlan)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('탭하면 확대됩니다',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _groupCard(String group, List<Map<String, dynamic>> list) {
    final isMass = group == '양산';
    final delayed = list.where((m) => m['status'] == '지연').length;
    final watched = list.where((m) => m['status'] == '주의').length;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ModelListScreen(
            projectKey: widget.projectKey,
            projectName: widget.projectName,
            groupName: group,
            models: list,
          ),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isMass ? const Color(0xFFDBEAFE) : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(isMass ? '🏭' : '🔧', style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group, style: AppText.bodyStrong.copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text('${list.length}개 모델 · 지연 $delayed · 주의 $watched',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  Widget _costCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ModelCostListScreen(
            projectKey: widget.projectKey,
            projectName: widget.projectName,
          ),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 140),  // 키보드/네비게이션 바 대비
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('💰', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('판가 및 재료비', style: AppText.bodyStrong.copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              const Text('모델별 판가 · 재료비 · 재료비율',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }
}

// ── 전체화면 확대 뷰어 (핀치 줌)
class _ZoomableImageScreen extends StatelessWidget {
  final String imageUrl;
  final String title;
  const _ZoomableImageScreen({required this.imageUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.3,
              maxScale: 8.0,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('이미지 로드 실패',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('닫기 ✕',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
