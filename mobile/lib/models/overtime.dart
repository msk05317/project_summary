// 전사 사업부별 잔업·특근 (GET /overtime/week, /overtime/week/{div}).
//
// 지표가 둘이다 — 잔업률(월~토)과 특근률(일요일). 한 숫자로 못 합친다.
// 각각 전체/직접/간접으로 또 갈린다.
//
// 비어 있는 값은 0 이 아니라 null 이다. 엑셀의 'X'(해당 없음)와 미입력을
// 0 으로 바꾸면 '아무도 안 나왔다' 로 읽힌다.

double? _dn(dynamic v) =>
    v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));

int? _in(dynamic v) => _dn(v)?.round();

/// 인원 묶음 — 전체 / 주간 / 야간
class OvGroup {
  final int? total;
  final int? day;
  final int? night;

  const OvGroup({this.total, this.day, this.night});

  static const OvGroup empty = OvGroup();

  factory OvGroup.fromJson(dynamic j) {
    if (j is! Map) return empty;
    return OvGroup(
      total: _in(j['total']),
      day: _in(j['day']),
      night: _in(j['night']),
    );
  }
}

/// 지원 인력 — 들어온 인원 / 나간 인원
class OvSupport {
  final int? inbound;
  final int? outbound;

  const OvSupport({this.inbound, this.outbound});

  static const OvSupport empty = OvSupport();

  factory OvSupport.fromJson(dynamic j) {
    if (j is! Map) return empty;
    return OvSupport(inbound: _in(j['in']), outbound: _in(j['out']));
  }
}

/// 전체 / 직접 / 간접 세 칸
class OvScoped {
  final double? total;
  final double? direct;
  final double? indirect;

  const OvScoped({this.total, this.direct, this.indirect});

  static const OvScoped empty = OvScoped();

  factory OvScoped.fromJson(dynamic j) {
    if (j is! Map) return empty;
    return OvScoped(
      total: _dn(j['total']),
      direct: _dn(j['direct']),
      indirect: _dn(j['indirect']),
    );
  }

  double? of(String scope) => scope == 'direct'
      ? direct
      : scope == 'indirect'
          ? indirect
          : total;
}

/// 잔업 또는 특근 한 덩어리
class OvKind {
  final String label;      // 잔업 / 특근
  final String range;      // 월~토 / 일
  final OvScoped people;   // 인원
  final OvScoped rate;     // 비율 (0~1)
  final Map<String, double?> byDay;

  const OvKind({
    required this.label,
    required this.range,
    required this.people,
    required this.rate,
    required this.byDay,
  });

  static const OvKind empty = OvKind(
    label: '',
    range: '',
    people: OvScoped.empty,
    rate: OvScoped.empty,
    byDay: <String, double?>{},
  );

  factory OvKind.fromJson(dynamic j) {
    if (j is! Map) return empty;
    final raw = j['by_day'];
    final by = <String, double?>{};
    if (raw is Map) {
      raw.forEach((k, v) => by['$k'] = _dn(v));
    }
    return OvKind(
      label: '${j['label'] ?? ''}',
      range: '${j['range'] ?? ''}',
      people: OvScoped.fromJson(j['people']),
      rate: OvScoped.fromJson(j['rate']),
      byDay: by,
    );
  }
}

/// 한 사업부(또는 전사)의 한 주 요약
class OvSummary {
  final String label;
  final OvGroup headcount;
  final OvSupport support;
  final OvGroup available;
  final OvGroup direct;
  final OvGroup indirect;
  final double? nightRate;
  final OvKind overtime;
  final OvKind special;
  final String note;
  final String check;

  const OvSummary({
    required this.label,
    required this.headcount,
    required this.support,
    required this.available,
    required this.direct,
    required this.indirect,
    required this.nightRate,
    required this.overtime,
    required this.special,
    required this.note,
    required this.check,
  });

  static const OvSummary empty = OvSummary(
    label: '',
    headcount: OvGroup.empty,
    support: OvSupport.empty,
    available: OvGroup.empty,
    direct: OvGroup.empty,
    indirect: OvGroup.empty,
    nightRate: null,
    overtime: OvKind.empty,
    special: OvKind.empty,
    note: '',
    check: '',
  );

