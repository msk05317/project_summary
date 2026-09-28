# 프로세스 엑셀 업로드가 이미 적어 둔 날짜를 지우면 안 된다
#   python3 backend/tests/test_process_import_keep.py
#
# 하바플레이트에서 공정 입력 17종이 통째로 비었다. 프로세스 엑셀의 빈 칸이
# 기존 값을 덮어썼기 때문이다 (단계 이름은 그대로, 날짜만 전부 빈 값).
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {}
want = {'_merge_process_keep', '_canon_step'}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in want:
        exec(ast.get_source_segment(SRC, n), g)
assert want <= set(g), want - set(g)
M = g['_merge_process_keep']
ok = 0


def step(key, name, e='', a='', s=''):
    return {'key': key, 'name': name, 'expected': e, 'actual': a, 'status': s}


OLD = [step('step_1', '01 FA PO', '', '2025-05-05', '완료'),
       step('step_2', '02 자재 발주', '2025-05-11', '2025-02-21', '완료'),
       step('step_3', '03 입고', '2025-04-04', '', '진행중')]

# ── 엑셀이 다 비어 있으면 기존 값 그대로 ──
NEW_EMPTY = [step('step_1', '01 FA PO'), step('step_2', '02 자재 발주'), step('step_3', '03 입고')]
out = M(OLD, NEW_EMPTY)
assert [x['actual'] for x in out] == ['2025-05-05', '2025-02-21', ''], out
assert [x['status'] for x in out] == ['완료', '완료', '진행중'], out
ok += 1

# ── 엑셀에 값이 있으면 그 값이 이긴다 ──
NEW = [step('step_1', '01 FA PO', '2025-05-01', '2025-05-02', '완료'),
       step('step_2', '02 자재 발주'),
       step('step_3', '03 입고', '', '2025-04-09', '완료')]
out = M(OLD, NEW)
assert out[0]['expected'] == '2025-05-01' and out[0]['actual'] == '2025-05-02'
assert out[1]['actual'] == '2025-02-21', '빈 칸이 기존 값을 덮었다'
assert out[2]['actual'] == '2025-04-09' and out[2]['expected'] == '2025-04-04'
ok += 1

# ── 단계 이름이 바뀌어도 key 로 짝을 찾는다 ──
RENAMED = [step('step_1', '01 FA PO (발주)'), step('step_2', '02 자재발주'), step('step_3', '03 자재 입고')]
out = M(OLD, RENAMED)
assert out[0]['actual'] == '2025-05-05' and out[1]['actual'] == '2025-02-21', out
ok += 1

# ── 기존이 없으면 엑셀 그대로 ──
assert M(None, NEW_EMPTY) == NEW_EMPTY and M([], NEW) == NEW
ok += 1

# ── 단계 수가 달라도 있는 만큼만 ──
out = M(OLD, NEW_EMPTY + [step('step_4', '04 CB')])
assert len(out) == 4 and out[3]['actual'] == ''
ok += 1

# 업로드 경로 두 군데가 다 이 규칙을 쓴다
assert SRC.count('_merge_process_keep(m.get(\'process\')') == 2, \
    '프로세스 엑셀 업로드 경로 한 곳이 아직 덮어쓴다'
ok += 1

print(f'test_process_import_keep: {ok} passed')
