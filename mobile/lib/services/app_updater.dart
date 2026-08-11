import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

class AppVersionInfo {
  final String latestVersion;
  final int latestVersionCode;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  AppVersionInfo({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
        latestVersion: (j['latest_version'] as String?) ?? '1.0.0',
        latestVersionCode: (j['latest_version_code'] as int?) ?? 1,
        downloadUrl: (j['download_url'] as String?) ?? (j['apk_url'] as String?) ?? '',
        releaseNotes: (j['release_notes'] as String?) ?? '',
        forceUpdate: (j['force_update'] as bool?) ?? false,
      );
}

class AppUpdater {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  final Dio _dio = Dio();

  /// 서버 버전 조회. 실패 시 null.
  Future<AppVersionInfo?> fetchLatest() async {
    try {
      // GitHub API 사용 (raw URL 캐시 문제 방지, 실시간 반영)
      const apiUrl = 'https://api.github.com/repos/msk05317/project_summary/contents/backend/app_version.json';
      final res = await _dio.get(apiUrl);
      if (res.statusCode != 200) return null;
      // GitHub API는 base64 인코딩된 content 반환
      final content = res.data['content'] as String?;
      if (content == null) return null;
      final decoded = utf8.decode(base64.decode(content.replaceAll('\n', '')));
      final jsonMap = jsonDecode(decoded) as Map<String, dynamic>;
      return AppVersionInfo.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  /// 현재 앱 versionCode 반환
  Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 1;
  }

  /// 시작 시 호출 — 업데이트가 있으면 다이얼로그 표시
  Future<void> checkAndPromptUpdate(BuildContext context) async {
    final latest = await fetchLatest();
    debugPrint('[AppUpdater] latest=${latest?.latestVersion}, latestCode=${latest?.latestVersionCode}');
    if (latest == null) return;
    final currentCode = await currentVersionCode();
    final currentInfo = await PackageInfo.fromPlatform();
    final currentVersion = currentInfo.version;
    debugPrint('[AppUpdater] currentCode=$currentCode, currentVersion=$currentVersion');

    // versionCode 또는 semantic version 중 하나라도 낮으면 업데이트 필요
    final needsUpdate = latest.latestVersionCode > currentCode ||
        _compareVersion(latest.latestVersion, currentVersion) > 0;

    if (!needsUpdate) return;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: !latest.forceUpdate,
      builder: (ctx) => _UpdateDialog(info: latest, updater: this),
    );
  }

  /// semantic version 비교 (예: "2.1.3" vs "2.1.2")
  /// - suffix(-test, +14 등)는 제거하고 숫자만 비교
  /// - 반환값: a>b -> 1, a==b -> 0, a<b -> -1
  int _compareVersion(String a, String b) {
    String normalize(String v) {
      var s = v.trim();
      s = s.replaceFirst(RegExp(r'^v'), '');
      s = s.split('+').first;
      s = s.split('-').first;
      return s;
    }

    final ap = normalize(a).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bp = normalize(b).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = ap.length > bp.length ? ap.length : bp.length;

    while (ap.length < maxLen) { ap.add(0); }
    while (bp.length < maxLen) { bp.add(0); }

    for (var i = 0; i < maxLen; i++) {
      if (ap[i] > bp[i]) return 1;
      if (ap[i] < bp[i]) return -1;
    }
    return 0;
  }

  /// 알림 클릭 등에서 호출하는 강제 업데이트 팝업.
  /// versionCode 비교 없이 무조건 다이얼로그를 띄운다.
  Future<void> promptUpdateForced(BuildContext context) async {
    final latest = await fetchLatest();
    if (latest == null) return;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: !latest.forceUpdate,
      builder: (ctx) => _UpdateDialog(info: latest, updater: this),
    );
  }

  /// 알림 클릭 시 바로 업데이트 다운로드 시작.
  /// 팝업 없이 APK 다운로드 후 설치 화면까지 바로 진행한다.
  Future<void> startDirectUpdateDownload({
    void Function(double progress)? onProgress,
  }) async {
    final latest = await fetchLatest();
    if (latest == null) return;

    await downloadAndInstall(
      info: latest,
      onProgress: onProgress ?? (_) {},
    );
  }

  /// APK 다운로드 + 설치 화면 열기
  Future<void> downloadAndInstall({
    required AppVersionInfo info,
    required void Function(double) onProgress,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final savePath = '${dir.path}/app_release.apk';
    final url = info.downloadUrl.startsWith('http')
        ? info.downloadUrl
        : '$kApiBaseUrl${info.downloadUrl}';

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (rcv, total) {
        if (total > 0) onProgress(rcv / total);
      },
    );

    if (kDebugMode) {
      debugPrint('APK saved: $savePath');
    }
    // 설치 화면 열기
    await OpenFilex.open(savePath, type: 'application/vnd.android.package-archive');
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppVersionInfo info;
  final AppUpdater updater;
  const _UpdateDialog({required this.info, required this.updater});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0.0;
  bool _downloading = false;

  Future<void> _start() async {
    setState(() => _downloading = true);
    try {
      await widget.updater.downloadAndInstall(
        info: widget.info,
        onProgress: (p) => setState(() => _progress = p),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업데이트 실패: $e')),
      );
      setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('새 버전 ${info.latestVersion}이(가) 있습니다'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.releaseNotes.isNotEmpty) ...[
            Text(info.releaseNotes),
            const SizedBox(height: 16),
          ],
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ],
        ],
      ),
      actions: [
        if (!info.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('나중에'),
          ),
        FilledButton(
          onPressed: _downloading ? null : _start,
          child: Text(_downloading ? '다운로드 중...' : '업데이트'),
        ),
      ],
    );
  }
}
