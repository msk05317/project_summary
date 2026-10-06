// 블룸 일 보드 (/projects/{key}/daily-board).
//
// 실패해도 화면이 안 깨지게 예외 대신 empty 를 돌려준다.
// 계산은 전부 서버에 둔다 — Admin 과 앱이 같은 숫자를 봐야 한다.

import '../config/app_config.dart';
import '../models/bloom_daily.dart';
import 'offline_store.dart';

class BloomService {
  static const String divisionId = 'bloom';
  static const String projectKey = 'bloom_main';

  // 품목 하나가 프로젝트 하나다. 캐시를 하나만 두면 YFP 를 열었다가
  // SL7 로 들어가면 남의 값이 잠깐 보인다.
  static final Map<String, BloomDailyBoard> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};
  static const Duration _cacheTtl = Duration(seconds: 60);

  /// [month] 는 'YYYY-MM'. 비우면 가장 최근 달.
  ///
  /// 10월이 되어도 9월 계획 대비 실적을 봐야 한다. 달마다 캐시를 따로
  /// 두는 이유도 같다 — 하나만 두면 9월을 보다가 돌아왔을 때 10월 자리에
  /// 9월 숫자가 잠깐 보인다.
  static Future<BloomDailyBoard> board({
    String projectKey_ = projectKey,
    String month = '',
    bool force = false,
  }) async {
    final ck = month.isEmpty ? projectKey_ : '$projectKey_@$month';
    final hit = _cache[ck];
    final at = _cacheAt[ck];
    if (!force &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return hit;
    }
    try {
      // 못 받아오면 마지막으로 받아둔 보드를 쓴다.
      final q = month.isEmpty ? '' : '?month=${Uri.encodeComponent(month)}';
      final got = await OfflineStore.fetch(
          '$kApiBaseUrl/projects/${Uri.encodeComponent(projectKey_)}/daily-board$q',
          'daily_board_$ck',
          timeout: const Duration(seconds: 12));
      final j = got.data;
      if (j is! Map) return BloomDailyBoard.empty;
      final out = BloomDailyBoard.fromJson(j);
      _cache[ck] = out;
      _cacheAt[ck] = DateTime.now();
      return out;
    } catch (_) {
      return BloomDailyBoard.empty;
    }
  }

  static void clear() {
    _cache.clear();
    _cacheAt.clear();
  }

  /// 블룸 품목 프로젝트인가. 품목 하나가 프로젝트 하나다.
  static bool isItemKey(String key) =>
      key.startsWith('bloom_') && key != projectKey;
}
