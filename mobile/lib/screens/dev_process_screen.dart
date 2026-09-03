import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../design/typography.dart';

class DevProcessScreen extends StatefulWidget {
  final String projectKey;
  final String modelId;
  final String modelName;
  const DevProcessScreen({
    super.key,
    required this.projectKey,
    required this.modelId,
    required this.modelName,
  });

  @override
  State<DevProcessScreen> createState() => _DevProcessScreenState();
}

class _DevProcessScreenState extends State<DevProcessScreen> {
  late Future<Map<String, dynamic>> _future;

  static const _groups = [
    ['발주', Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
    ['제작·검사', Color(0xFFFEF3C7), Color(0xFFB45309)],
    ['승인', Color(0xFFEDE9FE), Color(0xFF7C3AED)],
  ];

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final res = await http
        .get(Uri.parse(
            '$kApiBaseUrl/projects/${widget.projectKey}/models/${Uri.encodeComponent(widget.modelId)}/process'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.modelName, style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('로드 실패: ${snap.error}'));
          }
          final d = snap.data ?? {};
          final steps = (d['steps'] as List? ?? []).cast<Map<String, dynamic>>();
          final done = (d['done'] as num?)?.toInt() ?? 0;
          final total = (d['total'] as num?)?.toInt() ?? 13;
          final progress = (d['progress'] as num?)?.toInt() ?? 0;
          final devType = (d['dev_type'] ?? 'HVM').toString();
          final currentStage = (d['current_stage'] ?? '').toString();
          final currentExpected = (d['current_expected'] ?? '').toString();
          final issueLines = (d['issues'] ?? '')
              .toString()
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .toList();

          int num0 = 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 요약 카드
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
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: devType == 'RPM' ? const Color(0xFFE0F2FE) : const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(devType,
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: devType == 'RPM' ? const Color(0xFF0284C7) : const Color(0xFF7C3AED),
                            )),
                      ),
                      const Spacer(),
                      Text('$progress%',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0F2C59))),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF3F4F6),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F2C59)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentStage.isEmpty
                          ? '진행률 $done / $total 단계 · 일정 미등록'
                          : '진행률 $done / $total 단계 · 다음 단계: $currentStage'
                              '${currentExpected.isNotEmpty ? ' (예상 $currentExpected)' : ''}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              // 이슈사항 카드 (이슈 있을 때만 표시)
              if (issueLines.isNotEmpty) ...[
                const SizedBox(height: 12),
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
                      const Text('이슈사항',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 10),
                      for (final line in issueLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13)),
                              Expanded(
                                child: Text(line,
                                    style: const TextStyle(fontSize: 13, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // 단계 그룹
              ..._groups.map((g) {
                final list = steps.where((s) => s['group'] == g[0]).toList();
                if (list.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: g[1] as Color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(children: [
                          Text(g[0] as String,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: g[2] as Color)),
                          const Spacer(),
                          Text('${list.length}단계',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: g[2] as Color)),
                        ]),
                      ),
                      ...list.map((s) {
                        num0++;
                        final stepStatus = (s['status'] ?? '').toString().trim();
                        final isDone = (s['actual'] ?? '').toString().trim().isNotEmpty ||
                            stepStatus == '완료';
                        // 계획일·실적일·상태가 하나도 없으면 '진행중'으로 표시하지 않는다
                        final hasInput = (s['expected'] ?? '').toString().trim().isNotEmpty ||
                            (s['actual'] ?? '').toString().trim().isNotEmpty ||
                            stepStatus.isNotEmpty;
                        final isCurrent = !isDone &&
                            hasInput &&
                            (stepStatus == '진행중' ||
                                (currentStage.isNotEmpty && s['name'] == currentStage));
                        final expected = (s['expected'] ?? '').toString();
                        final actual = (s['actual'] ?? '').toString();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0xFFFFFBEB) : Colors.white,
                            border: const Border(top: BorderSide(color: Color(0xFFF3F4F6))),
                          ),
                          child: Row(children: [
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDone
                                    ? const Color(0xFFD1FAE5)
                                    : (isCurrent ? const Color(0xFFDBEAFE) : const Color(0xFFF3F4F6)),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isDone ? Icons.check : (isCurrent ? Icons.play_arrow : Icons.circle),
                                size: 14,
                                color: isDone
                                    ? const Color(0xFF059669)
                                    : (isCurrent ? const Color(0xFF1D4ED8) : const Color(0xFF9CA3AF)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${num0.toString().padLeft(2, '0')} ${s['name']}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '계획 ${expected.isNotEmpty ? expected : '-'} · 실제 ${actual.isNotEmpty ? actual : '미완료'}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                                ),
                              ]),
                            ),
                            Text(
                              isDone ? '완료' : (isCurrent ? '진행중' : '대기'),
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: isDone
                                    ? const Color(0xFF059669)
                                    : (isCurrent ? const Color(0xFF1D4ED8) : const Color(0xFF9CA3AF)),
                              ),
                            ),
                          ]),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
