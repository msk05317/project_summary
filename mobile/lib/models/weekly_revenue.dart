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

  // 숫자는 반드시 num 을 거쳐서 받는다.
  // 판가에 소수점이 생기면서 매출이 double 로 내려올 수 있는데,
  // 곧바로 int 에 대입하면 화면 전체가
  // "type 'double' is not a subtype of type 'int'" 로 죽는다.
  factory WeekCell.fromJson(Map<String, dynamic> j) => WeekCell(
        plan: (j['plan'] as num?)?.round() ?? 0,
        actual: (j['actual'] as num?)?.round() ?? 0,
        revenue: (j['revenue'] as num?)?.round(),
        planRevenue: (j['plan_revenue'] as num?)?.round(),
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
        poQty: (j['po_qty'] as num?)?.round() ?? 0,
        actualTotal: (j['actual_total'] as num?)?.round() ?? 0,
        remaining: (j['remaining'] as num?)?.round() ?? 0,
        unitPrice: (j['unit_price'] as num?)?.round(),
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
        combinedRevenue: (j['combined']?['total']?['revenue'] as num?)?.round()
            ?? (j['combined_revenue'] as num?)?.round()
            ?? 0,
        combinedPlanRevenue:
            (j['combined']?['total']?['plan_revenue'] as num?)?.round() ?? 0,
      );
}
