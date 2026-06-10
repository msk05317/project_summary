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
}

// ============================================================
// 대시보드 응답 컨테이너 (flat + grouped)
// ============================================================
class DashboardData {
  final List<ProductCard> cards;
  final List<GroupedCard> groupedCards;
  DashboardData({required this.cards, required this.groupedCards});
}
