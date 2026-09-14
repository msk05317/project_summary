// 자동차사업부 제품 화면 (앱)
//
// 경영진이 폰에서 열었을 때 먼저 답해야 하는 건 둘이다.
//   "얼마 벌기로 돼 있나"  → 연도별 계약 매출
//   "어디가 적자인가"      → 원가율이 100% 를 넘는 제품
// 그래서 위에 그 둘을 두고, 원가 구성 다섯 항목은 제품을 눌렀을 때 편다.
// 폰 너비에서 5단 막대를 목록마다 그리면 글자가 못 들어간다.
//
// 숫자는 서버(/projects/{key}/automotive-summary)가 계산한 걸 그대로 쓴다.
// 앱에서 다시 더하면 Admin 과 갈릴 수 있다.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../design/design.dart';

/// 원가 5항목 색 — OneView 가 이미 쓰는 카테고리 팔레트에서 고른 다섯.
///
/// 순서는 고정이다. 제품이 바뀌어도 재료비는 항상 같은 색이다.
/// 상태색(초록·빨강)은 빼뒀다. 원가율 표시와 겹치면 읽는 사람이 헷갈린다.
/// 색만으로 구분하게 두지 않는다 — 범례를 늘 띄우고, 큰 두 항목은 값을 직접 적고,
/// 조각 사이를 2px 띄운다.
const List<(String, String, Color)> kAutoCost = [
  ('material', '재료비', Color(0xFF1D4ED8)),
  ('process', '공정비', Color(0xFFB45309)),
  ('admin', '관리이윤', Color(0xFF9333EA)),
  ('depr', '감가상각', Color(0xFF4D7C0F)),
  ('logi', '물류', Color(0xFFBE185D)),
];

String _man(num v) {
  // 억원은 소수 한 자리, 그 아래는 정수
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _comma(num v) {
  final s = v.round().toString();
  return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

class AutomotiveOverviewCard extends StatefulWidget {
  final String projectKey;
  const AutomotiveOverviewCard({super.key, required this.projectKey});

  @override
  State<AutomotiveOverviewCard> createState() => _AutomotiveOverviewCardState();
}

class _AutomotiveOverviewCardState extends State<AutomotiveOverviewCard> {
  Map<String, dynamic>? _d;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uri = Uri.parse(
          '$kApiBaseUrl/projects/${Uri.encodeComponent(widget.projectKey)}/automotive-summary');
      final r = await http.get(uri);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (mounted) setState(() => _d = j);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) return _box(Text('불러오지 못했습니다', style: AppText.caption));
    if (_d == null) {
      return _box(const SizedBox(
          height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final products = (_d!['products'] as List?) ?? [];
    if (products.isEmpty) {
      return _box(Text('등록된 제품이 없습니다', style: AppText.caption));
    }
    final t = (_d!['totals'] as Map?) ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpiRow(t),
        const SizedBox(height: 12),
        _revenueChart(),
        const SizedBox(height: 12),
        _ratioList(products, t),
      ],
    );
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: child,
      );

  // ── KPI 줄 ──────────────────────────────────────────────────────
  // 숫자 셋뿐이라 차트가 아니라 타일이 맞다.
  Widget _kpiRow(Map t) {
    final over = (t['over_cost'] as num?)?.toInt() ?? 0;
    return _box(Row(
      children: [
        _kpi('계약 물량', _comma(t['qty'] ?? 0), 'EA'),
        _sep(),
        _kpi('계약 매출', _man(t['revenue'] ?? 0), '억원'),
        _sep(),
        _kpi('원가 ≥ 판가', '$over', '종',
            tone: over > 0 ? AppColors.statusRed : null),
      ],
    ));
  }

  Widget _sep() => Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.dividerSoft);

  Widget _kpi(String label, String value, String unit, {Color? tone}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption.copyWith(color: AppColors.textMute)),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.h2.copyWith(
                          color: tone ?? AppColors.textMain,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 2),
                Text(unit,
                    style: AppText.caption.copyWith(color: AppColors.textHint)),
              ],
            ),
          ],
        ),
      );

  // ── 연도별 계약 매출 ────────────────────────────────────────────
  // 한 갈래뿐이라 범례가 필요 없다. 제목이 곧 이름이다.
  Widget _revenueChart() {
    final years = ((_d!['years'] as List?) ?? []).cast<String>();
    final byYear = (_d!['by_year'] as Map?) ?? {};
    final vals = [
      for (final y in years) ((byYear[y] ?? {})['revenue'] as num?)?.toDouble() ?? 0.0
    ];
    final maxV = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return const SizedBox.shrink();
    final peak = vals.indexOf(maxV);

    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('연도별 계약 매출', style: AppText.bodyStrong),
        Text('억원', style: AppText.caption.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 14),
        SizedBox(
          height: 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < years.length; i++)
                Expanded(
                  child: Padding(
                    // 막대 사이 2px (양쪽 1px)
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 값은 모든 막대에 적지 않는다. 가장 큰 해만 짚는다.
                        if (i == peak)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(_man(vals[i]),
                                style: AppText.caption.copyWith(
                                    color: AppColors.textMain,
                                    fontWeight: FontWeight.w800)),
                          ),
                        Container(
                          height: (vals[i] / maxV * 86).clamp(2.0, 86.0),
                          decoration: BoxDecoration(
                            color: i == peak
                                ? AppColors.headerNavy
                                : AppColors.todayBlue.withValues(alpha: 0.55),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(years[i].substring(2),
                            style: AppText.caption
                                .copyWith(color: AppColors.textMute, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ));
  }

  // ── 제품별 원가율 ───────────────────────────────────────────────
  // 100% 가 기준선이다. 넘으면 팔수록 손해다.
  // 색만으로 알리지 않는다 — 넘은 제품엔 '원가 초과' 글자를 같이 붙인다.
  Widget _ratioList(List products, Map t) {
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('제품별 원가율', style: AppText.bodyStrong),
        Text('원가 ÷ 판가 · 100% 를 넘으면 팔수록 손해입니다',
            style: AppText.caption.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 12),
        for (final p in products) _ratioRow(p as Map<String, dynamic>),
      ],
    ));
  }

  Widget _ratioRow(Map<String, dynamic> p) {
    final ratio = (p['cost_ratio'] as num?)?.toDouble();
    final over = ratio != null && ratio >= 1;
    final color = ratio == null
        ? AppColors.statusGray
        : over
            ? AppColors.statusRed
            : (ratio >= 0.9 ? AppColors.summaryCaution : AppColors.summaryNormal);
    // 100% 를 막대의 3분의 2 자리에 둔다. 넘는 값도 끝까지 차지 않고 보인다.
    final w = ratio == null ? 0.0 : (ratio / 1.5).clamp(0.0, 1.0);

    return InkWell(
      onTap: () => _openDetail(p),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (over) ...[
                  Text('원가 초과',
                      style: AppText.caption.copyWith(
                          color: AppColors.statusRed, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                ],
                Text(ratio == null ? '판가 없음' : '${(ratio * 100).toStringAsFixed(0)}%',
                    style: AppText.bodyStrong.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 5),
            LayoutBuilder(builder: (ctx, c) {
              final full = c.maxWidth;
              return Stack(children: [
                Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.statusGraySoft,
                        borderRadius: BorderRadius.circular(3))),
                Container(
                    height: 6,
                    width: full * w,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3))),
                // 100% 기준선
                Positioned(
                    left: full * (1 / 1.5),
                    child: Container(
                        width: 1.5, height: 6, color: AppColors.textHint)),
              ]);
            }),
          ],
        ),
      ),
    );
  }

  // ── 제품 상세 (원가 구성) ───────────────────────────────────────
  void _openDetail(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _AutoDetailSheet(p: p, years: ((_d!['years'] as List?) ?? []).cast<String>()),
    );
  }
}

