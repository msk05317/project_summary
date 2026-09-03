import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../design/typography.dart';
import 'dev_process_screen.dart';

// 개발 승인 프로세스 13단계 (표시용)
const List<String> _devProcessStepsDefault = [
  'FA PO', '자재 발주', '입고', '가공(조립)', 'LA 입고',
  'LAIR 제출', 'LAIR 승인', 'Source Inspection',
  'FAIR 제출', 'FAIR 승인', 'LAP TEST', 'CDR', '최종 승인',
];

const Map<String, List<String>> _devProcessStepsByProject = {
  // 프레임: 12단계 (Machining 기반 — CB/BV 없음)
  'frame': [
    'FA PO', '자재 발주', '자재 입고', '가공(조립)', 'LA 입고',
    'LAIR 작성', 'Source Inspection', 'LAIR 승인',
    'FAIR 작성', 'PRR 승인', 'FAIR 승인', '최종 승인',
  ],
  // 메이저모듈: 12단계 (CB/BV1/BV2 기반 — LA 입고/LAP TEST 없음)
  'major_module': [
    'FA PO', '자재 발주', '자재 입고', 'CB', 'BV1', 'BV2',
    'Source Inspection', 'FAIR 작성', 'FAIR 승인',
    'PRR 작성', 'PRR 승인', '최종 승인',
  ],
  // 파워박스: EMA 기준 14단계 (13번 = CDR (PRR))
  'powerbox': [
    'FA PO', '자재 발주', '자재 입고', 'CB', 'BV1', 'BV2', 'LA 입고',
    'LAIR 작성', 'LAIR 승인', 'Source Inspection',
    'FAIR 작성', 'FAIR 승인', 'CDR (PRR)', '최종 승인',
  ],
};

List<String> _devProcessStepsFor(String projectKey) =>
    _devProcessStepsByProject[projectKey] ?? _devProcessStepsDefault;

