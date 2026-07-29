// 사업부 목록을 백엔드에서 가져오는 서비스.
// 단일 책임: GET /divisions → List<Division>
//
// 화면(UI)에서 직접 http 를 호출하지 않게 하기 위한 얇은 래퍼입니다.

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/division.dart';

class DivisionsService {
  // API_BASE_URL 은 빌드 시 --dart-define 으로 주입됩니다.
  // 주입이 없을 때를 대비해 운영 도메인을 기본값으로 둡니다.
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  // 전체 사업부 목록을 받아옵니다.
  // - 정상 응답: divisions 배열을 Division 모델 리스트로 변환
  // - 비정상 응답(200 외)/잘못된 JSON: Exception 으로 상위에 전달
  // 결과는 order 기준으로 오름차순 정렬됩니다.
  static Future<List<Division>> fetchAll() async {
    final uri = Uri.parse('$_baseUrl/divisions');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('DivisionsService: HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('DivisionsService: unexpected JSON shape');
    }

    final list = (decoded['divisions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Division.fromJson)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return list;
  }
}
