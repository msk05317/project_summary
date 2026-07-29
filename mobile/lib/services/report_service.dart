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
    if (decoded is! Map<String, dynamic>) {
      throw Exception('ReportService: unexpected JSON shape');
    }

    return ReportNote.fromJson(decoded);
  }
}