/// 개발 모델에 실제 공정 데이터가 입력되어 있는지 판정.
/// 13단계 틀은 자동 생성되므로 단계 수만으로는 판단할 수 없고,
/// 계획일(expected)/실적일(actual)/상태(status) 중 하나라도 채워져야 '데이터 있음'.
bool devHasProcessData(Map<String, dynamic> m) {
  final proc = (m['process'] as List?) ?? const [];
  for (final s in proc) {
    if (s is Map) {
      for (final k in const ['expected', 'actual', 'status']) {
        if ((s[k]?.toString().trim() ?? '').isNotEmpty) return true;
      }
    }
  }
  return ((m['done_steps'] as num?)?.toInt() ?? 0) > 0;
}

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
  // 현재 양산 카드는 보고서 확인 없이 상세로 바로 이동한다.
  // 보고서 게이트를 다시 켤 때 쓰려고 남겨둔 코드.
  // ignore: unused_element
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
                        for (int i = 0; i < _devProcessStepsFor(projectKey).length; i++)
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
                                  _devProcessStepsFor(projectKey)[i],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                              if (i < _devProcessStepsFor(projectKey).length - 1)
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
    // 계획(PO 수량)이 등록된 모델만 진행률 집계 대상. 미등록이면 '-' (0%와 구분)
    final hasPlanData = poQty > 0;
    final progress = hasPlanData ? ((shipped * 100) / poQty).round() : null;
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
                Text(hasPlanData ? '출하계획대비' : '계획 미등록',
                    style: TextStyle(
                        fontSize: 12,
                        color: hasPlanData ? _statusColor(status) : const Color(0xFF9CA3AF))),
              ]),
            ]),
          ),
          Text(progress == null ? '-' : '$progress%',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: progress == null ? const Color(0xFF9CA3AF) : const Color(0xFF0F2C59))),
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
    final expected = (m['current_expected'] ?? '').toString();
    final doneSteps = (m['done_steps'] as num?)?.toInt() ?? 0;
    final totalSteps = (m['total_steps'] as num?)?.toInt() ??
        ((m['process'] as List?)?.length ?? 0);
    // 공정 단계 틀만 있고 계획일/실적일/상태가 전부 비어 있으면 '데이터 없음' → '-' (집계 제외)
    final hasProcData = devHasProcessData(m);
    final progress = hasProcData ? ((m['progress'] as num?)?.toInt() ?? 0) : null;

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
                hasProcData ? _devStatusText(m) : '공정 데이터 없음',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
              ),
              if (expected.isNotEmpty)
                Text('완료예정 · $expected',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(progress == null ? '-' : '$progress%',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: progress == null ? const Color(0xFF9CA3AF) : const Color(0xFF0F2C59))),
            Text(hasProcData ? '$doneSteps/$totalSteps단계' : '공정 미입력',
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
// _checkReportExists 와 짝. 보고서 게이트를 다시 켤 때 사용.
// ignore: unused_element
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
class ModelDetailScreen extends StatefulWidget {
  final String projectName;
  final Map<String, dynamic> model;
  const ModelDetailScreen({super.key, required this.projectName, required this.model});

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  Map<String, dynamic> get model => widget.model;
  String get projectName => widget.projectName;
  String _selMonth = '';
  // 관리자 엑셀에서 빨간 박스로 표시한 '기준 주차'
  List<String> _markedWeeks = const [];

  @override
  void initState() {
    super.initState();
    _loadMarkedWeeks();
  }

  Future<void> _loadMarkedWeeks() async {
    final key = (model['project_key'] ?? model['project_id'] ?? '').toString();
    if (key.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/projects/$key/weekly-plan'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      final mw = (d is Map) ? d['marked_weeks'] : null;
      if (mw is List && mounted) {
        setState(() => _markedWeeks = mw.map((e) => e.toString()).toList());
      }
    } catch (_) {}
  }

  int get _poQty => (model['po_qty'] as num?)?.toInt() ?? 0;
  int get _shipped => (model['shipped_qty'] as num?)?.toInt() ?? 0;

  // ── 주차별 계획에서 '지금 보고 있는 월'을 해석 ──
  Map<String, dynamic> get _weeklyPlanMap {
    final wp = model['weekly_plan'];
    return wp is Map ? wp.map((k, v) => MapEntry(k.toString(), v)) : {};
  }

  List<String> get _planMonths {
    final ms = _weeklyPlanMap.keys.toList()..sort();
    return ms;
  }

  String get _resolvedMonth {
    final wp = _weeklyPlanMap;
    if (wp.isEmpty) return '';
    if (_selMonth.isNotEmpty && wp.containsKey(_selMonth)) return _selMonth;
    final now = DateTime.now();
    final cur = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (wp.containsKey(cur)) return cur;
    return _planMonths.last;
  }

  /// 선택한 월의 (계획, 실적). 주차 데이터가 없으면 null → PO 기준으로 폴백.
  ({int plan, int actual})? get _monthTotals {
    final month = _resolvedMonth;
    if (month.isEmpty) return null;
    final weeks = _weeklyPlanMap[month];
    if (weeks is! Map) return null;
    var p = 0, a = 0;
    for (final v in weeks.values) {
      if (v is Map) {
        p += (v['plan'] as num?)?.toInt() ?? 0;
        a += (v['actual'] as num?)?.toInt() ?? 0;
      }
    }
    return (plan: p, actual: a);
  }

  // 상단 KPI는 선택한 월 기준. 주차 데이터가 없는 모델만 PO 총계로 표시한다.
  bool get _byMonth => _monthTotals != null;
  int get _basePlan => _monthTotals?.plan ?? _poQty;
  int get _baseActual => _monthTotals?.actual ?? _shipped;
  int get _remaining => _basePlan - _baseActual;

  /// 계획보다 더 내보냈으면 '잔여'가 아니라 '초과'다.
  /// (-1 로 찍히면 마치 출하를 못 한 것처럼 읽힌다)
  bool get _isOver => _remaining < 0;
  String get _remainLabel =>
      '${_byMonth ? _monthShort : ''}${_isOver ? '초과 출하' : '잔여 수량'}';
  String get _remainValue => _isOver ? '+${-_remaining}' : '$_remaining';
  int get _shipProgress =>
      _basePlan > 0 ? ((_baseActual * 100) / _basePlan).round() : 0;
  String get _monthShort {
    final m = _resolvedMonth;
    if (m.isEmpty) return '';
    final parts = m.split('-');
    return parts.length == 2 ? '${int.tryParse(parts[1]) ?? ''}월 ' : '';
  }
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

  String get _note => (model['note'] ?? '').toString().trim();

  List<String> get _issueLines => (model['issues'] ?? '')
      .toString()
      .split('\n')
      .where((s) => s.trim().isNotEmpty)
      .toList();

  // ── 주차별 계획/실적 표 (반도체사업부 양산 모델만) ──
  bool get _isSemiconductor {
    final p = (model['project_key'] ?? model['project_id'] ?? '').toString();
    // 반도체사업부 프로젝트 키 목록
    const semi = ['chamber', 'enclosure', 'cup', 'hrva_plate', 'casting_enclosure',
                  'plating_cell', 'tolon', 'eos_chamber', 'faraday_4t',
                  'powerbox', 'major_module', 'frame'];
    if (semi.contains(p)) return true;
    // project_key가 없으면 weekly_plan 데이터 유무로 판단 (반도체 양산만 주차계획 사용)
    return model['weekly_plan'] is Map && (model['weekly_plan'] as Map).isNotEmpty;
  }

  // ── 주차별 계획/실적 표 (반도체사업부 양산, 모든 월 세로 나열) ──
  String _monthLabel(String m) {
    final p = m.split('-');
    return p.length == 2 ? '${int.tryParse(p[1]) ?? ''}월' : m;
  }

  /// 잔여 칸: 음수는 '+N'(초과)로, 초록색으로 보여준다.
  Widget _remainCell(int diff, {bool bold = false}) {
    final over = diff < 0;
    return Text(
      over ? '+${-diff}' : '$diff',
      style: TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
        color: over ? const Color(0xFF059669) : null,
      ),
    );
  }

  Widget _buildWeeklyTable() {
    if (!_isSemiconductor) return const SizedBox.shrink();
    final wp = model['weekly_plan'];
    if (wp is! Map || wp.isEmpty) return const SizedBox.shrink();
    final months = wp.keys.map((e) => e.toString()).toList()..sort();
    if (months.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final curKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final nxt = DateTime(now.year, now.month + 1, 1);
    final nxtKey = '${nxt.year}-${nxt.month.toString().padLeft(2, '0')}';
    final month = _resolvedMonth;

    final weeks = wp[month];
    if (weeks is! Map) return const SizedBox.shrink();
    final wkeys = weeks.keys.map((e) => e.toString()).toList()..sort();

    int tp = 0, ta = 0;
    final rows = <DataRow>[];
    for (final w in wkeys) {
      final v = weeks[w];
      final plan = (v is Map) ? ((v['plan'] as num?)?.toInt() ?? 0) : 0;
      final act = (v is Map) ? ((v['actual'] as num?)?.toInt() ?? 0) : 0;
      tp += plan; ta += act;
      final marked = _markedWeeks.contains(w);
      rows.add(DataRow(
        color: marked
            ? WidgetStateProperty.all(const Color(0xFFFFF1F1))
            : null,
        cells: [
          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
            Text(w,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: marked ? const Color(0xFFDC2626) : null)),
            if (marked) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999)),
                child: const Text('기준',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ])),
          DataCell(Text('$plan')),
          DataCell(Text('$act', style: TextStyle(color: act > 0 ? const Color(0xFF059669) : Colors.black45, fontWeight: act > 0 ? FontWeight.w700 : FontWeight.normal))),
          DataCell(_remainCell(plan - act)),
        ],
      ));
    }
    rows.add(DataRow(cells: [
      const DataCell(Text('합계', style: TextStyle(fontWeight: FontWeight.w800))),
      DataCell(Text('$tp', style: const TextStyle(fontWeight: FontWeight.w800))),
      DataCell(Text('$ta', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF059669)))),
      DataCell(_remainCell(tp - ta, bold: true)),
    ]));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('주차별 계획',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        // 월이 늘어나도 카드 밖으로 나가지 않도록 가로 스크롤
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: months.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final m = months[i];
              final sel = m == month;
              final tag = m == curKey ? '당월' : (m == nxtKey ? '다음달' : '');
              return ChoiceChip(
                label: Text('${_monthLabel(m)}${tag.isNotEmpty ? ' · $tag' : ''}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : const Color(0xFF374151))),
                selected: sel,
                showCheckmark: false,
                selectedColor: const Color(0xFF1E3A5F),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _selMonth = m),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 36,
            columnSpacing: 28,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            columns: const [
              DataColumn(label: Text('주차', style: TextStyle(fontSize: 12))),
              DataColumn(label: Text('계획', style: TextStyle(fontSize: 12)), numeric: true),
              DataColumn(label: Text('실적', style: TextStyle(fontSize: 12)), numeric: true),
              DataColumn(label: Text('잔여', style: TextStyle(fontSize: 12)), numeric: true),
            ],
            rows: rows,
          ),
        ),
        if (_price > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(children: [
              Expanded(
                  child: _moneyCell('계획 기준 예상 매출', _usd(tp * _price),
                      const Color(0xFF1E3A5F))),
              Container(width: 1, height: 30, color: const Color(0xFFE5E7EB)),
              Expanded(
                  child: _moneyCell('실적 매출', _usd(ta * _price),
                      const Color(0xFF059669))),
            ]),
          ),
          const SizedBox(height: 6),
          Text('판가 ${_usd(_price)} 기준',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ],
      ]),
    );
  }

  int get _price => (model['price'] as num?)?.toInt() ?? 0;

  String _usd(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  Widget _moneyCell(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );


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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Row(children: [
            _kpi(_remainLabel, _remainValue,
                _isOver ? const Color(0xFF059669) : Colors.black87),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_monthShort출하 진행률 $_shipProgress%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_shipProgress / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation(navy),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _byMonth
                    ? '계획 $_basePlan · 출하완료 $_baseActual  (전체 PO $_poQty · 누적 출하 $_shipped)'
                    : '계획 $_poQty · 출하완료 $_shipped',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ]),
          ),
          // ── 이슈사항 (출하 진행률 바로 아래 고정) ──
          const SizedBox(height: 16),
          Row(children: [
            const Text('이슈사항',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (_issueLines.isNotEmpty) ...[
              const SizedBox(width: 8),
              _badge('이슈', filled: true, color: const Color(0xFFFFA000)),
              if (delay > 0) ...[
                const SizedBox(width: 6),
                _badge('지연', filled: false, color: red),
              ],
            ],
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _issueLines.isEmpty
                ? _cardDeco()
                : BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: red.withValues(alpha: 0.4), width: 1.5),
                  ),
            child: _issueLines.isEmpty
                ? const Text('등록된 이슈가 없습니다',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in _issueLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(line,
                              style: const TextStyle(fontSize: 13, height: 1.5)),
                        ),
                    ],
                  ),
          ),
          // ── 주차별 계획 ──
          const SizedBox(height: 16),
          _buildWeeklyTable(),
          // ── 비고 (이슈와 별개로 자유롭게 적는 메모) ──
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('비고',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: _cardDeco(),
              child: Text(_note,
                  style: const TextStyle(fontSize: 13, height: 1.6)),
            ),
          ],
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
              color: Colors.black.withValues(alpha: 0.04),
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

