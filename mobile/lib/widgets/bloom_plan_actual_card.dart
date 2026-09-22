// 블룸 '계획 대비 실적' 카드 — 월간 / 일별.
//
// 블룸은 결국 계획 대비 실적을 본다. 일 보고 파일에 다 들어 있는데
// 화면은 '오늘 계획 · 어제 달성' 만 보여줘서 이번 달 어디까지 왔는지를
// 머리로 더해야 했다.
//
//   월간  맨 위에 매출 · 출하, 그 밑에 품목별 NCT · 조립 · 출하 막대
//   일별  날짜를 고르면 그날 품목 · 공정별 계획/실적
//
// 막대는 이달 전체 계획 대비다.
import 'package:flutter/material.dart';

import '../design/colors.dart';
import '../models/bloom_daily.dart';

const _kGood = Color(0xFF059669);
const _kWarn = Color(0xFFEA580C);
const _kBad = Color(0xFFDC2626);
const _kNone = Color(0xFFCBD5E1);
const _kTrack = Color(0xFFF1F5F9);
const _kNavy = Color(0xFF0F2C59);

/// 80% 이상 초록 · 50~79 주황 · 그 밑 빨강. 계획이 없으면 회색.
Color _rateColor(int? p) {
  if (p == null) return _kNone;
  if (p >= 80) return _kGood;
  if (p >= 50) return _kWarn;
  return _kBad;
}

int? _pct(int a, int p) => p > 0 ? (a * 100 / p).round() : null;

String _n(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return v < 0 ? '-$b' : b.toString();
}

String _man(double usd) => '\$${_n((usd / 10000).round())}만';

String _md(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  return (m == null || d == null) ? iso : '$m/$d';
}

String _dow(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  const w = ['월', '화', '수', '목', '금', '토', '일'];
  return w[(t.weekday - 1) % 7];
}

/// 품목 이름에서 '(102품목)' 같은 꼬리를 뗀다.
String _itemName(String s) => s.replaceAll(RegExp(r'\s*\(\d+\s*품목\)\s*$'), '').trim();

const List<String> _kGroups = ['NCT', '조립', '출하'];

class BloomPlanActualCard extends StatefulWidget {
  final BloomDailyBoard board;
  const BloomPlanActualCard({super.key, required this.board});

  @override
  State<BloomPlanActualCard> createState() => _BloomPlanActualCardState();
}

class _BloomPlanActualCardState extends State<BloomPlanActualCard> {
  bool _daily = false;
  ScrollController? _chips;

  @override
  void dispose() {
    _chips?.dispose();
    super.dispose();
  }
  String? _day;

  BloomDailyBoard get b => widget.board;

  /// 공정 묶음 하나의 월 합계 (품목 안에서 같은 묶음이 둘일 수도 있다)
  static ({int plan, int actual, int? ptd}) _sum(BloomItem it, String g) {
    var p = 0, a = 0, t = 0;
    var hasPtd = false, any = false;
    for (final s in it.steps) {
      if (s.group != g) continue;
      any = true;
      p += s.monthPlan ?? 0;
      a += s.monthActual ?? 0;
      final q = s.planToDate;
      if (q != null) {
        t += q;
        hasPtd = true;
      }
    }
    if (!any) return (plan: -1, actual: 0, ptd: null);
    return (plan: p, actual: a, ptd: hasPtd ? t : null);
  }

  /// 실적이 적힌 마지막 날 (보통 보고일 전날)
  String? _lastActual() {
    String? last;
    for (final it in b.items) {
      for (final s in it.steps) {
        final d = s.lastActualDate;
        if (d != null && (last == null || d.compareTo(last) > 0)) last = d;
      }
    }
    return last;
  }

  /// 일별에서 처음 골라둘 날 — 실적이 적힌 마지막 날
  String? _defaultDay() =>
      _lastActual() ?? (b.dates.isNotEmpty ? b.dates.last : null);

  String _asOf() {
    final last = _lastActual();
    final rep = b.reportDate.isNotEmpty ? ' · ${_md(b.reportDate)} 보고' : '';
    return last == null ? '실적 입력 전$rep' : '${_md(last)} 실적까지$rep';
  }

