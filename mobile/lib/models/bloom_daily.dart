// 블룸 일 보드 (/projects/{key}/daily-board).
//
// 반도체와 모양이 다르다. 반도체는 '주차 x 모델' 한 겹인데
// 블룸은 '날짜 x 품목 x 공정(NCT/조립/출하)' 세 겹이고 매일 실적이 들어온다.
//
// 실적이 '아직 안 적힌 것'과 '0개'는 다르다. 서버가 null 로 내려주는 걸
// 0 으로 바꾸면 오전에 화면이 전부 0% 로 보인다. 그래서 int? 로 받는다.

int? _nInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.round();
  final t = v.toString().trim();
  if (t.isEmpty) return null;
  return int.tryParse(t) ?? double.tryParse(t)?.round();
}

String _s(dynamic v) => (v ?? '').toString().trim();

class BloomCell {
  final int? plan;
  final int? actual;
  const BloomCell({this.plan, this.actual});

  factory BloomCell.fromJson(Map j) =>
      BloomCell(plan: _nInt(j['plan']), actual: _nInt(j['actual']));

  bool get pending => (plan ?? 0) > 0 && actual == null;
}

class BloomStep {
  /// 엑셀에 적힌 그대로 — 'NCT(박닌)' · '조립(박장)' · '출하'
  final String step;

  /// 공장을 뗀 묶음 이름 — 'NCT' · '조립' · '출하'. 합계 낼 때만 쓴다.
  final String group;

  final int? wip;
  final int? monthPlan;
  final int? monthActual;

  /// 날짜 칸이 시작되기 전까지의 계획/실적 ('9월 9일 이전 데이터' 칸)
  final int? priorPlan;
  final int? priorActual;
  final String note;
  final Map<String, BloomCell> days;

  const BloomStep({
    required this.step,
    required this.group,
    this.wip,
    this.monthPlan,
    this.monthActual,
    this.priorPlan,
    this.priorActual,
    this.note = '',
    this.days = const {},
  });

  factory BloomStep.fromJson(Map j) {
    final raw = (j['days'] as Map?) ?? const {};
    return BloomStep(
      step: _s(j['step']),
      group: _s(j['group']).isEmpty ? _s(j['step']) : _s(j['group']),
      wip: _nInt(j['wip']),
      monthPlan: _nInt(j['month_plan']),
      monthActual: _nInt(j['month_actual']),
      priorPlan: _nInt(j['prior_plan']),
      priorActual: _nInt(j['prior_actual']),
      note: _s(j['note']),
      days: {
        for (final e in raw.entries)
          e.key.toString(): BloomCell.fromJson((e.value as Map?) ?? const {})
      },
    );
  }

  BloomCell? at(String date) => days[date];

  /// 실적이 적힌 마지막 날. 없으면 null.
  String? get lastActualDate {
    String? last;
    for (final e in days.entries) {
      if (e.value.actual == null) continue;
      if (last == null || e.key.compareTo(last) > 0) last = e.key;
    }
    return last;
  }

  /// 실적이 적힌 날까지 잡혀 있던 계획.
  ///
  /// 9월 전체 계획과만 비교하면 22일인 지금은 다 뒤처져 보인다.
  /// 실적과 같은 날까지의 계획을 분모로 써야 '지금 제대로 가고 있나' 가 보인다.
  /// 일별 계획이 비어 있으면(출하가 그렇다) null.
  int? get planToDate {
    final last = lastActualDate;
    if (last == null) return null;
    var sum = priorPlan ?? 0;
    var any = (priorPlan ?? 0) > 0;
    for (final e in days.entries) {
      if (e.key.compareTo(last) > 0) continue;
      final p = e.value.plan ?? 0;
      if (p > 0) any = true;
      sum += p;
    }
    return any && sum > 0 ? sum : null;
  }

  /// 월 누적 달성률(%). 계획이 없으면 null.
  int? get monthPct {
    final p = monthPlan ?? 0;
    if (p <= 0) return null;
    return ((monthActual ?? 0) * 100 / p).round();
  }
}

class BloomItem {
  final String item;
  final String code;

  /// 출하 대기 (포장 완료)
  final int? waitShip;

  /// 조립 완료 · 구매품 입고 대기 — 여기가 막히면 출하가 안 나간다
  final int? waitPart;

  final List<BloomStep> steps;

  const BloomItem({
    required this.item,
    this.code = '',
    this.waitShip,
    this.waitPart,
    this.steps = const [],
  });

  factory BloomItem.fromJson(Map j) => BloomItem(
        item: _s(j['item']),
        code: _s(j['code']),
        waitShip: _nInt(j['wait_ship']),
        waitPart: _nInt(j['wait_part']),
        steps: ((j['steps'] as List?) ?? const [])
            .whereType<Map>()
            .map(BloomStep.fromJson)
            .toList(),
      );

  /// 그 날 이 품목이 해야 할 일. 공정별 계획이 있는 것만.
  List<MapEntry<BloomStep, BloomCell>> plannedOn(String date) {
    final out = <MapEntry<BloomStep, BloomCell>>[];
    for (final s in steps) {
      final c = s.at(date);
      if (c != null && (c.plan ?? 0) > 0) out.add(MapEntry(s, c));
    }
    return out;
  }

  int planOn(String date) => plannedOn(date)
      .fold(0, (a, e) => a + (e.value.plan ?? 0));
}

