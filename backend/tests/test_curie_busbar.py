# 큐리 버스바 11개를 한 모델로 합치기 (1회)
#   python3 backend/tests/test_curie_busbar.py
#
# 담당자는 엑셀에서 '버스바/시트메탈류(11종)' 한 줄로 관리하는데
# 품번별로 11개(560D~570D)가 들어가 있었다. PO 가 두 배로 잡힌다.
import ast, copy, pathlib, re

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
fn = next((ast.get_source_segment(SRC, n) for n in tree.body
           if isinstance(n, ast.FunctionDef) and n.name == '_merge_curie_busbar'), None)
assert fn, '_merge_curie_busbar 를 못 찾았다'
consts = {}
for n in tree.body:
    if isinstance(n, ast.Assign):
        for t in n.targets:
            if getattr(t, 'id', '') in ('_CURIE_KEY', '_CURIE_BUSBAR',
                                        '_CURIE_BUSBAR_RE', '_MIGRATION_KEY'):
                consts[t.id] = ast.unparse(n.value)
assert len(consts) == 4, consts.keys()

DATA = {'projects': {'spacex': {'models': (
    [{'id': '556B', 'name': '키스톤', 'po_qty': 2, 'shipped_qty': 0}] +
    [{'id': '568D', 'name': '버스바', 'po_qty': 880, 'shipped_qty': 0,
      'weekly_plan': {'2026-10': {'W41': {'plan': 100, 'actual': 5}}}},
     {'id': '569D', 'name': '버스바', 'po_qty': 440, 'shipped_qty': 10,
      'weekly_plan': {'2026-10': {'W41': {'plan': 60, 'actual': 0}}}}] +
    # 라이브에 실제로 들어가 있던 값
    [{'id': i, 'po_qty': q, 'shipped_qty': 0} for i, q in
     (('566D', 20), ('564D', 20), ('563D', 20), ('562D', 200),
      ('561D', 40), ('570D', 20), ('560D', 20), ('559D', 20), ('565D', 60))]
)}}}
saved = []
g = {'_as_int': lambda v: int(v or 0), 'print': lambda *a, **k: None}
exec('import re\n' + '\n'.join(f'{k} = {v}' for k, v in consts.items()), g)

def run(data):
    g['_load_models'] = lambda: data
    g['_save_models'] = lambda d: saved.append(1)
    exec(fn, g)
    g['_merge_curie_busbar']()
    return data

ok = 0
d = run(copy.deepcopy(DATA))
ms = {m['id']: m for m in d['projects']['spacex']['models']}
assert len(ms) == 2, list(ms)                      # 키스톤 + 버스바 하나
ok += 1
b = ms['버스바/시트메탈류(11종)']
assert b['po_qty'] == 1740, b['po_qty']          # 엑셀 버스바 행과 같다
assert b['shipped_qty'] == 10, b['shipped_qty']
ok += 1
assert b['weekly_plan']['2026-10']['W41'] == {'plan': 160, 'actual': 5}, b['weekly_plan']
ok += 1
assert ms['556B']['po_qty'] == 2, '다른 모델을 건드렸다'
ok += 1
assert d.get('migrations', {}).get('curie_busbar_merged') is True
ok += 1

# 두 번째는 아무것도 안 한다
n = len(saved)
run(d)
assert len(d['projects']['spacex']['models']) == 2 and len(saved) == n, '또 돌았다'
ok += 1

# 나중에 5xxD 를 새로 넣어도 다시 합치지 않는다
d['projects']['spacex']['models'].append({'id': '571D', 'po_qty': 7})
run(d)
assert any(m['id'] == '571D' for m in d['projects']['spacex']['models']), \
    '한 번 끝난 뒤에 새로 넣은 품번까지 먹었다'
ok += 1

# 엑셀에서 이미 받은 값이 있으면 그게 정본
d2 = copy.deepcopy(DATA)
d2['projects']['spacex']['models'].append(
    {'id': '버스바/시트메탈류(11종)', 'po_qty': 1740, 'shipped_qty': 0,
     'weekly_plan': {'2026-09': {'W40': {'plan': 1380, 'actual': 0}}}})
d2 = run(d2)
b2 = {m['id']: m for m in d2['projects']['spacex']['models']}['버스바/시트메탈류(11종)']
assert b2['po_qty'] == 1740 and b2['weekly_plan'] == {'2026-09': {'W40': {'plan': 1380, 'actual': 0}}}, b2
assert len(d2['projects']['spacex']['models']) == 2
ok += 1

# 대상이 없으면 조용히 표시만 남긴다
d3 = run({'projects': {'spacex': {'models': [{'id': 'X', 'po_qty': 1}]}}})
assert len(d3['projects']['spacex']['models']) == 1
assert d3['migrations']['curie_busbar_merged'] is True
ok += 1

# 배포 때 실제로 도는지
assert re.search(r'^_merge_curie_busbar\(\)$', SRC, re.M), '시작할 때 안 부른다'
ok += 1

print(f'전부 통과 ({ok}/10)')
