// 자동차사업부 화면이 쓰는 값.
//
// 반도체는 "이번 달 얼마 나갔나"로 읽지만 자동차는 연 단위 계약이라
// 같은 자리에 "올해 계약 매출 / 전체 계약 매출"이 온다.
// 합계는 전부 서버(/divisions/automotive/summary,
// /projects/{key}/automotive-summary)가 낸 값을 그대로 쓴다.
// 앱에서 다시 더하면 Admin 화면과 숫자가 갈린다.

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.round() ?? 0;
String _s(dynamic v) => (v ?? '').toString();

/// 화면에 찍는 숫자 모양. 억원은 소수 한 자리, 대수는 만 단위로 접는다.
class AutoFmt {
  static String comma(num v) => v
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  /// 1047.02 → '1,047.0억'
  static String eok(num v) {
    final n = v.abs();
    final s = n.toStringAsFixed(1);
    final dot = s.indexOf('.');
    final head = comma(int.parse(s.substring(0, dot)));
    return '${v < 0 ? '-' : ''}$head${s.substring(dot)}억';
  }

  /// 1252329 → '125.2만대', 7291 → '7,291대'
  static String qtyShort(num v, {String unit = '대'}) {
    if (v.abs() >= 100000) {
      return '${(v / 10000).toStringAsFixed(1)}만$unit';
    }
    return '${comma(v)}$unit';
  }

  static String won(num v) => '${comma(v)}원';

  /// 0.1384 → '138%'
  static String pct(double? r, {int digits = 0}) =>
      r == null ? '-' : '${(r * 100).toStringAsFixed(digits)}%';

  /// 엑셀은 비율을 소수로 적는다 — 0.31 은 31% 다.
  /// 0.31 → '31%', 0.315 → '31.5%'
  static String ratio(double v) {
    final n = v * 100;
    final s = n.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}%';
  }
}

class AutoYearCell {
  final int qty;
  final double revenue;
  const AutoYearCell({required this.qty, required this.revenue});

  factory AutoYearCell.fromJson(Map j) =>
      AutoYearCell(qty: _i(j['qty']), revenue: _d(j['revenue']));

  static Map<String, AutoYearCell> mapOf(dynamic v) {
    final out = <String, AutoYearCell>{};
    if (v is Map) {
      v.forEach((k, c) {
        if (c is Map) out['$k'] = AutoYearCell.fromJson(c);
      });
    }
    return out;
  }
}

// ── 사업부 화면 (고객사 목록) ────────────────────────────────────────

class AutoProjectRow {
  final String key;
  final String label;
  final int products;
  final int mass;
  final int dev;
  final int qty;
  final double revenue;
  final int yearQty;
  final double yearRevenue;
  final double share; // 사업부 전체 계약 매출에서 차지하는 몫 (막대 길이)
  final int overCost; // 원가가 판가를 넘는 제품 수
  final List<String> overCostNames;

  const AutoProjectRow({
    required this.key,
    required this.label,
    required this.products,
    required this.mass,
    required this.dev,
    required this.qty,
    required this.revenue,
    required this.yearQty,
    required this.yearRevenue,
    required this.share,
    required this.overCost,
    required this.overCostNames,
  });

  bool get hasContract => revenue > 0 || qty > 0;

  factory AutoProjectRow.fromJson(Map j) => AutoProjectRow(
        key: _s(j['key']),
        label: _s(j['label']),
        products: _i(j['products']),
        mass: _i(j['mass']),
        dev: _i(j['dev']),
        qty: _i(j['qty']),
        revenue: _d(j['revenue']),
        yearQty: _i(j['year_qty']),
        yearRevenue: _d(j['year_revenue']),
        share: _d(j['share']),
        overCost: _i(j['over_cost']),
        overCostNames:
            ((j['over_cost_names'] as List?) ?? []).map(_s).toList(),
      );
}

class AutoDivisionSummary {
  final int year;
  final List<String> years;
  final List<AutoProjectRow> projects;
  final Map<String, AutoYearCell> byYear;
  final int totalProjects;
  final int withContract;
  final int totalProducts;
  final int qty;
  final double revenue;
  final int yearQty;
  final double yearRevenue;
  final int overCost;
  final List<String> overCostNames;
  final bool loaded;

  const AutoDivisionSummary({
    required this.year,
    required this.years,
    required this.projects,
    required this.byYear,
    required this.totalProjects,
    required this.withContract,
    required this.totalProducts,
    required this.qty,
    required this.revenue,
    required this.yearQty,
    required this.yearRevenue,
    required this.overCost,
    required this.overCostNames,
    required this.loaded,
  });

  static const empty = AutoDivisionSummary(
    year: 0,
    years: [],
    projects: [],
    byYear: {},
    totalProjects: 0,
    withContract: 0,
    totalProducts: 0,
    qty: 0,
    revenue: 0,
    yearQty: 0,
    yearRevenue: 0,
    overCost: 0,
    overCostNames: [],
    loaded: false,
  );

  /// 올해가 전체 계약에서 차지하는 몫. 게이지 길이로 쓴다.
  double get yearShare => revenue > 0 ? (yearRevenue / revenue) : 0;

