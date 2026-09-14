// 자동차사업부 화면 최상단 네이비 카드.
//
// 반도체 화면(DivisionRevenueHero)과 같은 모양을 쓴다. 같은 앱에서 사업부만
// 바뀌었는데 첫 블록이 달라 보이면 읽는 사람이 매번 다시 배워야 한다.
// 다른 건 안에 들어가는 값뿐이다.
//   반도체 : 이번 달 실적 / 계획 매출
//   자동차 : 올해 계약 매출 / 전체 계약 매출 (연 단위 계약이라 월 실적이 없다)
import 'package:flutter/material.dart';

import '../../design/design.dart';

class AutomotiveHeroCard extends StatelessWidget {
  final String title;       // '계약 매출  2026년 / 전체'
  final String rightLabel;  // '2026–2031 · 6년'
  final String bigValue;    // '305.2억'
  final String subValue;    // '/ 2,651.9억'
  final String pillText;    // '올해 12%'
  final Color pillColor;
  final double ratio;       // 0~1
  final Color barColor;

  /// 게이지가 뜻하는 게 없는 화면(제품 상세)에서는 끈다.
  /// 뜻 없는 막대를 그려 두면 읽는 사람이 뜻을 찾는다.
  final bool showBar;
  final String leftLabel;
  final String leftValue;
  final String rightStatLabel;
  final String rightStatValue;
  final bool loading;
  final bool loaded;
  final String emptyText;
  final VoidCallback? onTap;

  const AutomotiveHeroCard({
    super.key,
    required this.title,
    required this.rightLabel,
    required this.bigValue,
    required this.subValue,
    required this.pillText,
    required this.pillColor,
    required this.ratio,
    required this.barColor,
    this.showBar = true,
    required this.leftLabel,
    required this.leftValue,
    required this.rightStatLabel,
    required this.rightStatValue,
    this.loading = false,
    this.loaded = true,
    this.emptyText = '등록된 계약이 없습니다',
    this.onTap,
  });

  static const Color label = Color(0xFF93A9BE);
  static const Color labelStrong = Color(0xFFD7E2ED);

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: loading ? const _Skeleton() : _body(),
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: box,
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: labelStrong,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(rightLabel,
                style: const TextStyle(fontSize: 11, color: label)),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, size: 16, color: label),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (!loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 17, color: label),
                SizedBox(width: 8),
                Text('계약 현황을 불러오지 못했습니다',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: label)),
              ],
            ),
          )
        else if (bigValue.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(emptyText,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: label)),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          bigValue,
                          style: const TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                    if (subValue.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          subValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: label,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (pillText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pillText,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showBar) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _Stat(label: leftLabel, value: leftValue)),
            Container(
              width: 1,
              height: 26,
              color: Colors.white.withValues(alpha: 0.16),
            ),
            Expanded(
              child: _Stat(
                  label: rightStatLabel,
                  value: rightStatValue,
                  padLeft: true),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool padLeft;

  const _Stat({required this.label, required this.value, this.padLeft = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: padLeft ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AutomotiveHeroCard.label,
              )),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              )),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(120, 13),
        const SizedBox(height: 12),
        bar(180, 28),
        const SizedBox(height: 14),
        bar(double.infinity, 6),
        const SizedBox(height: 16),
        bar(150, 14),
      ],
    );
  }
}
