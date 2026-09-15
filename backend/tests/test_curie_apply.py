# CURIE 계획&실적을 모델별 주차 계획으로 반영
#   python3 backend/tests/test_curie_apply.py
#
# 두 가지가 필요했다.
#   1) '키스톤 (556B)' 를 이름/품번으로 갈라 넣고, 품번만 모델명으로 넣어둔
#      기존 모델(556B)과도 붙어야 한다
#   2) '버스바/시트메탈류(11종)' 을 한 모델로 만든다 (큐리는 한 줄로 관리)
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)

WANT = {'_apply_plan_matrix', '_split_pn', '_norm_label', '_as_int', '_as_money',
        '_board_group_rows'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
consts = {}
for n in tree.body:
    if isinstance(n, ast.Assign):
        for t in n.targets:
            if getattr(t, 'id', '') == '_PN_IN_LABEL':
                consts[t.id] = n
assert set(consts) == {'_PN_IN_LABEL'}, consts.keys()

import re
g = {'re': re, '_get_month_weeks': lambda m: [], '_week_ord': lambda *a: 0}
exec("import re\n_PN_IN_LABEL = " + ast.unparse(consts['_PN_IN_LABEL'].value), g)
BUSBAR = ['568D', '569D', '566D', '564D', '563D', '562D', '561D',
          '570D', '560D', '559D', '565D']
# 보드 설정 대신 가짜로 — 이 테스트는 임포터만 본다
g['_load_board_spec'] = lambda pk: (
    {'sections': [{'rows': [{'key': 'busbar', 'label': '버스바/시트메탈류(11종)',
                             'models': BUSBAR}]}]} if pk == 'spacex' else {})
for n in ('_as_int', '_as_money', '_norm_label', '_split_pn',
          '_board_group_rows', '_apply_plan_matrix'):
    exec(srcs[n], g)
split, apply = g['_split_pn'], g['_apply_plan_matrix']

ok = 0
# ── 이름/품번 가르기 ──────────────────────────────────────────────
assert split('키스톤 (556B)') == ('키스톤', '556B')
assert split('리프트 캐리지 (66C)') == ('리프트 캐리지', '66C')
assert split('도기도어 (76C) ') == ('도기도어', '76C')
ok += 1
# 개수는 품번이 아니다 — 통째로 이름
assert split('버스바/시트메탈류(11종)') == ('버스바/시트메탈류(11종)', '')
assert split('Dep 챔버 15종') == ('Dep 챔버 15종', '')
ok += 1
assert split('EFEM') == ('EFEM', '') and split('') == ('', '')
ok += 1

def row(label, po, sh, weeks, agg=False):
    return {'label': label, 'po_qty': po, 'shipped_qty': sh, 'remaining': 0,
            'is_aggregate': agg, 'site': '', 'stock': None,
            'weeks': weeks, 'months': {}}

W = {'2026-09': {'W38': {'plan': 4, 'actual': 0}},
     '2026-10': {'W41': {'plan': 4, 'actual': 0}}}
PARSED = {'rows': [
    row('키스톤 (556B)', 2, 0, {'2026-09': {'W38': {'plan': 0, 'actual': 0}}}),
    row('리프트 캐리지 (66C)', 24, 12, W),
    row('버스바/시트메탈류(11종)', 1740, 0,
        {'2026-09': {'W40': {'plan': 1380, 'actual': 0}}}, agg=True),
]}

# ── 큐리: 품번만 모델명으로 들어가 있던 기존 모델과 붙는다 ─────────
data = {'projects': {'spacex': {'models': [
    {'id': '556B', 'name': '556B', 'po_qty': 2, 'shipped_qty': 0},
    {'id': '66C', 'name': '66C', 'po_qty': 24, 'shipped_qty': 12},
    {'id': '568D', 'name': '버스바', 'po_qty': 880, 'shipped_qty': 0},
    {'id': '569D', 'name': '버스바', 'po_qty': 860, 'shipped_qty': 0},
]}}}
res = apply(data, 'spacex', PARSED)
ms = {m['id']: m for m in data['projects']['spacex']['models']}
# 묶음 행은 모델로 만들지 않는다 — 모델 목록에는 품번별로 다 남는다
assert len(ms) == 4, list(ms)
assert '버스바/시트메탈류(11종)' not in ms, '묶음 행이 모델로 생겼다'
ok += 1
assert ms['66C']['weekly_plan']['2026-09']['W38'] == {'plan': 4, 'actual': 0}, ms['66C']
ok += 1
# 묶음 행의 주차 계획은 묶인 첫 모델에 얹는다 (보드가 행 안을 더한다)
assert ms['568D']['weekly_plan']['2026-09']['W40']['plan'] == 1380, ms['568D']
ok += 1
# PO 는 건드리지 않는다 — 모델별로 이미 있어서 더하면 두 배가 된다
assert ms['568D']['po_qty'] == 880 and ms['569D']['po_qty'] == 860, (ms['568D'], ms['569D'])
assert sum(m['po_qty'] for m in ms.values()) == 2 + 24 + 880 + 860, '묶음 PO 가 중복으로 들어갔다'
ok += 1
assert not res['unmatched'], res['unmatched']
ok += 1

# ── 새로 만들 때 이름/품번이 갈라진다 ─────────────────────────────
data2 = {'projects': {'spacex': {'models': []}}}
apply(data2, 'spacex', PARSED)
made = {m['id']: m for m in data2['projects']['spacex']['models']}
assert made['66C']['name'] == '리프트 캐리지', made['66C']
assert made['66C']['part_number'] == '66C', made['66C']
ok += 1

# ── 파워박스는 묶음 행을 모델로 만들면 안 된다 (이중 계산) ────────
data3 = {'projects': {'powerbox': {'models': []}}}
res3 = apply(data3, 'powerbox', {'rows': [
    row('양산19종', 500, 100, {'2026-09': {'W38': {'plan': 9, 'actual': 0}}}, agg=True)]})
assert not data3['projects']['powerbox']['models'], \
    '파워박스에 묶음 행이 모델로 생겼다 — 개별 모델과 이중 계산된다'
assert len(res3['unmatched']) == 1
ok += 1

print(f'전부 통과 ({ok}/10)')