  factory AutoDivisionSummary.fromJson(Map j) {
    final t = (j['totals'] as Map?) ?? {};
    return AutoDivisionSummary(
      year: _i(j['year']),
      years: ((j['years'] as List?) ?? []).map(_s).toList(),
      projects: ((j['projects'] as List?) ?? [])
          .whereType<Map>()
          .map(AutoProjectRow.fromJson)
          .toList(),
      byYear: AutoYearCell.mapOf(j['by_year']),
      totalProjects: _i(t['projects']),
      withContract: _i(t['with_contract']),
      totalProducts: _i(t['products']),
      qty: _i(t['qty']),
      revenue: _d(t['revenue']),
      yearQty: _i(t['year_qty']),
      yearRevenue: _d(t['year_revenue']),
      overCost: _i(t['over_cost']),
      overCostNames:
          ((t['over_cost_names'] as List?) ?? []).map(_s).toList(),
      loaded: true,
    );
  }
}

// ── 고객사 화면 (제품 목록) ──────────────────────────────────────────

class AutoProduct {
  final String id;
  final String name;
  final String group; // '양산' | '개발'
  final String endCustomer;
  final String carModel;
  final String site;   // 납품 위치 ('한국/이천공장', '인도 (CIF)')
  final String method; // 공법
  final String sop;
  final double weightKg;
  final int tonnage;
  final double defectRate;
  final int price;      // 원
  final Map<String, int> cost; // material/process/admin/depr/logi
  final int costTotal;
  final double? costRatio;     // 판가가 없으면 null — 0 으로 눕히지 않는다
  final Map<String, AutoYearCell> contract;
  final int qtyTotal;
  final double revenueTotal;

  const AutoProduct({
    required this.id,
    required this.name,
    required this.group,
    required this.endCustomer,
    required this.carModel,
    required this.site,
    required this.method,
    required this.sop,
    required this.weightKg,
    required this.tonnage,
    required this.defectRate,
    required this.price,
    required this.cost,
    required this.costTotal,
    required this.costRatio,
    required this.contract,
    required this.qtyTotal,
    required this.revenueTotal,
  });

  bool get overCost => costRatio != null && costRatio! >= 1;

  /// 대당 손익 (판가 - 원가). 판가가 없으면 null.
  int? get marginPerUnit => price > 0 ? price - costTotal : null;

  factory AutoProduct.fromJson(Map j) {
    final c = <String, int>{};
    final raw = (j['cost'] as Map?) ?? {};
    raw.forEach((k, v) => c['$k'] = _i(v));
    return AutoProduct(
      id: _s(j['id']),
      name: _s(j['name']),
      group: _s(j['group']).isEmpty ? '양산' : _s(j['group']),
      endCustomer: _s(j['end_customer']),
      carModel: _s(j['car_model']),
      site: _s(j['site']),
      method: _s(j['method']),
      sop: _s(j['sop']),
      weightKg: _d(j['weight_kg']),
      tonnage: _i(j['tonnage']),
      defectRate: _d(j['defect_rate']),
      price: _i(j['price']),
      cost: c,
      costTotal: _i(j['cost_total']),
      costRatio: j['cost_ratio'] == null ? null : _d(j['cost_ratio']),
      contract: AutoYearCell.mapOf(j['contract']),
      qtyTotal: _i(j['qty_total']),
      revenueTotal: _d(j['revenue_total']),
    );
  }
}

class AutoProjectSummary {
  final String key;
  final String label;
  final List<String> years;
  final List<AutoProduct> products;
  final Map<String, AutoYearCell> byYear;
  final int mass;
  final int dev;
  final int qty;
  final double revenue;
  final int overCost;
  final List<String> overCostNames;
  final bool loaded;

  const AutoProjectSummary({
    required this.key,
    required this.label,
    required this.years,
    required this.products,
    required this.byYear,
    required this.mass,
    required this.dev,
    required this.qty,
    required this.revenue,
    required this.overCost,
    required this.overCostNames,
    required this.loaded,
  });

  static const empty = AutoProjectSummary(
    key: '',
    label: '',
    years: [],
    products: [],
    byYear: {},
    mass: 0,
    dev: 0,
    qty: 0,
    revenue: 0,
    overCost: 0,
    overCostNames: [],
    loaded: false,
  );

  AutoYearCell? yearCell(int year) => byYear['$year'];

  factory AutoProjectSummary.fromJson(Map j) {
    final t = (j['totals'] as Map?) ?? {};
    return AutoProjectSummary(
      key: _s(j['project_key']),
      label: _s(j['label']),
      years: ((j['years'] as List?) ?? []).map(_s).toList(),
      products: ((j['products'] as List?) ?? [])
          .whereType<Map>()
          .map(AutoProduct.fromJson)
          .toList(),
      byYear: AutoYearCell.mapOf(j['by_year']),
      mass: _i(t['mass']),
      dev: _i(t['dev']),
      qty: _i(t['qty']),
      revenue: _d(t['revenue']),
      overCost: _i(t['over_cost']),
      overCostNames:
          ((t['over_cost_names'] as List?) ?? []).map(_s).toList(),
      loaded: true,
    );
  }
}
