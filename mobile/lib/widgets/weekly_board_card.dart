// 주차 현황 보드 (하바플레이트).
//
// 예전에는 엑셀 원본을 PNG 로 올려 이미지로 보여줬는데, 이제 admin 에서
// 같은 표를 데이터로 계산해 그린다. 앱도 그 계산 결과(/weekly-board)를 그대로 받아
// 동일한 모양으로 그린다.
//
// 열이 17개라 가로 스크롤이 필요하다. 열마다 폭을 고정하고, 각 열을 Column 으로
// 세워서 행 높이를 맞춘다. (Table 위젯은 셀 병합이 안 돼서 3단 머리글을 못 만든다)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

const double _kHeadH = 22;   // 머리글 한 줄 (x3 = 표 머리글 전체 높이)
const double _kRowH = 52;    // 데이터 행 (양산 / 개발)
const double _kTotalH = 32;  // 합계 행
const double _kSecRowH = 38; // 섹션형 데이터 행 (행이 많아 낮게)

const Color _navy = Color(0xFF0F2C59);
const Color _line = Color(0xFFE5E7EB);
const Color _red = Color(0xFFDC2626);

class WeeklyBoardCard extends StatefulWidget {
  final String projectKey;
  final String? month;

  const WeeklyBoardCard({super.key, required this.projectKey, this.month});

  @override
  State<WeeklyBoardCard> createState() => _WeeklyBoardCardState();
}

