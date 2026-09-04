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

const double _kHeadH = 26;   // 머리글 한 줄
const double _kRowH = 52;    // 데이터 행 (양산 / 개발)
const double _kTotalH = 32;  // 합계 행

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
        return _shell(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _table(d),
        ));
      },
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
  Widget _table(Map<String, dynamic> d) {
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
      width: 116,
      child: Column(
        children: [
          _cell('', _kHeadH * 3, head: true, align: TextAlign.left),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
