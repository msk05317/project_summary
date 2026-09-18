import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../design/typography.dart';
import 'model_cost_detail_screen.dart';
import '../utils/material_ratio.dart';

class ModelCostListScreen extends StatefulWidget {
  final String projectKey;
  final String projectName;
  const ModelCostListScreen({super.key, required this.projectKey, required this.projectName});

  @override
  State<ModelCostListScreen> createState() => _ModelCostListScreenState();
}

class _ModelCostListScreenState extends State<ModelCostListScreen> {
  String _tab = '양산';
  RatioBand _band = RatioBand.all;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await http
        .get(Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}/models'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return (data['models'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('${widget.projectName} 판가 · 재료비',
            style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('로드 실패: ${snap.error}'));
          }
          final all = snap.data ?? [];
          if (all.isEmpty) {
            return const Center(child: Text('등록된 모델이 없습니다'));
          }
          final inTab = all.where((m) => (m['group'] ?? '양산') == _tab).toList();
          final filtered = _band == RatioBand.all
              ? inTab
              : inTab.where((m) => bandOf(ratioOf(m)) == _band).toList();
          return Column(
            children: [
              // ── 양산/개발 탭 (필터 역할)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: ['양산', '개발'].map((g) {
                    final sel = _tab == g;
                    final cnt = all.where((m) => (m['group'] ?? '양산') == g).length;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = g),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFF0F2C59) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text('$g $cnt개',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : const Color(0xFF6B7280),
                              )),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // ── 재료비율 구간 필터
              _bandChips(inTab),
              // ── 모델 리스트
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(_band == RatioBand.all
                            ? '$_tab 모델이 없습니다'
                            : '${kRatioBandLabel[_band]} 모델이 없습니다'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final m = filtered[i];
                          final ratio = ratioOf(m);
                          final group = m['group'] ?? '양산';
                          return GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ModelCostDetailScreen(model: m),
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
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(m['name'] ?? m['id'] ?? '',
                                            style: AppText.bodyStrong.copyWith(fontSize: 15)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: group == '양산'
                                                ? const Color(0xFFDBEAFE)
                                                : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(group,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: group == '양산'
                                                    ? const Color(0xFF1D4ED8)
                                                    : const Color(0xFFB45309),
                                              )),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        ratio != null ? '${ratio.toStringAsFixed(1)}%' : '-',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: ratioColor(ratio),
                                        ),
                                      ),
                                      const Text('재료비율',
                                          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 재료비율 구간 칩. 0 건인 구간은 자리만 차지하니 '판가 미등록' 은 있을 때만.
  Widget _bandChips(List<Map<String, dynamic>> inTab) {
    final counts = <RatioBand, int>{
      for (final b in RatioBand.values)
        b: b == RatioBand.all
            ? inTab.length
            : inTab.where((m) => bandOf(ratioOf(m)) == b).length,
    };
    Widget chip(RatioBand b) {
      final on = _band == b;
      final tint = kRatioBandColor[b]!;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _band = b),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? tint : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(99),
              border:
                  Border.all(color: on ? tint : const Color(0xFFE5E7EB)),
            ),
            child: Text('${kRatioBandLabel[b]} ${counts[b]}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : const Color(0xFF4B5563),
                )),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip(RatioBand.all),
          chip(RatioBand.high),
          chip(RatioBand.mid),
          chip(RatioBand.low),
          if ((counts[RatioBand.none] ?? 0) > 0) chip(RatioBand.none),
        ]),
      ),
    );
  }
}
