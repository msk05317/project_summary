// 자동차사업부 고객사 화면 (앱).
//
// 반도체 사업부 화면과 같은 순서로 읽히게 맞췄다.
//   네이비 요약 카드 → (경고띠) → 그림 한 장 → 목록
// 경영진이 폰에서 먼저 답을 얻어야 하는 건 둘이다.
//   "얼마 벌기로 돼 있나" → 연도별 계약 매출
//   "어디가 적자인가"     → 원가가 판가를 넘는 제품
//
// 숫자는 서버(/projects/{key}/automotive-summary)가 계산한 걸 그대로 쓴다.
// 앱에서 다시 더하면 Admin 과 갈릴 수 있다.
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/automotive.dart';
import '../services/automotive_service.dart';
import '../components/division/automotive_hero_card.dart';
import '../components/division/automotive_row_card.dart';
import '../screens/automotive_product_screen.dart';

/// 원가 5항목 색 — OneView 카테고리 팔레트에서 고른 다섯. 순서는 고정이다.
/// 제품이 바뀌어도 재료비는 늘 같은 색이다. 상태색(초록·빨강)은 뺐다 —
/// 원가율 표시와 겹치면 읽는 사람이 헷갈린다.
/// 색만으로 구분하게 두지 않는다: 범례를 늘 띄우고, 큰 두 항목은 값을 적고,
/// 조각 사이를 2px 띄운다.
const List<(String, String, Color)> kAutoCost = [
  ('material', '재료비', Color(0xFF1D4ED8)),
  ('process', '공정비', Color(0xFFB45309)),
  ('admin', '관리이윤', Color(0xFF9333EA)),
  ('depr', '감가상각', Color(0xFF4D7C0F)),
  ('logi', '물류', Color(0xFFBE185D)),
];

class AutomotiveOverviewCard extends StatefulWidget {
  final String projectKey;
  final String projectName;

  const AutomotiveOverviewCard({
    super.key,
    required this.projectKey,
    this.projectName = '',
  });

  @override
  State<AutomotiveOverviewCard> createState() => _AutomotiveOverviewCardState();
}

