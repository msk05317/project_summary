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
assert 'onProgress' not in U, '진행률을 아직 콜백으로 넘긴다'
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

# ── 받아 둔 파일을 다시 열 수 있다 ──
#
# 설치 화면을 놓쳤을 때 60MB 를 다시 받게 하면 안 된다.
assert 'openSavedApk' in U and 'String? get savedApk' in U, \
    '설치 화면을 놓치면 다시 받아야 한다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