class _WeeklyBoardCardState extends State<WeeklyBoardCard> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>?> _fetch() async {
    try {
      final q = (widget.month == null || widget.month!.isEmpty)
          ? ''
          : '?month=${Uri.encodeComponent(widget.month!)}';
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/projects/${Uri.encodeComponent(widget.projectKey)}/weekly-board$q'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is! Map<String, dynamic> || d['rows'] == null) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  String _n(dynamic v) {
    final i = (v is num) ? v.round() : int.tryParse('$v');
    if (i == null) return '-';
    final s = i.abs().toString();
    final b = StringBuffer();
    for (var k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) b.write(',');
      b.write(s[k]);
    }
    return (i < 0 ? '-' : '') + b.toString();
  }

  String _mon(String? ym) {
    if (ym == null || !ym.contains('-')) return '';
    final m = int.tryParse(ym.split('-')[1]);
    return m == null ? '' : '$m월';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _shell(const SizedBox(
            height: 90,
            child: Center(child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ));
        }
        final d = snap.data;
        if (d == null) {
          // 서버가 아직 보드 API 를 모르면 조용히 사라지지 말고 한 줄로 알린다
          return _shell(const Text('주차 현황을 불러오지 못했습니다',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))));
        }
        return _shell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 표 폭이 화면보다 훨씬 넓다(약 980px). 가로 스크롤만으로는
              // 오른쪽에 주차가 더 있다는 걸 모른다. 오른쪽 끝을 흐리게 해서
              // 이어진다는 걸 보이고, 탭하면 전체를 확대해서 본다.
              Stack(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _table(d),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 22,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _openZoom(d),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.zoom_out_map_rounded,
                          size: 15, color: Color(0xFF156082)),
                      SizedBox(width: 5),
                      Text('전체 크게 보기',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF156082),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 표 전체를 화면 가득 펼쳐 손가락으로 확대·이동해 본다.
  // 폰을 가로로 눕히면 주차가 거의 다 들어온다.
  void _openZoom(Map<String, dynamic> d) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: const Color(0xFFF8FAFC),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('주차 현황 보드',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.pinch_rounded, size: 13, color: Color(0xFF9CA3AF)),
                    SizedBox(width: 5),
                    Expanded(
                      child: Text('손가락으로 확대·이동할 수 있어요. 폰을 눕히면 더 넓게 보입니다.',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFF6B7280))),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  constrained: false,
                  minScale: 0.4,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(120),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _table(d),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shell(Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('주차 현황 보드',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // ── 표 ────────────────────────────────────────────────────────────
  // 백엔드가 두 가지 모양을 돌려준다.
  //   layout: 'sections'  프로젝트별 행 구성 (챔버 — 기존/내재화/Dep 챔버)
  //   그 외                양산/개발 두 줄 + 주차 (하바플레이트)
  Widget _table(Map<String, dynamic> d) {
    if ((d['layout'] ?? '') == 'sections') return _sectionTable(d);
    return _weekTable(d);
  }

  // ── 섹션형 (구분 | 행 | 현황 | PO | 실적 | 잔량 | 월… | 비고) ──────
  Widget _sectionTable(Map<String, dynamic> d) {
    final byWeek = (d['columns'] ?? 'month') == 'week';
    final months = (d['months'] as List? ?? const []).map((e) => '$e').toList();
    final weeks = (d['weeks'] as List? ?? const []).map((e) => '$e').toList();
    final nowMon = (d['current_month'] ?? '').toString();  // 이번 달 = 빨간 테두리
    final nowWeek = (d['current_week'] ?? '').toString();  // 이번 주차 = 빨간 테두리
    final showStatus = d['show_status'] != false;
    final sections = (d['sections'] as List? ?? const []).cast<Map>();
    final total = (d['total'] as Map?) ?? const {};

    final flat = <Map>[];
    for (final sec in sections) {
      flat.addAll((sec['rows'] as List? ?? const []).cast<Map>());
    }
    final hasNote = flat.any((r) => '${r['note'] ?? ''}'.trim().isNotEmpty);

    // 주차 모드는 머리글이 3단(월 / 주차 / 계획·실적), 월 모드는 2단이다.
    final headSpan = byWeek ? 3 : 2;

    List<String> col(String f) => [...flat.map((r) => _n(r[f])), _n(total[f])];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 구분 — 섹션 이름을 한 칸으로 묶어 세로로 이어 보이게 한다
        SizedBox(
          width: 74,
          child: Column(
            children: [
              _cell('구분', _kHeadH * headSpan, head: true, align: TextAlign.left),
              for (final sec in sections)
                _cell('${sec['name']}',
                    _kSecRowH * ((sec['rows'] as List? ?? const []).length),
                    align: TextAlign.left, bold: true, size: 10),
              _cell('', _kTotalH, total: true),
            ],
          ),
        ),
        SizedBox(
          width: 84,
          child: Column(
            children: [
              _cell('', _kHeadH * headSpan, head: true),
              for (final r in flat)
                _cell('${r['label']}', _kSecRowH, bold: true, size: 10.5),
              _cell('합계', _kTotalH, total: true),
            ],
          ),
        ),
        if (showStatus)
          SizedBox(
            width: 52,
            child: Column(
              children: [
                _cell('현황', _kHeadH * headSpan, head: true),
                for (final r in flat) _cell('${r['status'] ?? ''}', _kSecRowH, size: 10),
                _cell('', _kTotalH, total: true),
              ],
            ),
          ),
        _numCol2('PO 수량', col('po_qty'), 62, span: headSpan),
        _numCol2('실적', col('actual_total'), 56, span: headSpan),
        _numCol2('잔량', col('remaining'), 56, span: headSpan),
        for (final mon in months)
          _numCol2(
            _mon(mon),
            [
              ...flat.map((r) => _n(((r['months'] as Map?)?[mon] as Map?)?['plan'])),
              _n(((total['months'] as Map?)?[mon] as Map?)?['plan']),
            ],
            52,
            isNow: mon == nowMon,
            span: headSpan,
          ),
        if (byWeek) ...[
          _numCol2(_mon('${d['prev_month']}'), col('prev_month_actual'), 46,
              span: headSpan),
          for (final w in weeks)
            _secPairCol(w, [
              ...flat.map((r) => [
                    _n(((r['weeks'] as Map?)?[w] as Map?)?['plan']),
                    _n(((r['weeks'] as Map?)?[w] as Map?)?['actual']),
                  ]),
              [
                _n(((total['weeks'] as Map?)?[w] as Map?)?['plan']),
                _n(((total['weeks'] as Map?)?[w] as Map?)?['actual']),
              ],
            ], w == nowWeek),
          _secPairCol(_mon('${d['month']}'), [
            ...flat.map((r) => [_n(r['month_plan']), _n(r['month_actual'])]),
            [_n(total['month_plan']), _n(total['month_actual'])],
          ], false),
        ],
        if (hasNote)
          SizedBox(
            width: 150,
            child: Column(
              children: [
                _cell('비고', _kHeadH * headSpan, head: true),
                for (final r in flat)
                  _cell('${r['note'] ?? ''}', _kSecRowH,
                      align: TextAlign.left, size: 9.5),
                _cell('', _kTotalH, total: true),
              ],
            ),
          ),
      ],
    );
  }

  // 섹션형 머리글은 2단이라 별도 (주차형은 3단)
  // isNow = 이번 달 열. 주차형의 이번 주차와 같게 빨간 테두리를 두른다.
  Widget _numCol2(String title, List<String> values, double w,
      {bool isNow = false, int span = 2}) {
    return Container(
      width: w,
      decoration: isNow
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: _red, width: 2),
                right: BorderSide(color: _red, width: 2),
              ),
            )
          : null,
      child: Column(
        children: [
          _cell(title, _kHeadH * span, head: true, redHead: isNow),
          for (var i = 0; i < values.length - 1; i++)
            _cell(values[i], _kSecRowH, tint: isNow),
          _cell(values.last, _kTotalH, total: true, redHead: isNow),
        ],
      ),
    );
  }

  // 섹션형의 계획/실적 두 칸 열 (머리글 3단: 제목 / 주차 / 계획·실적)
  Widget _secPairCol(String title, List<List<String>> values, bool isNow) {
    return Container(
      width: 76,
      decoration: isNow
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: _red, width: 2),
                right: BorderSide(color: _red, width: 2),
              ),
            )
          : null,
      child: Column(
        children: [
          _cell(title, _kHeadH * 2, head: true, redHead: isNow),
          Row(children: [
            Expanded(child: _cell('계획', _kHeadH, head: true, redHead: isNow)),
            Expanded(child: _cell('실적', _kHeadH, head: true, redHead: isNow)),
          ]),
          for (var i = 0; i < values.length - 1; i++)
            Row(children: [
              Expanded(child: _cell(values[i][0], _kSecRowH, tint: isNow)),
              Expanded(child: _cell(values[i][1], _kSecRowH, tint: isNow)),
            ]),
          Row(children: [
            Expanded(child: _cell(values.last[0], _kTotalH, total: true, redHead: isNow)),
            Expanded(child: _cell(values.last[1], _kTotalH, total: true, redHead: isNow)),
          ]),
        ],
      ),
    );
  }

  Widget _weekTable(Map<String, dynamic> d) {
    final weeks = (d['weeks'] as List? ?? const []).map((e) => '$e').toList();
    final now = (d['current_week'] ?? '').toString();
    final rows = (d['rows'] as List? ?? const []).cast<Map>();
    final total = (d['total'] as Map?) ?? const {};

    List<String> col(String field) => [
          ...rows.map((r) => _n(r[field])),
          _n(total[field]),
        ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelCol(rows),
        _numCol('PO 수량', col('po_qty'), 62),
        _numCol('실적', col('actual_total'), 58),
        _numCol('잔량', col('remaining'), 54),
        _numCol(_mon(d['prev_month'] as String?), col('prev_month_actual'), 46),
        for (final w in weeks)
          _pairCol(w, [
            ...rows.map((r) => [
                  _n(((r['weeks'] as Map?)?[w] as Map?)?['plan']),
                  _n(((r['weeks'] as Map?)?[w] as Map?)?['actual']),
                ]),
            [
              _n(((total['weeks'] as Map?)?[w] as Map?)?['plan']),
              _n(((total['weeks'] as Map?)?[w] as Map?)?['actual']),
            ],
          ], now == w),
        _pairCol(_mon(d['month'] as String?), [
          ...rows.map((r) => [_n(r['month_plan']), _n(r['month_actual'])]),
          [_n(total['month_plan']), _n(total['month_actual'])],
        ], false),
        _numCol(_mon(d['next_month'] as String?), col('next_month_plan'), 46),
        _deltaCol((d['po_delta'] as Map?) ?? const {}),
      ],
    );
  }

  // 구분 열 (머리글은 빈 칸, 3단 높이)
  Widget _labelCol(List<Map> rows) {
    return SizedBox(
      width: 128,
      child: Column(
        children: [
          _cell('구분', _kHeadH * 3, head: true, align: TextAlign.left),
          for (final r in rows)
            _cell('${r['label']}', _kRowH,
                align: TextAlign.left, bold: true, size: 9.5),
          _cell('합계', _kTotalH, total: true, align: TextAlign.left),
        ],
      ),
    );
  }

  // 한 칸짜리 숫자 열
  Widget _numCol(String title, List<String> values, double w) {
    return SizedBox(
      width: w,
      child: Column(
        children: [
          _cell(title, _kHeadH * 3, head: true),
          for (var i = 0; i < values.length - 1; i++) _cell(values[i], _kRowH),
          _cell(values.last, _kTotalH, total: true),
        ],
      ),
    );
  }

  // 계획/실적 두 칸짜리 열 (주차 또는 월 합계)
  Widget _pairCol(String title, List<List<String>> values, bool isNow) {
    final border = isNow
        ? const Border(
            left: BorderSide(color: _red, width: 2),
            right: BorderSide(color: _red, width: 2))
        : null;
    return Container(
      width: 84,
      decoration: BoxDecoration(border: border),
      child: Column(
        children: [
          _cell(title, _kHeadH * 2, head: true, redHead: isNow),
          Row(children: [
            Expanded(child: _cell('계획', _kHeadH, head: true, redHead: isNow)),
            Expanded(child: _cell('실적', _kHeadH, head: true, redHead: isNow)),
          ]),
          for (var i = 0; i < values.length - 1; i++)
            Row(children: [
              Expanded(child: _cell(values[i][0], _kRowH, tint: isNow)),
              Expanded(child: _cell(values[i][1], _kRowH, tint: isNow)),
            ]),
          Row(children: [
            Expanded(child: _cell(values.last[0], _kTotalH, total: true, redHead: isNow)),
            Expanded(child: _cell(values.last[1], _kTotalH, total: true, redHead: isNow)),
          ]),
        ],
      ),
    );
  }

  // PO증감 — 양산/개발 두 행에 걸친 한 칸
  Widget _deltaCol(Map delta) {
    final months = (delta['months'] as List? ?? const []).cast<Map>();
    final wks = (delta['weeks'] as List? ?? const []).cast<Map>();
    final lines = <Widget>[
      for (final m in months) _deltaLine(_mon('${m['key']}'), m['delta']),
      if (wks.isNotEmpty && months.isNotEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Divider(height: 1, color: Color(0xFFCBD5E1)),
        ),
      for (final w in wks) _deltaLine('${w['key']}', w['delta']),
    ];
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          _cell('PO증감', _kHeadH * 3, head: true),
          Container(
            width: double.infinity,
            height: _kRowH * 2,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line), right: BorderSide(color: _line)),
            ),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines.isEmpty
                    ? <Widget>[
                        const Text('-',
                            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)))
                      ]
                    : lines,
              ),
            ),
          ),
          _cell('', _kTotalH, total: true),
        ],
      ),
    );
  }

  Widget _deltaLine(String label, dynamic v) {
    final n = (v is num) ? v.round() : 0;
    return Text('$label: ${_n(n.abs())} ${n >= 0 ? '▲' : '▼'}',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: 8.5,
          height: 1.42,
          fontWeight: FontWeight.w700,
          color: n >= 0 ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8),
        ));
  }

  Widget _cell(String text, double h,
      {bool head = false,
      bool total = false,
      bool redHead = false,
      bool tint = false,
      bool bold = false,
      double? size,
      TextAlign align = TextAlign.center}) {
    Color bg = Colors.white;
    Color fg = const Color(0xFF0F172A);
    if (head) {
      bg = redHead ? const Color(0xFF7F1D1D) : _navy;
      fg = Colors.white;
    } else if (total) {
      bg = redHead ? const Color(0xFF7F1D1D) : _navy;
      fg = Colors.white;
    } else if (tint) {
      bg = const Color(0xFFFEF2F2);
    }
    return Container(
      height: h,
      width: double.infinity,
      alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.center,
      // 좌우 4px 이면 글자가 구분선에 붙어 읽기 힘들다.
      // 가운데 정렬 칸은 6px, 왼쪽 정렬(구분 열)은 10px 을 준다.
      padding: EdgeInsets.symmetric(
          horizontal: align == TextAlign.left ? 10 : 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: head || total ? const Color(0xFF1E3A63) : _line),
          right: BorderSide(color: head || total ? const Color(0xFF1E3A63) : _line),
        ),
      ),
      child: Text(text,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: size ?? (head || total ? 9.5 : 10.5),
            fontWeight: head || total || bold ? FontWeight.w800 : FontWeight.w500,
            color: fg,
            height: 1.15,
          )),
    );
  }
}
