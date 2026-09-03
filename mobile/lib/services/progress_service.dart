// 프로젝트별 진행률 요약 (/projects-progress-summary).
//
// 집계 규칙(백엔드 _model_progress_value 와 동일):
//  - 양산: PO 수량(계획)이 등록된 모델만. 출하 0이면 0%.
//  - 개발: 공정 단계에 계획일/실적일/상태 중 하나라도 입력된 모델만.
//  - 데이터가 없는 모델은 집계에서 빠지고, 전부 빠지면 progress = null → 화면에 '-'.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ProjectProgress {
  final String projectKey;
  final int? progress; // null = 집계 가능한 데이터 없음
  final int scoredCount; // 집계에 들어간 모델 수
  final int scoreSum; // 집계 모델 진행률 합 (가중 평균용)
  final int modelsTotal;

  const ProjectProgress({
    required this.projectKey,
    required this.progress,
    required this.scoredCount,
    required this.scoreSum,
    required this.modelsTotal,
  });

  bool get hasData => scoredCount > 0;

  factory ProjectProgress.fromJson(String key, Map j) => ProjectProgress(
        projectKey: (j['project_key'] ?? key).toString(),
        progress: (j['progress'] as num?)?.toInt(),
        scoredCount: (j['scored_count'] as num?)?.toInt() ?? 0,
        scoreSum: (j['score_sum'] as num?)?.toInt() ?? 0,
        modelsTotal: (j['models_total'] as num?)?.toInt() ?? 0,
      );
}

class ProgressSummary {
  final Map<String, ProjectProgress> projects;
  final int? progress; // 전체 가중 평균
  final int scoredCount;
  final int modelsTotal;

  const ProgressSummary({
    required this.projects,
    required this.progress,
    required this.scoredCount,
    required this.modelsTotal,
  });

  static const ProgressSummary empty = ProgressSummary(
    projects: {},
    progress: null,
    scoredCount: 0,
    modelsTotal: 0,
  );

  ProjectProgress? of(String projectKey) => projects[projectKey];

  /// 주어진 프로젝트들만의 가중 평균 (집계 모델 기준). 대상이 없으면 null.
  int? weightedFor(Iterable<String> projectKeys) {
    var count = 0;
    var sum = 0;
    for (final k in projectKeys) {
      final e = projects[k];
      if (e == null) continue;
      count += e.scoredCount;
      sum += e.scoreSum;
    }
    if (count == 0) return null;
    return (sum / count).round();
  }

  int scoredModelsFor(Iterable<String> projectKeys) {
    var count = 0;
    for (final k in projectKeys) {
      count += projects[k]?.scoredCount ?? 0;
    }
    return count;
  }

  factory ProgressSummary.fromJson(Map j) {
    final raw = (j['projects'] as Map?) ?? const {};
    final map = <String, ProjectProgress>{};
    raw.forEach((k, v) {
      if (v is Map) map[k.toString()] = ProjectProgress.fromJson(k.toString(), v);
    });
    return ProgressSummary(
      projects: map,
      progress: (j['progress'] as num?)?.toInt(),
      scoredCount: (j['scored_count'] as num?)?.toInt() ?? 0,
      modelsTotal: (j['models_total'] as num?)?.toInt() ?? 0,
    );
  }
}

class ProgressService {
  /// 실패해도 화면은 떠야 하므로 예외 대신 empty 를 돌려준다.
  static Future<ProgressSummary> fetch() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/projects-progress-summary'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return ProgressSummary.empty;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return ProgressSummary.empty;
      return ProgressSummary.fromJson(decoded);
    } catch (_) {
      return ProgressSummary.empty;
    }
  }
}

// ── 진행률 추이 (/progress-trend) ──────────────────────────────
// 주차 실적(양산) / 공정 실적일(개발)로 과거 시점을 재구성한 값이다.
// 마지막 점은 ProgressSummary.progress 와 일치한다.
class TrendPoint {
  final String label;
  final String date;
  final int? value;
  final int scoredCount;

  const TrendPoint({
    required this.label,
    required this.date,
    required this.value,
    required this.scoredCount,
  });

  factory TrendPoint.fromJson(Map j) => TrendPoint(
        label: (j['label'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        value: (j['value'] as num?)?.toInt(),
        scoredCount: (j['scored_count'] as num?)?.toInt() ?? 0,
      );
}

class ProgressTrend {
  final List<TrendPoint> points;
  final int? current;
  final int? delta; // 직전 구간 대비
  final int? deltaVsAverage; // 이전 구간 평균 대비

  const ProgressTrend({
    required this.points,
    required this.current,
    required this.delta,
    required this.deltaVsAverage,
  });

  static const ProgressTrend empty = ProgressTrend(
    points: [],
    current: null,
    delta: null,
    deltaVsAverage: null,
  );

  factory ProgressTrend.fromJson(Map j) => ProgressTrend(
        points: ((j['points'] as List?) ?? const [])
            .whereType<Map>()
            .map(TrendPoint.fromJson)
            .toList(),
        current: (j['current'] as num?)?.toInt(),
        delta: (j['delta'] as num?)?.toInt(),
        deltaVsAverage: (j['delta_vs_average'] as num?)?.toInt(),
      );
}

class TrendService {
  /// period: 'day' | 'week' | 'month'
  static Future<ProgressTrend> fetch({
    String period = 'week',
    int points = 4,
    String? divisionId,
  }) async {
    try {
      final q = {
        'period': period,
        'points': '$points',
        'division_id': ?divisionId,
      };
      final uri = Uri.parse('$kApiBaseUrl/progress-trend')
          .replace(queryParameters: q);
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return ProgressTrend.empty;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return ProgressTrend.empty;
      return ProgressTrend.fromJson(decoded);
    } catch (_) {
      return ProgressTrend.empty;
    }
  }
}
