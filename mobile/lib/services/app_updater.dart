import 'dart:convert';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
    // 크롬(flutter run -d chrome)으로 띄웠을 때는 APK 를 깔 수 없다.
    // 업데이트 팝업이 화면을 가려서 볼 일만 방해했다.
    if (kIsWeb) return;
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

  // ── OS 쪽 작업과 이어 붙이기 ─────────────────────────────
  //
  // 받는 일은 OS 가 한다. 앱은 '지금 받고 있는 작업' 에 붙어서 보기만 한다.
  //
  // 전에는 다시 누를 때마다 cancelTaskWithId 로 남아 있던 작업을 먼저
  // 죽이고 새로 받았다. 앱을 나갔다 들어와서 다시 누르면, OS 가 마저
  // 받고 있던 걸 우리가 끊은 셈이다 — '나가면 끊긴다' 의 절반이 이거였다.
  // 끊긴 작업은 취소 알림을 남기고, 그룹 알림 모드에서는 취소가 '실패' 로
  // 세어져서 '업데이트를 받지 못했습니다' 가 계속 떴다.
  bool _started = false;

  /// 앱을 켤 때 한 번. 꺼져 있던 사이의 결과를 받아 오고, 받고 있던
  /// 작업이 있으면 진행률에 다시 붙는다. 여러 번 불러도 한 번만 돈다.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    // 웹에는 백그라운드 다운로더가 없다 (플랫폼 확인에서 바로 터진다)
    if (kIsWeb) return;
    try {
      await FileDownloader().configure(androidConfig: [
        // 포그라운드로 돌리지 않으면 앱을 나가자마자 삼성 절전이 작업을
        // 세운다. 알림판의 진행률 막대가 곧 포그라운드 표시다.
        (Config.runInForeground, Config.always),
      ]);
    } catch (_) {}
    _configureNotification();
    FileDownloader().updates.listen(_onUpdate);
    try {
      // 추적 켜기 + 꺼져 있던 동안의 상태 받아오기 + 죽은 작업 다시 걸기
      await FileDownloader().start();
    } catch (_) {}
    final live = await _liveTask();
    if (live != null) {
      downloading.value = true;
    } else {
      await _clearStaleNotifications();
    }
  }

  /// 지금 OS 에 걸려 있는 우리 작업 (대기 · 받는 중 · 재시도 대기 · 멈춤).
  Future<Task?> _liveTask() async {
    try {
      return await FileDownloader().taskForId(_taskId);
    } catch (_) {
      return null;
    }
  }

  /// 예전 버전이 남긴 업데이트 알림을 걷어낸다.
  ///
  /// 2.3.28 까지는 받을 때마다 작업 id 가 새로 생겨서 알림이 하나씩
  /// 쌓였고, 그 뒤로는 그룹 알림이 따로 남았다. 둘 다 이 채널에 있다.
  /// 받고 있는 게 없을 때만 지운다 — 진행 중인 막대까지 지우면 안 된다.
  Future<void> _clearStaleNotifications() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return;
      final active = await android.getActiveNotifications();
      for (final n in active) {
        if (n.channelId == _notifChannel && n.id != null) {
          await android.cancel(id: n.id!, tag: n.tag);
        }
      }
    } catch (_) {
      // 못 지워도 그만이다. 사용자가 밀어서 지울 수 있다.
    }
  }

  /// OS 가 보내는 상태 · 진행률. 앱이 꺼져 있던 사이의 것도 start() 가 모아서 준다.
  Future<void> _onUpdate(TaskUpdate u) async {
    if (u.task.taskId != _taskId) return;
    if (u is TaskProgressUpdate) {
      if (u.progress >= 0 && u.progress <= 1) {
        progress.value = u.progress;
        if (u.progress < 1 && !downloading.value) downloading.value = true;
      }
      return;
    }
    if (u is! TaskStatusUpdate) return;
    switch (u.status) {
      case TaskStatus.enqueued:
      case TaskStatus.running:
      case TaskStatus.waitingToRetry:
      case TaskStatus.paused:
        downloading.value = true;
        downloadError.value = null;
        break;
      case TaskStatus.complete:
        downloading.value = false;
        progress.value = 1;
        _downloadingInfo = null;
        try {
          final path = await u.task.filePath();
          _savedApk = path;
          if (kDebugMode) debugPrint('APK saved: $path');
          // 앱을 보고 있으면 바로 설치 화면이 뜬다. 꺼져 있었으면
          // 알림을 누르면 열린다 (tapOpensFile).
          await OpenFilex.open(path,
              type: 'application/vnd.android.package-archive');
        } catch (_) {}
        break;
      case TaskStatus.canceled:
        // 우리가 옛 버전 작업을 걷었거나, 사용자가 알림에서 취소한 것.
        // 실패가 아니니 빨간 글을 띄우지 않는다.
        downloading.value = false;
        break;
      case TaskStatus.notFound:
      case TaskStatus.failed:
        downloading.value = false;
        downloadError.value = _downloadMessage(_TaskFailed(u));
        break;
    }
  }

  /// APK 를 받아 두고 설치 화면을 연다.
  ///
  /// 이미 받고 있으면 새로 걸지 않고 그 작업에 붙는다. 같은 버전을 다
  /// 받아 둔 게 있으면 받지 않고 바로 연다.
  Future<void> downloadAndInstall(AppVersionInfo info) async {
    await init();
    if (downloading.value) return;
    downloadError.value = null;
    final tag = '${info.latestVersionCode}';
    final url = info.downloadUrl.startsWith('http')
        ? info.downloadUrl
        : '$kApiBaseUrl${info.downloadUrl}';

    // 1) OS 가 받고 있는 게 있으면 붙는다. 다른 버전이면 그것만 걷는다.
    final live = await _liveTask();
    if (live != null) {
      if (live.metaData == tag) {
        downloading.value = true;
        _downloadingInfo = info;
        return;
      }
      try {
        await FileDownloader().cancelTaskWithId(_taskId);
      } catch (_) {}
    }

    // 2) 같은 버전을 이미 다 받아 뒀으면 그걸 연다.
    try {
      final rec = await FileDownloader().database.recordForId(_taskId);
      if (rec != null &&
          rec.status == TaskStatus.complete &&
          rec.task.metaData == tag) {
        final path = await rec.task.filePath();
        if (await File(path).exists()) {
          _savedApk = path;
          progress.value = 1;
          await OpenFilex.open(path,
              type: 'application/vnd.android.package-archive');
          return;
        }
      }
    } catch (_) {}

    // 3) 새로 받는다.
    downloading.value = true;
    progress.value = 0;
    _downloadingInfo = info;
    final task = DownloadTask(
      taskId: _taskId,
      url: url,
      // 버전을 이름에 넣는다. 옛 APK 를 새 것으로 착각해 여는 일이 없게.
      filename: 'oneview_$tag.apk',
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      // 9분이 넘으면 멈췄다가 이어받는다. 신호가 나쁜 공장 안에서
      // 60MB 를 처음부터 다시 받는 일이 없어야 한다.
      allowPause: true,
      retries: 2,
      // 0 이면 안드로이드 14+ 에서 '사용자가 시작한 전송' 으로 돈다.
      // OS 가 끝까지 지켜주는 종류라 앱을 나가도, 화면을 꺼도 안 끊긴다.
      priority: 0,
      metaData: tag,
    );
    bool ok = false;
    try {
      ok = await FileDownloader().enqueue(task);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      downloading.value = false;
      downloadError.value = '업데이트를 시작하지 못했습니다. 다시 시도해 주세요.';
    }
  }

  /// 내려받기 작업 이름을 고정한다.
  ///
  /// 안 주면 플러그인이 매번 새 id 를 만들고, 알림 id 는 그 id 의
  /// 해시라서 다시 받을 때마다 알림이 하나씩 쌓였다. 같은 이름을 쓰면
  /// 같은 알림을 고쳐 쓴다.
  static const String _taskId = 'oneview_apk';

  /// background_downloader 가 알림을 올리는 채널 (Notifications.kt).
  static const String _notifChannel = 'background_downloader';
  bool _notifConfigured = false;

  /// 진행률 알림. 플러그인이 알림판에 직접 띄운다 — 앱이 꺼져 있어도
  /// 막대가 남아 있고, 다 받은 알림을 누르면 설치 화면이 열린다.
  ///
  /// 그룹 알림(groupNotificationId)은 쓰지 않는다. 한 번에 하나만 받는데
  /// 그룹으로 묶으면 취소가 '실패' 로 세어져 에러 알림이 떴고, 누르면
  /// 설치 화면이 열리던 것도 그룹 알림에서는 안 됐다. 작업 이름이 고정이라
  /// 알림은 원래 하나다.
  void _configureNotification() {
    if (_notifConfigured) return;
    _notifConfigured = true;
    FileDownloader().configureNotification(
      running: const TaskNotification('OneView 업데이트 받는 중', '{progress}'),
      complete: const TaskNotification('업데이트 준비 완료', '눌러서 설치하세요'),
      error: const TaskNotification('업데이트를 받지 못했습니다', '앱에서 다시 시도해 주세요'),
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
