import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/report_note.dart';

class ReportService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  static Future<ReportNote> fetchByProject(String projectKey) async {
    // /projects/{project_key} 는 notes + status + division_label 을 함께 주기 때문에
    // 상세 화면용으로 /notes/by_project 보다 더 적합합니다.
    final uri = Uri.parse('$_baseUrl/projects/$projectKey');

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('ReportService: HTTP ${res.statusCode} for $projectKey');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));

    // 서버가 /projects/{key} 에서 Map이 아닌 List(merged 카드 배열)를
    // 반환하는 경우가 있어 방어한다.
    Map<String, dynamic>? map;
    if (decoded is Map<String, dynamic>) {
      map = decoded;
    } else if (decoded is List && decoded.isNotEmpty) {
      // title이 projectKey와 매칭되는 카드를 우선 선택, 없으면 첫 번째
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final t = (item['title'] ?? item['label'] ?? item['name'] ?? '').toString().trim();
          if (t.isNotEmpty && t == projectKey.trim()) {
            map = item;
            break;
          }
        }
      }
      // 매칭 실패 시 첫 번째 Map 요소 사용
      if (map == null) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) { map = item; break; }
        }
      }
    }

    if (map == null) {
      throw Exception('ReportService: unexpected JSON shape for $projectKey');
    }

    return ReportNote.fromJson(map);
  }
}
