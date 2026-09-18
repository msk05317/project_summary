import 'dart:convert';
import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';

class AppVersionInfo {
  final String latestVersion;
  final int latestVersionCode;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  /// 서버에 받을 APK 가 실제로 올라와 있는지.
  /// 저장소가 비공개라 GitHub 릴리스 주소로는 앱이 못 받는다 (404).
  final bool apkReady;

  AppVersionInfo({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    this.apkReady = false,
  });

  /// 실제로 받을 수 있는 주소인가
  bool get downloadable =>
      apkReady || (downloadUrl.isNotEmpty && !downloadUrl.contains('github.com'));

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
        latestVersion: (j['latest_version'] as String?) ?? '1.0.0',
        latestVersionCode: (j['latest_version_code'] as int?) ?? 1,
        downloadUrl: (j['download_url'] as String?) ?? (j['apk_url'] as String?) ?? '',
        releaseNotes: (j['release_notes'] as String?) ?? '',
        forceUpdate: (j['force_update'] as bool?) ?? false,
        apkReady: j['apk_ready'] == true,
      );
}

class AppUpdater {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  final Dio _dio = Dio();

  // ── 내려받기 상태 ────────────────────────────────────────
  //
  // 전에는 팝업 State 가 다운로드를 들고 있었다. 팝업을 닫거나 화면을
  // 나가면 State 가 사라지고, 진행률 콜백이 없어진 State 에 setState 를
  // 불러서 다운로드가 통째로 죽었다. 60MB 를 다시 받아야 했다.
  //
  // 이제 싱글턴이 들고 있다. 화면은 보기만 한다 — 팝업을 닫아도, 다른
  // 화면으로 가도 계속 받는다. 앱을 완전히 끄면 그때는 멈춘다.
  final ValueNotifier<bool> downloading = ValueNotifier<bool>(false);
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// 마지막 실패 사유. 성공하거나 다시 시작하면 지운다.
  final ValueNotifier<String?> downloadError = ValueNotifier<String?>(null);

  /// 다 받아 둔 파일. 설치 화면을 놓쳤을 때 다시 열 수 있다.
  String? _savedApk;
  AppVersionInfo? _downloadingInfo;

  String? get savedApk => _savedApk;

  /// 받아 둔 APK 의 설치 화면을 다시 연다.
  Future<void> openSavedApk() async {
    final p = _savedApk;
    if (p == null) return;
    await OpenFilex.open(p,
        type: 'application/vnd.android.package-archive');
  }

  /// 최신 버전 조회. 실패 시 null.
  ///
  /// 두 곳을 본다. 둘 다 같은 파일(backend/app_version.json)을 가리키지만
  /// 갱신되는 시점이 다르다 — 서버는 배포해야 바뀌고, GitHub 은 push 하면
  /// 바로 바뀐다. 그래서 둘 다 물어보고 버전이 높은 쪽을 쓴다.
  ///
  /// GitHub 한 곳만 보면 저장소가 비공개이거나 API 호출 한도(시간당 60회)에
  /// 걸렸을 때 업데이트 안내가 통째로 사라진다. 서버는 앱이 이미 쓰는 곳이라
  /// 그런 제약이 없다.
  Future<AppVersionInfo?> fetchLatest() async {
    final results = await Future.wait([_fromServer(), _fromGithub()]);
    AppVersionInfo? best;
    for (final r in results) {
      if (r == null) continue;
      if (best == null || r.latestVersionCode > best.latestVersionCode) {
        best = r;
      }
    }
    return best;
  }

