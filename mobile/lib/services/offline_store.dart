// 마지막으로 받아온 데이터를 기기에 남겨 둔다.
//
// 지금까지는 열 때마다 fly.io 에서 받아왔고, 연결이 안 되면 화면이
// 비거나 '불러오지 못했습니다' 만 떴다. 비행기 안이나 공장 안처럼
// 신호가 없는 곳에서도 마지막으로 본 내용은 바로 보여야 한다.
//
// 규칙
//  - 받아오면 저장한다 (JSON 그대로, 화면별 키).
//  - 못 받아오면 저장해 둔 걸 돌려주고 fromCache=true 로 알린다.
//  - 저장된 것도 없으면 그때만 예외를 던진다.
//  - 저장된 내용을 보여줄 때는 언제 것인지 반드시 같이 보여준다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 받아온 값 + 언제 것인지 + 저장본인지
class Cached<T> {
  final T data;
  final DateTime? savedAt;
  final bool fromCache;

  const Cached(this.data, {this.savedAt, this.fromCache = false});

  Cached<R> map<R>(R Function(T) f) =>
      Cached<R>(f(data), savedAt: savedAt, fromCache: fromCache);
}

/// 앱 전체의 연결 상태. 홈 배너가 이걸 본다.
class OfflineStatus {
  /// null = 정상. 값이 있으면 '그 시각에 저장된 내용을 보고 있다'.
  static final ValueNotifier<DateTime?> savedAt = ValueNotifier<DateTime?>(null);

  static void online() {
    if (savedAt.value != null) savedAt.value = null;
  }

  static void offline(DateTime? at) {
    savedAt.value = at ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool get isOffline => savedAt.value != null;
}

class OfflineStore {
  static Directory? _dir;

  static Future<Directory?> _root() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/offline');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      return d;
    } catch (_) {
      return null; // 저장을 못 해도 앱은 돌아가야 한다
    }
  }

  static String _safe(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<void> save(String key, dynamic json) async {
    try {
      final d = await _root();
      if (d == null) return;
      final f = File('${d.path}/${_safe(key)}.json');
      await f.writeAsString(jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'data': json,
      }));
    } catch (_) {}
  }

  static Future<Cached<dynamic>?> load(String key) async {
    try {
      final d = await _root();
      if (d == null) return null;
      final f = File('${d.path}/${_safe(key)}.json');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return null;
      return Cached<dynamic>(m['data'],
          savedAt: DateTime.tryParse((m['saved_at'] ?? '').toString()),
          fromCache: true);
    } catch (_) {
      return null;
    }
  }

  /// 받아오고 저장한다. 실패하면 저장해 둔 걸 돌려준다.
  /// 둘 다 없으면 예외를 던진다 (화면이 '불러오지 못했습니다' 를 띄울 수 있게).
  ///
  /// [onFresh] 를 주면 **저장된 값을 먼저 돌려주고** 새 값은 뒤에서 받아
  /// 알려 준다. 지금까지는 앱을 열 때마다 fly.io 응답을 먼저 기다렸다.
  /// 저장된 값이 멀쩡히 있어도 홈이 빈 채로 있었고, 신호가 나쁘면 그게
  /// 8초, 20초까지 갔다. 어제 본 숫자라도 0.1초에 보이는 편이 낫다.
  static Future<Cached<dynamic>> fetch(
    String url,
    String key, {
    Duration timeout = const Duration(seconds: 8),
    void Function(Cached<dynamic>)? onFresh,
  }) async {
    if (onFresh != null) {
      final c = await load(key);
      if (c != null) {
        // 저장된 게 있으면 그걸 먼저 준다. 새 값은 따라온다.
        unawaited(_network(url, key, timeout).then((f) {
          if (f != null) {
            onFresh(f);
          } else {
            // 뒤에서 받아오다 실패했으면 배너가 그 사실을 말해야 한다.
            OfflineStatus.offline(c.savedAt);
          }
        }));
        return c;
      }
    }
    final fresh = await _network(url, key, timeout);
    if (fresh != null) return fresh;
    final c = await load(key);
    if (c != null) {
      OfflineStatus.offline(c.savedAt);
      return c;
    }
    throw const SocketException('받아오지 못했고 저장된 것도 없습니다');
  }

  /// 네트워크에서만 받아 저장한다. 실패하면 null — 여기서는 저장본을
  /// 보지 않는다. 저장본으로 떨어질지는 부르는 쪽이 정한다.
  static Future<Cached<dynamic>?> _network(
      String url, String key, Duration timeout) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      await save(key, data);
      OfflineStatus.online();
      return Cached<dynamic>(data, savedAt: DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// 저장된 것 중 가장 오래된 시각. 배너 문구에 쓴다.
  static String describe(DateTime? at) {
    if (at == null || at.millisecondsSinceEpoch == 0) return '저장된 내용';
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return sameDay
        ? '오늘 $hh:$mm 기준'
        : '${at.month}/${at.day} $hh:$mm 기준';
  }
}
