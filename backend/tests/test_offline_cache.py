# 오프라인일 때 마지막으로 받아둔 내용을 보여주는지
#   python3 backend/tests/test_offline_cache.py
#
# 지금까지는 열 때마다 서버에서 받아왔고, 신호가 없으면 화면이 비거나
# '불러오지 못했습니다' 만 떴다. 공장 안이나 이동 중에도 마지막으로 본
# 내용은 바로 떠야 한다. 대신 그게 언제 것인지 반드시 같이 말해야 한다.
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIB = ROOT / 'mobile' / 'lib'
S = (LIB / 'services' / 'offline_store.dart').read_text(encoding='utf-8')
ok = 0

# ── 저장소 ──
for name in ('class OfflineStore', 'class OfflineStatus', 'class Cached',
             'static Future<void> save(', 'static Future<Cached<dynamic>?> load(',
             'static Future<Cached<dynamic>> fetch('):
    assert name in S, f'{name} 이 없다'
ok += 1

# 받아오면 저장하고, 못 받아오면 저장본을 돌려준다
f = S[S.index('static Future<Cached<dynamic>> fetch('):]
f = f[f.index('}) async {'):]
f = f[:f.index('\n  }')]
n = S[S.index('static Future<Cached<dynamic>?> _network('):]
n = n[:n.index('\n  }')]
assert 'await save(key, data)' in n, '받아온 걸 저장하지 않는다'
assert 'OfflineStatus.online()' in n, '받아왔는데 배너가 안 내려간다'
assert 'OfflineStatus.offline(' in f, '저장본을 보여주면서 말을 안 한다'
assert 'throw' in f, '저장본도 없는데 조용히 빈 값을 돌려준다'
ok += 1

# ── 저장된 값부터 그린다 ──
#
# "처음 껐다 킬 때 앱 로딩속도가 너무 느려"
#
# 열 때마다 네트워크를 먼저 기다렸다. 저장된 값이 멀쩡히 있어도 홈이
# 빈 채로 있었고, /home/alerts 하나만으로 20초까지 갔다.
assert 'void Function(Cached<dynamic>)? onFresh' in S, '저장본 먼저 그릴 길이 없다'
assert 'if (onFresh != null)' in f, '저장본을 먼저 안 돌려준다'
H = (LIB / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert H.count('onFresh:') >= 6, '홈이 아직 여섯 개를 다 기다린다'
assert 'void _swap(' in H and 'if (!mounted) return;' in H, \
    '뒤에서 온 값으로 갈아 끼울 때 화면이 살아 있는지 안 본다'
ok += 1

# ── 첫 프레임을 막는 것을 줄인다 ──
#
# WorkManager 등록은 안드로이드 작업 DB 를 건드려서 콜드 스타트에
# 수백 ms 가 걸린다. 30분마다 도는 백그라운드 새로고침이라 첫 화면과는
# 상관이 없는데 그동안 앱이 흰 화면으로 서 있었다.
M = (LIB / 'main.dart').read_text(encoding='utf-8')
_pre = M[M.index('Future<void> main()'):M.index('runApp(')]
assert 'BackgroundService' not in _pre, 'runApp 전에 WorkManager 를 기다린다'
assert 'BackgroundService' in M, '백그라운드 새로고침을 아예 안 건다'
ok += 1

# 저장이 안 되는 기기에서도 앱은 돌아야 한다
assert 'return null; // 저장을 못 해도' in S or 'catch (_) {\n      return null;' in S
ok += 1

# 언제 것인지 말해 준다
assert 'static String describe(' in S and '기준' in S
ok += 1

# ── 서비스들이 실제로 쓰는지 ──
USERS = {
    'divisions_service.dart': 'divisions',
    'dashboard_service.dart': 'dashboard',
    'progress_service.dart': 'progress',
    'overview_service.dart': 'overview_',
    'home_alerts_service.dart': 'home_alerts',
    'bloom_service.dart': 'daily_board_',
}
for fname, key in USERS.items():
    src = (LIB / 'services' / fname).read_text(encoding='utf-8')
    assert 'OfflineStore.fetch(' in src, f'{fname} 이 저장본을 안 쓴다'
    assert key in src, f'{fname} 의 저장 키가 다르다'
    # 남아 있는 직접 호출이 있으면 그 화면만 오프라인에서 깨진다
    assert not re.search(r'http\.get\(Uri\.parse\([^)]*\)\)\s*\n?\s*\.timeout', src) \
        or fname == 'progress_service.dart', f'{fname} 에 직접 호출이 남아 있다'
ok += 1

# 프로젝트 화면도 (모델 상세 · 주차 계획)
O = (LIB / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert "'models_${widget.projectKey}'" in O and "'weekly_plan_${widget.projectKey}'" in O
assert '_fromCache' in O and 'OfflineStore.describe(_savedAt)' in O, \
    '저장본인데 언제 것인지 안 보여준다'
ok += 1

# ── 오프라인 표시 ──
H = (LIB / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert 'ValueListenableBuilder<DateTime?>' in H and 'OfflineStatus.savedAt' in H, \
    '홈에 오프라인 표시가 없다'
assert '오프라인 ·' in H and '다시 시도' in H
ok += 1

print(f'전부 통과 · {ok}개 항목')
