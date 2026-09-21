# 모델 상태 '진행' 은 옛 값 — '정상' 으로 바꾸고 다시 안 들어오게.
#   python3 backend/tests/test_legacy_status.py
#
# "정상이랑 진행 차이를 뭐로 둔거야?" — 차이가 없었다. '진행' 은
# MODEL_STATUSES 에 없는 옛 값이라 판정에서는 정상과 똑같이 셌고,
# admin 드롭다운에만 따로 보였다. 파워박스 36종 · 메이저모듈 1종.
import ast, copy, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {}
for x in tree.body:
    if isinstance(x, ast.Assign) and getattr(x.targets[0], 'id', '') in (
            'MODEL_STATUSES', '_LEGACY_MODEL_STATUS'):
        exec(ast.get_source_segment(SRC, x), g)
fn = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
      if isinstance(n, ast.FunctionDef) and n.name == '_cleanup_legacy_status'}
assert fn, '_cleanup_legacy_status 가 없다'
ok = 0

assert g['_LEGACY_MODEL_STATUS'] == {'진행': '정상'}
assert '진행' not in g['MODEL_STATUSES']
ok += 1

# ── 기동 정리: 모델 status 만 바꾸고 공정 단계 '진행중' 은 안 건드린다 ──
DATA = {'projects': {
    'powerbox': {'models': [
        {'id': 'A', 'status': '진행', 'process': [{'key': 's1', 'status': '진행중'}]},
        {'id': 'B', 'status': '정상'},
        {'id': 'C', 'status': '보류'},
        {'id': 'D', 'status': ' 진행 '},
    ]},
    'major_module': {'models': [{'id': 'Mach I', 'status': '진행'}]},
}}
store = {'data': copy.deepcopy(DATA), 'saves': 0}
g['_load_models'] = lambda: store['data']
def _save(d):
    store['saves'] += 1
    store['data'] = d
g['_save_models'] = _save
exec(fn['_cleanup_legacy_status'], g)
g['_cleanup_legacy_status']()
P = store['data']['projects']
st = {m['id']: m['status'] for m in P['powerbox']['models']}
assert st == {'A': '정상', 'B': '정상', 'C': '보류', 'D': '정상'}, st
assert P['major_module']['models'][0]['status'] == '정상'
assert P['powerbox']['models'][0]['process'][0]['status'] == '진행중', \
    '공정 단계의 진행중까지 바꿨다'
assert store['saves'] == 1
ok += 1

# 두 번째 기동에는 아무 일도 안 한다 (저장도 안 한다)
g['_cleanup_legacy_status']()
assert store['saves'] == 1, '바꿀 게 없는데 또 저장했다'
ok += 1

# ── 기동할 때 실제로 부른다 ──
assert '\n_cleanup_legacy_status()' in SRC, '기동 때 안 부른다'
ok += 1

# ── 다시 들어오지 않게: 입력 받는 두 곳 ──
nm = SRC[SRC.index('def _normalize_model('):]
nm = nm[:nm.index('\ndef ')]
assert '_LEGACY_MODEL_STATUS.get(status, status)' in nm, '새 모델로 들어올 때 옛 값을 못 거른다'
up = SRC[SRC.index('    if "status" in payload:'):]
up = up[:300]
assert '_LEGACY_MODEL_STATUS.get(s, s)' in up, '모델 수정으로 들어올 때 옛 값을 못 거른다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
