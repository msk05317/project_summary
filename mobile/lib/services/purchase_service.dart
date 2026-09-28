// 사업부 매입·지급 현황을 받아온다 (GET /division/{id}/purchase).
//
// 매입은 사업부마다 형식이 달라서 지금은 PCB 만 채워져 있다. 데이터가
// 없는 사업부는 has_data=false 로 와서 화면에서 카드를 통째로 감춘다.
import '../models/purchase_status.dart';
import 'offline_store.dart';

class PurchaseService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  static Future<PurchaseStatus> fetch(String divisionId) async {
    final id = divisionId.trim();
    if (id.isEmpty) return PurchaseStatus.empty;
    try {
      final got = await OfflineStore.fetch(
        '$_baseUrl/division/$id/purchase',
        'purchase_$id',
      );
      final d = got.data;
      if (d is! Map) return PurchaseStatus.empty;
      return PurchaseStatus.fromJson(d.cast<String, dynamic>());
    } catch (_) {
      // 붙지 않는 서버에서도 화면은 그냥 카드만 빠진다.
      return PurchaseStatus.empty;
    }
  }
}
