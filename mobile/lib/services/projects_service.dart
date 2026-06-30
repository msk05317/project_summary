// 프로젝트 목록을 백엔드에서 가져오는 서비스.
// 단일 책임: GET /projects → List<ProjectSummary>
//
// 또한, "즐겨찾기한 project_key 들" 만 필터해서 가져오는 헬퍼도 제공합니다.
// 이 헬퍼는 홈 화면의 즐겨찾기 영역에서 사용합니다.

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/project_summary.dart';

class ProjectsService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://projectsummary-production.up.railway.app',
  );

  // 전체 프로젝트 요약을 받아옵니다.
  // /projects 응답의 'projects' 배열을 모델 리스트로 변환합니다.
  static Future<List<ProjectSummary>> fetchAll() async {
    final uri = Uri.parse('$_baseUrl/projects');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('ProjectsService: HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('ProjectsService: unexpected JSON shape');
    }

    final list = (decoded['projects'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ProjectSummary.fromJson)
        .toList();

    return list;
  }

  // 특정 key 집합에 해당하는 프로젝트만 골라서 반환합니다.
  // 사용 예: 사용자가 별표(즐겨찾기)한 프로젝트들만 카드로 보여줄 때.
  // 빈 집합이 들어오면 추가 네트워크 호출 없이 즉시 빈 리스트를 반환합니다.
  static Future<List<ProjectSummary>> fetchByKeys(Set<String> keys) async {
    if (keys.isEmpty) return const [];

    final all = await fetchAll();
    // key 로 빠르게 조회하기 위한 map.
    final byKey = {for (final p in all) p.key: p};

    final result = <ProjectSummary>[];
    for (final k in keys) {
      final hit = byKey[k];
      if (hit != null) result.add(hit);
    }
    return result;
  }
}
