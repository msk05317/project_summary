// 홈 화면 한 눈 요약 (/home/alerts).
//
// 예전 홈은 /dashboard 의 주간보고 카드로 사업부 상태를 셌다. 주간보고가
// 없는 사업부는 집계에서 통째로 빠져서 '12개 중 정상 2' 처럼 나왔고,
// 프로젝트 안에는 지연이 널려 있는데 홈은 '지연 0' 이었다.
// 여기서는 프로젝트 안에서 보는 값과 똑같은 모델 alert 를 그대로 받는다.

import '../config/app_config.dart';
import 'offline_store.dart';

/// 문제(지연·이슈)나 임박이 걸린 프로젝트 한 줄
class AlertProject {
  final String key;
  final String label;
  final int delayed;
  final int issue;
  final int soon;
  final int worstDays;
  final String worstModel;

  /// by_kind 로 올 때의 그 종류 건수. by_project 로 올 때는 0.
  final int count;

  const AlertProject({
    required this.key,
    required this.label,
    required this.delayed,
    required this.soon,
    this.worstDays = 0,
    this.worstModel = '',
    this.issue = 0,
    this.count = 0,
  });

  /// 경영진이 보는 것은 '문제 있냐 없냐' 다. 지연과 이슈가 그 둘이다.
  int get blocked => delayed + issue;

