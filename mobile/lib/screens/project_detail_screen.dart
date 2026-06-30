import '../config/app_config.dart';
import 'package:flutter/material.dart';
import '../design/design.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class ProjectDetailScreen extends StatefulWidget {
  final String projectKey;
  final String projectLabel;
  final String? status;

  const ProjectDetailScreen({
    super.key,
    required this.projectKey,
    required this.projectLabel,
    this.status,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Map<String, dynamic>? detail;       // 기존 PPT 카드 (백워드 호환)
  Map<String, dynamic>? noteCard;     // 주간 보고 노트
  String noteReportDate = '';
  String noteDivisionId = '';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // 1) 주간 보고 노트 우선 로드
      final noteRes = await http.get(
        Uri.parse('$kApiBaseUrl/notes/by_project?project_key=${Uri.encodeComponent(widget.projectKey)}'),
      );
      Map<String, dynamic>? nc;
      String nd = '';
      String ndiv = '';
      if (noteRes.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(noteRes.bodyBytes));
        if (decoded is Map && decoded['card'] != null) {
          nc = Map<String, dynamic>.from(decoded['card']);
          nd = (decoded['report_date'] ?? '').toString();
          ndiv = (decoded['division_id'] ?? '').toString();
        }
      }

      // 2) 노트 없으면 기존 PPT 카드 폴백
      Map<String, dynamic>? d;
      if (nc == null) {
        final res = await http.get(
          Uri.parse('$kApiBaseUrl/projects/${widget.projectKey}'),
        );
        if (res.statusCode == 200) {
          d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        }
      }

      setState(() {
        noteCard = nc;
        noteReportDate = nd;
        noteDivisionId = ndiv;
        detail = d;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  bool _circledGroupActive = false;
  bool _numberedGroupActive = false;

  // rich_parts 가 있으면 RichText, 없으면 Text
  Widget _buildItemText(Map<String, dynamic> it, String text, TextStyle base) {
    final parts = it['rich_parts'];
    if (parts is List && parts.isNotEmpty) {
      final spans = <TextSpan>[];
      for (final p in parts) {
        if (p is! Map) continue;
        final ptext = (p['text'] ?? '').toString();
        final pcolor = (p['color'] ?? '').toString().toLowerCase();
        Color? c;
        if (pcolor == 'red') c = AppColors.statusRed;
        else if (pcolor == 'blue') c = const Color(0xFF1E88E5);
        else if (pcolor == 'orange') c = AppColors.statusYellow;
        spans.add(TextSpan(
          text: ptext,
          style: c != null ? base.copyWith(color: c) : base,
        ));
      }
      return RichText(text: TextSpan(style: base, children: spans));
    }
    return Text(text, style: base);
  }

  // 웹 미리보기와 동일한 D-day 칩
  Widget _buildDueChip(dynamic dueRaw) {
    final raw = (dueRaw ?? '').toString().trim();
    if (raw.isEmpty) return const SizedBox.shrink();
    final due = DateTime.tryParse(raw);
    if (due == null) return const SizedBox.shrink();

    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final d = DateTime(due.year, due.month, due.day);
    final diff = d.difference(today).inDays;
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');

    late final String label;
    late final Color bg;
    late final Color fg;
    late final Color bd;

    if (diff == 0) {
      label = 'D-0 오늘 ($mm/$dd)';
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFF9A3412);
      bd = const Color(0xFFFDBA74);
    } else if (diff > 0) {
      label = 'D-$diff ($mm/$dd)';
      bg = const Color(0xFFEEF2FF);
      fg = const Color(0xFF4338CA);
      bd = const Color(0xFFC7D2FE);
    } else {
      label = 'D+${-diff} 지남 ($mm/$dd)';
      bg = const Color(0xFFFFE4E6);
      fg = const Color(0xFFBE123C);
      bd = const Color(0xFFFDA4AF);
    }

    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.0)),
    );
  }

  Color? _itemColor(Map<String, dynamic> it) {
    switch ((it['color'] ?? '').toString().toLowerCase()) {
      case 'red':
        return Colors.red.shade700;
      case 'blue':
        return Colors.blue.shade700;
      case 'orange':
        return Colors.orange.shade800;
      default:
        return null;
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

  String _absUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '$kApiBaseUrl$url';
    return '$kApiBaseUrl/$url';
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = noteCard != null
        ? Colors.indigo
        : (detail != null ? _statusColor(detail!['status'] ?? 'BLACK') : Colors.grey);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectLabel),
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        bottom: true,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text('오류: $error'))
                : (noteCard != null
                    ? _buildNoteContent()
                    : (detail != null
                        ? _buildLegacyContent()
                        : const Center(child: Text('데이터 없음')))),
      ),
    );
  }

  // ============================== 주간 보고 노트 ==============================
  Widget _buildNoteContent() {
    final c = noteCard!;
    final title = (c['title'] ?? widget.projectLabel).toString();
    final sections = (c['sections'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 헤더
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (noteReportDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('보고일자: $noteReportDate',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sections.map<Widget>((s) => _buildNoteSection(s as Map<String, dynamic>)),
        ],
      ),
    );
  }


  Widget _buildNoteSection(Map<String, dynamic> s) {
    final _title0 = (s['title'] ?? '').toString().trim();
    final _items0 = (s['items'] as List?) ?? const [];
    if (_isProcessSectionTitle(_title0)) {
      final groups = _extractProcessGroupsFromItems(_items0);
      if (groups.isNotEmpty) {
        return _buildProcessGroupsSection(_title0, groups);
      }
    }

    final title = (s['title'] ?? '').toString();
    final items = (s['items'] as List?) ?? [];
    final secTableData = s['table_data'];   // 섹션 레벨 표 (호환)

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            if (title.isNotEmpty) const SizedBox(height: 10),
            ..._buildItemsWithGroups(items),
            // 섹션 레벨 표 (구버전 호환)
            if (secTableData != null) ...[
              const SizedBox(height: 8),
              _buildTableMini(secTableData as Map<String, dynamic>),
            ],
          ],
        ),
      ),
    );
  }

  // group_id 같은 항목들을 노란 박스로 묶어 렌더
  List<Widget> _buildItemsWithGroups(List items) {
    _circledGroupActive = false;
    _numberedGroupActive = false;
    final widgets = <Widget>[];
    int i = 0;
    while (i < items.length) {
      final raw = items[i];
      final it = (raw is String)
          ? {'type': 'bullet', 'text': raw}
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      final gid = (it['group_id'] ?? '').toString();

      if (gid.isNotEmpty) {
        // 같은 group_id 연속 구간 모으기
        final groupItems = <dynamic>[];
        int j = i;
        while (j < items.length) {
          final r = items[j];
          final x = (r is String)
              ? {'type': 'bullet', 'text': r}
              : (r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{});
          if ((x['group_id'] ?? '').toString() != gid) break;
          groupItems.add(r);
          j++;
        }

        // 일반 항목 / group_note 분리
        final normals = <dynamic>[];
        final notes = <dynamic>[];
        for (final g in groupItems) {
          final o = (g is String)
              ? {'type': 'bullet', 'text': g}
              : (g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{});
          if ((o['type'] ?? '').toString() == 'group_note') {
            notes.add(g);
          } else {
            normals.add(g);
          }
        }

        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: Colors.amber.shade700, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...normals.map<Widget>((g) => _buildNoteItem(g)),
              if (notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.amber.shade300,
                          width: 1,
                          style: BorderStyle.solid,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: notes.map<Widget>((g) {
                        final o = (g is String)
                            ? {'text': g}
                            : (g is Map ? Map<String, dynamic>.from(g) : <String, dynamic>{});
                        final text = (o['text'] ?? '').toString();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('↪ ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade800)),
                              Expanded(
                                child: Text(text,
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        color: Colors.brown.shade800,
                                        fontStyle: FontStyle.italic)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ));
        i = j;
      } else {
        // group_id 없는 항목
        widgets.add(_buildNoteItem(raw));
        i++;
      }
    }
    return widgets;
  }


  bool _isProcessSectionTitle(String title) {
    final t = title.trim();
    return t.contains('제품별 진행 현황') || t.contains('제품별진행현황');
  }

  String? _detectProcessStage(String raw) {
    final text = raw.trim();
    if (text.startsWith('[원자재]') || text.startsWith('[원자재발주]')) return '원자재';
    if (text.startsWith('[입고]')) return '입고';
    if (text.startsWith('[생산]') || text.startsWith('[생산일정]')) return '생산';
    if (text.startsWith('[납기]') || text.startsWith('[출하]')) return '납기';
    return null;
  }

  String _stripProcessPrefix(String stage, String raw) {
    var text = raw.trim();
    final prefixes = <String>[
      '[$stage]',
      if (stage == '원자재') '[원자재발주]',
      if (stage == '생산') '[생산일정]',
      if (stage == '납기') '[출하]',
    ];
    for (final p in prefixes) {
      if (text.startsWith(p)) {
        text = text.substring(p.length).trim();
        break;
      }
    }
    return text;
  }

  double _extractProcessPercent(String stage, String text) {
    // 1) 명시 퍼센트 우선
    final explicit = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(text);
    if (explicit != null) {
      return double.tryParse(explicit.group(1) ?? '') ?? 0;
    }

    // 2) 납기: 출하완료 / 총 PO
    if (stage == '납기') {
      final shipped = RegExp(r'출하완료\s*([\d,]+)').firstMatch(text);
      final total = RegExp(r'(?:총\s*PO|PO)\s*([\d,]+)').firstMatch(text);
      if (shipped != null && total != null) {
        final a = double.tryParse((shipped.group(1) ?? '0').replaceAll(',', '')) ?? 0;
        final b = double.tryParse((total.group(1) ?? '0').replaceAll(',', '')) ?? 0;
        if (b > 0) return ((a / b) * 100.0).clamp(0, 100);
      }
    }

    // 3) 일반 비율: 108 / 640
    final ratio = RegExp(r'([\d,]+)\s*/\s*([\d,]+)').firstMatch(text);
    if (ratio != null) {
      final a = double.tryParse((ratio.group(1) ?? '0').replaceAll(',', '')) ?? 0;
      final b = double.tryParse((ratio.group(2) ?? '0').replaceAll(',', '')) ?? 0;
      if (b > 0) return ((a / b) * 100.0).clamp(0, 100);
    }

    // 4) 키워드 기반
    if (text.contains('완료') && !text.contains('미완')) return 100;
    if (text.contains('진행')) return 50;
    if (text.contains('예정') || text.contains('대기')) return 0;
    return 0;
  }

  Color _processStageColor(String stage, double percent, String detail) {
    final d = detail.toLowerCase();
    if (d.contains('지연') || d.contains('부족') || d.contains('문제') || d.contains('불가')) {
      return AppColors.statusRed;
    }
    if (percent >= 100) return const Color(0xFF16A34A);
    if (percent > 0) return AppColors.statusYellow;
    return AppColors.statusGray;
  }

  String _processPercentLabel(double value) {
    if (value == value.roundToDouble()) return '${value.toInt()}%';
    return '${value.toStringAsFixed(1)}%';
  }

  List<Map<String, dynamic>> _extractProcessGroupsFromItems(List items) {
    final groups = <Map<String, dynamic>>[];
    Map<String, dynamic>? current;

    void flush() {
      if (current != null) {
        groups.add(current!);
        current = null;
      }
    }

    for (final raw in items) {
      if (raw is! Map) continue;
      final type = (raw['type'] ?? 'bullet').toString().toLowerCase();
      final text = (raw['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;

      if (type == 'sub') {
        flush();
        current = {
          'title': text,
          'stages': <Map<String, dynamic>>[],
        };
        continue;
      }

      final stage = _detectProcessStage(text);
      if (stage != null) {
        current ??= {
          'title': '',
          'stages': <Map<String, dynamic>>[],
        };
        final detail = _stripProcessPrefix(stage, text);
        final percent = _extractProcessPercent(stage, detail);
        current!['stages'].add({
          'stage': stage,
          'percent': percent,
          'detail': detail,
          'color': _processStageColor(stage, percent, detail),
        });
      }
    }

    flush();
    return groups;
  }

  Widget _buildProcessStageDot(String stage, double percent, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _processPercentLabel(percent),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color == AppColors.statusGray
                  ? AppColors.textMute
                  : color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessGroupsSection(String title, List<Map<String, dynamic>> groups) {
    const order = ['원자재', '입고', '생산', '납기'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: AppColors.bgPage,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderDefault),
              ),
              child: Builder(
                builder: (context) {
                  final group = groups[i];
                  final groupTitle = (group['title'] ?? '').toString();
                  final stages = (group['stages'] as List).cast<Map<String, dynamic>>();

                  Map<String, dynamic>? findStage(String stage) {
                    for (final s in stages) {
                      if ((s['stage'] ?? '') == stage) return s;
                    }
                    return null;
                  }

                  final stageMap = {
                    for (final key in order)
                      key: findStage(key) ??
                          {
                            'stage': key,
                            'percent': 0.0,
                            'detail': '',
                            'color': AppColors.statusGray,
                          }
                  };

                  Widget detailLine(String stage, String detail) {
                    if (detail.trim().isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$stage  ',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF374151),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              detail,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groupTitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            groupTitle,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMain,
                            ),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProcessStageDot(
                            '원자재',
                            (stageMap['원자재']!['percent'] as num).toDouble(),
                            stageMap['원자재']!['color'] as Color,
                          ),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(top: 9),
                              height: 2,
                              color: AppColors.borderDefault,
                            ),
                          ),
                          _buildProcessStageDot(
                            '입고',
                            (stageMap['입고']!['percent'] as num).toDouble(),
                            stageMap['입고']!['color'] as Color,
                          ),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(top: 9),
                              height: 2,
                              color: AppColors.borderDefault,
                            ),
                          ),
                          _buildProcessStageDot(
                            '생산',
                            (stageMap['생산']!['percent'] as num).toDouble(),
                            stageMap['생산']!['color'] as Color,
                          ),
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(top: 9),
                              height: 2,
                              color: AppColors.borderDefault,
                            ),
                          ),
                          _buildProcessStageDot(
                            '납기',
                            (stageMap['납기']!['percent'] as num).toDouble(),
                            stageMap['납기']!['color'] as Color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      detailLine('원자재', (stageMap['원자재']!['detail'] ?? '').toString()),
                      detailLine('입고', (stageMap['입고']!['detail'] ?? '').toString()),
                      detailLine('생산', (stageMap['생산']!['detail'] ?? '').toString()),
                      detailLine('납기', (stageMap['납기']!['detail'] ?? '').toString()),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildNoteItem(dynamic raw) {
    // 문자열도 허용 (구버전)
    if (raw is String) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(raw, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );
    }
    if (raw is! Map) return const SizedBox.shrink();
    final it = Map<String, dynamic>.from(raw);
    final type = (it['type'] ?? 'bullet').toString();
    final text = (it['text'] ?? '').toString();
    final rawText = text.trim();

    final isStar = rawText.startsWith('※');
    final isAsterisk = rawText.startsWith('*') && !rawText.startsWith('**');
    final isCircledSub = type == 'sub' &&
        RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳]').hasMatch(rawText);
    final isNumberedSub = type == 'sub' &&
        RegExp(r'^\s*\d+[.)]\s').hasMatch(rawText);

    // 그룹 상태 갱신
    if (isCircledSub) {
      _circledGroupActive = true;
      _numberedGroupActive = false;
    }
    if (isNumberedSub) {
      _numberedGroupActive = true;
      _circledGroupActive = false;
    }
    final inGroup = (_circledGroupActive || _numberedGroupActive);

    switch (type) {
      case 'highlight': {
        final colorOverride = _itemColor(it);
        final mainColor = colorOverride ?? Colors.red.shade800;
        final prefixColor = colorOverride ?? Colors.red.shade700;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isStar && !isAsterisk)
                Text('★ ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: prefixColor)),
              Expanded(
                child: _buildItemText(
                  it,
                  text,
                  TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: mainColor),
                ),
              ),
              _buildDueChip(it['due_date']),
            ],
          ),
        );
      }
      case 'sub': {
        final colorOverride = _itemColor(it);
        final hasArrow = RegExp(r'^(?:→|↳|=>)\s*').hasMatch(rawText);

        // 원형/숫자 sub: 화살표 없이 소제목처럼 표시
        if (isCircledSub || isNumberedSub) {
          final mainColor = colorOverride ?? Colors.grey.shade900;
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildItemText(
                    it,
                    text,
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: mainColor),
                  ),
                ),
                _buildDueChip(it['due_date']),
              ],
            ),
          );
        }

        final mainColor = colorOverride ?? Colors.grey.shade800;
        final prefixColor = colorOverride ?? Colors.grey.shade600;
        final leftPad = inGroup ? 32.0 : 24.0;
        return Padding(
          padding: EdgeInsets.only(left: leftPad, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hasArrow)
                Text('→ ', style: TextStyle(color: prefixColor)),
              Expanded(
                child: _buildItemText(
                  it,
                  text,
                  TextStyle(fontSize: 13.5, color: mainColor),
                ),
              ),
              _buildDueChip(it['due_date']),
            ],
          ),
        );
      }
      case 'group_note':
        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: Colors.amber.shade700, width: 3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('↪ ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                Expanded(
                  child: _buildItemText(
                    it,
                    text,
                    TextStyle(
                        fontSize: 13.5,
                        color: Colors.brown.shade800,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        );
      case 'table':
        return const SizedBox.shrink();
      case 'photo':
        final ref = (it['photo_ref'] ?? '').toString();
        if (ref.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildPhotoMini('/note_photos/$ref'),
        );
      case 'bullet':
      default: {
        final colorOverride = _itemColor(it);
        final mainColor = colorOverride ?? Colors.black87;

        // 그룹 상태에서 일반 bullet → 화살표 + 들여쓰기
        if (inGroup && !isStar && !isAsterisk) {
          final prefixColor = colorOverride ?? Colors.grey.shade600;
          return Padding(
            padding: const EdgeInsets.only(left: 24, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('→ ', style: TextStyle(color: prefixColor)),
                Expanded(
                  child: _buildItemText(
                    it,
                    text,
                    TextStyle(fontSize: 13.5, color: mainColor),
                  ),
                ),
                _buildDueChip(it['due_date']),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isStar && !isAsterisk)
                Text('• ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: mainColor)),
              Expanded(
                child: _buildItemText(
                  it,
                  text,
                  TextStyle(
                      fontSize: 14,
                      fontWeight: isStar ? FontWeight.w700 : FontWeight.w400,
                      color: mainColor),
                ),
              ),
              _buildDueChip(it['due_date']),
            ],
          ),
        );
      }
    }
  }

  Widget _buildTableMini(Map<String, dynamic> table) {
    final title = (table['title'] ?? '').toString();
    final headers = (table['headers'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (table['rows'] as List?) ?? [];
    final previewRows = rows.take(3).toList();
    final hasMore = rows.length > 3;

    return InkWell(
      onTap: () => _openTableFull(table),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart, size: 16, color: Colors.indigo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title.isEmpty ? '표' : title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Icon(Icons.zoom_out_map, size: 14, color: Colors.grey.shade600),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 32,
                columnSpacing: 16,
                horizontalMargin: 4,
                columns: headers
                    .map((h) => DataColumn(
                        label: Text(h,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold))))
                    .toList(),
                rows: previewRows
                    .map<DataRow>((r) => DataRow(
                          cells: (r as List)
                              .map<DataCell>((c) => DataCell(Text(c.toString(),
                                  style: const TextStyle(fontSize: 12))))
                              .toList(),
                        ))
                    .toList(),
              ),
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('… 외 ${rows.length - 3}행 (탭하여 전체 보기)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
          ],
        ),
      ),
    );
  }

  void _openTableFull(Map<String, dynamic> table) {
    final title = (table['title'] ?? '표').toString();
    final headers = (table['headers'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rows = (table['rows'] as List?) ?? [];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: InteractiveViewer(
                  constrained: false,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: DataTable(
                    columns: headers
                        .map((h) => DataColumn(
                            label: Text(h,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))))
                        .toList(),
                    rows: rows
                        .map<DataRow>((r) => DataRow(
                              cells: (r as List)
                                  .map<DataCell>((c) => DataCell(Text(c.toString())))
                                  .toList(),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoMini(String relPath) {
    final url = _absUrl(relPath);
    return InkWell(
      onTap: () => _openPhotoFull(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          height: 160,
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            height: 100,
            color: Colors.grey.shade200,
            child: const Center(child: Text('사진 로드 실패')),
          ),
        ),
      ),
    );
  }

  void _openPhotoFull(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(0),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================== 기존 PPT 카드 (백워드 호환) ==============================
  Widget _buildLegacyContent() {
    final d = detail!;
    final sections = (d['sections'] as List?) ?? [];
    final headerSummary = d['header_summary']?.toString() ?? '';
    final headerMetrics = (d['header_metrics'] as Map?) ?? {};
    final reportDate = d['report_date']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _statusColor(d['status'] ?? 'BLACK').withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['label']?.toString() ?? '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (reportDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('보고일자: $reportDate',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ),
                  if (headerSummary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('※ $headerSummary',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                  ...headerMetrics.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 14)),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sections.map<Widget>((s) => _buildLegacySection(s as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildLegacySection(Map<String, dynamic> s) {
    final title = s['title']?.toString() ?? '';
    final items = (s['items'] as List?) ?? [];
    final notes = (s['notes'] as List?) ?? [];
    final images = (s['image_urls'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            ..._buildItemsWithGroups(items),
            ...notes.map<Widget>((n) {
              if (n is Map) {
                return _buildNoteItem(Map<String, dynamic>.from(n));
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('※ \$n',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                        fontStyle: FontStyle.italic)),
              );
            }),
            ...images.map<Widget>((img) => _buildLegacyImage(img)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyImage(dynamic imgData) {
    String url;
    String caption = '';
    if (imgData is String) {
      url = imgData;
    } else if (imgData is Map) {
      url = (imgData['url'] ?? '').toString();
      caption = (imgData['caption'] ?? '').toString();
    } else {
      return const SizedBox.shrink();
    }
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openPhotoFull(_absUrl(url)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(_absUrl(url),
                  fit: BoxFit.cover, width: double.infinity, height: 200,
                  errorBuilder: (_, __, ___) => Container(
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Center(child: Text('이미지 로드 실패')),
                      )),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }
}
