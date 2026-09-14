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

  static Future<AutoDivisionSummary> division({int? year}) async {
    try {
      final q = year == null ? '' : '?year=$year';
      final r = await http
          .get(Uri.parse('$kApiBaseUrl/divisions/automotive/summary$q'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return AutoDivisionSummary.empty;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return AutoDivisionSummary.empty;
      return AutoDivisionSummary.fromJson(j);
    } catch (_) {
      return AutoDivisionSummary.empty;
    }
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