  @override
  Widget build(BuildContext context) {
    if (!b.hasBoard || b.items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${_monthOf()}월 계획 대비 실적',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain),
              ),
            ),
            _Seg(
              left: '월간',
              right: '일별',
              rightOn: _daily,
              onChanged: (v) => setState(() {
                _daily = v;
                _day ??= _defaultDay();
              }),
            ),
          ]),
          // 파일은 매일 아침 '전날까지' 실적으로 올라온다 — 보고일이 아니라
          // 실적이 적힌 마지막 날을 앞에 쓴다.
          if (b.reportDate.isNotEmpty || _lastActual() != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_asOf(),
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ),
          const SizedBox(height: 12),
          if (_daily) _dailyView() else _monthView(),
        ],
      ),
    );
  }

  String _monthOf() {
    final m = b.money?.month ?? '';
    if (m.isNotEmpty) return m;
    // 10/1 보고는 9/30 실적 — 달은 보고일이 아니라 실적 날짜로 잡는다
    final d = _lastActual() ??
        (b.reportDate.isNotEmpty ? b.reportDate : (b.dates.isNotEmpty ? b.dates.last : ''));
    final p = d.split('-');
    return p.length == 3 ? '${int.tryParse(p[1]) ?? p[1]}' : '';
  }

  // ── 월간 ────────────────────────────────────────────────────
  Widget _monthView() {
    var sp = 0, sa = 0;
    for (final it in b.items) {
      final r = _sum(it, '출하');
      if (r.plan > 0) sp += r.plan;
      sa += r.actual;
    }
    final money = b.money;
    final items = [...b.items]
      ..sort((x, y) => _sum(y, '출하').plan.compareTo(_sum(x, '출하').plan));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (money != null) ...[
            Expanded(
              child: _Kpi(
                label: '매출',
                value: _man(money.doneUsd),
                of: '/ ${_man(money.planUsd)}',
                pct: money.pct,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: _Kpi(
              label: '출하',
              value: _n(sa),
              of: '/ ${_n(sp)}대',
              pct: _pct(sa, sp),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const _Legend(),
        const SizedBox(height: 6),
        for (var i = 0; i < items.length; i++)
          _ItemMonth(
            item: items[i],
            first: i == 0,
            sum: (g) => _sum(items[i], g),
          ),
      ],
    );
  }

  // ── 일별 ────────────────────────────────────────────────────
  Widget _dailyView() {
    final dates = [...b.dates]..sort(); // 날짜 순
    final day = _day ?? _defaultDay();
    // 처음 열 때 고른 날이 보이도록 (앞에 이틀 정도 여유)
    final at = day == null ? 0 : dates.indexOf(day);
    _chips ??= ScrollController(
        initialScrollOffset: at > 2 ? (at - 2) * 56.0 : 0);
    if (day == null || dates.isEmpty) {
      return const Text('날짜별 계획이 없습니다',
          style: TextStyle(fontSize: 12, color: AppColors.textHint));
    }
    bool hasActual(String d) =>
        b.items.any((it) => it.steps.any((s) => s.at(d)?.actual != null));

    // 그날 공정 묶음별 합계
    final tot = <String, List<int?>>{}; // g -> [plan, actual(null=입력 전)]
    for (final it in b.items) {
      for (final s in it.steps) {
        final c = s.at(day);
        if (c == null) continue;
        final cur = tot.putIfAbsent(s.group, () => [0, null]);
        cur[0] = (cur[0] ?? 0) + (c.plan ?? 0);
        if (c.actual != null) cur[1] = (cur[1] ?? 0) + c.actual!;
      }
    }
    final rows = b.items.where((it) => it.steps.any((s) {
          final c = s.at(day);
          return c != null && ((c.plan ?? 0) > 0 || c.actual != null);
        })).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            controller: _chips,
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final d = dates[i];
              return _DayChip(
                label: _md(d),
                sub: _dow(d),
                on: d == day,
                filled: hasActual(d),
                onTap: () => setState(() => _day = d),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // 그날 합계
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final g in [..._kGroups, ...tot.keys.where((k) => !_kGroups.contains(k))])
            if (tot[g] != null) _DayTotal(group: g, plan: tot[g]![0] ?? 0, actual: tot[g]![1]),
        ]),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('이날은 계획도 실적도 없습니다',
                style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          ),
        for (var i = 0; i < rows.length; i++) _ItemDay(item: rows[i], day: day, first: i == 0),
      ],
    );
  }
}

// ── 조각들 ─────────────────────────────────────────────────────

