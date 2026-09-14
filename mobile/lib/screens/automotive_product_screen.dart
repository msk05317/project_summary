// 자동차사업부 제품 한 건 (앱).
//
// 고객사 화면에서 제품 줄을 누르면 여기로 온다. 여기서 답해야 하는 건 셋이다.
//   "이 제품 남나"     → 대당 판가 · 원가 · 손익
//   "어디서 새나"      → 원가 다섯 덩어리
//   "언제 얼마 나가나" → 연도별 계약
//
// 계산은 서버가 이미 해 놨다. 여기서는 그대로 그리기만 한다.
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/automotive.dart';
import '../components/division/automotive_hero_card.dart';
import '../widgets/automotive_overview_card.dart' show kAutoPriceParts;

class AutomotiveProductScreen extends StatelessWidget {
  final AutoProduct product;
  final String projectLabel;

  const AutomotiveProductScreen({
    super.key,
    required this.product,
    this.projectLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final p = product;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(p.name, style: AppText.bodyStrong.copyWith(fontSize: 17)),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
        bottom: projectLabel.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '목록 > 자동차사업부 > $projectLabel > ${p.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                        fontSize: 11, color: const Color(0xFF7C8594)),
                  ),
                ),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AutomotiveHeroCard(
            title: '대당 판가',
            rightLabel: _headLine(p),
            bigValue: AutoFmt.won(p.price),
            subValue: '',
            pillText: p.group,
            pillColor: p.group == '개발'
                ? AppColors.summaryCaution
                : AppColors.todayBlue,
            showBar: false,
            ratio: 0,
            barColor: AppColors.todayBlue,
            leftLabel: '계약 물량',
            leftValue: '${AutoFmt.comma(p.qtyTotal)}대',
            rightStatLabel: '계약 매출',
            rightStatValue: AutoFmt.eok(p.revenueTotal),
          ),
          const SizedBox(height: 10),
          _PriceCard(product: p),
          const SizedBox(height: 10),
          _ContractCard(product: p),
          const SizedBox(height: 10),
          _SpecCard(product: p),
        ],
      ),
    );
  }

  String _headLine(AutoProduct p) {
    final parts = <String>[
      if (p.endCustomer.isNotEmpty) p.endCustomer,
      if (p.carModel.isNotEmpty) p.carModel,
      if (p.sop.isNotEmpty) '${p.sop} SOP',
    ];
    return parts.join(' · ');
  }
}

/// 판가를 이루는 다섯 덩어리. 조각 사이를 2px 띄우고 범례에 값을 적는다 —
/// 색만으로 구분하게 두지 않는다.
class _PriceCard extends StatelessWidget {
  final AutoProduct product;
  const _PriceCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final items = <(String, String, Color, int)>[];
    for (final (key, label, color) in kAutoPriceParts) {
      final v = p.parts[key] ?? 0;
      if (v > 0) items.add((key, label, color, v));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return _Card(
      title: '판가 구성',
      trailing: '합계 ${AutoFmt.won(p.price)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: items[i].$4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: items[i].$3,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: it.$3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(it.$2,
                      style: AppText.caption.copyWith(
                          fontSize: 12.5, color: AppColors.textMute)),
                  const Spacer(),
                  Text(AutoFmt.won(it.$4),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 38,
                    child: Text(
                      p.price > 0 ? '${(it.$4 * 100 / p.price).round()}%' : '-',
                      textAlign: TextAlign.right,
                      style: AppText.caption.copyWith(
                          fontSize: 12, color: AppColors.textHint),
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

class _ContractCard extends StatelessWidget {
  final AutoProduct product;
  const _ContractCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final years = product.contract.keys.toList()..sort();
    if (years.isEmpty) return const SizedBox.shrink();

    Widget row(String a, String b, String c,
        {bool head = false, bool sum = false}) {
      final style = TextStyle(
        fontSize: head ? 11 : 12.5,
        fontWeight: sum ? FontWeight.w800 : FontWeight.w600,
        color: head ? AppColors.textHint : AppColors.textMain,
      );
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            // 합계 줄은 위에만 선을 긋는다. 아래에도 그으면 카드 끝과 겹친다.
            bottom: sum
                ? BorderSide.none
                : BorderSide(
                    color:
                        head ? AppColors.borderDefault : AppColors.dividerSoft,
                  ),
            top: sum
                ? const BorderSide(color: AppColors.borderDefault)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 66,
              child: Text(a,
                  style: style.copyWith(
                      color: head || sum
                          ? style.color
                          : AppColors.textMute)),
            ),
            Expanded(child: Text(b, textAlign: TextAlign.right, style: style)),
            SizedBox(
                width: 82,
                child:
                    Text(c, textAlign: TextAlign.right, style: style)),
          ],
        ),
      );
    }

    return _Card(
      title: '연도별 계약',
      trailing: '매출 단위 억원',
      child: Column(
        children: [
          row('연도', '물량', '매출', head: true),
          for (final y in years)
            row(y, AutoFmt.comma(product.contract[y]!.qty),
                product.contract[y]!.revenue.toStringAsFixed(1)),
          row('합계', AutoFmt.comma(product.qtyTotal),
              product.revenueTotal.toStringAsFixed(1),
              sum: true),
        ],
      ),
    );
  }
}

class _SpecCard extends StatelessWidget {
  final AutoProduct product;
  const _SpecCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    // 엑셀에 있는 것만 적는다. 없는 값을 채워 넣으면 그게 사실처럼 읽힌다.
    // (계약 통화는 엑셀에 열이 없어서 뺐다 — 환율만 보고 찍던 값이었다)
    final rows = <(String, String)>[
      if (p.site.isNotEmpty) ('납품 위치', p.site),
      if (p.method.isNotEmpty) ('공법', p.method),
      if (p.sop.isNotEmpty) ('양산 시작 (SOP)', p.sop),
      if (p.weightKg > 0) ('제품 중량', '${p.weightKg} kg'),
      if (p.tonnage > 0) ('주조톤수', '${AutoFmt.comma(p.tonnage)} ton'),
      if (p.defectRate > 0) ('불량률', AutoFmt.ratio(p.defectRate)),
      // 엑셀 '판가' 열. 판가(다섯 항목 합계)와 다른 값이라 참고로만 적는다.
      if (p.quote > 0)
        ('외화 견적 (참고)',
            p.quoteFx != null && p.quoteRate != null
                ? '${p.quoteFx} × ${AutoFmt.comma(p.quoteRate!)} = ${AutoFmt.won(p.quote)}'
                : AutoFmt.won(p.quote)),
      ('구분', p.group),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _Card(
      title: '제품 정보',
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이름 칸을 고정해야 값이 한 줄로 선다.
                  // Spacer 와 Flexible 을 같이 두면 둘 다 flex 라 남는 폭을
                  // 반씩 나눠 갖고, 값이 줄마다 다른 자리에서 시작한다.
                  SizedBox(
                    width: 112,
                    child: Text(r.$1,
                        style: AppText.caption.copyWith(
                            fontSize: 12.5, color: AppColors.textMute)),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain),
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

class _Card extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;

  const _Card({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
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
              Text(title,
                  style: AppText.bodyStrong
                      .copyWith(fontSize: 13.5, color: AppColors.textMain)),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                    style: AppText.caption
                        .copyWith(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
