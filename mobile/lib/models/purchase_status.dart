// 사업부 월별 매입·지급 현황 (GET /division/{id}/purchase).
//
// 잔액은 서버가 '적힌 값'을 그대로 준다. 매입-지급과 다를 수 있다.
class PurchaseItem {
  final String key;
  final String label;
  final double buy;
  final double paid;
  final double balance;
  final bool balanceAuto;
  final double payRate;

  const PurchaseItem({
    required this.key,
    required this.label,
    required this.buy,
    required this.paid,
    required this.balance,
    required this.balanceAuto,
    required this.payRate,
  });

  static double _d(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        buy: _d(j['buy']),
        paid: _d(j['paid']),
        balance: _d(j['balance']),
        balanceAuto: j['balance_auto'] == true,
        payRate: _d(j['pay_rate']),
      );
}

class PurchasePayment {
  final double prepaid;
  final double actualPaid;
  final double? invest;
  final double total;

  const PurchasePayment({
    required this.prepaid,
    required this.actualPaid,
    required this.invest,
    required this.total,
  });

  static const empty =
      PurchasePayment(prepaid: 0, actualPaid: 0, invest: null, total: 0);

  factory PurchasePayment.fromJson(Map<String, dynamic> j) => PurchasePayment(
        prepaid: PurchaseItem._d(j['prepaid']),
        actualPaid: PurchaseItem._d(j['actual_paid']),
        invest: j['invest'] == null ? null : PurchaseItem._d(j['invest']),
        total: PurchaseItem._d(j['total']),
      );
}

class PurchaseMonth {
  final String month;   // '2026-08' 또는 'total'
  final String label;   // '8월' / '누적'
  final String range;   // 누적일 때 '4월~8월'
  final double revenue;
  final double buy;
  final double paid;
  final double balance;
  final double payRate;
  final List<PurchaseItem> items;
  final PurchasePayment payment;

  const PurchaseMonth({
    required this.month,
    required this.label,
    required this.range,
    required this.revenue,
    required this.buy,
    required this.paid,
    required this.balance,
    required this.payRate,
    required this.items,
    required this.payment,
  });

  bool get isTotal => month == 'total';

  /// 매입/매출 비율 (매출이 없으면 null)
  double? get buyOverRevenue =>
      revenue > 0 ? (buy / revenue * 100) : null;

  factory PurchaseMonth.fromJson(Map<String, dynamic> j) => PurchaseMonth(
        month: '${j['month'] ?? ''}',
        label: '${j['label'] ?? ''}',
        range: '${j['range'] ?? ''}',
        revenue: PurchaseItem._d(j['revenue']),
        buy: PurchaseItem._d(j['buy']),
        paid: PurchaseItem._d(j['paid']),
        balance: PurchaseItem._d(j['balance']),
        payRate: PurchaseItem._d(j['pay_rate']),
        items: (j['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PurchaseItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
        payment: j['payment'] is Map
            ? PurchasePayment.fromJson(
                (j['payment'] as Map).cast<String, dynamic>())
            : PurchasePayment.empty,
      );
}

class PurchaseStatus {
  final String division;
  final String currency;
  final bool hasData;
  final String latest;
  final List<PurchaseMonth> months;
  final PurchaseMonth? total;
  final bool loaded;

  const PurchaseStatus({
    required this.division,
    required this.currency,
    required this.hasData,
    required this.latest,
    required this.months,
    required this.total,
    this.loaded = false,
  });

  static const empty = PurchaseStatus(
    division: '', currency: 'USD', hasData: false, latest: '',
    months: <PurchaseMonth>[], total: null, loaded: false,
  );

  /// 칩에 걸 목록 — 월들 + 맨 뒤 누적
  List<PurchaseMonth> get tabs => [
        ...months,
        if (total != null && months.length > 1) total!,
      ];

  factory PurchaseStatus.fromJson(Map<String, dynamic> j) => PurchaseStatus(
        division: '${j['division'] ?? ''}',
        currency: '${j['currency'] ?? 'USD'}',
        hasData: j['has_data'] == true,
        latest: '${j['latest'] ?? ''}',
        months: (j['months'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PurchaseMonth.fromJson(e.cast<String, dynamic>()))
            .toList(),
        total: j['total'] is Map
            ? PurchaseMonth.fromJson((j['total'] as Map).cast<String, dynamic>())
            : null,
        loaded: true,
      );
}
