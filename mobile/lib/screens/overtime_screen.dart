// 전사 잔업·특근 — 주차 하나, 지표 하나.
//
// 사업부 16곳 × 잔업/특근 × 전체/직접/간접 = 96칸이다. 토글로 하나씩
// 보여 주지 않으면 폰에서 읽을 방법이 없다.
//
// 한 주치를 한 번만 받는다. 지표·범위를 바꿀 때는 서버를 다시 부르지
// 않는다 — 전에는 토글할 때마다 다시 불러서 매번 로딩이 돌았다. 여섯
// 칸이 다 들어 있으니 화면에서 골라 그리면 된다. 주차를 바꿀 때만 받는다.
//
// '확인이 필요한 것' 은 여기 두지 않는다. 고칠 수 있는 사람이 보는
// 화면은 admin 이고, 앱에서 보는 사람은 고칠 수 없다.
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
    _future = OvertimeService.fetchWeek(week: _week);
  }

  /// 주차를 바꿀 때만 다시 받는다.
  void _goWeek(String w) => setState(() {
        _week = w;
        _future = OvertimeService.fetchWeek(week: w);
      });

  Color get _tone => _kind == 'special' ? kSpColor : kOtColor;

  double? _avgOf(OvertimeWeek w) => w.total.kind(_kind).rate.of(_scope);

  double? _avgDeltaOf(OvertimeWeek w) {
    final now = _avgOf(w);
    final was = w.prevTotal?.kind(_kind).rate.of(_scope);
    if (now == null || was == null) return null;
    return now - was;
  }

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [
              _weekNav(w),
              const SizedBox(height: 10),
              _kindToggle(w),
              const SizedBox(height: 10),
              _hero(w),
              const SizedBox(height: 10),
              _summaryLines(w),
              const SizedBox(height: 10),
              _ranking(w),
            ],
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
            onPressed: hasPrev ? () => _goWeek(weeks[at - 1]) : null,
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
            onPressed: hasNext ? () => _goWeek(weeks[at + 1]) : null,
          ),
        ],
      ),
    );
  }

  // ── 지표 · 범위 토글 (서버를 다시 부르지 않는다) ─────────
  Widget _kindToggle(OvertimeWeek w) {
    final kinds = w.kinds.isEmpty
        ? const [
            OvLabel(key: 'overtime', label: '잔업률', range: '월~토'),
            OvLabel(key: 'special', label: '특근률', range: '일'),
          ]
        : w.kinds;
    final scopes = w.scopes.isEmpty
        ? const [
            OvLabel(key: 'total', label: '전체'),
            OvLabel(key: 'direct', label: '직접'),
            OvLabel(key: 'indirect', label: '간접'),
          ]
        : w.scopes;
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
                  behavior: HitTestBehavior.opaque,
                  onTap: on ? null : () => setState(() => _kind = k.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
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
            for (final s in scopes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: s.key == _scope
                      ? null
                      : () => setState(() => _scope = s.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
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
                        color:
                            s.key == _scope ? Colors.white : AppColors.textSub,
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
    final avg = _avgOf(w);
    final delta = _avgDeltaOf(w);
    final people = k.people.of(_scope)?.round();
    final label = _kind == 'special' ? '특근' : '잔업';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('전사 $label률',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13, color: AppColors.textMain)),
              const SizedBox(width: 6),
              Text(_scopeLabel(w),
                  style: AppText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _tone)),
              const Spacer(),
              if (w.prevLabel.isNotEmpty && avg != null && delta != null)
                Text('${w.prevLabel} ${ovPct(avg - delta)}',
                    style: AppText.caption
                        .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avg == null ? '—' : (avg * 100).toStringAsFixed(1),
                style: AppText.h1.copyWith(
                  fontSize: 32,
                  height: 1.05,
                  color: AppColors.textMain,
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
                    if (delta != null)
                      Text(
                        '${delta > 0 ? '▲' : (delta < 0 ? '▼' : '')} '
                        '${(delta.abs() * 100).toStringAsFixed(1)}%p',
                        style: AppText.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ovDeltaColor(delta)),
                      ),
                    Text('$label ${ovNum(people)}명',
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

  String _scopeLabel(OvertimeWeek w) {
    for (final s in w.scopes) {
      if (s.key == _scope) return s.label;
    }
    return _scope == 'direct'
        ? '직접'
        : _scope == 'indirect'
            ? '간접'
            : '전체';
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
                  style: AppText.captionStrong
                      .copyWith(fontSize: 11.5, color: AppColors.textMain)),
            ],
          ),
          const SizedBox(height: 4),
          _bar((v ?? 0).clamp(0.0, 1.0), color, 8),
        ],
      ),
    );
  }

  /// 값이 바뀌면 길이가 미끄러지듯 움직인다 — 토글이 끊겨 보이지 않게.
  Widget _bar(double value, Color color, double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (_, t, _) => LinearProgressIndicator(
          value: t,
          minHeight: height,
          backgroundColor: const Color(0xFFE6EAF0),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }

  // ── 두 줄 요약 ──────────────────────────────────────────
  //
  // 전에는 '전사 초과 / 이하 / 전주보다 ↑ / ↓' 네 칸에 숫자만 있었다.
  // 무엇의 몇 곳인지가 안 적혀 있어서 뜻이 안 읽혔다. 문장으로 적고
  // 분모(전체 몇 곳)를 같이 보여 준다.
  Widget _summaryLines(OvertimeWeek w) {
    final avg = _avgOf(w);
    var over = 0, up = 0, rated = 0;
    for (final it in w.items) {
      final v = it.rateOf(_kind, _scope);
      if (v == null) continue;
      rated++;
      if (avg != null && v > avg) over++;
      final d = it.deltaOf(_kind, _scope);
      if (d != null && d > 0) up++;
    }
    final label = _kind == 'special' ? '특근률' : '잔업률';
    return _card(
      child: Column(
        children: [
          _summaryLine('$label이 전사 평균(${ovPct(avg)})보다 높은 곳', over, rated),
          const SizedBox(height: 11),
          _summaryLine(
              w.prevLabel.isEmpty ? '지난주보다 오른 곳' : '${w.prevLabel}보다 오른 곳',
              up,
              rated),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, int n, int of) {
    final frac = of <= 0 ? 0.0 : (n / of).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.caption
                      .copyWith(fontSize: 12, color: AppColors.textSub)),
            ),
            const SizedBox(width: 8),
            Text('$n',
                style: AppText.bodyStrong.copyWith(
                    fontSize: 16, color: AppColors.textMain, height: 1.1)),
            Text(' / $of곳',
                style: AppText.caption
                    .copyWith(fontSize: 11, color: AppColors.textMute)),
          ],
        ),
        const SizedBox(height: 5),
        _bar(frac, _tone.withValues(alpha: .55), 6),
      ],
    );
  }

  // ── 사업부 순위 ─────────────────────────────────────────
  Widget _ranking(OvertimeWeek w) {
    final avg = _avgOf(w);
    final items = List<OvItem>.from(w.items);
    int cmp(double? x, double? y) {
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    }

    items.sort((a, b) => _sort == _Sort.delta
        ? cmp(a.deltaOf(_kind, _scope), b.deltaOf(_kind, _scope))
        : cmp(a.rateOf(_kind, _scope), b.rateOf(_kind, _scope)));

    var max = 0.0;
    for (final it in items) {
      final v = it.rateOf(_kind, _scope) ?? 0;
      if (v > max) max = v;
    }
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
                _sortChip('높은 순', _Sort.value),
                const SizedBox(width: 5),
                _sortChip('많이 오른 순', _Sort.delta),
              ],
            ),
          ),
          for (final it in items) _rankRow(w, it, scale, avg),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Text(
              '세로 선 = 전사 평균 ${ovPct(avg)} · 진한 막대는 평균보다 높은 곳',
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
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sort = s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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

  Widget _rankRow(OvertimeWeek w, OvItem it, double scale, double? avg) {
    final rate = it.rateOf(_kind, _scope);
    final delta = it.deltaOf(_kind, _scope);
    final over = rate != null && avg != null && rate > avg;
    final frac = ((rate ?? 0) / scale).clamp(0.0, 1.0);
    final avgFrac = avg == null ? null : (avg / scale).clamp(0.0, 1.0);
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
              child: Text(it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.captionStrong.copyWith(
                      fontSize: 11.5,
                      color: over ? AppColors.textMain : AppColors.textSub)),
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
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: frac),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, _) => FractionallySizedBox(
                        widthFactor: t,
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                over ? _tone : _tone.withValues(alpha: .28),
                            borderRadius: BorderRadius.circular(6),
                          ),
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
                  Text(ovPct(rate),
                      style: AppText.captionStrong
                          .copyWith(fontSize: 11.5, color: AppColors.textMain)),
                  if (delta != null)
                    Text(ovDelta(delta),
                        style: AppText.caption.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: ovDeltaColor(delta))),
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
