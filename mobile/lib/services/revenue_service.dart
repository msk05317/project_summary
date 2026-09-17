// 사업부 매출 (/revenue).
//
// 실적과 예상은 출처가 다르다.
//   실적 — 주간보고 엑셀. 확정 금액이다.
//   예상 — 사람이 admin 에서 넣는다. 주간보고의 '실행계획' 열을 쓰던 때가
//          있었는데 그 열은 작년에 짜 둔 숫자였다 (9월 기준 $1,964만 대
//          실제 예상 $2,422만).
//
// 반도체사업부 전체다 — 구미·화성·용인·USA·데이터센터까지 들어간다.
import '../config/app_config.dart';
import 'offline_store.dart';

/// 품목 한 줄 — 실적만 있다.
class RevenueItem {
  final String item;
  final int actual;

  /// 어느 묶음인지 (semi · dc · space · internal)
  final String group;

  /// 엑셀에서 이 줄이 붙어 있던 고객·사이트 이름
  final String cust;

  const RevenueItem({
    required this.item,
    required this.actual,
    this.group = 'semi',
    this.cust = '',
  });

  factory RevenueItem.fromJson(Map j) => RevenueItem(
        item: (j['item'] ?? '').toString(),
        actual: (j['actual'] as num?)?.toInt() ?? 0,
        group: (j['group'] ?? 'semi').toString(),
        cust: (j['cust'] ?? '').toString(),
      );
}

/// 보고서 묶음 한 줄 (반도체 · 데이터 센터 · 우주항공 · 내부거래)
class RevenueGroup {
  final String key;
  final String label;
  final int actual;

  /// 이 묶음 몫의 예상. Estimate 파일의 Commodity 를 이어 붙인 값이다.
  /// 금액만 넣은 달은 0 이고, 그때는 달성률을 지어내지 않는다.
  final int estimate;
  final int? rate;

  /// 그 묶음 안의 세부 줄
  final List<RevenueItem> items;

  const RevenueGroup({
    required this.key,
    required this.label,
    required this.actual,
    this.estimate = 0,
    this.rate,
    this.items = const [],
  });

  factory RevenueGroup.fromJson(Map j) => RevenueGroup(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        actual: (j['actual'] as num?)?.toInt() ?? 0,
        estimate: (j['estimate'] as num?)?.toInt() ?? 0,
        rate: (j['rate'] as num?)?.toInt(),
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map(RevenueItem.fromJson)
            .toList(),
      );

  /// 화면에 쓸 짧은 이름. '반도체 (SEMI)' 를 그대로 쓰면 줄이 넘친다.
  String get short {
    final i = label.indexOf(' (');
    return i > 0 ? label.substring(0, i) : label;
  }
}

class RevenueMonth {
  final String month;
  final List<RevenueItem> items;
  final int actual;

  /// 사람이 넣은 그 달 예상 매출. 안 넣었으면 0.
  final int estimate;
  final int? rate;
  final int left;

  /// 올해 누적 실적
  final int ytd;

  /// 실적이 들어온 마지막 주차 (W37). 달성률이 낮아 보이는 이유가 여기 있다.
  final String asOf;

  /// 매출합계 쪽 묶음 (반도체 · 데이터 센터 · 우주항공)
  final List<RevenueGroup> groups;

  /// 내부거래 — 텍슨 사이트끼리 오간 것
  final RevenueGroup? internal;
  final bool hasData;

  /// 예상이 아직 안 들어온 달이면 false. 실적만 보여준다.
  final bool hasEstimate;

  /// 예상이 묶음별로 나뉘어 들어왔는지. 금액만 넣은 달은 false.
  final bool hasEstimateGroups;
  final bool loaded;
  final bool fromCache;
  final DateTime? savedAt;

  const RevenueMonth({
    required this.month,
    required this.items,
    required this.actual,
    required this.left,
    required this.ytd,
    required this.asOf,
    this.estimate = 0,
    this.groups = const [],
    this.internal,
    this.rate,
    this.hasData = false,
    this.hasEstimate = false,
    this.hasEstimateGroups = false,
    this.loaded = true,
    this.fromCache = false,
    this.savedAt,
  });

  static const RevenueMonth empty = RevenueMonth(
    month: '', items: [], actual: 0, left: 0, ytd: 0, asOf: '',
    groups: [], hasData: false, loaded: false,
  );

  /// 카드에 그릴 줄. 보고서와 같은 묶음이다 —
  /// 반도체 · 데이터 센터 · 우주항공 · 내부거래.
  List<RevenueGroup> get lines {
    final out = <RevenueGroup>[...groups];
    if (internal != null) out.add(internal!);
    return out.where((g) => g.actual > 0).toList();
  }

  /// 실적 큰 것부터. 홈 카드는 이 순서로 보여준다.
  List<RevenueItem> get byActual {
    final out = [...items];
    out.sort((a, b) => b.actual.compareTo(a.actual));
    return out;
  }

  RevenueMonth copyWith({bool? fromCache, DateTime? savedAt}) => RevenueMonth(
        month: month, items: items, actual: actual, left: left,
        ytd: ytd, asOf: asOf, rate: rate, hasData: hasData, loaded: loaded,
        groups: groups, internal: internal, estimate: estimate,
        hasEstimate: hasEstimate, hasEstimateGroups: hasEstimateGroups,
        fromCache: fromCache ?? this.fromCache,
        savedAt: savedAt ?? this.savedAt,
      );

  factory RevenueMonth.fromJson(Map j) {
    final groups = ((j['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map(RevenueGroup.fromJson)
        .toList();
    final internal = (j['internal'] is Map)
        ? RevenueGroup.fromJson(j['internal'] as Map)
        : null;
    final items = [
      for (final g in groups) ...g.items,
      if (internal != null) ...internal.items,
    ];
    return RevenueMonth(
      month: (j['month'] ?? '').toString(),
      items: items,
      actual: (j['actual'] as num?)?.toInt() ?? 0,
      estimate: (j['estimate'] as num?)?.toInt() ?? 0,
      rate: (j['rate'] as num?)?.toInt(),
      left: (j['left'] as num?)?.toInt() ?? 0,
      ytd: (j['ytd'] as num?)?.toInt() ?? 0,
      asOf: (j['as_of'] ?? '').toString(),
      groups: groups,
      internal: internal,
      hasData: j['has_data'] == true && groups.isNotEmpty,
      hasEstimate: j['has_estimate'] == true,
      hasEstimateGroups: j['has_estimate_groups'] == true,
    );
  }
}

class RevenueService {
  /// 실패하면 예외 대신 empty. 아직 엑셀을 한 번도 안 올렸으면 hasData=false
  /// 라서, 카드가 예전 방식(모델 계산)으로 그린다.
  static Future<RevenueMonth> fetch(
      {String month = '', void Function(RevenueMonth)? onFresh}) async {
    final q = month.isEmpty ? '' : '?month=$month';
    try {
      final got = await OfflineStore.fetch(
          '$kApiBaseUrl/revenue$q', 'revenue${month.isEmpty ? '' : '_$month'}',
          timeout: const Duration(seconds: 20),
          onFresh: onFresh == null ? null : (c) => onFresh(_parse(c)));
      return _parse(got);
    } catch (_) {
      return RevenueMonth.empty;
    }
  }

  static RevenueMonth _parse(Cached<dynamic> got) {
    final decoded = got.data;
    if (decoded is! Map) return RevenueMonth.empty;
    return RevenueMonth.fromJson(decoded)
        .copyWith(fromCache: got.fromCache, savedAt: got.savedAt);
  }
}
