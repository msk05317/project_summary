import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_card.dart';

// Android 에뮬레이터에서 macOS localhost 접근용
const String baseUrl = 'http://10.0.2.2:8000';

class ApiClient {
  /// 대시보드 카드 목록
  Future<List<ProductCard>> fetchDashboard() async {
    final res = await http.get(Uri.parse('$baseUrl/dashboard'));
    print('🟡 /dashboard 응답: ${res.statusCode}');

    if (res.statusCode != 200) {
      throw Exception('대시보드 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final List rawCards = decoded['cards'] ?? [];
    print('🟢 받은 카드 수: ${rawCards.length}');

    return rawCards
        .map((j) => ProductCard.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// 프로젝트 버튼 목록
  Future<List<Map<String, dynamic>>> fetchProjects() async {
    final res = await http.get(Uri.parse('$baseUrl/projects'));
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
    final res = await http.get(Uri.parse('$baseUrl/projects/$key'));
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
      '$baseUrl/reports/$docId/${Uri.encodeComponent(productName)}',
    );
    final res = await http.get(url);

    if (res.statusCode != 200) {
      throw Exception('제품 상세 로드 실패 (${res.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return ProductDetail.fromJson(decoded as Map<String, dynamic>);
  }
}