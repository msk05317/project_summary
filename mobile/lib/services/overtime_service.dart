// 전사 잔업·특근을 받아온다.
//
//   GET /overtime/week?w=&kind=&scope=   전사 한 주 + 사업부 순위
//   GET /overtime/week/{div}?w=          사업부 한 곳 + 요일별
//
// 아직 한 주도 안 올렸으면 has_data=false 로 와서 홈 카드가 통째로 빠진다.
import '../models/overtime.dart';
import 'offline_store.dart';

class OvertimeService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  static String _q(Map<String, String> p) {
    final parts = <String>[];
    p.forEach((k, v) {
      if (v.trim().isNotEmpty) {
        parts.add('$k=${Uri.encodeQueryComponent(v.trim())}');
      }
    });
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  static Future<OvertimeWeek> fetchWeek({
    String week = '',
    String kind = 'overtime',
    String scope = 'total',
  }) async {
    final qs = _q({'w': week, 'kind': kind, 'scope': scope});
    try {
      final got = await OfflineStore.fetch(
        '$_baseUrl/overtime/week$qs',
        'overtime_week_${week}_${kind}_$scope',
      );
      final d = got.data;
      if (d is! Map) return OvertimeWeek.empty;
      return OvertimeWeek.fromJson(d.cast<String, dynamic>());
    } catch (_) {
      // 붙지 않는 서버에서도 화면은 카드만 빠진다.
      return OvertimeWeek.empty;
    }
  }

  static Future<OvertimeDivision> fetchDivision(
    String division, {
    String week = '',
  }) async {
    final id = division.trim();
    if (id.isEmpty) return OvertimeDivision.empty;
    final qs = _q({'w': week});
    try {
      final got = await OfflineStore.fetch(
        '$_baseUrl/overtime/week/${Uri.encodeComponent(id)}$qs',
        'overtime_div_${id}_$week',
      );
      final d = got.data;
      if (d is! Map) return OvertimeDivision.empty;
      return OvertimeDivision.fromJson(d.cast<String, dynamic>());
    } catch (_) {
      return OvertimeDivision.empty;
    }
  }
}
