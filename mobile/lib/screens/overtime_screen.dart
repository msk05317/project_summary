// 전사 잔·특근 — 주차 하나, 지표 하나.
//
// 사업부 16곳 × 잔업/특근 × 전체/직접/간접 = 96칸이다. 토글로 하나씩
// 보여 주지 않으면 폰에서 읽을 방법이 없다.
//
// 순위는 값순이 기본이고 증감순으로 바꿀 수 있다. "누가 제일 높나" 와
// "어디가 갑자기 뛰었나" 는 다른 질문이고, W39 는 후자가 더 중요했다 —
// 헬스케어가 한 주에 +19.7%p 올랐다.
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/overtime.dart';
import '../services/overtime_service.dart';
import 'overtime_division_screen.dart';

const Color kOtColor = Color(0xFF2A78D6);   // 잔업
const Color kSpColor = Color(0xFFEB6834);   // 특근

String ovPct(double? v, {int digits = 1}) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(digits)}%';

String ovNum(int? n) {
  if (n == null) return '—';
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

String ovDelta(double? v) {
  if (v == null) return '';
  final p = v * 100;
  if (p.abs() < 0.05) return '±0.0';
  return '${p > 0 ? '+' : '−'}${p.abs().toStringAsFixed(1)}';
}

Color ovDeltaColor(double? v) {
  if (v == null || v.abs() < 0.0005) return AppColors.textHint;
  return v > 0 ? AppColors.statusRed : AppColors.statusGreen;
}

enum _Sort { value, delta }

class OvertimeScreen extends StatefulWidget {
  final String initialWeek;

  const OvertimeScreen({super.key, this.initialWeek = ''});

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen> {
  late String _week;
  String _kind = 'overtime';
  String _scope = 'total';
  _Sort _sort = _Sort.value;
  late Future<OvertimeWeek> _future;

  @override
  void initState() {
    super.initState();
    _week = widget.initialWeek;
    _future = _load();
  }

  Future<OvertimeWeek> _load() =>
      OvertimeService.fetchWeek(week: _week, kind: _kind, scope: _scope);

  void _reload() => setState(() => _future = _load());

  Color get _tone => _kind == 'special' ? kSpColor : kOtColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.reportPageBg,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('전사 잔·특근',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<OvertimeWeek>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final w = snap.data ?? OvertimeWeek.empty;
          if (!w.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  '아직 올린 주차가 없습니다.\n주간 잔특근 취합 엑셀을 올리면 여기에 나옵니다.',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.reportBody),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                _weekNav(w),
                const SizedBox(height: 10),
                _kindToggle(w),
                const SizedBox(height: 10),
                _hero(w),
                const SizedBox(height: 10),
                _counts(w),
                if (w.issues.isNotEmpty || w.counts.audit > 0) ...[
                  const SizedBox(height: 10),
                  _issues(w),
                ],
                const SizedBox(height: 10),
                _ranking(w),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 주차 이동 ────────────────────────────────────────────
  Widget _weekNav(OvertimeWeek w) {
    final weeks = w.weeks;
    final at = weeks.indexOf(w.week);
    final hasPrev = at > 0;
    final hasNext = at >= 0 && at < weeks.length - 1;
    return _card(
      pad: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            color: hasPrev ? AppColors.textSub : AppColors.statusGray,
            onPressed: hasPrev
                ? () => setState(() {
                      _week = weeks[at - 1];
                      _future = _load();
                    })
                : null,
          ),
          Text(w.weekLabel,
              style: AppText.bodyStrong
                  .copyWith(fontSize: 14, color: AppColors.textMain)),
          const SizedBox(width: 8),
          Text(w.range,
              style: AppText.caption
                  .copyWith(fontSize: 11, color: AppColors.textHint)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            color: hasNext ? AppColors.textSub : AppColors.statusGray,
            onPressed: hasNext
                ? () => setState(() {
                      _week = weeks[at + 1];
                      _future = _load();
                    })
                : null,
          ),
        ],
      ),
    );
  }

  // ── 지표 · 범위 토글 ─────────────────────────────────────
  Widget _kindToggle(OvertimeWeek w) {
    final kinds = w.kinds.isEmpty
        ? const [
            OvLabel(key: 'overtime', label: '잔업률', range: '월~토'),
            OvLabel(key: 'special', label: '특근률', range: '일'),
          ]
        : w.kinds;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFECEFF3),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: kinds.map((k) {
              final on = k.key == _kind;
              final tone = k.key == 'special' ? kSpColor : kOtColor;
              return Expanded(
                child: GestureDetector(
                  onTap: on
                      ? null
                      : () => setState(() {
                            _kind = k.key;
                            _future = _load();
                          }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: on ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: on
                          ? const [
                              BoxShadow(
                                  color: Color(0x17101828),
                                  blurRadius: 2,
                                  offset: Offset(0, 1))
                            ]
                          : null,
                    ),
                    child: Text(
                      '${k.label}${k.range.isEmpty ? '' : ' (${k.range})'}',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: on ? tone : AppColors.textMute,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in (w.scopes.isEmpty
                ? const [
                    OvLabel(key: 'total', label: '전체'),
                    OvLabel(key: 'direct', label: '직접'),
                    OvLabel(key: 'indirect', label: '간접'),
                  ]
                : w.scopes))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: s.key == _scope
                      ? null
                      : () => setState(() {
                            _scope = s.key;
                            _future = _load();
                          }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: s.key == _scope
                          ? AppColors.headerNavy
                          : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: s.key == _scope
                              ? AppColors.headerNavy
                              : AppColors.borderDefault),
                    ),
                    child: Text(
                      s.label,
                      style: AppText.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: s.key == _scope
                            ? Colors.white
                            : AppColors.textSub,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── 히어로 ──────────────────────────────────────────────
  Widget _hero(OvertimeWeek w) {
    final k = w.total.kind(_kind);
    final people = k.people.of(_scope)?.round();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('전사 ${w.kindLabel}률',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
              const SizedBox(width: 6),
              Text(w.scopeLabel,
                  style: AppText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _tone)),
              const Spacer(),
              if (w.prevLabel.isNotEmpty)
                Text('${w.prevLabel} ${ovPct(w.avg == null || w.avgDelta == null ? null : w.avg! - w.avgDelta!)}',
                    style: AppText.caption
                        .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                w.avg == null ? '—' : (w.avg! * 100).toStringAsFixed(1),
                style: AppText.h1.copyWith(
                  fontSize: 32,
                  height: 1.05,
                  color: AppColors.textMain,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 1),
                child: Text('%',
                    style: AppText.bodyStrong
                        .copyWith(fontSize: 14, color: AppColors.textMute)),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (w.avgDelta != null)
                      Text(
                        '${w.avgDelta! > 0 ? '▲' : (w.avgDelta! < 0 ? '▼' : '')} ${ovDelta(w.avgDelta).replaceAll('+', '').replaceAll('−', '')}%p',
                        style: AppText.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ovDeltaColor(w.avgDelta)),
                      ),
                    Text('${w.kindLabel} ${ovNum(people)}명',
                        style: AppText.caption.copyWith(
                            fontSize: 11, color: AppColors.textMute)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _split('직접', k.rate.direct, _tone),
              const SizedBox(width: 10),
              _split('간접', k.rate.indirect, _tone.withValues(alpha: .38)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _split(String label, double? v, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textMute)),
              const Spacer(),
              Text(ovPct(v),
                  style: AppText.captionStrong.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textMain,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (v ?? 0).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE6EAF0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ── 몇 곳이 넘었나 ──────────────────────────────────────
  Widget _counts(OvertimeWeek w) {
    final c = w.counts;
    Widget one(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Column(
              children: [
                Text('$n',
                    style: AppText.bodyStrong.copyWith(
                        fontSize: 16,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 1),
                Text(label,
                    style: AppText.caption
                        .copyWith(fontSize: 10, color: AppColors.textMute)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        one('전사 초과', c.over, AppColors.statusRed),
        const SizedBox(width: 7),
        one('이하', c.under, AppColors.textSub),
        const SizedBox(width: 7),
        one('전주보다 ↑', c.up, AppColors.statusRed),
        const SizedBox(width: 7),
        one('↓', c.down, AppColors.statusGreen),
      ],
    );
  }

  // ── 확인이 필요한 것 ────────────────────────────────────
  Widget _issues(OvertimeWeek w) {
    final rows = <Widget>[];
    for (final it in w.items) {
      for (final a in it.audit) {
        rows.add(_issueRow('검산', it.label, a, true));
      }
    }
    for (final s in w.issues) {
      final i = s.indexOf('—');
      rows.add(_issueRow('파일', i > 0 ? s.substring(0, i).trim() : '',
          i > 0 ? s.substring(i + 1).trim() : s, false));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(
      pad: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text('확인이 필요한 것',
                style: AppText.bodyStrong
                    .copyWith(fontSize: 13, color: AppColors.textMain)),
          ),
          ...rows,
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _issueRow(String tag, String who, String what, bool ours) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: ours
                  ? AppColors.statusRedSoft
                  : AppColors.statusGraySoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(tag,
                style: AppText.caption.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color:
                        ours ? const Color(0xFFB42318) : AppColors.textMute)),
          ),
          const SizedBox(width: 8),
          if (who.isNotEmpty) ...[
            SizedBox(
              width: 72,
              child: Text(who,
                  style: AppText.captionStrong
                      .copyWith(fontSize: 11.5, color: AppColors.textMain)),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(what,
                style: AppText.caption
                    .copyWith(fontSize: 11.5, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  // ── 사업부 순위 ─────────────────────────────────────────
  Widget _ranking(OvertimeWeek w) {
    final items = List<OvItem>.from(w.items);
    if (_sort == _Sort.delta) {
      items.sort((a, b) {
        final x = a.delta, y = b.delta;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });
    }
    final max = items.fold<double>(
        0, (p, e) => (e.rate ?? 0) > p ? (e.rate ?? 0) : p);
    final scale = max <= 0 ? 1.0 : max;

    return _card(
      pad: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Text('사업부별',
                    style: AppText.bodyStrong
                        .copyWith(fontSize: 13, color: AppColors.textMain)),
                const Spacer(),
                _sortChip('값순', _Sort.value),
                const SizedBox(width: 5),
                _sortChip('증감순', _Sort.delta),
              ],
            ),
          ),
          for (final it in items) _rankRow(w, it, scale),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Text(
              '점선 = 전사 ${ovPct(w.avg)} · 진한 막대 = 전사 초과',
              style: AppText.caption
                  .copyWith(fontSize: 10.5, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, _Sort s) {
    final on = _sort == s;
    return GestureDetector(
      onTap: () => setState(() => _sort = s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? AppColors.headerNavy : AppColors.bgCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? AppColors.headerNavy : AppColors.borderDefault),
        ),
        child: Text(label,
            style: AppText.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : AppColors.textSub)),
      ),
    );
  }

  Widget _rankRow(OvertimeWeek w, OvItem it, double scale) {
    final frac = ((it.rate ?? 0) / scale).clamp(0.0, 1.0);
    final avgFrac =
        w.avg == null ? null : (w.avg! / scale).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OvertimeDivisionScreen(
          divisionKey: it.key,
          divisionLabel: it.label,
          week: w.week,
        ),
      )),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              child: Row(
                children: [
                  Flexible(
                    child: Text(it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.captionStrong.copyWith(
                            fontSize: 11.5,
                            color: it.overAvg
                                ? AppColors.textMain
                                : AppColors.textSub)),
                  ),
                  if (it.needsCheck)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(Icons.error_outline_rounded,
                          size: 11, color: AppColors.statusRed),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 12,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF1F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: frac,
                      child: Container(
                        decoration: BoxDecoration(
                          color: it.overAvg
                              ? _tone
                              : _tone.withValues(alpha: .28),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    if (avgFrac != null)
                      FractionallySizedBox(
                        widthFactor: avgFrac,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                              width: 1.4, color: const Color(0xFF98A5B5)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(ovPct(it.rate),
                      style: AppText.captionStrong.copyWith(
                          fontSize: 11.5,
                          color: AppColors.textMain,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  if (it.delta != null)
                    Text(ovDelta(it.delta),
                        style: AppText.caption.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: ovDeltaColor(it.delta),
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 15, color: AppColors.statusGray),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? pad}) {
    return Container(
      width: double.infinity,
      padding: pad ?? const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: child,
    );
  }
}
