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
        downloadUrl: (j['download_url'] as String?) ?? '',
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
      final res = await _dio.get('$kApiBaseUrl/app/version');
      if (res.statusCode != 200) return null;
      return AppVersionInfo.fromJson(
          Map<String, dynamic>.from(res.data as Map));
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
    if (latest == null) return;
    final currentCode = await currentVersionCode();
    if (latest.latestVersionCode <= currentCode) return;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: !latest.forceUpdate,
      builder: (ctx) => _UpdateDialog(info: latest, updater: this),
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
