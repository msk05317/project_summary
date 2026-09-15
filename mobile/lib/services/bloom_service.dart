// 블룸 일 보드 (/projects/{key}/daily-board).
//
// 실패해도 화면이 안 깨지게 예외 대신 empty 를 돌려준다.
// 계산은 전부 서버에 둔다 — Admin 과 앱이 같은 숫자를 봐야 한다.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/bloom_daily.dart';

class BloomService {
  static const String divisionId = 'bloom';
  static const String projectKey = 'bloom_main';

  // 품목 하나가 프로젝트 하나다. 캐시를 하나만 두면 YFP 를 열었다가
  // SL7 로 들어가면 남의 값이 잠깐 보인다.
  static final Map<String, BloomDailyBoard> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};
  static const Duration _cacheTtl = Duration(seconds: 60);

  static Future<BloomDailyBoard> board({
    String projectKey_ = projectKey,
    bool force = false,
  }) async {
    final hit = _cache[projectKey_];
    final at = _cacheAt[projectKey_];
    if (!force &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return hit;
    }
    try {
      final uri = Uri.parse(
          '$kApiBaseUrl/projects/${Uri.encodeComponent(projectKey_)}/daily-board');
      final r = await http.get(uri).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return BloomDailyBoard.empty;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return BloomDailyBoard.empty;
      final out = BloomDailyBoard.fromJson(j);
      _cache[projectKey_] = out;
      _cacheAt[projectKey_] = DateTime.now();
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
