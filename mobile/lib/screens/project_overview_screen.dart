import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../design/typography.dart';
import 'model_list_screen.dart';
import 'dev_process_screen.dart';
import 'model_cost_list_screen.dart';
import '../models/weekly_revenue.dart';
import '../widgets/weekly_revenue_card.dart';
import '../widgets/weekly_board_card.dart';
import '../utils/issue_text.dart';
import '../utils/status_words.dart';
import '../design/colors.dart';
import '../models/bloom_daily.dart';
import '../services/bloom_service.dart';
import '../widgets/bloom_plan_actual_card.dart';
import '../widgets/bloom_today_card.dart';
import '../widgets/automotive_overview_card.dart';
import '../services/api_service.dart';
import '../services/offline_store.dart';

/// '확인 필요' 목록의 한 줄. 지연·임박·보류·이슈·비고를 한 가지 모양으로 만든다.
///
/// 예전에는 지연 개수는 KPI 카드에, 지연 목록은 이슈 섹션 아래에,
/// 이슈 텍스트는 AI 요약 블록에 따로 있었다. 숫자 15 와 목록 14 가
/// 서로 다른 것을 세고 있어도 알 수가 없었다.
class _CheckRow {
  final Map<String, dynamic> model;
  final String name;
  final String kind;   // 지연 · 마감 임박 · 드롭예정 · 보류 · 이슈 · 비고
  final int rank;      // 정렬 순서
  final int days;      // 지연 일수
  final String stage;
  final String expected;
  final List<String> lines;

  /// 0~2 는 문제(지연·이슈·보류), 3~4 는 참고(임박·비고).
  /// 경영진이 보는 것은 문제 유무다. 임박은 아직 안 늦은 것이고,
  /// 비고는 하바처럼 상태 표시로 쓰는 프로젝트에서 23줄이 쏟아진다.
  bool get isProblem => rank <= 2;

