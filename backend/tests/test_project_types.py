# 프로젝트 유형(dev_type) — 목록에 없는 유형도 잃지 않는다
#   python3 backend/tests/test_project_types.py
#
# 챔버가 그랬다. 엑셀로 올라온 모델 14개가 'DEP챔버' 인데 프로젝트의 유형
# 목록은 비어 있었다. admin 표는 유형 칸을 '—' 로 그렸고(있는 값을 못 그림),
# 그 줄을 저장하면 빈 값으로 덮여 주차별 현황의 'Dep 챔버' 줄이 비었다.
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {'MODELS_FILE': 'x'}
want = {'_get_project_types'}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in want:
        exec(ast.get_source_segment(SRC, n), g)
assert want <= set(g)
ok = 0

DATA = {'projects': {
    'chamber': {'types': [], 'models': [
        {'id': 'a', 'dev_type': 'DEP챔버'},
        {'id': 'b', 'dev_type': 'DEP챔버'},
        {'id': 'c', 'dev_type': '화성 내재화'},
        {'id': 'd', 'dev_type': None},
        'not a dict',
    ]},
    'powerbox': {'types': ['SI', 'EMA'], 'models': [
        {'id': 'e', 'dev_type': 'EMA'},
        {'id': 'f', 'dev_type': 'PDU'},      # 목록에 없는 값
    ]},
    'empty': {'models': []},
}}
g['_read_json'] = lambda *a, **k: DATA
T = g['_get_project_types']

# 목록이 비어도 쓰이는 유형이 나온다
assert T('chamber') == ['DEP챔버', '화성 내재화'], T('chamber')
ok += 1

# 정해 둔 목록이 먼저, 쓰이는데 목록에 없는 것은 뒤에
assert T('powerbox') == ['SI', 'EMA', 'PDU'], T('powerbox')
ok += 1

# 모델이 없으면 빈 목록
assert T('empty') == [] and T('없는프로젝트') == []
ok += 1

# admin 표도 목록에 없는 현재 값을 살려 둔다
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert "if (cur && list.indexOf(cur) < 0) list.push(cur);" in HTML, \
    'admin 표가 목록에 없는 유형을 버린다 (저장하면 빈 값으로 덮인다)'
ok += 1

print(f'test_project_types: {ok} passed')
