import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class CacheService {
  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    if (await dir.exists()) {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try { total += await e.length(); } catch (_) {}
        }
      }
    }
    return total;
  }

  static Future<int> totalCacheBytes() async {
    var total = 0;
    total += await _dirSize(await getTemporaryDirectory());
    total += PaintingBinding.instance.imageCache.currentSizeBytes;
    return total;
  }

  static String format(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  /// 정리된 용량(bytes) 반환
  static Future<int> clear() async {
    final before = await totalCacheBytes();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    final tmp = await getTemporaryDirectory();
    if (await tmp.exists()) {
      await for (final e in tmp.list(followLinks: false)) {
        try { await e.delete(recursive: true); } catch (_) {}
      }
    }
    final after = await totalCacheBytes();
    return before - after;
  }
}