  const _CheckRow({
    required this.model,
    required this.name,
    required this.kind,
    required this.rank,
    required this.days,
    required this.stage,
    required this.expected,
    required this.lines,
  });
}

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
    if (_isBloomItem) _loadBloom();
    _modelsFuture = _fetchModels();
    _planFuture = _fetchWeeklyPlan();
    _summaryFuture = _fetchIssuesSummary();
  }

  /// 블룸은 품목 하나가 프로젝트 하나다. 모델이 아니라 일 보드를 본다.
  bool get _isBloomItem => BloomService.isItemKey(widget.projectKey);
  BloomDailyBoard _bloom = BloomDailyBoard.empty;

  Future<void> _loadBloom() async {
    final b = await BloomService.board(projectKey_: widget.projectKey, force: true);
    if (mounted) setState(() => _bloom = b);
  }

  /// 저장해 둔 게 언제 것인지 (오프라인 표시용)
  DateTime? _savedAt;
  bool _fromCache = false;

  Future<Map<String, dynamic>> _fetchModels() async {
    // 못 받아오면 마지막으로 받아둔 걸 쓴다. 신호 없는 곳에서도 열리게.
    final got = await OfflineStore.fetch(
        '$kApiBaseUrl/projects/${widget.projectKey}/models/detail',
        'models_${widget.projectKey}');
    _fromCache = got.fromCache;
    _savedAt = got.savedAt;
    final d = got.data;
    if (d is! Map) throw Exception('unexpected JSON');
    return Map<String, dynamic>.from(d);
  }

  Future<Map<String, dynamic>> _fetchWeeklyPlan() async {
    try {
      final got = await OfflineStore.fetch(
          '$kApiBaseUrl/projects/${widget.projectKey}/weekly-plan',
          'weekly_plan_${widget.projectKey}');
      final d = got.data;
      if (d is! Map) return {'has_plan': false};
      return Map<String, dynamic>.from(d);
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

  /// 화면 맨 위에 쓸 이름. 안 넘어왔으면 키라도 보여준다 — 빈 줄보다 낫다.
  String get _title {
    final n = widget.projectName.trim();
    return n.isNotEmpty ? n : widget.projectKey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      // 이름이 안 넘어오는 경로가 있어서, 맨 위가 뒤로가기 화살표만 있는
      // 빈 줄이 된 적이 있다. 무슨 프로젝트인지 화면에서 알 수가 없었다.
      // 모델 상세와 같은 남색 머리로 맞춘다 — 같은 깊이의 화면이다.
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2C59),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('목록 > $_title',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ),
        ),
      ),
      // 자동차사업부는 주차·진행률로 움직이지 않는다. 모델 목록 대신
      // 계약 화면(요약 → 연도별 매출 → 제품)만 그린다.
      body: _isAutomotive
          ? RefreshIndicator(
              onRefresh: () async {
                setState(() => _autoReload++);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AutomotiveOverviewCard(
                    key: ValueKey('auto-$_autoReload'),
                    projectKey: widget.projectKey,
                    projectName: widget.projectName,
                  ),
                ],
              ),
            )
          : FutureBuilder<Map<String, dynamic>>(
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
            final note = (data['status_note'] ?? '').toString();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 현황이 있으면 그것을 먼저 보여준다 (내용 없는 카드는 숨김)
                _buildStatusNote(note),
                _buildWeeklyPlanSection(),
                // 안내는 한 줄로만
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      note.trim().isEmpty
                          ? '아직 등록된 내용이 없습니다'
                          : '등록된 모델이 없습니다',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                ),
              ],
            );
          }

          final total = models.length;
          // 진행률 집계: 데이터가 있는 모델만 포함
          //  - 양산: PO 수량(계획)이 등록된 모델 (실적 0이면 0%로 집계)
          //  - 개발: 공정에 실제 입력(계획일/실적일/상태)이 있는 모델
          // 데이터가 없는 모델은 '-'로 두고 평균에서 제외
          final scored = <int>[];
          for (final m in models) {
            if (m['group'] == '개발') {
              // 13단계 틀은 자동 생성 → 실제 입력(계획일/실적일/상태)이 있어야 집계
              if (devHasProcessData(m)) {
                scored.add((m['progress'] as num?)?.toInt() ?? 0);
              }
            } else {
              final po = (m['po_qty'] as num?)?.toInt() ?? 0;
              final sh = (m['shipped_qty'] as num?)?.toInt() ?? 0;
              if (po > 0) scored.add(((sh * 100) / po).round());
            }
          }
          final int? avgProgress = scored.isEmpty
              ? null
              : (scored.reduce((a, b) => a + b) / scored.length).round();
          // 서버가 정한 값(alert)을 쓴다. 손으로 적은 status 만 보면
          // 목록에는 '지연중' 이 다섯인데 카드는 0 으로 뜬다.
          // 프로젝트가 통째로 멈춰 있으면 그것부터 말한다.
          final projHold = (data['hold'] ?? '').toString();
          final holdWhy = (data['hold_reason'] ?? '').toString();
          final delayed = models.where((m) => _alertOf(m) == '지연').length;
          // 보류·드롭예정은 멈춰 세운 것이라 지연이 아니다. 따로 칸을 두면
          // 네 칸 합이 전체와 안 맞아서 집중관리로 같이 센다 (목록 칩과 동일).
          final watched = models
              .where((m) => holdOf(m).isNotEmpty || _alertOf(m) == '주의')
              .length;
          // 정상 = 멈추지도, 끝나지도, 밀리지도 않았고 적어 둔 문제도 없는 것.
          // 문제만 세 칸 늘어놓으면 나머지가 다 제대로 가고 있다는 게 안 보인다.
          // '완료' 칸은 없앴다 (목록도 같다). 개발 최종 승인이 끝나도 PO 를
          // 기다리는 중이고, 양산은 다음 PO 가 들어오면 다시 0% 부터다.
          final normal = models.where((m) {
            if (holdOf(m).isNotEmpty) return false;
            final al = _alertOf(m);
            if (al == '지연' || al == '주의') return false;
            return (m['issues'] ?? '').toString().trim().isEmpty;
          }).length;

          final byGroup = <String, List<Map<String, dynamic>>>{'양산': [], '개발': []};
          for (final m in models) {
            // 전환 주차가 지난 모델은 양산으로 본다 (서버가 준 display_group).
            final g = (m['display_group'] ?? m['group']) == '개발' ? '개발' : '양산';
            byGroup[g]!.add(m);
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _modelsFuture = _fetchModels();
                _planFuture = _fetchWeeklyPlan();
                _summaryFuture = _fetchIssuesSummary();
              });
              if (_isBloomItem) await _loadBloom();
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 연결이 안 됐을 때. 언제 것인지 밝히고 보여준다.
                if (_fromCache)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 14, color: Color(0xFF92400E)),
                        const SizedBox(width: 6),
                        Text('오프라인 · ${OfflineStore.describe(_savedAt)} 저장된 내용',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E))),
                      ]),
                    ),
                  ),
                if (_isBloomItem && _bloom.hasBoard) ...[
                  BloomPlanActualCard(board: _bloom),
                  const SizedBox(height: 12),
                  BloomTodayCard(board: _bloom),
                  const SizedBox(height: 12),
                ],
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
                      Text(avgProgress == null ? '-' : '$avgProgress%',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: avgProgress == null
                                  ? const Color(0xFF9CA3AF)
                                  : const Color(0xFF0F2C59))),
                      const SizedBox(height: 4),
                      Text('집계 대상 ${scored.length}개 / 전체 $total개 (데이터 없는 모델 제외)',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (avgProgress ?? 0) / 100,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFF3F4F6),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F2C59)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 카드 세 장을 따로 두면 숫자만 보이고 '뭐가 지연인데' 를
                      // 다시 물어야 한다. 진행률과 같은 카드에 두고 누르게 한다.
                      Row(children: [
                        _pill('전체', total, const Color(0xFF0E2841), models, null),
                        const SizedBox(width: 6),
                        _pill(StatusWords.normal, normal,
                            AppColors.summaryNormal, models,
                            ModelBucket.running),
                        const SizedBox(width: 6),
                        _pill(StatusWords.delayed, delayed,
                            const Color(0xFFDC2626), models,
                            ModelBucket.delayed),
                        const SizedBox(width: 6),
                        _pill(StatusWords.soon, watched,
                            const Color(0xFFE97132), models, ModelBucket.soon),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (projHold.isNotEmpty) ...[
                  _holdBanner(projHold, holdWhy, models.length),
                  const SizedBox(height: 12),
                ],
                // ── 확인 필요 (지연 · 임박 · 이슈 · 비고를 한 목록으로)
                _buildCheckSection(models),
                _buildStatusNote((data['status_note'] ?? '').toString()),
                // ── 주차별 계획 (엑셀 → PNG, 탭하면 확대)
                _buildWeeklyPlanSection(),
                // ── 주차별 매출 현황
                // 자동차사업부는 주차로 움직이지 않는다. 연도별 계약이 기준이라
                // 위의 제품 화면이 그 자리를 대신한다.
                if (!_isAutomotive) FutureBuilder<WeeklyRevenue?>(
                  future: fetchWeeklyRevenue(widget.projectKey),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SizedBox(height: 80,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('매출 로드 실패: ${snap.error}',
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)));
                    }
                    final rev = snap.data;
                    if (rev == null) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('주차별 매출 데이터 없음',
                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)));
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: WeeklyRevenueCard(rev: rev),
                    );
                  },
                ),
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

  // ignore: unused_element
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

  /// 진행률 카드 안의 작은 칩. 누르면 그 상태만 걸린 목록이 열린다.
  /// 프로젝트 전체가 멈춰 있을 때. 적어둔 이유를 그대로 보여준다.
  Widget _holdBanner(String kind, String why, int n) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.pause_circle_outline, size: 18, color: Color(0xFF6B7280)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('프로젝트 전체 $kind · 모델 $n종',
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF374151))),
            if (why.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(why,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.4, color: Color(0xFF6B7280))),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text('멈춰 있는 일정이라 지연으로 세지 않습니다',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF))),
            ),
          ]),
        ),
      ]),
    );
  }

  bool _checkAll = false;

  Widget _pill(String label, int n, Color color,
      List<Map<String, dynamic>> models, ModelBucket? bucket) {
    final on = n > 0;
    return Expanded(
      child: GestureDetector(
        onTap: !on && bucket != null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ModelListScreen(
                    projectKey: widget.projectKey,
                    projectName: widget.projectName,
                    groupName: '전체',
                    models: models,
                    initialFilter: bucket,
                  ),
                )),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: on ? color.withValues(alpha: 0.25) : const Color(0xFFE5E7EB)),
          ),
          child: Column(children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$n',
                    style: TextStyle(
                        fontSize: 17,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: on ? color : const Color(0xFFCBD5E1))),
                const SizedBox(width: 1),
                Text('종',
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: on
                            ? color.withValues(alpha: 0.65)
                            : const Color(0xFFCBD5E1))),
              ],
            ),
            const SizedBox(height: 1),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
          ]),
        ),
      ),
    );
  }

  static int _daysPast(Map m) {
    final e = (m['current_expected'] ?? '').toString();
    if (e.isEmpty) return 0;
    try {
      return DateTime.now().difference(DateTime.parse(e)).inDays;
    } catch (_) {
      return 0;
    }
  }

  /// 확인이 필요한 모델을 한 목록으로. 급한 순서대로.
  List<_CheckRow> _checkRows(
      List<Map<String, dynamic>> models, Map<String, List<String>> ai) {
    final out = <_CheckRow>[];
    for (final m in models) {
      final name = (m['name'] ?? m['id'] ?? '').toString();
      final hold = holdOf(m);
      final alert = _alertOf(m);
      final issues = (m['issues'] ?? '').toString().trim();
      final note = (m['note'] ?? '').toString().trim();

      // 프로젝트 전체 보류인데 이 모델만의 사유가 따로 없으면 배너가 대신한다.
      // 똑같은 '보류' 29줄을 늘어놓을 이유가 없다.
      final scope = (m['hold_scope'] ?? '').toString();
      if (scope == 'project' && issues.isEmpty && note.isEmpty) continue;

      // rank 0~2 는 '문제', 3~4 는 '참고'.
      //   0 지연  일정이 이미 밀렸다
      //   1 이슈  사람이 적어 둔 문제
      //   2 보류  멈춰 세운 것 (드롭예정 포함)
      //   3 임박  아직 안 늦었다
      //   4 비고  메모
      String kind;
      int rank;
      if (hold.isNotEmpty) {
        kind = hold;
        rank = 2;
      } else if (alert == '지연') {
        kind = StatusWords.delayed;
        rank = 0;
      } else if (issues.isNotEmpty) {
        kind = StatusWords.issue;
        rank = 1;
      } else if (alert == '주의') {
        kind = StatusWords.soon;
        rank = 3;
      } else if (note.isNotEmpty) {
        kind = '비고';
        rank = 4;
      } else {
        continue;
      }

      final lines = <String>[];
      if (issues.isNotEmpty) {
        // AI 가 정리해 준 문장이 있으면 그걸 쓰고, 없으면 적어둔 그대로.
        // 엑셀 한 칸에 쉼표로 이어 적은 것을 줄바꿈으로만 끊으면
        // 여섯 건이 한 줄로 흘러서 뒤가 잘린다.
        final got = ai[name] ?? ai[(m['id'] ?? '').toString()];
        lines.addAll((got != null && got.isNotEmpty)
            ? got
            : IssueText.lines(issues));
      }
      if (note.isNotEmpty) lines.addAll(IssueText.lines(note));

      out.add(_CheckRow(
        model: m,
        name: name,
        kind: kind,
        rank: rank,
        days: _daysPast(m),
        stage: (m['current_stage'] ?? '').toString(),
        expected: (m['current_expected'] ?? '').toString(),
        lines: lines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .take(3)
            .toList(),
      ));
    }
    out.sort((a, b) => a.rank != b.rank ? a.rank - b.rank : b.days - a.days);
    return out;
  }

  static Color _kindColor(String kind) {
    switch (kind) {
      case StatusWords.delayed:
        return const Color(0xFFDC2626);
      case StatusWords.soon:
        return const Color(0xFFE97132);
      case StatusWords.issue:
        return const Color(0xFFDC2626);
      case '비고':
        return const Color(0xFF9CA3AF);
      default:
        return const Color(0xFF6B7280); // 드롭예정 · 보류
    }
  }

  /// '확인 필요' 한 줄을 눌렀을 때. 개발은 공정 화면, 양산은 모델 상세.
  /// 어느 쪽도 아니면(품목 등) 예전처럼 목록으로 간다.
  void _openCheckRow(_CheckRow r, List<Map<String, dynamic>> models) {
    final m = r.model;
    final g = (m['display_group'] ?? m['group'] ?? '').toString();
    final id = (m['id'] ?? m['name'] ?? '').toString();
    if (g == '개발' && id.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DevProcessScreen(
          projectKey: widget.projectKey,
          modelId: id,
          modelName: (m['name'] ?? id).toString(),
        ),
      ));
      return;
    }
    if (g == '양산') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ModelDetailScreen(
            projectName: widget.projectName, model: m),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ModelListScreen(
        projectKey: widget.projectKey,
        projectName: widget.projectName,
        groupName: '전체',
        models: models,
      ),
    ));
  }

  Widget _checkRowTile(_CheckRow r, List<Map<String, dynamic>> models) {
    final c = _kindColor(r.kind);
    final sub = <String>[
      if (r.stage.isNotEmpty) r.stage,
      if (r.expected.isNotEmpty) '완료예정 ${r.expected}',
    ].join(' · ');
    return InkWell(
      // 목록을 한 번 더 거치게 하면 늦은 모델을 다시 찾아야 한다.
      // 개발이면 공정 화면으로, 양산이면 모델 상세로 바로 넘긴다.
      onTap: () => _openCheckRow(r, models),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6, height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                ),
                const SizedBox(width: 6),
                Text(
                    r.days > 0 && (r.kind == StatusWords.delayed)
                        ? '${r.kind} ${r.days}일'
                        : r.kind,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: c)),
              ]),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(sub,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF9CA3AF))),
                ),
              // 적어 둔 사유와 '미기재' 는 같은 종류의 정보다.
              // 하나는 검정 보통, 하나는 주황 굵게면 왜 다른지 물어야 한다.
              for (final l in r.lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(l,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309))),
                ),
              // 늦었는데 아무도 이유를 안 적어 두면 그 사실을 말한다.
              // 빈칸으로 두면 사유가 없는 건지 화면이 안 보여주는 건지
              // 알 수가 없어서, 결국 사람한테 다시 물어봐야 한다.
              if (r.lines.isEmpty && r.kind == StatusWords.delayed)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('지연 사유 미기재',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309))),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// 확인 필요 — 지연·임박·보류·이슈·비고가 한 목록에 한 가지 모양으로 들어간다.
  Widget _buildCheckSection(List<Map<String, dynamic>> models) {
    return FutureBuilder<List<Map<String, String>>>(
      future: _summaryFuture,
      builder: (context, snap) {
        // AI 정리는 있으면 쓰고 없으면 적어둔 그대로 쓴다. 기다리지 않는다.
        final ai = <String, List<String>>{};
        for (final it in (snap.data ?? const <Map<String, String>>[])) {
          final k = (it['model'] ?? '').trim();
          if (k.isEmpty) continue;
          ai.putIfAbsent(k, () => []).addAll((it['summary'] ?? '')
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty));
        }
        // 확인 필요 = 문제(지연·이슈·보류)만.
        //
        // 임박·비고는 '참고' 로 접어서 밑에 뒀었는데, 접혀 있는 걸 펴 보는
        // 사람이 없었다. 둘 다 다른 데서 볼 수 있다 — 임박은 위 진행률 칸의
        // '마감 임박' 을 누르면 모델 목록이 그 필터로 열리고, 비고는 모델
        // 줄과 상세에 그대로 있다.
        final rows = _checkRows(models, ai)
            .where((r) => r.isProblem)
            .toList(growable: false);
        final counts = <String, int>{};
        for (final r in rows) {
          counts[r.kind] = (counts[r.kind] ?? 0) + 1;
        }
        final shown = _checkAll ? rows : rows.take(6).toList();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('확인 필요',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: rows.isEmpty
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${rows.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: rows.isEmpty
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626))),
              ),
            ]),
            if (counts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                    counts.entries.map((e) => '${e.key} ${e.value}').join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF))),
              ),
            const SizedBox(height: 2),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('문제 없음 — 지연·이슈·보류 없습니다',
                    style: TextStyle(fontSize: 13, color: Color(0xFF059669))),
              )
            else ...[
              for (int i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _checkRowTile(shown[i], models),
              ],
              if (rows.length > 6)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => setState(() => _checkAll = !_checkAll),
                    child: Text(
                        _checkAll ? '접기' : '모두 보기 (${rows.length})',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF156082))),
                  ),
                ),
            ],
          ]),
        );
      },
    );
  }

  // 지연 개수는 KPI 카드에, 지연 목록은 여기에, 이슈 텍스트는 AI 블록에
  // 따로 있던 예전 구성. _buildCheckSection 으로 합쳤다.
  // ignore: unused_element
  Widget _buildIssueSection(List<Map<String, dynamic>> models) {
    // issues 텍스트가 실제로 있는 모델만 추출
    final withIssues = models
        .where((m) => (m['issues'] ?? '').toString().trim().isNotEmpty)
        .toList();
    // 이슈 라인 총 개수 (모델별 여러 줄 가능)
    final issueLines = withIssues.fold<int>(
        0,
        (s, m) =>
            s +
            (m['issues'] ?? '')
                .toString()
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .length);

    // 이슈 칸이 비어 있어도 위험한 것들. 적어둔 게 어디에도 안 뜨면
    // '연결이 하나도 안 된다'는 말이 나온다.
    final late = models
        .where((m) => _alertOf(m) == '지연' &&
            (m['issues'] ?? '').toString().trim().isEmpty)
        .toList();
    final notes = models
        .where((m) => (m['note'] ?? '').toString().trim().isNotEmpty)
        .toList();
    final totalLines = issueLines + late.length + notes.length;

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
                // 아래에 지연·비고가 붙는데 여기서 '없습니다'라고 하면 앞뒤가 안 맞는다
                if (late.isNotEmpty || notes.isNotEmpty) {
                  return const SizedBox.shrink();
                }
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
          ),
          // ── 이슈 칸은 비었지만 일정이 지난 모델
          if (late.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('일정 지연',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            for (final m in late.take(8))
              _riskLine(
                  const Color(0xFFDC2626),
                  '${m['name'] ?? m['id'] ?? ''} · '
                  '${(m['current_expected'] ?? '').toString().isEmpty
                      ? '완료예정일 지남'
                      : '완료예정 ${m['current_expected']} 경과'}'),
            if (late.length > 8)
              _riskLine(const Color(0xFFDC2626), '그 외 ${late.length - 8}종'),
          ],
          // ── 비고에 적어둔 내용 (드롭 예정 같은 것)
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('비고',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
            const SizedBox(height: 4),
            for (final m in notes.take(8))
              _riskLine(
                  holdOf(m).isNotEmpty
                      ? const Color(0xFF6B7280)
                      : const Color(0xFF156082),
                  '${m['name'] ?? m['id'] ?? ''} · '
                  '${(m['note'] ?? '').toString().trim().replaceAll('\n', ' · ')}'),
            if (notes.length > 8)
              _riskLine(const Color(0xFF156082), '그 외 ${notes.length - 8}종'),
          ],
        ],
      ),
    );
  }

  /// 이슈/리스크 한 줄
  static Widget _riskLine(Color dot, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 5, color: dot),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, height: 1.45, color: Color(0xFF374151))),
        ),
      ]),
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

  // 주차 현황 보드로 바뀐 프로젝트. 엑셀 이미지 대신 계산된 표를 그린다.
  // 주차별 계획을 엑셀 이미지 대신 '주차 현황 보드'로 그리는 프로젝트.
  // 행 구성은 백엔드 config/boards.json 이 갖고 있고, 없으면 양산/개발 2줄.
  static const _boardProjects = {
    'hrva_plate', 'havaplate', 'hrva-plate',
    'chamber',
    'enclosure',
    'powerbox',
    'major_module',
  };

  /// 자동차사업부인가. 프로젝트 키가 전부 auto_ 로 시작해 고객사가 늘어도 따라온다.
  /// 자동차 화면을 다시 받게 하는 값. 당겨서 새로고침할 때만 올린다.
  int _autoReload = 0;

  bool get _isAutomotive =>
      widget.projectKey.toLowerCase().startsWith('auto_');

  Widget _buildWeeklyPlanSection() {
    // 자동차사업부는 주차 계획이 아니라 연도별 계약으로 움직인다.
    // 계약 화면은 본문이 직접 그리므로 여기서는 아무것도 두지 않는다.
    if (_isAutomotive) return const SizedBox.shrink();
    if (_boardProjects.contains(widget.projectKey.toLowerCase())) {
      return WeeklyBoardCard(projectKey: widget.projectKey);
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _planFuture,
      builder: (context, snap) {
        final plan = snap.data ?? {};
        final hasPlan = plan['has_plan'] == true && (plan['url'] ?? '').toString().isNotEmpty;
        // 로딩이 끝났는데 등록된 계획이 없으면 섹션을 통째로 숨긴다
        if (snap.connectionState == ConnectionState.done && !hasPlan) {
          return const SizedBox.shrink();
        }
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
              else
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.black87,
                        pageBuilder: (_, a, s) => _ZoomableImageScreen(
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
                      errorBuilder: (_, e, st) => const Text('이미지 로드 실패',
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

  /// 지연/주의 판정. 서버가 alert 로 내려준다.
  /// 옛 서버에 붙었을 때를 위해 status 로 떨어진다.
  static String _alertOf(Map m) {
    // 드롭·보류는 일정이 멈춘 것이다. 예정일이 지났다고 지연으로 세면
    // 카드에는 '지연 1' 인데 실제로는 드롭이라 숫자가 거짓말을 한다.
    if (holdOf(m).isNotEmpty) return '정상';
    final a = (m['alert'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    return (m['status'] ?? '').toString().trim();
  }

  Widget _groupCard(String group, List<Map<String, dynamic>> list) {
    final isMass = group == '양산';
    final delayed = list.where((m) => _alertOf(m) == '지연').length;
    final watched = list.where((m) => _alertOf(m) == '주의').length;
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
