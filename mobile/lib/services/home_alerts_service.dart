// 홈 화면 한 눈 요약 (/home/alerts).
//
// 예전 홈은 /dashboard 의 주간보고 카드로 사업부 상태를 셌다. 주간보고가
// 없는 사업부는 집계에서 통째로 빠져서 '12개 중 정상 2' 처럼 나왔고,
// 프로젝트 안에는 지연이 널려 있는데 홈은 '지연 0' 이었다.
// 여기서는 프로젝트 안에서 보는 값과 똑같은 모델 alert 를 그대로 받는다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// 지연·임박이 걸린 프로젝트 한 줄
class AlertProject {
  final String key;
  final String label;
  final int delayed;
  final int soon;
  final int worstDays;
  final String worstModel;

  const AlertProject({
    required this.key,
    required this.label,
    required this.delayed,
    required this.soon,
    required this.worstDays,
    required this.worstModel,
  });

  factory AlertProject.fromJson(Map j) => AlertProject(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        delayed: (j['delayed'] as num?)?.toInt() ?? 0,
        soon: (j['soon'] as num?)?.toInt() ?? 0,
        worstDays: (j['worst_days'] as num?)?.toInt() ?? 0,
        worstModel: (j['worst_model'] ?? '').toString(),
      );
}

/// 모델 한 건 (지연·임박)
class AlertModel {
  final String projectKey;
  final String project;
  final String model;
  final String kind; // 지연 · 임박
  final String expected;
  final int? days;
  final String stage;
  final String note;

  const AlertModel({
    required this.projectKey,
    required this.project,
    required this.model,
    required this.kind,
    required this.expected,
    required this.days,
    required this.stage,
    required this.note,
  });

  factory AlertModel.fromJson(Map j) => AlertModel(
        projectKey: (j['project_key'] ?? '').toString(),
        project: (j['project'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        expected: (j['expected'] ?? '').toString(),
        days: (j['days'] as num?)?.toInt(),
        stage: (j['stage'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
      );
}

class HomeAlerts {
  final String date;
  final int total;
  final int delayed;
  final int soon;
  final int hold;
  final int poWait;
  final int done;
  final int running;
  final int projects;
  final int projectsWithAlert;
  final int alertsTotal;
  final List<AlertProject> byProject;
  final List<AlertModel> alerts;
  final bool loaded;

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
    required this.alerts,
    this.loaded = true,
  });

  static const HomeAlerts empty = HomeAlerts(
    date: '', total: 0, delayed: 0, soon: 0, hold: 0, poWait: 0, done: 0,
    running: 0, projects: 0, projectsWithAlert: 0, alertsTotal: 0,
    byProject: [], alerts: [], loaded: false,
  );

  factory HomeAlerts.fromJson(Map j) {
    final c = (j['counts'] as Map?) ?? const {};
    int n(String k) => (c[k] as num?)?.toInt() ?? 0;
    return HomeAlerts(
      date: (j['date'] ?? '').toString(),
      total: n('total'),
      delayed: n('delayed'),
      soon: n('soon'),
      hold: n('hold'),
      poWait: n('po_wait'),
      done: n('done'),
      running: n('running'),
      projects: (j['projects'] as num?)?.toInt() ?? 0,
      projectsWithAlert: (j['projects_with_alert'] as num?)?.toInt() ?? 0,
      alertsTotal: (j['alerts_total'] as num?)?.toInt() ?? 0,
      byProject: ((j['by_project'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertProject.fromJson)
          .toList(),
      alerts: ((j['alerts'] as List?) ?? const [])
          .whereType<Map>()
          .map(AlertModel.fromJson)
          .toList(),
    );
  }
}

class HomeAlertsService {
  /// 실패하면 예외 대신 empty 를 돌려준다 — 홈이 통째로 깨지면 안 된다.
  /// 대신 loaded=false 라서 화면이 '지연 없음' 과 구분해서 말할 수 있다.
  static Future<HomeAlerts> fetch({int limit = 12}) async {
    try {
      final uri = Uri.parse('$kApiBaseUrl/home/alerts?limit=$limit');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return HomeAlerts.empty;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return HomeAlerts.empty;
      return HomeAlerts.fromJson(decoded);
    } catch (_) {
      return HomeAlerts.empty;
    }
  }
}