class _Seg extends StatelessWidget {
  final String left, right;
  final bool rightOn;
  final ValueChanged<bool> onChanged;
  const _Seg({required this.left, required this.right, required this.rightOn, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget b(String t, bool on, bool v) => GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: on ? _kNavy : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : AppColors.textMute)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: _kTrack, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        b(left, !rightOn, false),
        b(right, rightOn, true),
      ]),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label, value, of;
  final int? pct;
  const _Kpi({required this.label, required this.value, required this.of, required this.pct});

  @override
  Widget build(BuildContext context) {
    final c = _rateColor(pct);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF1F5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHint)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _kNavy,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(of,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textHint)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Bar(pct: pct, color: c, height: 6),
        const SizedBox(height: 3),
        Text(pct == null ? '-' : '$pct%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final int? pct;
  final Color color;
  final double height;
  const _Bar({required this.pct, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final w = ((pct ?? 0).clamp(0, 100)) / 100.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: _kTrack),
          FractionallySizedBox(
            widthFactor: w,
            child: Container(color: color),
          ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget d(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 10.5, color: AppColors.textMute)),
        ]);
    return Wrap(spacing: 12, runSpacing: 4, children: [
      d(_kGood, '80% 이상'),
      d(_kWarn, '50~79%'),
      d(_kBad, '50% 미만'),
    ]);
  }
}

class _ItemMonth extends StatelessWidget {
  final BloomItem item;
  final bool first;
  final ({int plan, int actual, int? ptd}) Function(String g) sum;
  const _ItemMonth({required this.item, required this.first, required this.sum});

  @override
  Widget build(BuildContext context) {
    final groups = [
      ..._kGroups,
      ...{for (final s in item.steps) s.group}.where((g) => !_kGroups.contains(g)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_itemName(item.item),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMain)),
        const SizedBox(height: 6),
        for (final g in groups) _stepRow(g, sum(g)),
      ]),
    );
  }

  Widget _stepRow(String g, ({int plan, int actual, int? ptd}) r) {
    if (r.plan < 0) return const SizedBox.shrink(); // 이 품목에 없는 공정
    final p = _pct(r.actual, r.plan);
    final c = _rateColor(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 34,
            child: Text(g,
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMute)),
          ),
          Expanded(child: _Bar(pct: p, color: c)),
          const SizedBox(width: 8),
          SizedBox(
            width: 116,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: _n(r.actual),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.textMain)),
                TextSpan(text: ' / ${_n(r.plan)}'),
                TextSpan(
                    text: p == null ? '' : '  $p%',
                    style: TextStyle(fontWeight: FontWeight.w800, color: c)),
              ]),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMute,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label, sub;
  final bool on, filled;
  final VoidCallback onTap;
  const _DayChip(
      {required this.label, required this.sub, required this.on, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : (filled ? AppColors.textMain : AppColors.textHint);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        decoration: BoxDecoration(
          color: on ? _kNavy : (filled ? Colors.white : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? _kNavy : AppColors.borderDefault),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
          Text(filled ? sub : '$sub · 계획',
              style: TextStyle(
                  fontSize: 9.5,
                  color: on ? Colors.white70 : AppColors.textHint)),
        ]),
      ),
    );
  }
}

class _DayTotal extends StatelessWidget {
  final String group;
  final int plan;
  final int? actual;
  const _DayTotal({required this.group, required this.plan, required this.actual});

  @override
  Widget build(BuildContext context) {
    final p = actual == null ? null : _pct(actual!, plan);
    final c = actual == null ? AppColors.textHint : _rateColor(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEF1F5)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$group  ',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMute)),
          TextSpan(
              text: actual == null ? '입력 전' : _n(actual!),
              style: TextStyle(fontWeight: FontWeight.w800, color: actual == null ? c : AppColors.textMain)),
          TextSpan(text: ' / ${_n(plan)}'),
          if (p != null)
            TextSpan(text: '  $p%', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        ]),
        style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textMute,
            fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _ItemDay extends StatelessWidget {
  final BloomItem item;
  final String day;
  final bool first;
  const _ItemDay({required this.item, required this.day, required this.first});

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final s in item.steps)
        if (s.at(day) != null && ((s.at(day)!.plan ?? 0) > 0 || s.at(day)!.actual != null))
          (s, s.at(day)!),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 92,
          child: Text(_itemName(item.item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textMain)),
        ),
        Expanded(
          child: Column(children: [
            for (final e in cells) _cell(e.$1, e.$2),
          ]),
        ),
      ]),
    );
  }

  Widget _cell(BloomStep s, BloomCell c) {
    final plan = c.plan ?? 0;
    final a = c.actual;
    final p = a == null ? null : _pct(a, plan);
    final col = a == null ? AppColors.textHint : _rateColor(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Text(s.group,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMute)),
        ),
        Expanded(child: _Bar(pct: a == null ? 0 : (p ?? (a > 0 ? 100 : 0)), color: col, height: 5)),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: a == null ? '입력 전' : _n(a),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: a == null ? AppColors.textHint : AppColors.textMain)),
              TextSpan(text: ' / ${_n(plan)}'),
              if (p != null)
                TextSpan(text: '  $p%', style: TextStyle(fontWeight: FontWeight.w800, color: col)),
            ]),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMute,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ]),
    );
  }
}
