// 대시보드 데이터를 백엔드에서 가져오는 서비스.
// 단일 책임: GET /dashboard → List<DashboardCard>
//
// 홈 화면은 이 서비스가 돌려준 List<DashboardCard> 로부터
// DashboardSummary.fromCards(...) 를 통해 KPI 를 계산합니다.

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/dashboard.dart';

class DashboardService {
  // API_BASE_URL 은 빌드 시 --dart-define 으로 주입됩니다.
  // 주입이 없을 때를 대비해 운영 도메인을 기본값으로 둡니다.
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  // 대시보드 카드 전체를 가져옵니다.
  // 응답에는 cards / grouped_cards 가 함께 있는데,
  // 홈 KPI 용도로는 cards 만 사용합니다.
  // - 비정상 응답(200 외) / 잘못된 JSON: Exception 으로 상위에 전달
  static Future<List<DashboardCard>> fetchCards() async {
    final uri = Uri.parse('$_baseUrl/dashboard');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('DashboardService: HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('DashboardService: unexpected JSON shape');
    }

    final cards = (decoded['cards'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DashboardCard.fromJson)
        .toList();

    return cards;
  }
}
