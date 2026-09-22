# 블룸 품목 중복 — 'Corva KPE' (9/14 파일) 와 'Corva KPE (117품목)' (9/22 파일).
#   python3 backend/tests/test_bloom_dupes.py
#
# 파일마다 품목 이름에 '(N품목)' 을 붙였다 뗐다 하고, 공정도 'NCT(박장)' →
# 'NCT(박닌)' 처럼 공장만 바뀐다. 이름이 다르다고 따로 쌓으면 화면에 두 줄씩 뜬다.
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import bloom_daily_import as bd          # noqa: E402

SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {}
want = {'_norm_label', '_bloom_pick', '_bloom_last_day', '_bloom_fold_steps',
        '_bloom_fold', '_bloom_merge', '_bloom_slice'}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in want:
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.Assign) and any(getattr(t, 'id', '') == '_BLOOM_DIFF_CAP' for t in n.targets):
        exec(ast.get_source_segment(SRC, n), g)
assert want <= set(g), want - set(g)
ok = 0

assert bd.clean_item('Corva KPE (117품목)') == 'Corva KPE'
assert bd.clean_item('BOP 기구 (33 품목)') == 'BOP 기구'
assert bd.clean_item('BOP Assy') == 'BOP Assy'
assert bd.step_key('NCT(박장)') == bd.step_key('NCT(박닌)') == 'NCT'
ok += 1


def step(name, days, mp=None, ma=None):
    return {'step': name, 'group': bd.step_group(name), 'month_plan': mp, 'month_actual': ma,
            'days': {d: {'plan': p, 'actual': a} for d, (p, a) in days.items()}}


OLD = {'items': [
    {'item': 'Corva KPE', 'steps': [step('NCT(박닌)', {'2026-09-11': (10, 8)}, 1000, 100)]},
    {'item': 'BOP 기구', 'steps': [step('NCT(박장)', {'2026-09-11': (80, 70)}, 1600, 500)]},
    {'item': 'YFP', 'steps': [step('출하', {'2026-09-11': (0, 0)})]},
]}
NEW = {'items': [
    {'item': 'Corva KPE (117품목)', 'steps': [step('NCT(박닌)', {'2026-09-21': (50, 50)}, 1050, 525)]},
    {'item': 'BOP 기구 (33품목)', 'steps': [step('NCT(박닌)', {'2026-09-21': (80, 38)}, 1600, 1002)]},
]}

# ── 업로드 합치기: 이름이 달라도 한 품목 · 한 공정 ──
b, diff = g['_bloom_merge'](OLD, NEW)
names = [i['item'] for i in b['items']]
assert names == ['Corva KPE', 'BOP 기구', 'YFP'], names
kpe = b['items'][0]
assert len(kpe['steps']) == 1, kpe['steps']
assert set(kpe['steps'][0]['days']) == {'2026-09-11', '2026-09-21'}, '옛 날짜가 사라졌다'
assert kpe['steps'][0]['month_plan'] == 1050, '새 월계획이 안 들어갔다'
bop = b['items'][1]
assert len(bop['steps']) == 1 and bop['steps'][0]['step'] == 'NCT(박닌)', bop['steps']
assert set(bop['steps'][0]['days']) == {'2026-09-11', '2026-09-21'}
assert diff['items_new'] == [] and diff['steps_new'] == [], diff
ok += 1

# ── 이미 두 줄로 저장된 보드도 합친다 (새 날짜 쪽 값이 이긴다) ──
DUP = OLD['items'][:2] + NEW['items']
f = g['_bloom_fold'](DUP)
assert [i['item'] for i in f] == ['Corva KPE', 'BOP 기구'], [i['item'] for i in f]
assert f[0]['steps'][0]['month_actual'] == 525, f[0]['steps'][0]
assert len(f[1]['steps']) == 1
ok += 1

# ── 순서가 거꾸로 저장돼 있어도 새 날짜 쪽이 이긴다 ──
f2 = g['_bloom_fold'](NEW['items'] + OLD['items'][:2])
assert f2[0]['steps'][0]['month_actual'] == 525
ok += 1

# ── 품목 프로젝트 화면: 'Corva KPE' 로 등록돼 있어도 새 이름 품목을 찾는다 ──
s = g['_bloom_slice']({'items': NEW['items']}, 'Corva KPE')
assert len(s['items']) == 1
ok += 1

print(f'test_bloom_dupes: {ok} passed')
