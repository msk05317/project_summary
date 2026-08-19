import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../design/typography.dart';
import 'dev_process_screen.dart';

// 개발 승인 프로세스 13단계 (표시용)
const List<String> _devSteps = [
  'FA PO', '자재 발주', '입고', '가공(조립)', 'LA 입고',
  'LAIR 제출', 'LAIR 승인', 'Source Inspection',
  'FAIR 제출', 'FAIR 승인', 'LAP TEST', 'CDR', '최종 승인',
];

class ModelListScreen extends StatelessWidget {
  final String projectKey;
  final String projectName;
  final String groupName;
  final List<Map<String, dynamic>> models;

  const ModelListScreen({
    super.key,
    required this.projectKey,
    required this.projectName,
    required this.groupName,
    required this.models,
  });

  // ── 보고서 존재 여부 확인
  Future<bool> _checkReportExists(String projectKey) async {
    try {
      final uri = Uri.parse('\$kApiBaseUrl/projects/\$projectKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded.isNotEmpty) return true;
      if (decoded is List && decoded.isNotEmpty) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── 개발 모델 상태 색상/텍스트 (예상일 기반)
  Color _devStatusColor(Map<String, dynamic> m) {
    final expected = (m['current_expected'] ?? '').toString();
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    
    if (progress >= 100) return const Color(0xFF059669); // 완료
    
    if (expected.isEmpty) return const Color(0xFF9CA3AF); // 예상일 없음 → 회색
    
    try {
      final expectedDate = DateTime.parse(expected);
      final now = DateTime.now();
      final daysLeft = expectedDate.difference(now).inDays;
      
      if (daysLeft < 0) return const Color(0xFFDC2626); // 지연 → 빨강
      if (daysLeft <= 7) return const Color(0xFFD97706); // 곧 다가옴 → 주황
      return const Color(0xFF059669); // 진행 중 → 초록
    } catch (_) {
      return const Color(0xFF9CA3AF); // 파싱 실패 → 회색
    }
  }

  String _devStatusText(Map<String, dynamic> m) {
    final expected = (m['current_expected'] ?? '').toString();
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final stage = (m['current_stage'] ?? '').toString();
    
    if (progress >= 100) return '완료';
    if (progress == 0) return '대기중';
    
    if (expected.isEmpty) return '진행중 · $stage';
    
    try {
      final expectedDate = DateTime.parse(expected);
      final now = DateTime.now();
      final daysLeft = expectedDate.difference(now).inDays;
      
      if (daysLeft < 0) return '지연중 · $stage';
      if (daysLeft <= 7) return '임박 · $stage';
      return '진행중 · $stage';
    } catch (_) {
      return '진행중 · $stage';
    }
  }

  Color _statusColor(String s) {
    if (s == '지연') return const Color(0xFFDC2626);
    if (s == '주의') return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }

  @override
  Widget build(BuildContext context) {
    final isDev = groupName == '개발';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('$projectName · $groupName', style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: models.isEmpty
          ? const Center(child: Text('등록된 모델이 없습니다'))
          : Column(
              children: [
                if (isDev)
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('개발 승인 프로세스',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
                        const SizedBox(height: 8),
                        Wrap(
                      spacing: 4,
                      runSpacing: 6,
                      children: [
                        for (int i = 0; i < _devSteps.length; i++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _devSteps[i],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                              if (i < _devSteps.length - 1)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(Icons.arrow_forward_ios,
                                      size: 8, color: Colors.grey[400]),
                                ),
                            ],
                          ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (isDev) const Divider(height: 1, color: Color(0xFFE5E7EB)),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: models.length,
                    itemBuilder: (context, i) =>
                        isDev ? _devCard(context, models[i]) : _massCard(context, models[i]),
                  ),
                ),
              ],
            ),
    );
  }

  // ── 양산 모델 카드 (보고서 존재 여부 확인 후 이동)
  Widget _massCard(BuildContext context, Map<String, dynamic> m) {
    final progress = (m['progress'] as num?)?.toInt() ?? 0;
    final status = (m['status'] ?? '정상').toString();
    return GestureDetector(
      onTap: () async {
        final hasReport = await _checkReportExists(projectKey);
        if (!context.mounted) return;
        if (hasReport) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _NoReportScreen(projectName: projectName)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _NoReportScreen(projectName: projectName)),
          );
        }
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
          Container(width: 4, height: 44,
              decoration: BoxDecoration(color: _statusColor(status), borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['name']?.toString() ?? '', style: AppText.bodyStrong.copyWith(fontSize: 15)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.circle, size: 8, color: _statusColor(status)),
                const SizedBox(width: 4),
                Text('출하계획대비', style: TextStyle(fontSize: 12, color: _statusColor(status))),
              ]),
            ]),
          ),
          Text('$progress%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2C59))),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  // ── 개발 모델 카드 (HVM/RPM 칩 + 현황 + 완료예정일 + 자동 진행률)
  Widget _devCard(BuildContext context, Map<String, dynamic> m) {
    final devType = (m['dev_type'] ?? 'HVM').toString().toUpperCase();
    final isRpm = devType == 'RPM';
    final progress = (m['progress'] as num?)?.toInt() ?? 0;

    final expected = (m['current_expected'] ?? '').toString();
    final doneSteps = (m['done_steps'] as num?)?.toInt() ?? 0;
    final totalSteps = (m['total_steps'] as num?)?.toInt() ?? 13;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DevProcessScreen(
            projectKey: projectKey,
            modelId: m['id']?.toString() ?? '',
            modelName: m['name']?.toString() ?? '',
          ),
        ),
      ),
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
            width: 4, height: 52,
            decoration: BoxDecoration(
              color: _devStatusColor(m),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(m['name']?.toString() ?? '',
                      style: AppText.bodyStrong.copyWith(fontSize: 15),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRpm ? const Color(0xFFE0F2FE) : const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(devType,
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800,
                        color: isRpm ? const Color(0xFF0284C7) : const Color(0xFF7C3AED),
                      )),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                _devStatusText(m),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
              ),
              if (expected.isNotEmpty)
                Text('완료예정 · $expected',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$progress%',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F2C59))),
            Text('$doneSteps/$totalSteps단계',
                style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }
}

// ── 보고서 없음 안내 화면
class _NoReportScreen extends StatelessWidget {
  final String projectName;
  const _NoReportScreen({required this.projectName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(projectName, style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '아직 등록된 보고서가 없습니다',
                style: AppText.bodyStrong.copyWith(fontSize: 18, color: const Color(0xFF374151)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '주간 보고서가 등록되면 여기서 확인할 수 있습니다.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('뒤로 가기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F2C59),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