  Future<AppVersionInfo?> _fromServer() async {
    try {
      final res = await _dio.get(
        '$kApiBaseUrl/app/version',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      if (res.statusCode != 200) return null;
      final d = res.data;
      final m = d is String
          ? jsonDecode(d) as Map<String, dynamic>
          : Map<String, dynamic>.from(d as Map);
      return AppVersionInfo.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  Future<AppVersionInfo?> _fromGithub() async {
    try {
      // raw URL 은 캐시가 오래 남아 실시간 반영이 안 된다. API 로 받는다.
      const apiUrl =
          'https://api.github.com/repos/msk05317/project_summary/contents/backend/app_version.json';
      final res = await _dio.get(
        apiUrl,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      if (res.statusCode != 200) return null;
      // GitHub API 는 base64 로 감싼 content 를 준다
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
    // 받을 수 없는 주소면 팝업을 띄우지 않는다. 눌러도 404 만 나고,
    // 사용자는 Dio 예외 문구를 읽게 된다 (실제로 그렇게 떴다).
    if (!latest.downloadable) {
      debugPrint('[AppUpdater] APK 를 받을 수 없어 팝업을 건너뜀: ${latest.downloadUrl}');
      return;
    }
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
  Future<void> startDirectUpdateDownload() async {
    final latest = await fetchLatest();
    if (latest == null) return;
    await downloadAndInstall(latest);
  }

  /// APK 를 받아 두고 설치 화면을 연다.
  ///
  /// 이미 받고 있으면 아무것도 하지 않는다 — 두 번 누르면 같은 파일을
  /// 두 군데서 쓰다가 반쪽짜리 APK 가 남는다.
  Future<void> downloadAndInstall(AppVersionInfo info) async {
    if (downloading.value) return;
    downloading.value = true;
    downloadError.value = null;
    progress.value = 0;
    _downloadingInfo = info;
    try {
      final url = info.downloadUrl.startsWith('http')
          ? info.downloadUrl
          : '$kApiBaseUrl${info.downloadUrl}';

      // 받는 일은 OS 에 맡긴다.
      //
      // 앱 안에서 받으면 홈으로 나간 사이에 안드로이드가 프로세스를
      // 죽이면 그대로 끝이다. background_downloader 는 네이티브
      // WorkManager 로 받아서 앱을 완전히 꺼도 마저 받는다. 진행률
      // 알림도 이쪽이 띄운다 — 다 받은 알림을 누르면 설치 화면이 열린다.
      _configureNotification();
      final task = DownloadTask(
        url: url,
        filename: _apkName,
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        // 9분이 넘으면 멈췄다가 이어받는다. 신호가 나쁜 공장 안에서
        // 60MB 를 처음부터 다시 받는 일이 없어야 한다.
        allowPause: true,
        retries: 2,
      );
      final res = await FileDownloader().download(
        task,
        onProgress: (p) {
          if (p >= 0) progress.value = p;
        },
      );
      if (res.status != TaskStatus.complete) {
        throw _TaskFailed(res);
      }

      final path = await task.filePath();
      if (kDebugMode) debugPrint('APK saved: $path');
      _savedApk = path;
      progress.value = 1;
      // 설치 화면 열기. 앱을 보고 있으면 바로 뜨고, 꺼져 있었으면
      // 알림을 눌렀을 때 열린다.
      await OpenFilex.open(path,
          type: 'application/vnd.android.package-archive');
    } catch (e) {
      downloadError.value = _downloadMessage(e);
    } finally {
      downloading.value = false;
      _downloadingInfo = null;
    }
  }

  static const String _apkName = 'app_release.apk';
  bool _notifConfigured = false;

  /// 진행률 알림. 플러그인이 알림판에 직접 띄운다 — 앱이 꺼져 있어도
  /// 막대가 남아 있고, 다 받은 알림을 누르면 설치 화면이 열린다.
  void _configureNotification() {
    if (_notifConfigured) return;
    _notifConfigured = true;
    FileDownloader().configureNotification(
      running: const TaskNotification('OneView 업데이트 받는 중', '{progress}'),
      complete: const TaskNotification('업데이트 준비 완료', '눌러서 설치하세요'),
      error: const TaskNotification('업데이트를 받지 못했습니다', '다시 시도해 주세요'),
      paused: const TaskNotification('업데이트 잠시 멈춤', '연결되면 이어받습니다'),
      progressBar: true,
      tapOpensFile: true,
    );
  }

  /// 다시 받기. 실패한 뒤 배지를 눌렀을 때.
  Future<void> retryDownload() async {
    final info = _downloadingInfo ?? await fetchLatest();
    if (info == null) return;
    await downloadAndInstall(info);
  }

  /// Dio 예외를 그대로 보여주면 영문 스택이 화면을 덮는다.
  ///
  /// 전에는 예외 글자에 'Connection' 이 섞이기만 해도 '연결이
  /// 불안정합니다' 라고 했다. 네트워크가 멀쩡한데 앱이 제 버그로 죽은
  /// 것을 통신 탓으로 돌렸다. 이제 Dio 가 말해 주는 종류만 보고,
  /// 모르면 모른다고 한다.
  static String _downloadMessage(Object e) {
    if (e is _TaskFailed) {
      switch (e.update.status) {
        case TaskStatus.notFound:
          return '업데이트 파일이 서버에 없습니다. 관리자에게 알려 주세요.';
        case TaskStatus.canceled:
          return '업데이트를 멈췄습니다.';
        default:
          if (e.update.exception is TaskConnectionException) {
            return '연결이 불안정합니다. 네트워크를 확인하고 다시 시도해 주세요.';
          }
          return '업데이트 파일을 받지 못했습니다. 잠시 후 다시 시도해 주세요.';
      }
    }
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return '연결이 불안정합니다. 네트워크를 확인하고 다시 시도해 주세요.';
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode;
          if (code == 404) {
            return '업데이트 파일이 서버에 없습니다. 관리자에게 알려 주세요.';
          }
          return '서버가 파일을 주지 않았습니다 (HTTP $code).';
        case DioExceptionType.cancel:
          return '업데이트를 멈췄습니다.';
        case DioExceptionType.badCertificate:
        case DioExceptionType.unknown:
          break;
      }
    }
    return '업데이트 파일을 받지 못했습니다. 잠시 후 다시 시도해 주세요.';
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
  // 팝업은 진행률을 보기만 한다. 받는 일은 AppUpdater 가 들고 있어서
  // 이 팝업을 닫아도 계속 받는다.
  AppUpdater get _up => widget.updater;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return ValueListenableBuilder<bool>(
      valueListenable: _up.downloading,
      builder: (context, busy, _) {
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
              if (busy) ...[
                ValueListenableBuilder<double>(
                  valueListenable: _up.progress,
                  builder: (context, p, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: p),
                      const SizedBox(height: 8),
                      Text('${(p * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text('창을 닫아도 계속 받습니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ],
              ValueListenableBuilder<String?>(
                valueListenable: _up.downloadError,
                builder: (context, err, _) => err == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(err,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFFB91C1C))),
                      ),
              ),
            ],
          ),
          actions: [
            if (!info.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(busy ? '닫기' : '나중에'),
              ),
            FilledButton(
              onPressed: busy ? null : () => _up.downloadAndInstall(info),
              child: Text(busy ? '받는 중...' : '업데이트'),
            ),
          ],
        );
      },
    );
  }
}

/// 내려받기가 끝났는데 완료가 아닐 때. 사유를 그대로 들고 온다.
class _TaskFailed implements Exception {
  final TaskStatusUpdate update;
  const _TaskFailed(this.update);

  @override
  String toString() => 'download ${update.status}';
}
