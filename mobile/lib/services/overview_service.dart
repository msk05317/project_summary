// 홈 화면 경영 요약 (/overview).
//
// 백엔드가 이미 계산해 주는 값을 그대로 받는다.
//  - 이번 달 계획 기준 예상 매출 / 실적 매출 / 달성률
//  - 출하 수량 계획·실적
//  - 프로젝트별 진행률
// 실패해도 화면이 깨지지 않도록 예외 대신 empty 를 돌려준다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class OverviewProject {
  final String key;
  final String label;
  final String? divisionId;
  final int modelsTotal;
  final int? progress;
  final int qtyPlan;
  final int qtyActual;
  final int revenue;
  final int planRevenue;
  final bool hasWeekly;

  const OverviewProject({
    required this.key,
    required this.label,
    required this.divisionId,
    required this.modelsTotal,
    required this.progress,
    required this.qtyPlan,
    required this.qtyActual,
    required this.revenue,
    required this.planRevenue,
    required this.hasWeekly,
  });

  factory OverviewProject.fromJson(Map j) => OverviewProject(
        key: (j['key'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        divisionId: j['division_id']?.toString(),
        modelsTotal: (j['models_total'] as num?)?.toInt() ?? 0,
        progress: (j['progress'] as num?)?.toInt(),
        qtyPlan: (j['qty_plan'] as num?)?.toInt() ?? 0,
        qtyActual: (j['qty_actual'] as num?)?.toInt() ?? 0,
        revenue: (j['revenue'] as num?)?.toInt() ?? 0,
        planRevenue: (j['plan_revenue'] as num?)?.toInt() ?? 0,
        hasWeekly: j['has_weekly'] == true,
      );
}

class OverviewSummary {
  final String month;
  final int projects;
  final int projectsActive;
  final int models;
  final int? progress;
  final int qtyPlan;
  final int qtyActual;
  final int revenue;
  final int planRevenue;
  final List<OverviewProject> items;
  final bool loaded;

  const OverviewSummary({
    required this.month,
    required this.projects,
    required this.projectsActive,
    required this.models,
    required this.progress,
    required this.qtyPlan,
    required this.qtyActual,
    required this.revenue,
    required this.planRevenue,
    required this.items,
    this.loaded = true,
  });

  static const OverviewSummary empty = OverviewSummary(
    month: '',
    projects: 0,
    projectsActive: 0,
    models: 0,
    progress: null,
    qtyPlan: 0,
    qtyActual: 0,
    revenue: 0,
    planRevenue: 0,
    items: <OverviewProject>[],
    loaded: false,
  );

  bool get hasRevenue => planRevenue > 0 || revenue > 0;

  /// 계획 대비 달성률(%). 계획이 없으면 null.
  int? get achievement =>
      planRevenue <= 0 ? null : (revenue * 100 / planRevenue).round();

  /// 매출이 있는 프로젝트를 실적 큰 순으로.
  List<OverviewProject> get topByRevenue {
    final list = items.where((e) => e.planRevenue > 0 || e.revenue > 0).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list;
  }

  factory OverviewSummary.fromJson(Map j) {
    final t = (j['totals'] as Map?) ?? const {};
    final raw = (j['projects'] as List?) ?? const [];
    return OverviewSummary(
      month: (j['month'] ?? '').toString(),
      projects: (t['projects'] as num?)?.toInt() ?? 0,
      projectsActive: (t['projects_active'] as num?)?.toInt() ?? 0,
      models: (t['models'] as num?)?.toInt() ?? 0,
      progress: (t['progress'] as num?)?.toInt(),
      qtyPlan: (t['qty_plan'] as num?)?.toInt() ?? 0,
      qtyActual: (t['qty_actual'] as num?)?.toInt() ?? 0,
      revenue: (t['revenue'] as num?)?.toInt() ?? 0,
      planRevenue: (t['plan_revenue'] as num?)?.toInt() ?? 0,
      items: raw
          .whereType<Map>()
          .map((e) => OverviewProject.fromJson(e))
          .toList(),
    );
  }
}

class OverviewService {
  static Future<OverviewSummary> fetch({String? month, String? divisionId}) async {
    try {
      final q = <String, String>{};
      if (month != null && month.isNotEmpty) q['month'] = month;
      if (divisionId != null && divisionId.isNotEmpty) q['division_id'] = divisionId;
      final uri = Uri.parse('$kApiBaseUrl/overview').replace(queryParameters: q.isEmpty ? null : q);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return OverviewSummary.empty;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return OverviewSummary.empty;
      return OverviewSummary.fromJson(decoded);
    } catch (_) {
      return OverviewSummary.empty;
    }
  }
}
