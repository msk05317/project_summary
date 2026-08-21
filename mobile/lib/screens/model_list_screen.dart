import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
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
      final uri = Uri.parse('$kApiBaseUrl/projects/$projectKey');
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
    final poQty = (m['po_qty'] as num?)?.toInt() ?? 0;
    final shipped = (m['shipped_qty'] as num?)?.toInt() ?? 0;
    final progress = poQty > 0 ? ((shipped * 100) / poQty).round() : 0;
    final status = (m['status'] ?? '정상').toString();
    return GestureDetector(
      onTap: () async {
        Map<String, dynamic> modelData = m;
        try {
          final uri = Uri.parse('$kApiBaseUrl/projects/$projectKey/models');
          final res = await http.get(uri).timeout(const Duration(seconds: 8));
          if (res.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(res.bodyBytes));
            final groups = decoded['groups'] as Map<String, dynamic>? ?? const {};
            outer:
            for (final g in groups.values) {
              final list = (g['models'] as List? ?? const []);
              for (final x in list) {
                if (x is Map<String, dynamic> &&
                    (x['id'] ?? x['name']) == (m['id'] ?? m['name'])) {
                  modelData = x;
                  break outer;
                }
              }
            }
          }
        } catch (_) {}
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ModelDetailScreen(projectName: projectName, model: modelData),
          ),
        );
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

// ── 모델 상세 화면 (models.json 기반 KPI + 이슈)
class ModelDetailScreen extends StatelessWidget {
  final String projectName;
  final Map<String, dynamic> model;
  const ModelDetailScreen({super.key, required this.projectName, required this.model});

  int get _poQty => (model['po_qty'] as num?)?.toInt() ?? 0;
  int get _shipped => (model['shipped_qty'] as num?)?.toInt() ?? 0;
  int get _remaining => _poQty - _shipped;
  int get _shipProgress => _poQty > 0 ? ((_shipped * 100) / _poQty).round() : 0;
  String get _dueText => (model['due_text'] ?? '').toString();

  int get _delayDays {
    final mm = RegExp(r'(\d{1,2})월\s*(\d{1,2})일').firstMatch(_dueText);
    if (mm == null) return 0;
    final now = DateTime.now();
    var due = DateTime(now.year, int.parse(mm.group(1)!), int.parse(mm.group(2)!));
    if (due.isBefore(now)) due = DateTime(now.year + 1, due.month, due.day);
    final d = now.difference(due).inDays;
    return d > 0 ? d : 0;
  }

  List<String> get _issueLines => (model['issues'] ?? '')
      .toString()
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0F2C59);
    const red = Color(0xFFD32F2F);
    final delay = _delayDays;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${model['name'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '목록 > $projectName > ${model['group'] ?? ''} > ${model['name'] ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _kpi('잔여 수량', '$_remaining', Colors.black87),
            const SizedBox(width: 8),
            _kpi('목표 납기일', _dueText.isEmpty ? '-' : _dueText, Colors.black87),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('출하 진행률 $_shipProgress%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _shipProgress / 100,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation(navy),
                ),
              ),
              const SizedBox(height: 8),
              Text('PO $_poQty · 출하완료 $_shipped',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('이슈사항',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          if (_issueLines.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDeco(),
              child: const Text('등록된 이슈가 없습니다',
                  style: TextStyle(color: Color(0xFF6B7280))),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: red.withOpacity(0.4), width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _badge('이슈', filled: true, color: const Color(0xFFFFA000)),
                  if (delay > 0) ...[
                    const SizedBox(width: 6),
                    _badge('지연', filled: false, color: red),
                  ],
                ]),
                const SizedBox(height: 10),
                for (final line in _issueLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line,
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color valueColor) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: _cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: valueColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          ]),
        ),
      );

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      );

  Widget _badge(String txt, {required bool filled, required Color color}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          border: filled ? null : Border.all(color: color),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(txt,
            style: TextStyle(
                color: filled ? Colors.white : color,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