class _AutoDetailSheet extends StatelessWidget {
  final Map<String, dynamic> p;
  final List<String> years;
  const _AutoDetailSheet({required this.p, required this.years});

  @override
  Widget build(BuildContext context) {
    final cost = (p['cost'] as Map?) ?? {};
    final total = (p['cost_total'] as num?)?.toDouble() ?? 0;
    final ratio = (p['cost_ratio'] as num?)?.toDouble();
    final parts = [
      for (final c in kAutoCost)
        (c.$2, ((cost[c.$1] as num?)?.toDouble() ?? 0), c.$3)
    ].where((e) => e.$2 > 0).toList();
    // 큰 두 항목만 값을 직접 적는다. 나머지는 범례가 받는다.
    final ranked = [...parts]..sort((a, b) => b.$2.compareTo(a.$2));
    final labelled = ranked.take(2).map((e) => e.$1).toSet();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.borderDefault,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Text(p['name'] ?? '', style: AppText.h2),
              const SizedBox(height: 2),
              Text([
                if ((p['end_customer'] ?? '').toString().isNotEmpty) p['end_customer'],
                if ((p['car_model'] ?? '').toString().isNotEmpty) p['car_model'],
                if ((p['site'] ?? '').toString().isNotEmpty)
                  p['site'].toString().replaceAll('\n', ' '),
              ].join(' · '), style: AppText.caption.copyWith(color: AppColors.textMute)),
              const SizedBox(height: 16),

              if (total > 0) ...[
                Row(children: [
                  Text('원가 구성', style: AppText.bodyStrong),
                  const Spacer(),
                  Text('${_comma(total)}원', style: AppText.bodyStrong),
                ]),
                const SizedBox(height: 2),
                Text(
                    ratio == null
                        ? '판가가 없어 원가율은 낼 수 없습니다'
                        : '판가 ${_comma((p['price'] as num?) ?? 0)}원 · 원가율 ${(ratio * 100).toStringAsFixed(1)}%',
                    style: AppText.caption.copyWith(color: AppColors.textMute)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      for (var i = 0; i < parts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2), // 조각 사이 2px
                        Expanded(
                          flex: (parts[i].$2 / total * 1000).round().clamp(1, 1000),
                          child: Container(
                            decoration: BoxDecoration(
                                color: parts[i].$3,
                                borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final e in parts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: e.$3, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e.$1, style: AppText.body)),
                      Text('${(e.$2 / total * 100).toStringAsFixed(1)}%',
                          style: AppText.caption.copyWith(
                              color: AppColors.textMute,
                              fontWeight: labelled.contains(e.$1)
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 76,
                        child: Text(_comma(e.$2),
                            textAlign: TextAlign.right,
                            style: AppText.body.copyWith(
                                fontWeight: labelled.contains(e.$1)
                                    ? FontWeight.w800
                                    : FontWeight.w500)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),
              ],

              Text('연도별 계약', style: AppText.bodyStrong),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {
                  0: FixedColumnWidth(56),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
                children: [
                  TableRow(children: [
                    _th('연도'), _th('물량', right: true), _th('매출(억)', right: true),
                  ]),
                  for (final y in years)
                    TableRow(children: [
                      _td(y),
                      _td(_comma(((p['contract'] ?? {})[y] ?? {})['qty'] ?? 0),
                          right: true),
                      _td(_man(((p['contract'] ?? {})[y] ?? {})['revenue'] ?? 0),
                          right: true),
                    ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(String s, {bool right = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(s,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: AppText.caption.copyWith(
                color: AppColors.textHint, fontWeight: FontWeight.w700)),
      );

  Widget _td(String s, {bool right = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(s,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: AppText.body),
      );
}
