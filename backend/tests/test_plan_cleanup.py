# 주차별 계획 '원본'(프로젝트에 올린 엑셀→이미지) 일괄 정리 검증
#   python3 backend/tests/test_plan_cleanup.py
#
# 주의: 여기서 지우는 건 proj['weekly_plan'](photo_ref 가 있는 업로드 원본)이다.
#       모델 안의 m['weekly_plan'](월/주차별 계획·실적)은 이름만 같고 전혀 다른 값이며
#       절대 건드리면 안 된다. 아래 테스트가 그걸 지킨다.
import ast, copy, pathlib, sys

SRC_PATH = pathlib.Path(__file__).resolve().parents[1] / 'main.py'
SRC = SRC_PATH.read_text(encoding='utf-8')
tree = ast.parse(SRC)

want = {'_cleanup_plan_originals'}
funcs = {n.name: ast.get_source_segment(SRC, n)
         for n in tree.body
         if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in want}
assert set(funcs) == want, f'함수를 못 찾았다: {set(funcs)}'

# main.py 의 _PLAN_KEEP 실제 값을 그대로 읽어온다
KEEP = None
for n in tree.body:
    if isinstance(n, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == '_PLAN_KEEP' for t in n.targets):
        KEEP = ast.literal_eval(n.value)
assert KEEP == {'chamber'}, f'_PLAN_KEEP 가 예상과 다르다: {KEEP}'

DATA = {'projects': {
    'chamber':      {'weekly_plan': {'photo_ref': 'ph_ch', 'file_name': 'CUP.xlsx'},
                     'models': [{'name': 'M1', 'weekly_plan': {'2026-08': {'w1': {'plan': 3}}}}]},
    'hrva_plate':   {'weekly_plan': {'photo_ref': 'ph_hv', 'file_name': '하바플레이트.xlsx'},
                     'models': [{'name': 'M2', 'weekly_plan': {'2026-08': {'w2': {'plan': 5, 'actual': 4}}}}]},
    'cup':          {'weekly_plan': {'photo_ref': 'ph_cp', 'file_name': 'CUP.xlsx'},
                     'models': [{'name': 'M3', 'weekly_plan': {'2026-09': {'w1': {'plan': 1}}}}]},
    'powerbox':     {'models': [{'name': 'PBX',
                                 'weekly_plan': {'2026-09': {'w1': {'plan': 9, 'actual': 9}}},
                                 'process': [{'name': 'FA PO', 'status': '완료'}]}]},
    'major_module': {'models': [{'name': 'MM', 'weekly_plan': {'2026-09': {'w2': {'plan': 2}}}}]},
    'auto_kefico':  {'weekly_plan': {'photo_ref': 'ph_au', 'file_name': '자동차.xlsx'}, 'models': []},
}}
SNAP = copy.deepcopy(DATA)
deleted, saved = [], []


class _FakeConfig:
    @staticmethod
    def get_projects(division_id=None):
        if division_id == 'semiconductor':
            return [{'id': k} for k in
                    ('chamber', 'hrva_plate', 'cup', 'powerbox', 'major_module')]
        return []


sys.modules['config_loader'] = _FakeConfig

g = {
    '_PLAN_KEEP': KEEP,
    '_load_models': lambda: DATA,
    '_save_models': lambda d: saved.append(1),
    '_delete_note_photo': lambda ref: deleted.append(ref),
}
for src in funcs.values():
    exec(src, g)

g['_cleanup_plan_originals']()

ok = 0
P = DATA['projects']

assert 'weekly_plan' in P['chamber'], '챔버 원본이 지워졌다'
ok += 1
assert 'weekly_plan' in P['auto_kefico'], '반도체가 아닌 프로젝트 원본이 지워졌다'
ok += 1
assert 'weekly_plan' not in P['hrva_plate'], '하바플레이트 원본이 남았다'
ok += 1
assert 'weekly_plan' not in P['cup'], '큐피 원본이 남았다'
ok += 1
assert sorted(deleted) == ['ph_cp', 'ph_hv'], f'사진 삭제 목록이 다르다: {deleted}'
ok += 1
assert len(saved) == 1, f'저장 횟수가 다르다: {saved}'
ok += 1

for key in P:
    now = [m.get('weekly_plan') for m in (P[key].get('models') or [])]
    was = [m.get('weekly_plan') for m in (SNAP['projects'][key].get('models') or [])]
    assert now == was, f'{key}: 모델별 주차별 계획이 바뀌었다'
ok += 1

for key in ('powerbox', 'major_module'):
    assert P[key] == SNAP['projects'][key], f'{key} 가 통째로 변경됐다'
ok += 1

deleted.clear()
saved.clear()
g['_cleanup_plan_originals']()
assert deleted == [] and saved == [], f'두 번째 실행이 또 건드렸다: {deleted} {saved}'
ok += 1

print(f'전부 통과 ({ok}/9)')
