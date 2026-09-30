// 홈 · 전사 잔·특근 카드.
//
// 첫 화면 구조는 건드리지 않고 매출 카드 밑에 한 장만 얹는다. 16개
// 사업부짜리 자료라 홈의 '전체 현황'(반도체) 과 범위가 달라서, 제목에
// '전사업부' 를 박아 같은 화면에서 '전체' 의 뜻이 둘이 되지 않게 한다.
//
// 껍데기는 다른 홈 카드(ExecRevenueCard)와 같다 — 흰 바탕, radius lg,
// 패딩 16. 전에는 혼자 회색 바탕에 다른 반경이라 홈에서 튀었다.
//
// 잔업률과 특근률은 한 숫자로 못 합친다. 좌우로 나누고 가운데 가는 선을
// 둔다. 숫자 밑 게이지는 '69.9% 가 얼마나 높은가' 를 읽게 해 준다 —
// 퍼센트만 있으면 크고 작음이 안 잡힌다.
import 'package:flutter/material.dart';

import '../design/design.dart';
import '../models/overtime.dart';

class OvertimeHomeCard extends StatelessWidget {
  final OvertimeWeek week;
  final bool loading;
  final VoidCallback onTap;

  const OvertimeHomeCard({
    super.key,
    required this.week,
    required this.loading,
    required this.onTap,
  });

  static const Color _ot = Color(0xFF2A78D6);   // 잔업
  static const Color _sp = Color(0xFFEB6834);   // 특근

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _shell(
        child: SizedBox(
          height: 92,
          child: Center(
            child: Text('불러오는 중…',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          ),
        ),
      );
    }

    final t = week.total;
    final avail = t.available.total;

    return _shell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('전사업부 잔·특근',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.h2),
              ),
              const SizedBox(width: 8),
              Text(
                [
                  if (week.weekLabel.isNotEmpty) week.weekLabel,
                  if (week.range.isNotEmpty) week.range,
                ].join(' · '),
                style: AppText.caption
                    .copyWith(fontSize: 11.5, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _metric('잔업', t.overtime.range.isEmpty ? '월~토' : t.overtime.range,
                      t.overtime.rate.total, week.deltaOf('overtime'), _ot),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.borderSoft,
                ),
                Expanded(
                  child: _metric('특근', t.special.range.isEmpty ? '일' : t.special.range,
                      t.special.rate.total, week.deltaOf('special'), _sp),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.borderSoft),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (avail != null) '가용 ${_comma(avail)}명',
                    '${week.counts.divisions}개 사업부',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption
                      .copyWith(fontSize: 12, color: AppColors.textMute),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMute),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(
      String label, String range, double? rate, double? delta, Color color) {
    final v = (rate ?? 0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.captionStrong
                    .copyWith(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textHint)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              rate == null ? '—' : (rate * 100).toStringAsFixed(1),
              style: AppText.h1.copyWith(
                  fontSize: 27, height: 1.05, color: AppColors.textMain),
            ),
            Text('%',
                style: AppText.bodyStrong
                    .copyWith(fontSize: 13, color: AppColors.textMute)),
            if (delta != null && delta.abs() >= 0.0005) ...[
              const SizedBox(width: 6),
              Text(
                '${delta > 0 ? '▲' : '▼'}${(delta.abs() * 100).toStringAsFixed(1)}%',
                style: AppText.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: delta > 0
                        ? AppColors.statusRed
                        : AppColors.statusGreen),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: v),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => LinearProgressIndicator(
              value: t,
              minHeight: 5,
              backgroundColor: const Color(0xFFEDF0F4),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  static String _comma(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  Widget _shell({required Widget child, VoidCallback? onTap}) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: box,
    );
  }
}