  factory OvSummary.fromJson(dynamic j) {
    if (j is! Map) return empty;
    return OvSummary(
      label: '${j['label'] ?? ''}',
      headcount: OvGroup.fromJson(j['headcount']),
      support: OvSupport.fromJson(j['support']),
      available: OvGroup.fromJson(j['available']),
      direct: OvGroup.fromJson(j['direct']),
      indirect: OvGroup.fromJson(j['indirect']),
      nightRate: _dn(j['night_rate']),
      overtime: OvKind.fromJson(j['overtime']),
      special: OvKind.fromJson(j['special']),
      note: '${j['note'] ?? ''}',
      check: '${j['check'] ?? ''}',
    );
  }

  OvKind kind(String key) => key == 'special' ? special : overtime;

  bool get needsCheck => check == '확인필요';
}

/// 순위 목록 한 줄
class OvItem {
  final String key;
  final String label;
  final double? rate;
  final double? delta;
  final int? people;
  final int? available;
  final bool overAvg;
  final String note;
  final String check;
  final List<String> audit;

  const OvItem({
    required this.key,
    required this.label,
    required this.rate,
    required this.delta,
    required this.people,
    required this.available,
    required this.overAvg,
    required this.note,
    required this.check,
    required this.audit,
  });

  factory OvItem.fromJson(Map<String, dynamic> j) => OvItem(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        rate: _dn(j['rate']),
        delta: _dn(j['delta']),
        people: _in(j['people']),
        available: _in(j['available']),
        overAvg: j['over_avg'] == true,
        note: '${j['note'] ?? ''}',
        check: '${j['check'] ?? ''}',
        audit: ((j['audit'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  bool get hasRate => rate != null;
  bool get needsCheck => check == '확인필요' || audit.isNotEmpty;
}

class OvLabel {
  final String key;
  final String label;
  final String range;

  const OvLabel({required this.key, required this.label, this.range = ''});

  factory OvLabel.fromJson(Map<String, dynamic> j) => OvLabel(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        range: '${j['range'] ?? ''}',
      );
}

class OvCounts {
  final int divisions;
  final int over;
  final int under;
  final int up;
  final int down;
  final int check;
  final int audit;

  const OvCounts({
    this.divisions = 0,
    this.over = 0,
    this.under = 0,
    this.up = 0,
    this.down = 0,
    this.check = 0,
    this.audit = 0,
  });

  factory OvCounts.fromJson(dynamic j) {
    if (j is! Map) return const OvCounts();
    int g(String k) => _in(j[k]) ?? 0;
    return OvCounts(
      divisions: g('divisions'),
      over: g('over'),
      under: g('under'),
      up: g('up'),
      down: g('down'),
      check: g('check'),
      audit: g('audit'),
    );
  }

  /// 확인이 필요한 곳 — 파일이 '확인필요' 라 한 곳과 우리 검산에 걸린 곳
  int get attention => check > audit ? check : audit;
}

/// 전사 한 주 (GET /overtime/week)
class OvertimeWeek {
  final String week;
  final String weekLabel;
  final String range;
  final String prevWeek;
  final String prevLabel;
  final String kind;
  final String kindLabel;
  final String kindRange;
  final String scope;
  final String scopeLabel;
  final List<OvLabel> kinds;
  final List<OvLabel> scopes;
  final List<String> weeks;
  final OvSummary total;
  final OvSummary? prevTotal;
  final double? avg;
  final double? avgDelta;
  final OvCounts counts;
  final List<OvItem> items;
  final List<String> issues;
  final bool hasData;

  const OvertimeWeek({
    required this.week,
    required this.weekLabel,
    required this.range,
    required this.prevWeek,
    required this.prevLabel,
    required this.kind,
    required this.kindLabel,
    required this.kindRange,
    required this.scope,
    required this.scopeLabel,
    required this.kinds,
    required this.scopes,
    required this.weeks,
    required this.total,
    required this.prevTotal,
    required this.avg,
    required this.avgDelta,
    required this.counts,
    required this.items,
    required this.issues,
    required this.hasData,
  });

  static const OvertimeWeek empty = OvertimeWeek(
    week: '',
    weekLabel: '',
    range: '',
    prevWeek: '',
    prevLabel: '',
    kind: 'overtime',
    kindLabel: '잔업',
    kindRange: '월~토',
    scope: 'total',
    scopeLabel: '전체',
    kinds: <OvLabel>[],
    scopes: <OvLabel>[],
    weeks: <String>[],
    total: OvSummary.empty,
    prevTotal: null,
    avg: null,
    avgDelta: null,
    counts: OvCounts(),
    items: <OvItem>[],
    issues: <String>[],
    hasData: false,
  );

  factory OvertimeWeek.fromJson(Map<String, dynamic> j) {
    List<OvLabel> labels(dynamic v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((e) => OvLabel.fromJson(e.cast<String, dynamic>()))
        .toList();
    return OvertimeWeek(
      week: '${j['week'] ?? ''}',
      weekLabel: '${j['week_label'] ?? ''}',
      range: '${j['range'] ?? ''}',
      prevWeek: '${j['prev_week'] ?? ''}',
      prevLabel: '${j['prev_label'] ?? ''}',
      kind: '${j['kind'] ?? 'overtime'}',
      kindLabel: '${j['kind_label'] ?? ''}',
      kindRange: '${j['kind_range'] ?? ''}',
      scope: '${j['scope'] ?? 'total'}',
      scopeLabel: '${j['scope_label'] ?? ''}',
      kinds: labels(j['kinds']),
      scopes: labels(j['scopes']),
      weeks: ((j['weeks'] as List?) ?? const []).map((e) => '$e').toList(),
      total: OvSummary.fromJson(j['total']),
      prevTotal: j['prev_total'] == null
          ? null
          : OvSummary.fromJson(j['prev_total']),
      avg: _dn(j['avg']),
      avgDelta: _dn(j['avg_delta']),
      counts: OvCounts.fromJson(j['counts']),
      items: ((j['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => OvItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
      issues: ((j['issues'] as List?) ?? const []).map((e) => '$e').toList(),
      hasData: j['has_data'] == true,
    );
  }

  /// 홈 카드가 두 지표를 같이 보여 준다. 전주 합계를 받아 두면 뺄셈만 하면 된다.
  double? deltaOf(String kindKey) {
    final now = total.kind(kindKey).rate.total;
    final before = prevTotal?.kind(kindKey).rate.total;
    if (now == null || before == null) return null;
    return now - before;
  }
}

/// 사업부 한 곳 (GET /overtime/week/{div})
class OvDay {
  final String day;
  final String label;
  final String kind;
  final String kindLabel;
  final double? rate;
  final int? people;
  final int? available;

  const OvDay({
    required this.day,
    required this.label,
    required this.kind,
    required this.kindLabel,
    required this.rate,
    required this.people,
    required this.available,
  });

  factory OvDay.fromJson(Map<String, dynamic> j) => OvDay(
        day: '${j['day'] ?? ''}',
        label: '${j['label'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        kindLabel: '${j['kind_label'] ?? ''}',
        rate: _dn(j['rate']),
        people: _in(j['people']),
        available: _in(j['available']),
      );

  bool get isSunday => day == 'sun';
}

class OvertimeDivision {
  final String division;
  final String week;
  final String weekLabel;
  final String range;
  final String prevLabel;
  final OvSummary summary;
  final Map<String, OvScoped> deltas;
  final List<OvDay> byDay;
  final bool hasData;

  const OvertimeDivision({
    required this.division,
    required this.week,
    required this.weekLabel,
    required this.range,
    required this.prevLabel,
    required this.summary,
    required this.deltas,
    required this.byDay,
    required this.hasData,
  });

  static const OvertimeDivision empty = OvertimeDivision(
    division: '',
    week: '',
    weekLabel: '',
    range: '',
    prevLabel: '',
    summary: OvSummary.empty,
    deltas: <String, OvScoped>{},
    byDay: <OvDay>[],
    hasData: false,
  );

  factory OvertimeDivision.fromJson(Map<String, dynamic> j) {
    final raw = j['deltas'];
    final d = <String, OvScoped>{};
    if (raw is Map) {
      raw.forEach((k, v) => d['$k'] = OvScoped.fromJson(v));
    }
    return OvertimeDivision(
      division: '${j['division'] ?? ''}',
      week: '${j['week'] ?? ''}',
      weekLabel: '${j['week_label'] ?? ''}',
      range: '${j['range'] ?? ''}',
      prevLabel: '${j['prev_label'] ?? ''}',
      summary: OvSummary.fromJson(j['summary']),
      deltas: d,
      byDay: ((j['by_day'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => OvDay.fromJson(e.cast<String, dynamic>()))
          .toList(),
      hasData: j['has_data'] == true,
    );
  }

  OvScoped deltaOf(String kind) => deltas[kind] ?? OvScoped.empty;
}
