class WeekCell {
  final int plan;
  final int actual;
  final int? revenue;

  /// 계획 수량 x 판가 = 계획 기준 예상 매출 (백엔드 plan_revenue)
  final int? planRevenue;

  WeekCell({
    required this.plan,
    required this.actual,
    this.revenue,
    this.planRevenue,
  });

  factory WeekCell.fromJson(Map<String, dynamic> j) => WeekCell(
        plan: j['plan'] ?? 0,
        actual: j['actual'] ?? 0,
        revenue: j['revenue'],
        planRevenue: j['plan_revenue'],
      );
}

class GroupSummary {
  final int poQty, actualTotal, remaining;
  final int? unitPrice;
  final Map<String, WeekCell> weeks;
  final WeekCell total;
  GroupSummary({
    required this.poQty, required this.actualTotal, required this.remaining,
    this.unitPrice, required this.weeks, required this.total,
  });
  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
        poQty: j['po_qty'] ?? 0,
        actualTotal: j['actual_total'] ?? 0,
        remaining: j['remaining'] ?? 0,
        unitPrice: j['unit_price'],
        weeks: (j['weeks'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, WeekCell.fromJson(v))),
        total: WeekCell.fromJson(j['total'] ?? {}),
      );
}

class WeeklyRevenue {
  final String month, startWeek;
  final List<String> weeks;
  final GroupSummary mass, dev;
  final int combinedRevenue;

  /// 이 달 계획 기준 예상 매출 합계
  final int combinedPlanRevenue;

  WeeklyRevenue({
    required this.month, required this.startWeek, required this.weeks,
    required this.mass, required this.dev, required this.combinedRevenue,
    this.combinedPlanRevenue = 0,
  });

  /// 계획 대비 달성률(%). 계획이 없으면 null.
  int? get achievement => combinedPlanRevenue <= 0
      ? null
      : (combinedRevenue * 100 / combinedPlanRevenue).round();
  factory WeeklyRevenue.fromJson(Map<String, dynamic> j) => WeeklyRevenue(
        month: j['month'] ?? '',
        startWeek: j['start_week'] ?? '',
        weeks: List<String>.from(j['weeks'] ?? []),
        mass: GroupSummary.fromJson(j['groups']['양산'] ?? {}),
        dev: GroupSummary.fromJson(j['groups']['개발'] ?? {}),
        combinedRevenue: (j['combined']?['total']?['revenue'] as num?)?.toInt()
            ?? j['combined_revenue'] ?? 0,
        combinedPlanRevenue:
            (j['combined']?['total']?['plan_revenue'] as num?)?.toInt() ?? 0,
      );
}
