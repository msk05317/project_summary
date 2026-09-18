# 업데이트 받는 도중에 화면을 옮겨도 계속 받는지
#   python3 backend/tests/test_update_download.py
#
# "다운로드 받을 때 그 화면을 나가거나 어디 잘못 누르면 다운로드에
#  나가지고 다시 해야되는데"
#
# 팝업 State 가 다운로드를 들고 있었다. 팝업을 닫으면 State 가 사라지고,
# 진행률 콜백이 없어진 State 에 setState 를 불러서 다운로드가 통째로
# 죽었다. 60MB 를 처음부터 다시 받아야 했다.
import pathlib

LIB = pathlib.Path(__file__).resolve().parents[2] / 'mobile' / 'lib'
U = (LIB / 'services' / 'app_updater.dart').read_text(encoding='utf-8')
M = (LIB / 'main.dart').read_text(encoding='utf-8')
ok = 0

# ── 받는 일은 싱글턴이 들고 있다 ──
for name in ('ValueNotifier<bool> downloading',
             'ValueNotifier<double> progress',
             'ValueNotifier<String?> downloadError'):
    assert name in U, f'{name} 이 없다'
assert 'Future<void> downloadAndInstall(AppVersionInfo info)' in U, \
    '다운로드가 아직 화면에서 콜백을 받는다'
# 화면에서 콜백을 받지 않는다 (FileDownloader 의 onProgress 는 별개다)
assert 'void Function(double) onProgress' not in U, \
    '진행률을 아직 화면 콜백으로 넘긴다'
ok += 1

# ── 팝업은 보기만 한다 ──
_dlg = U[U.index('class _UpdateDialogState'):]
assert 'setState' not in _dlg, '팝업이 아직 제 State 로 진행률을 들고 있다'
assert 'ValueListenableBuilder' in _dlg, '팝업이 싱글턴을 안 본다'
assert '창을 닫아도 계속 받습니다' in _dlg, '닫아도 되는지 말해 주지 않는다'
# 받는 중에도 닫을 수 있어야 한다 (강제 업데이트만 예외)
assert 'if (!info.forceUpdate)' in _dlg, '받는 중에는 닫지도 못한다'
ok += 1

# ── 두 번 눌러도 한 번만 받는다 ──
#
# 같은 파일을 두 군데서 쓰면 반쪽짜리 APK 가 남는다.
assert 'if (downloading.value) return;' in U, '두 번 누르면 두 번 받는다'
ok += 1

# ── 어느 화면에 있든 진행률이 보인다 ──
assert '_UpdateBadge' in M, '받고 있는지 알 길이 없다'
assert 'AppUpdater.instance' in M and 'up.downloading' in M
assert 'up.retryDownload' in M, '실패했을 때 다시 받을 데가 없다'
ok += 1

# ── 앱을 꺼도 OS 가 마저 받는다 ──
#
# "앱을 나가도 끄지 않는 이상 알아서 다운 받게끔"
#
# 앱 안에서 받으면 홈으로 나간 사이에 안드로이드가 프로세스를 죽이면
# 그대로 끝이다. 네이티브 WorkManager 로 넘긴다.
PUB = (LIB.parent / 'pubspec.yaml').read_text(encoding='utf-8')
assert 'background_downloader' in PUB, '아직 앱 안에서 받는다'
# 9.6 부터 Flutter 3.47 을 요구한다. 우리는 3.44 라서 9.5 대로 묶어야 한다.
assert "'>=9.5.9 <9.6.0'" in PUB, '버전을 안 묶어서 빌드가 깨질 수 있다'
assert 'FileDownloader().download(' in U, '다운로드를 OS 에 안 맡긴다'
assert 'BaseDirectory.applicationSupport' in U
assert 'allowPause: true' in U, '9분이 넘으면 처음부터 다시 받는다'
assert '_dio.download(' not in U, '앱 안에서 받는 길이 남아 있다'
# 알림이 쌓이지 않는다.
#
# "중간에 끊겨서 다시 업데이트하면 알림판에 업데이트 창만 겁나게 추가돼"
#
# 작업 id 를 안 주면 플러그인이 매번 새로 만들고, 알림 id 는 그 id 의
# 해시라서 다시 받을 때마다 알림이 하나씩 쌓인다.
assert 'taskId: _taskId' in U, '작업 이름이 매번 바뀌어 알림이 쌓인다'
assert "_taskId = 'oneview_apk'" in U
assert 'cancelTaskWithId(_taskId)' in U, '받다 만 작업이 남는다'
assert "groupNotificationId: 'oneview_update'" in U, '알림이 한 줄로 안 묶인다'
ok += 1
ok += 1

# ── 알림판에 진행률 막대 ──
#
# "첫 번째 사진처럼 저기에 다운로드 로딩이 보였으면 좋겠고"
assert 'configureNotification(' in U and 'progressBar: true' in U, \
    '알림판에 막대가 없다'
assert 'tapOpensFile: true' in U, '다 받은 알림을 눌러도 설치가 안 열린다'
assert 'OneView 업데이트 받는 중' in U
ok += 1

# ── 매니페스트 ──
MAN = (LIB.parent / 'android' / 'app' / 'src' / 'main' /
       'AndroidManifest.xml').read_text(encoding='utf-8')
for perm in ('FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_DATA_SYNC',
             'RUN_USER_INITIATED_JOBS', 'REQUEST_INSTALL_PACKAGES'):
    assert perm in MAN, f'{perm} 권한이 없다'
ok += 1

# ── 로컬 알림은 Firebase 와 따로 준비한다 ──
#
# Firebase 초기화가 실패하면 return 해 버려서 로컬 알림이 통째로 죽었다.
F = (LIB / 'services' / 'fcm_service.dart').read_text(encoding='utf-8')
_init = F[F.index('static Future<void> initialize()'):]
assert _init.index('_initLocal()') < _init.index('Firebase.initializeApp'), \
    'Firebase 가 안 붙으면 알림도 못 띄운다'
ok += 1

# ── 원인을 문자열로 짐작하지 않는다 ──
#
# 예외 글자에 'Connection' 이 섞이기만 해도 '연결이 불안정합니다' 라고
# 했다. 네트워크가 멀쩡한데 앱이 제 버그로 죽은 것을 통신 탓으로 돌렸다.
_msg = U[U.index('static String _downloadMessage'):]
_msg = _msg[:_msg.index('\n  }\n')]
assert 'TaskConnectionException' in _msg, '실패 사유를 안 보고 짐작한다'
assert "t.contains('Connection')" not in _msg, '아직 글자로 짐작한다'
ok += 1

# ── 받아 둔 파일을 다시 열 수 있다 ──
#
# 설치 화면을 놓쳤을 때 60MB 를 다시 받게 하면 안 된다.
assert 'openSavedApk' in U and 'String? get savedApk' in U, \
    '설치 화면을 놓치면 다시 받아야 한다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
