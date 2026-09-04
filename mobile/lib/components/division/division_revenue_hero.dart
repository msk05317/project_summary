// 사업부 화면 최상단 매출 히어로 카드 (디자인 A).
//
// 경영진이 앱을 여는 이유는 순서가 정해져 있다.
//   "이번 달 얼마 나갔나" → "왜 그런가" → "누구 때문인가"
// 그래서 사업부 화면의 첫 블록은 진행률(%)이 아니라 이 달의 매출이다.
//
// 표시 내용
//  - 이번 달 실적 매출 (가장 크게) / 계획 매출 / 달성률
//  - 계획 대비 게이지
//  - 출하 계획 → 실적, 남은 영업일
// 탭하면 사업부로 좁힌 매출 상세 화면으로 들어간다.
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../utils/format.dart';

class DivisionRevenueHero extends StatelessWidget {
  final String month;          // '2026-09'
  final int revenue;           // 실적 매출
  final int planRevenue;       // 계획 매출
  final int qtyPlan;
  final int qtyActual;
  final String weekLabel;      // 'W36'
  final int? businessDaysLeft; // 이번 달이 아니면 null
  final bool loading;
  final bool loaded;           // false = 불러오지 못함 (0원과 구분해야 한다)
  final VoidCallback? onTap;

  const DivisionRevenueHero({
    super.key,
    required this.month,
    required this.revenue,
    required this.planRevenue,
    required this.qtyPlan,
    required this.qtyActual,
    required this.weekLabel,
    this.businessDaysLeft,
    this.loading = false,
    this.loaded = true,
    this.onTap,
  });

  // 네이비 위에 얹는 보조 색상. 본문 토큰(textMute 등)은 밝은 배경 기준이라
  // 그대로 쓰면 대비가 안 나와서 히어로 전용으로만 둔다.
  static const Color _label = Color(0xFF7E96B4);
  static const Color _labelStrong = Color(0xFFA8BBD1);
  static const Color _planText = Color(0xFF8FA6C0);

  bool get _hasRevenue => planRevenue > 0 || revenue > 0;

  /// '2026-09' 가 비어 있으면 이번 달로 본다 (아직 응답 전).
  String get _month {
    if (month.isNotEmpty) return month;
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  int? get _rate => planRevenue <= 0 ? null : (revenue * 100 / planRevenue).round();

  @override
  Widget build(BuildContext context) {
    if (loading) return const _HeroSkeleton();

    final rate = _rate;
    final ratio = rate == null ? 0.0 : (rate / 100).clamp(0.0, 1.0);
    final accent = rate == null
        ? AppColors.statusGray
        : (rate >= 100
            ? const Color(0xFF4ADE80)
            : (rate >= 80 ? const Color(0xFF7DD3FC) : AppColors.summaryCaution));

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${Fmt.monthShort(_month)} 매출',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _labelStrong,
              ),
            ),
            const SizedBox(width: 6),
            const Text('실적 / 계획',
                style: TextStyle(fontSize: 11, color: _label)),
            const Spacer(),
            Text(
              _todayLabel(),
              style: const TextStyle(fontSize: 11, color: _label),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right, size: 16, color: _label),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (!loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 17, color: _planText),
                SizedBox(width: 8),
                Text(
                  '매출 현황을 불러오지 못했습니다',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _planText,
                  ),
                ),
              ],
            ),
          )
        else if (!_hasRevenue)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '${Fmt.monthShort(_month)} 등록된 매출 계획이 없습니다',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _planText,
              ),
            ),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.money(revenue),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('/ ${Fmt.moneyShort(planRevenue)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _planText,
                  )),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rate == null ? '-' : '달성 $rate%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _HeroStat(
                label: '출하 (계획 → 실적)',
                value: '${Fmt.qty(qtyPlan)} → ${Fmt.qty(qtyActual)}대',
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            Expanded(
              child: _HeroStat(
                label: businessDaysLeft == null ? '기준 주차' : '남은 영업일',
                value: businessDaysLeft == null
                    ? weekLabel
                    : '$businessDaysLeft일',
                padLeft: true,
              ),
            ),
          ],
        ),
      ],
    );

    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: body,
    );

    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: box,
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    final base = '${now.month}월 ${now.day}일';
    return weekLabel.isEmpty ? base : '$base · $weekLabel';
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final bool padLeft;

  const _HeroStat({
    required this.label,
    required this.value,
    this.padLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: padLeft ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DivisionRevenueHero._label,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.headerNavy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(90, 13),
          const SizedBox(height: 12),
          bar(180, 28),
          const SizedBox(height: 14),
          bar(double.infinity, 7),
          const SizedBox(height: 16),
          bar(150, 14),
        ],
      ),
    );
  }
}
