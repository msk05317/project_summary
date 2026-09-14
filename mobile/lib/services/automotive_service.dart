// 자동차사업부 데이터 (/divisions/automotive/summary, /projects/{key}/automotive-summary).
//
// 실패해도 화면이 깨지지 않게 예외 대신 empty 를 돌려준다.
// 사업부 화면과 고객사 화면이 같은 숫자를 보게 하려고 계산은 전부 서버에 둔다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/automotive.dart';

class AutomotiveService {
  static const String divisionId = 'automotive';

  /// 프로젝트 키만 보고 자동차사업부인지 가른다.
  /// (프로젝트 목록을 한 번 더 받아오지 않으려고 키 규칙을 쓴다)
  static bool isAutoKey(String key) =>
      key.toLowerCase().startsWith('auto_');

  /// 사업부 합계. 서버가 한 번에 내주는 게 정답이지만, 앱은 폰에 깔린 채로
  /// 서버보다 오래 산다. 그 엔드포인트가 없는 서버(배포 전)에 붙으면
  /// 화면이 통째로 빈다 — 그래서 고객사별 요약을 모아 같은 값을 만든다.
  /// 두 길 모두 제품 단위 계산은 서버가 낸 값을 그대로 쓰므로 숫자는 같다.
  // 홈 화면과 사업부 화면이 같은 값을 쓴다. 앱을 열자마자 두 번 받지 않게
  // 잠깐 들고 있는다. 당겨서 새로고침할 때는 force 로 지운다.
  static AutoDivisionSummary? _cache;
  static DateTime? _cacheAt;
  static const Duration _cacheTtl = Duration(seconds: 60);

  static Future<AutoDivisionSummary> division({
    int? year,
    List<String> keys = const [],
    bool force = false,
  }) async {
    final y = year ?? DateTime.now().year;
    final hit = _cache;
    final at = _cacheAt;
    if (!force &&
        hit != null &&
        hit.loaded &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return hit;
    }
    try {
      final r = await http
          .get(Uri.parse('$kApiBaseUrl/divisions/automotive/summary?year=$y'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map) {
          final s = AutoDivisionSummary.fromJson(j);
          if (s.projects.isNotEmpty) return _keep(s);
        }
      }
    } catch (_) {
      // 아래 우회로로 간다
    }
    if (keys.isEmpty) return AutoDivisionSummary.empty;
    return _keep(await _fromProjects(keys, y));
  }

  static AutoDivisionSummary _keep(AutoDivisionSummary s) {
    if (s.loaded) {
      _cache = s;
      _cacheAt = DateTime.now();
    }
    return s;
  }

  /// 고객사별 요약을 받아 사업부 합계를 만든다 (우회로).
  static Future<AutoDivisionSummary> _fromProjects(
      List<String> keys, int year) async {
    final list = await Future.wait(keys.map(project));

    double total = 0;
    final years = <String>{};
    for (final s in list) {
      if (!s.loaded) continue;
      total += s.revenue;
      years.addAll(s.years);
    }

    final rows = <AutoProjectRow>[];
    final over = <String>[];
    for (var i = 0; i < keys.length; i++) {
      final s = list[i];
      if (!s.loaded) continue;
      final cell = s.byYear['$year'];
      rows.add(AutoProjectRow(
        key: keys[i],
        label: s.label,
        products: s.products.length,
        mass: s.mass,
        dev: s.dev,
        qty: s.qty,
        revenue: s.revenue,
        yearQty: cell?.qty ?? 0,
        yearRevenue: cell?.revenue ?? 0,
        share: total > 0 ? s.revenue / total : 0,
        overCost: s.overCost,
        overCostNames: s.overCostNames,
      ));
      over.addAll(s.overCostNames);
    }
    if (rows.isEmpty) return AutoDivisionSummary.empty;

    rows.sort((a, b) {
      final c = b.revenue.compareTo(a.revenue);
      return c != 0 ? c : a.label.compareTo(b.label);
    });

    final ylist = years.toList()..sort();
    final byYear = <String, AutoYearCell>{};
    for (final y in ylist) {
      var q = 0;
      var rev = 0.0;
      for (final s in list) {
        final c = s.byYear[y];
        if (c == null) continue;
        q += c.qty;
        rev += c.revenue;
      }
      byYear[y] = AutoYearCell(qty: q, revenue: rev);
    }

    return AutoDivisionSummary(
      year: year,
      years: ylist,
      projects: rows,
      byYear: byYear,
      totalProjects: rows.length,
      withContract: rows.where((r) => r.hasContract).length,
      totalProducts: rows.fold(0, (a, r) => a + r.products),
      qty: rows.fold(0, (a, r) => a + r.qty),
      revenue: total,
      yearQty: rows.fold(0, (a, r) => a + r.yearQty),
      yearRevenue: rows.fold(0.0, (a, r) => a + r.yearRevenue),
      overCost: over.length,
      overCostNames: over,
      loaded: true,
    );
  }

  static Future<AutoProjectSummary> project(String key) async {
    try {
      final r = await http
          .get(Uri.parse(
              '$kApiBaseUrl/projects/${Uri.encodeComponent(key)}/automotive-summary'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return AutoProjectSummary.empty;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return AutoProjectSummary.empty;
      return AutoProjectSummary.fromJson(j);
    } catch (_) {
      return AutoProjectSummary.empty;
    }
  }
}
