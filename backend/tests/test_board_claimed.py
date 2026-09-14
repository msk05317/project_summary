# 쓸어담기 행이 다른 행의 품번까지 가져가 두 번 세어지던 문제
#   python3 backend/tests/test_board_claimed.py
import ast, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_board_row_models', '_spec_claimed_models', '_norm_group'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
g = {}
for n in ('_norm_group', '_spec_claimed_models', '_board_row_models'):
    exec(srcs[n], g)
rows_of, claimed_of = g['_board_row_models'], g['_spec_claimed_models']

BOARDS = json.loads((ROOT / 'config' / 'boards.json').read_text(encoding='utf-8'))['boards']

# ── 챔버: 205 는 개발이고 자기 행이 있는데 dev_type 이 DEP챔버 라 Dep 에도 잡혔다
CH = {'models': (
    [{'id': '715-044854-002', 'group': '양산'}] +
    [{'id': '715-181531-205', 'group': '개발', 'dev_type': 'DEP챔버'}] +
    [{'id': f'dep{i}', 'group': '개발', 'dev_type': 'DEP챔버'} for i in range(15)] +
    [{'id': '15-152302-00', 'group': '개발', 'dev_type': 'HVM'},
     {'id': '15-379966-00', 'group': '개발', 'dev_type': 'HVM'},
     {'id': '15-389568-00', 'group': '개발'},
     {'id': '853-268706-003', 'group': '개발', 'dev_type': 'HVM'}])}

spec = BOARDS['chamber']
cl = claimed_of(spec)
assert '715-181531-205' in cl and '715-044854-002' in cl, cl

def find(spec, key):
    for sec in spec['sections']:
        for r in sec['rows']:
            if r['key'] == key:
                return r
    raise KeyError(key)

ok = 0
dep = rows_of(CH, find(spec, 'dep'), cl)
assert len(dep) == 15, f'Dep 챔버가 15종이 아니다: {len(dep)}'
assert all(m['id'] != '715-181531-205' for m in dep), '205 가 아직 Dep 에 잡힌다'
ok += 1

m205 = rows_of(CH, find(spec, 'm205'), cl)
assert [m['id'] for m in m205] == ['715-181531-205'], f'205 행이 비었다: {m205}'
ok += 1

m002 = rows_of(CH, find(spec, 'm002'), cl)
assert [m['id'] for m in m002] == ['715-044854-002'], m002
ok += 1

# 어떤 모델도 두 행에 겹쳐 잡히면 안 된다
seen, dup = set(), []
for sec in spec['sections']:
    for r in sec['rows']:
        if r.get('manual'):
            continue
        for m in rows_of(CH, r, cl):
            if m['id'] in seen:
                dup.append(m['id'])
            seen.add(m['id'])
assert not dup, f'두 행에 겹쳐 잡힌 모델: {dup}'
ok += 1

# ── 엔클로저: 손으로 적어둔 exclude 와 결과가 같아야 한다 (회귀 방지)
EN = {'models': [{'id': '714-025898-009', 'group': '양산', 'dev_type': '009'},
                 {'id': '714-000000-009', 'group': '양산', 'dev_type': '009'},
                 {'id': '714-000000-413', 'group': '양산', 'dev_type': '413'}]}
es = BOARDS['enclosure']
ec = claimed_of(es)
direct = [m['id'] for m in rows_of(EN, find(es, 't009_direct'), ec)]
jabil = [m['id'] for m in rows_of(EN, find(es, 't009_jabil'), ec)]
assert direct == ['714-000000-009'], direct
assert jabil == ['714-025898-009'], jabil
ok += 1

# ── 파워박스: AetherGDX 가 양산19종에 섞이면 안 된다
PB = {'models': [{'id': '925-800083-394', 'group': '양산'},
                 {'id': 'pb-mass', 'group': '양산'},
                 {'id': 'pb-ema', 'group': '양산', 'dev_type': 'EMA'},
                 {'id': 'pb-dev', 'group': '개발'}]}
ps = BOARDS['powerbox']
pc = claimed_of(ps)
mass = [m['id'] for m in rows_of(PB, find(ps, 'mass19'), pc)]
assert mass == ['pb-mass'], mass
assert [m['id'] for m in rows_of(PB, find(ps, 'aether'), pc)] == ['925-800083-394']
assert [m['id'] for m in rows_of(PB, find(ps, 'ema10'), pc)] == ['pb-ema']
ok += 1

# ── claimed 를 안 넘기면 예전 동작 그대로 (다른 호출부 보호)
assert len(rows_of(CH, find(spec, 'dep'), None)) == 16, 'claimed 없이도 걸러버렸다'
ok += 1

# ── 실제 조립부가 claimed 를 넘기는지
assert '_board_row_models(proj, row, claimed)' in SRC, '보드 조립부가 claimed 를 안 넘긴다'
assert 'claimed = _spec_claimed_models(spec)' in SRC
ok += 1

print(f'전부 통과 ({ok}/8)')
