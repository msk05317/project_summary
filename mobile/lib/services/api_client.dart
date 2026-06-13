import '../config/app_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_card.dart';

// Android 에뮬레이터에서 macOS localhost 접근용

class ApiClient {
  /// 대시보드 카드 목록 (호환: flat 카드만 반환)
  Future<List<ProductCard>> fetchDashboard() async {
    final data = await fetchDashboardData();
    return data.cards;
  }

  /// 대시보드 통합 응답 (flat + grouped 둘 다)
  Future<DashboardData> fetchDashboardData() async {
    final res = await http.get(Uri.parse('$kApiBaseUrl/dashboard'));
    print('🟡 /dashboard 응답: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('대시보드 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final List rawCards = decoded['cards'] ?? [];
    final List rawGrouped = decoded['grouped_cards'] ?? [];
    print('🟢 flat: ${rawCards.length} / grouped: ${rawGrouped.length}');

    final cards = rawCards
        .map((j) => ProductCard.fromJson(j as Map<String, dynamic>))
        .toList();
    final grouped = rawGrouped
        .map((j) => GroupedCard.fromJson(j as Map<String, dynamic>))
        .toList();
    return DashboardData(cards: cards, groupedCards: grouped);
  }

  /// 프로젝트 버튼 목록
  Future<List<Map<String, dynamic>>> fetchProjects() async {
    final res = await http.get(Uri.parse('$kApiBaseUrl/projects'));
    print('🟡 /projects 응답: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('프로젝트 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final List rawProjects = decoded['projects'] ?? [];
    print('🟢 받은 프로젝트 수: ${rawProjects.length}');

    return rawProjects
        .map<Map<String, dynamic>>((p) => Map<String, dynamic>.from(p as Map))
        .toList();
  }

  /// 프로젝트 상세
  Future<Map<String, dynamic>> fetchProjectDetail(String key) async {
    final res = await http.get(Uri.parse('$kApiBaseUrl/projects/$key'));
    print('🟡 /projects/$key 응답: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('프로젝트 상세 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return Map<String, dynamic>.from(decoded as Map);
  }

  /// 제품 상세
  Future<ProductDetail> fetchProductDetail(
    String docId,
    String productName,
  ) async {
    final url = Uri.parse(
      '$kApiBaseUrl/reports/$docId/${Uri.encodeComponent(productName)}',
    );
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('제품 상세 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return ProductDetail.fromJson(decoded as Map<String, dynamic>);
  }

  /// 공개 사업부 목록 (id, label) 반환
  Future<List<Map<String, String>>> fetchDivisions() async {
    try {
      final res = await http.get(Uri.parse('$kApiBaseUrl/divisions'));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = (body['divisions'] as List?) ?? const [];
      return [
        for (final d in list)
          {
            'id': (d['id'] as String?) ?? '',
            'label': (d['label'] as String?) ?? '',
          }
      ].where((m) => m['id']!.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 특정 사업부의 모든 프로젝트(빈 것 포함) 반환.
  /// 백엔드 /divisions 응답에서 해당 사업부의 projects 배열을 추출.
  Future<List<Map<String, dynamic>>> fetchDivisionProjects(String divisionId) async {
    try {
      final res = await http.get(Uri.parse('$kApiBaseUrl/divisions'));
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final divs = (body['divisions'] as List?) ?? const [];
      for (final d in divs) {
        if (d is! Map) continue;
        if ((d['id'] as String?) != divisionId) continue;
        final ps = (d['projects'] as List?) ?? const [];
        return ps.map<Map<String, dynamic>>((p) {
          final m = Map<String, dynamic>.from(p as Map);
          m['division_id'] = divisionId;
          m['key'] = m['id']; // dashboard_screen에서 'key' 사용 호환
          return m;
        }).toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 사업부별 최신 업데이트 시각 맵 반환 (division_id -> ISO8601 문자열)
  Future<Map<String, String>> fetchDivisionUpdates() async {
    try {
      final res = await http.get(Uri.parse('$kApiBaseUrl/divisions/updates'));
      if (res.statusCode != 200) return {};
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = (body['divisions'] as List?) ?? const [];
      return {
        for (final d in list)
          (d['division_id'] as String):
              (d['latest_updated_at'] as String? ?? ''),
      };
    } catch (_) {
      return {};
    }
  }
}

// ============================================================
// 대시보드 응답 컨테이너 (flat + grouped)
// ============================================================
class DashboardData {
  final List<ProductCard> cards;
  final List<GroupedCard> groupedCards;
  DashboardData({required this.cards, required this.groupedCards});
}