  factory AlertProject.fromJson(Map j) => AlertProject(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        delayed: (j['delayed'] as num?)?.toInt() ?? 0,
        issue: (j['issue'] as num?)?.toInt() ?? 0,
        soon: (j['soon'] as num?)?.toInt() ?? 0,
        worstDays: (j['worst_days'] as num?)?.toInt() ?? 0,
        worstModel: (j['worst_model'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// 모델 한 건 (지연 · 이슈 · 임박)
class AlertModel {
  final String projectKey;
  final String project;
  final String model;
  final String kind; // 지연 · 이슈 · 임박
  final String expected;
  final int? days;
  final String stage;
  final String note;
  /// 사람이 적어 둔 문제. kind 가 '이슈' 일 때 채워진다.
  final String issue;

  const AlertModel({
    required this.projectKey,
    required this.project,
    required this.model,
    required this.kind,
    required this.expected,
    required this.days,
    required this.stage,
    required this.note,
    this.issue = '',
  });

  /// 화면에 한 줄로 보여줄 말. 이슈면 적어 둔 내용이 먼저다.
  String get line => issue.isNotEmpty ? issue : (stage.isNotEmpty ? stage : note);

  factory AlertModel.fromJson(Map j) => AlertModel(
        projectKey: (j['project_key'] ?? '').toString(),
        project: (j['project'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        expected: (j['expected'] ?? '').toString(),
        days: (j['days'] as num?)?.toInt(),
        stage: (j['stage'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        issue: (j['issue'] ?? '').toString(),
      );
}

/// 블룸 오늘 상황. 모델이 없는 사업부라 일 보고 보드로 본다.
class BloomBrief {
  final String date;
  final int plan;
  final int actual;
  final bool pending;
  final String prevDate;
  final int prevPlan;
  final int prevActual;
  final int items;

  const BloomBrief({
    required this.date,
    required this.plan,
    required this.actual,
    required this.pending,
    required this.prevDate,
    required this.prevPlan,
    required this.prevActual,
    required this.items,
  });

  factory BloomBrief.fromJson(Map j) => BloomBrief(
        date: (j['date'] ?? '').toString(),
        plan: (j['plan'] as num?)?.toInt() ?? 0,
        actual: (j['actual'] as num?)?.toInt() ?? 0,
        pending: j['pending'] == true,
        prevDate: (j['prev_date'] ?? '').toString(),
        prevPlan: (j['prev_plan'] as num?)?.toInt() ?? 0,
        prevActual: (j['prev_actual'] as num?)?.toInt() ?? 0,
        items: (j['items'] as num?)?.toInt() ?? 0,
      );

  bool get hasData => plan > 0 || actual > 0 || prevPlan > 0;
}

class HomeAlerts {
  final String date;
  final int total;
  final int delayed;
  final int issue;
  final int soon;
  final int hold;
  final int poWait;
  final int done;
  final int running;
  /// 문제 없이 가고 있는 모델 수. 화면에 문제만 늘어놓으면 이게 안 보인다.
  final int normal;
  final int projects;
  final int projectsWithAlert;
  final int alertsTotal;
  final List<AlertProject> byProject;

  /// 타일별 내역. '지연'·'이슈'·'임박'·'보류'·'정상' → 그 종류의 프로젝트들.
  /// 홈의 전체 현황 타일을 누르면 바로 아래 펼쳐지는 목록이다.
  final Map<String, List<AlertProject>> byKind;
  final List<AlertModel> alerts;
  final List<AlertModel> holds;
  final List<AlertModel> poWaits;
  final List<AlertModel> normals;
  final BloomBrief? bloom;
  final bool loaded;
  /// 저장해 둔 걸 보여주는 중인지, 그게 언제 것인지
  final bool fromCache;
  final DateTime? savedAt;

  const HomeAlerts({
    required this.date,
    required this.total,
    required this.delayed,
    required this.soon,
    required this.hold,
    required this.poWait,
    required this.done,
    required this.running,
    required this.projects,
    required this.projectsWithAlert,
    required this.alertsTotal,
    required this.byProject,
    this.byKind = const {},
    required this.alerts,
    required this.holds,
    required this.poWaits,
    required this.bloom,
    this.normal = 0,
    this.normals = const [],
    this.issue = 0,
    this.loaded = true,
    this.fromCache = false,
    this.savedAt,
  });

  /// 지금 막혀 있는 것 — 지연 + 이슈. 임박은 아직 문제가 아니다.
  int get blocked => delayed + issue;

  /// 지연·이슈만 (임박 제외)
  List<AlertModel> get blockers =>
      alerts.where((a) => a.kind == '지연' || a.kind == '이슈').toList();

  HomeAlerts copyWith({bool? fromCache, DateTime? savedAt}) => HomeAlerts(
        date: date, total: total, delayed: delayed, issue: issue,
        soon: soon, hold: hold,
        poWait: poWait, done: done, running: running, projects: projects,
        projectsWithAlert: projectsWithAlert, alertsTotal: alertsTotal,
        byProject: byProject, byKind: byKind,
        alerts: alerts, holds: holds, poWaits: poWaits,
        normal: normal, normals: normals,
        bloom: bloom, loaded: loaded,
        fromCache: fromCache ?? this.fromCache,
        savedAt: savedAt ?? this.savedAt,
      );

  static const HomeAlerts empty = HomeAlerts(
    date: '', total: 0, delayed: 0, soon: 0, hold: 0, poWait: 0, done: 0,
    running: 0, projects: 0, projectsWithAlert: 0, alertsTotal: 0,
    byProject: [], byKind: {},
    alerts: [], holds: [], poWaits: [], normals: [], bloom: null,
    normal: 0, issue: 0, loaded: false,
  );

  factory HomeAlerts.fromJson(Map j) {
    final c = (j['counts'] as Map?) ?? const {};
    int n(String k) => (c[k] as num?)?.toInt() ?? 0;
    return HomeAlerts(
      date: (j['date'] ?? '').toString(),
      total: n('total'),
      delayed: n('delayed'),
      issue: n('issue'),
      soon: n('soon'),
      hold: n('hold'),
      poWait: n('po_wait'),
      done: n('done'),
      running: n('running'),
      normal: n('normal'),
      projects: (j['projects'] as num?)?.toInt() ?? 0,
      projectsWithAlert: (j['projects_with_alert'] as num?)?.toInt() ?? 0,
      alertsTotal: (j['alerts_total'] as num?)?.toInt() ?? 0,
      byProject: ((j['by_project'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertProject.fromJson)
          .toList(),
      byKind: {
        for (final e in ((j['by_kind'] as Map?) ?? const {}).entries)
          e.key.toString(): ((e.value as List?) ?? const [])
              .whereType<Map>()
              .map(AlertProject.fromJson)
              .toList(),
      },
      alerts: ((j['alerts'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertModel.fromJson)
          .toList(),
      holds: ((j['holds'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertModel.fromJson)
          .toList(),
      poWaits: ((j['po_waits'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertModel.fromJson)
          .toList(),
      normals: ((j['normals'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertModel.fromJson)
          .toList(),
      bloom: (j['bloom'] is Map) ? BloomBrief.fromJson(j['bloom'] as Map) : null,
    );
  }
}

class HomeAlertsService {
  /// 실패하면 예외 대신 empty 를 돌려준다 — 홈이 통째로 깨지면 안 된다.
  /// 대신 loaded=false 라서 화면이 '지연 없음' 과 구분해서 말할 수 있다.
  static Future<HomeAlerts> fetch(
      {int limit = 300, void Function(HomeAlerts)? onFresh}) async {
    try {
      final got = await OfflineStore.fetch(
          '$kApiBaseUrl/home/alerts?limit=$limit', 'home_alerts',
          timeout: const Duration(seconds: 20),
          onFresh: onFresh == null ? null : (c) => onFresh(_parse(c)));
      return _parse(got);
    } catch (_) {
      return HomeAlerts.empty;
    }
  }

  static HomeAlerts _parse(Cached<dynamic> got) {
    final decoded = got.data;
    if (decoded is! Map) return HomeAlerts.empty;
    return HomeAlerts.fromJson(decoded)
        .copyWith(fromCache: got.fromCache, savedAt: got.savedAt);
  }
}
