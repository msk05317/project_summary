// 사업부 매출 (/revenue).
//
// 모델 판가 × 수량으로 계산하던 값이 아니라, 일일보고(실적)와 월 계획
// 엑셀에서 받은 확정 금액이다. 하바플레이트 55종 중 52종이 판가 3,400
// 으로 일괄 입력돼 있어서 9월 매출이 18만 달러 부풀어 있었다.
//
// 반도체사업부 전체다 — 구미·화성·용인·USA·데이터센터까지 들어간다.
// 모델이 있는 프로젝트만 세던 예전 값($400만)보다 크다($679만).
import '../config/app_config.dart';
import 'offline_store.dart';

/// 품목 한 줄
class RevenueItem {
  final String item;
  final int plan;
  final int actual;
  final int qty;
  final int? rate;

  const RevenueItem({
    required this.item,
    required this.plan,
    required this.actual,
    this.qty = 0,
    this.rate,
  });

  factory RevenueItem.fromJson(Map j) => RevenueItem(
        item: (j['item'] ?? '').toString(),
        plan: (j['plan'] as num?)?.toInt() ?? 0,
        actual: (j['actual'] as num?)?.toInt() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        rate: (j['rate'] as num?)?.toInt(),
      );
}

class RevenueMonth {
  final String month;
  final List<RevenueItem> items;
  final int plan;
  final int actual;
  final int? rate;
  final int left;
  /// 올해 누적 실적
  final int ytd;
  /// 실적이 들어온 마지막 날 (YYYY-MM-DD). 달성률이 낮아 보이는 이유가 여기 있다.
  final String asOf;
  final bool hasData;
  final bool loaded;
  final bool fromCache;
  final DateTime? savedAt;

  const RevenueMonth({
    required this.month,
    required this.items,
    required this.plan,
    required this.actual,
    required this.left,
    required this.ytd,
    required this.asOf,
    this.rate,
    this.hasData = false,
    this.loaded = true,
    this.fromCache = false,
    this.savedAt,
  });

  static const RevenueMonth empty = RevenueMonth(
    month: '', items: [], plan: 0, actual: 0, left: 0, ytd: 0, asOf: '',
    hasData: false, loaded: false,
  );

  /// 실적 큰 것부터. 홈 카드는 이 순서로 보여준다.
  List<RevenueItem> get byActual {
    final out = [...items];
    out.sort((a, b) => b.actual.compareTo(a.actual));
    return out;
  }

  RevenueMonth copyWith({bool? fromCache, DateTime? savedAt}) => RevenueMonth(
        month: month, items: items, plan: plan, actual: actual, left: left,
        ytd: ytd, asOf: asOf, rate: rate, hasData: hasData, loaded: loaded,
        fromCache: fromCache ?? this.fromCache,
        savedAt: savedAt ?? this.savedAt,
      );

  factory RevenueMonth.fromJson(Map j) {
    final items = ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(RevenueItem.fromJson)
        .toList();
    return RevenueMonth(
      month: (j['month'] ?? '').toString(),
      items: items,
      plan: (j['plan'] as num?)?.toInt() ?? 0,
      actual: (j['actual'] as num?)?.toInt() ?? 0,
      rate: (j['rate'] as num?)?.toInt(),
      left: (j['left'] as num?)?.toInt() ?? 0,
      ytd: (j['ytd'] as num?)?.toInt() ?? 0,
      asOf: (j['as_of'] ?? '').toString(),
      hasData: j['has_data'] == true && items.isNotEmpty,
    );
  }
}

class RevenueService {
  /// 실패하면 예외 대신 empty. 아직 엑셀을 한 번도 안 올렸으면 hasData=false
  /// 라서, 카드가 예전 방식(모델 계산)으로 그린다.
  static Future<RevenueMonth> fetch({String month = ''}) async {
    final q = month.isEmpty ? '' : '?month=$month';
    try {
      final got = await OfflineStore.fetch(
          '$kApiBaseUrl/revenue$q', 'revenue${month.isEmpty ? '' : '_$month'}',
          timeout: const Duration(seconds: 20));
      final decoded = got.data;
      if (decoded is! Map) return RevenueMonth.empty;
      return RevenueMonth.fromJson(decoded)
          .copyWith(fromCache: got.fromCache, savedAt: got.savedAt);
    } catch (_) {
      return RevenueMonth.empty;
    }
  }
}
