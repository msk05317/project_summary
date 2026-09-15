# 큐리 버스바 품번 되살리기 (1회)
#   python3 backend/tests/test_curie_restore.py
#
# 내가 잘못 만든 합치기가 품번 11개를 지웠다. _save_models 가 덮어쓰기 전에
# 남긴 자동 백업에서 큐리 모델 목록만 되돌린다.
import ast, copy, json, os, pathlib, tempfile

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
fn = next((ast.get_source_segment(SRC, n) for n in tree.body
           if isinstance(n, ast.FunctionDef) and n.name == '_restore_curie_busbar'), None)
assert fn, '_restore_curie_busbar 를 못 찾았다'
consts = {n.targets[0].id: ast.unparse(n.value) for n in tree.body
          if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '')
          in ('_CURIE_KEY', '_CURIE_PN_RE', '_CURIE_RESTORE_KEY')}
assert len(consts) == 3, consts.keys()

PNS = ['568D', '569D', '566D', '564D', '563D', '562D', '561D', '570D', '560D', '559D', '565D']
OLD = {'projects': {'spacex': {'models':
    [{'id': '556B', 'name': '키스톤', 'po_qty': 2},
     {'id': '66C', 'name': '리프트 캐리지', 'po_qty': 24,
      'weekly_plan': {'2026-09': {'W38': {'plan': 4, 'actual': 0}}}}] +
    [{'id': i, 'name': '버스바', 'po_qty': 20, 'price': 100} for i in PNS]}}}
# 합치기가 지나간 뒤 (품번이 사라지고 묶음 모델만 남았다)
NOW = {'projects': {'spacex': {'models': [
    {'id': '556B', 'name': '키스톤', 'po_qty': 2},
    {'id': '66C', 'name': '리프트 캐리지', 'po_qty': 24,
     'weekly_plan': {'2026-09': {'W38': {'plan': 4, 'actual': 0}}}},
    {'id': '버스바/시트메탈류(11종)', 'po_qty': 1740},
]}}}


def run(now, backups, tmp):
    saved = []
    g = {'os': os, 'MODELS_FILE': os.path.join(tmp, 'models.json'),
         '_load_models': lambda: now,
         '_save_models': lambda d: saved.append(1),
         'print': lambda *a, **k: None}
    exec('import re\n' + '\n'.join(f'{k} = {v}' for k, v in consts.items()), g)
    for i, b in enumerate(backups):
        with open(os.path.join(tmp, f'models.json.auto_{i:03d}'), 'w', encoding='utf-8') as f:
            json.dump(b, f, ensure_ascii=False)
    exec(fn, g)
    g['_restore_curie_busbar']()
    return now, saved


ok = 0
with tempfile.TemporaryDirectory() as tmp:
    now, saved = run(copy.deepcopy(NOW), [OLD], tmp)
    ms = {m['id']: m for m in now['projects']['spacex']['models']}
    assert set(PNS) <= set(ms), f'품번이 안 돌아왔다: {sorted(ms)}'
    ok += 1
    assert '버스바/시트메탈류(11종)' not in ms, '합치면서 만든 묶음 모델이 남았다'
    ok += 1
    # 품번별 판가가 살아 있어야 한다 (합쳐버리면 넣을 자리가 없어진다)
    assert ms['568D']['price'] == 100, ms['568D']
    ok += 1
    # 다른 모델의 주차 계획도 백업 것으로 같이 돌아온다
    assert ms['66C']['weekly_plan']['2026-09']['W38'] == {'plan': 4, 'actual': 0}
    ok += 1
    assert now['migrations']['curie_busbar_restored'] is True and len(saved) == 1
    ok += 1

    # 두 번째는 아무것도 안 한다
    n = len(saved)
    before = copy.deepcopy(now)
    now2, saved2 = run(now, [OLD], tmp)
    assert now2 == before, '또 돌았다'
    ok += 1

with tempfile.TemporaryDirectory() as tmp:
    # 이미 품번이 있으면 백업을 안 쓴다 (되돌리면 그 뒤 입력이 날아간다)
    cur = copy.deepcopy(OLD)
    cur['projects']['spacex']['models'][0]['po_qty'] = 999
    now3, _ = run(cur, [OLD], tmp)
    assert now3['projects']['spacex']['models'][0]['po_qty'] == 999, '멀쩡한 데이터를 덮었다'
    assert now3['migrations']['curie_busbar_restored'] is True
    ok += 1

with tempfile.TemporaryDirectory() as tmp:
    # 쓸 만한 백업이 없으면 아무것도 안 하고, 표시도 안 남긴다 (다음에 다시 시도)
    now4, saved4 = run(copy.deepcopy(NOW), [{'projects': {}}], tmp)
    assert '버스바/시트메탈류(11종)' in {m['id'] for m in now4['projects']['spacex']['models']}
    assert not (now4.get('migrations') or {}).get('curie_busbar_restored'), \
        '못 되살렸는데 끝난 것으로 표시했다'
    assert not saved4
    ok += 1

assert '_restore_curie_busbar()' in SRC.split('\n')[-5:] or \
       any(l.strip() == '_restore_curie_busbar()' for l in SRC.split('\n')), '시작할 때 안 부른다'
ok += 1
print(f'전부 통과 ({ok}/9)')
