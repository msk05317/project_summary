// 홈 · 전사 잔·특근 카드.
//
// 첫 화면 구조는 건드리지 않고 매출 카드 밑에 한 장만 얹는다. 16개
// 사업부짜리 자료라 홈의 '전체 현황'(반도체) 과 범위가 달라서, 제목 옆에
// '전사업부' 를 붙여 같은 화면에서 '전체' 의 뜻이 둘이 되지 않게 한다.
//
// 잔업률과 특근률은 한 숫자로 못 합친다. 나란히 둔다.
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

  String _pc(double? v) =>
      v == null ? '—' : (v * 100).toStringAsFixed(1);

  String _delta(double? v) {
    if (v == null) return '';
    final p = (v * 100);
    if (p.abs() < 0.05) return '전주와 같음';
    return '${p > 0 ? '▲' : '▼'} ${p.abs().toStringAsFixed(1)}%p';
  }

  Color _deltaColor(double? v) {
    if (v == null || v.abs() < 0.0005) return AppColors.textHint;
    return v > 0 ? AppColors.statusRed : AppColors.statusGreen;
  }

  Widget _metric(String label, String range, double? rate, double? delta,
      Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ($range)',
            style: AppText.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _pc(rate),
                style: AppText.h1.copyWith(
                  fontSize: 25,
                  height: 1.1,
                  color: AppColors.textMain,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '%',
                style: AppText.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            _delta(delta),
            style: AppText.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _deltaColor(delta),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _shell(
        child: SizedBox(
          height: 96,
          child: Center(
            child: Text('불러오는 중…',
                style: AppText.caption.copyWith(color: AppColors.textHint)),
          ),
        ),
      );
    }

    final t = week.total;
    final avail = t.available.total;
    final attention = week.counts.attention;

    return _shell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('전사 잔·특근',
                  style: AppText.bodyStrong.copyWith(
                      fontSize: 13.5, color: AppColors.headerNavy)),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFD6E2F2)),
                ),
                child: Text('전사업부',
                    style: AppText.caption.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.headerNavy)),
              ),
              const Spacer(),
              Text(
                week.weekLabel.isEmpty
                    ? ''
                    : '${week.weekLabel}${week.range.isEmpty ? '' : ' · ${week.range}'}',
                style: AppText.caption
                    .copyWith(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metric('잔업률', t.overtime.range.isEmpty ? '월~토' : t.overtime.range,
                  t.overtime.rate.total, week.deltaOf('overtime'), _ot),
              const SizedBox(width: 12),
              _metric('특근률', t.special.range.isEmpty ? '일' : t.special.range,
                  t.special.rate.total, week.deltaOf('special'), _sp),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (avail != null) '가용 ${_comma(avail)}명',
              '${week.counts.divisions}개 사업부',
              if (week.counts.up > 0) '전주 대비 ${week.counts.up}곳 증가',
            ].join(' · '),
            style: AppText.caption
                .copyWith(fontSize: 11, color: AppColors.textMute),
          ),
          if (attention > 0) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Text(
                '⚠ 확인 필요 $attention건',
                style: AppText.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A3412)),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('탭하면 사업부별로',
                  style: AppText.caption
                      .copyWith(fontSize: 11, color: AppColors.textHint)),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded,
                  size: 15, color: AppColors.textHint),
            ],
          ),
        ],
      ),
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
    return Material(
      color: const Color(0xFFEFF4FB),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: const Color(0xFFD6E2F2)),
          ),
          child: child,
        ),
      ),
    );
  }
}