class BloomNote {
  final String text;
  final String eta;
  const BloomNote({this.text = '', this.eta = ''});
  factory BloomNote.fromJson(Map j) =>
      BloomNote(text: _s(j['text']), eta: _s(j['eta']));
}

/// 하루치 공정별 합계. 서버가 계산해 내려준다.
class BloomDaySummary {
  final String date;
  final Map<String, int> plan;
  final Map<String, int> actual;
  final Map<String, bool> hasActual;
  final int totalPlan;
  final int totalActual;

  /// 계획은 있는데 실적이 하나도 안 적힌 상태. 0% 와 다르다.
  final bool pending;

  const BloomDaySummary({
    this.date = '',
    this.plan = const {},
    this.actual = const {},
    this.hasActual = const {},
    this.totalPlan = 0,
    this.totalActual = 0,
    this.pending = false,
  });

  factory BloomDaySummary.fromJson(Map j) {
    final groups = (j['groups'] as Map?) ?? const {};
    final plan = <String, int>{};
    final actual = <String, int>{};
    final has = <String, bool>{};
    for (final e in groups.entries) {
      final g = (e.value as Map?) ?? const {};
      plan[e.key.toString()] = _nInt(g['plan']) ?? 0;
      actual[e.key.toString()] = _nInt(g['actual']) ?? 0;
      has[e.key.toString()] = g['has_actual'] == true;
    }
    return BloomDaySummary(
      date: _s(j['date']),
      plan: plan,
      actual: actual,
      hasActual: has,
      totalPlan: _nInt(j['plan']) ?? 0,
      totalActual: _nInt(j['actual']) ?? 0,
      pending: j['pending'] == true,
    );
  }

  bool get isEmpty => date.isEmpty;

  int? get pct {
    if (totalPlan <= 0) return null;
    return (totalActual * 100 / totalPlan).round();
  }

  /// 화면에 늘 이 순서로 — 공정이 흐르는 순서다.
  static const List<String> order = ['NCT', '조립', '출하'];

  List<String> get groupsInOrder {
    final keys = {...plan.keys, ...actual.keys};
    final head = order.where(keys.contains).toList();
    final rest = keys.where((k) => !order.contains(k)).toList()..sort();
    return [...head, ...rest];
  }
}

/// '금액 실적' 시트 한 달 치 (USD). 계획은 예상실적 기준.
class BloomMoney {
  final String month;
  final double planUsd;
  final double doneUsd;
  final double salesUsd;
  const BloomMoney({
    this.month = '',
    this.planUsd = 0,
    this.doneUsd = 0,
    this.salesUsd = 0,
  });

  static BloomMoney? fromJson(dynamic j) {
    if (j is! Map) return null;
    final t = (j['total'] as Map?) ?? const {};
    double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
    final m = BloomMoney(
      month: _s(j['month']),
      planUsd: d(t['plan_usd']),
      doneUsd: d(t['done_usd']),
      salesUsd: d(t['sales_usd']),
    );
    return m.planUsd > 0 || m.doneUsd > 0 ? m : null;
  }

  int? get pct => planUsd > 0 ? (doneUsd * 100 / planUsd).round() : null;
}

class BloomDailyBoard {
  final bool hasBoard;
  final String title;
  final String reportDate;
  final String fileName;
  final List<String> dates;
  final List<BloomItem> items;
  final List<BloomNote> notes;
  final BloomDaySummary today;
  final BloomDaySummary? prev;

  /// 금액 실적 (블룸 전체 화면에만 온다. 품목 화면은 null)
  final BloomMoney? money;

  const BloomDailyBoard({
    this.hasBoard = false,
    this.title = '',
    this.reportDate = '',
    this.fileName = '',
    this.dates = const [],
    this.items = const [],
    this.notes = const [],
    this.today = const BloomDaySummary(),
    this.prev,
    this.money,
  });

  static const BloomDailyBoard empty = BloomDailyBoard();

  factory BloomDailyBoard.fromJson(Map j) {
    final sum = (j['summary'] as Map?) ?? const {};
    final prevRaw = sum['prev'];
    return BloomDailyBoard(
      hasBoard: j['has_board'] == true,
      title: _s(j['title']),
      reportDate: _s(j['report_date']),
      fileName: _s(j['file_name']),
      dates: ((j['dates'] as List?) ?? const []).map((e) => e.toString()).toList(),
      items: ((j['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(BloomItem.fromJson)
          .toList(),
      notes: ((j['notes'] as List?) ?? const [])
          .whereType<Map>()
          .map(BloomNote.fromJson)
          .toList(),
      today: BloomDaySummary.fromJson((sum['today'] as Map?) ?? const {}),
      prev: prevRaw is Map ? BloomDaySummary.fromJson(prevRaw) : null,
      money: BloomMoney.fromJson(j['money']),
    );
  }

  /// 오늘 할 일이 있는 품목만, 많은 순.
  List<BloomItem> itemsOn(String date) {
    final out = items.where((i) => i.planOn(date) > 0).toList();
    out.sort((a, b) => b.planOn(date).compareTo(a.planOn(date)));
    return out;
  }

  /// 조립은 끝났는데 구매품이 없어 못 나가는 것. 여기가 진짜 병목이다.
  List<BloomItem> get blocked {
    final out = items.where((i) => (i.waitPart ?? 0) > 0).toList();
    out.sort((a, b) => (b.waitPart ?? 0).compareTo(a.waitPart ?? 0));
    return out;
  }
}