class _AutomotiveOverviewCardState extends State<AutomotiveOverviewCard> {
  AutoProjectSummary _s = AutoProjectSummary.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AutomotiveService.project(widget.projectKey);
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  int get _year => DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: AutomotiveHeroCard(
          title: '계약 매출',
          rightLabel: '',
          bigValue: '',
          subValue: '',
          pillText: '',
          pillColor: AppColors.summaryCaution,
          ratio: 0,
          barColor: AppColors.summaryCaution,
          leftLabel: '',
          leftValue: '',
          rightStatLabel: '',
          rightStatValue: '',
          loading: true,
        ),
      );
    }

    final cell = s.yearCell(_year);
    final yearRev = cell?.revenue ?? 0;
    final yearQty = cell?.qty ?? 0;
    final y = s.years;
    final span = y.isEmpty ? '' : '${y.first}–${y.last} · ${y.length}년';
    final has = s.revenue > 0;
    final over = s.overCost > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AutomotiveHeroCard(
          title: '계약 매출  $_year년 / 전체',
          rightLabel: span,
          bigValue: has ? AutoFmt.eok(yearRev) : '',
          subValue: has ? '/ ${AutoFmt.eok(s.revenue)}' : '',
          pillText: !has
              ? ''
              : (over ? '원가 초과 ${s.overCost}종' : '올해 ${_pct(yearRev, s.revenue)}%'),
          pillColor: over ? AppColors.statusRed : AppColors.summaryCaution,
          ratio: s.revenue > 0 ? yearRev / s.revenue : 0,
          barColor: over ? AppColors.summaryCaution : AppColors.todayBlue,
          leftLabel: '계약 물량 ($_year → 전체)',
          leftValue: has
              ? '${AutoFmt.qtyShort(yearQty, unit: '')} → ${AutoFmt.qtyShort(s.qty)}'
              : '-',
          rightStatLabel: '제품',
          rightStatValue: s.products.isEmpty
              ? '없음'
              : [
                  if (s.mass > 0) '양산 ${s.mass}종',
                  if (s.dev > 0) '개발 ${s.dev}종',
                ].join(' · '),
          loaded: s.loaded,
          emptyText: '등록된 계약이 없습니다',
        ),
        if (s.products.isEmpty) ...[
          const SizedBox(height: 10),
          _Note(s.loaded ? '등록된 제품이 없습니다' : '불러오지 못했습니다'),
        ] else ...[
          if (over) ...[
            const SizedBox(height: 10),
            AutomotiveWarnStrip(count: s.overCost, names: s.overCostNames),
          ],
          if (y.isNotEmpty) ...[
            const SizedBox(height: 10),
            _YearChart(years: y, byYear: s.byYear),
          ],
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('제품',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 14, color: AppColors.headerNavy)),
              const SizedBox(width: 8),
              Text('계약 매출순 · ${s.products.length}종',
                  style: AppText.caption
                      .copyWith(fontSize: 11.5, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in s.products) ...[
            _productRow(p, s),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  int _pct(num part, num whole) =>
      whole > 0 ? (part * 100 / whole).round() : 0;

  Widget _productRow(AutoProduct p, AutoProjectSummary s) {
    final over = p.overCost;
    final accent = p.price <= 0
        ? AppColors.statusGray
        : (over ? AppColors.summaryCaution : AppColors.todayBlue);
    final badge = [p.endCustomer, p.carModel]
        .where((e) => e.isNotEmpty)
        .join(' ');
    return AutomotiveRowCard(
      dotColor: accent,
      name: p.name,
      badge: badge,
      value: AutoFmt.eok(p.revenueTotal),
      subValue: '/ ${AutoFmt.qtyShort(p.qtyTotal)}',
      ratio: s.revenue > 0 ? p.revenueTotal / s.revenue : 0,
      barColor: accent,
      meta1: p.price > 0 ? '판가 ${AutoFmt.won(p.price)}' : '판가 미등록',
      meta2: '원가 ${AutoFmt.won(p.costTotal)}',
      trailing: p.costRatio == null
          ? '원가율 -'
          : '원가율 ${AutoFmt.pct(p.costRatio)}',
      trailingColor: over ? AppColors.statusRed : null,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AutomotiveProductScreen(
              product: p,
              projectLabel:
                  widget.projectName.isNotEmpty ? widget.projectName : s.label,
            ),
          ),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        alignment: Alignment.center,
        child: Text(text,
            style:
                AppText.caption.copyWith(fontSize: 12, color: AppColors.textHint)),
      );
}

/// 연도별 계약 매출. 한 계열뿐이라 범례는 두지 않고 제목이 계열 이름이다.
/// 값은 가장 큰 해에만 적는다 — 막대마다 숫자를 붙이면 그림이 표가 된다.
class _YearChart extends StatelessWidget {
  final List<String> years;
  final Map<String, AutoYearCell> byYear;

  const _YearChart({required this.years, required this.byYear});

  @override
  Widget build(BuildContext context) {
    double max = 0;
    String peak = '';
    for (final y in years) {
      final v = byYear[y]?.revenue ?? 0;
      if (v > max) {
        max = v;
        peak = y;
      }
    }
    if (max <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('연도별 계약 매출',
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13.5, color: AppColors.textMain)),
              const Spacer(),
              Text('단위 억원',
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final y in years)
                  Expanded(
                    child: _Bar(
                      year: y,
                      value: byYear[y]?.revenue ?? 0,
                      max: max,
                      peak: y == peak,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String year;
  final double value;
  final double max;
  final bool peak;

  const _Bar({
    required this.year,
    required this.value,
    required this.max,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final h = max <= 0 ? 0.0 : (value / max) * 96;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (peak)
            Text(
              value.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.headerNavy,
              ),
            ),
          if (peak) const SizedBox(height: 5),
          Container(
            height: h < 2 && value > 0 ? 2 : h,
            decoration: BoxDecoration(
              color: peak
                  ? AppColors.headerNavy
                  : AppColors.todayBlue.withValues(alpha: 0.55),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              year,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: peak ? FontWeight.w700 : FontWeight.w500,
                color: peak ? AppColors.textSub : AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
