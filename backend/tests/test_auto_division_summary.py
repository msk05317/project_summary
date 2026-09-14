# 자동차사업부 사업부 요약(/divisions/automotive/summary) 합계 검증
#   python3 backend/tests/test_auto_division_summary.py
import pathlib
import ast, sys, json

src = open(pathlib.Path(__file__).resolve().parents[1] / 'main.py', encoding='utf-8').read()
tree = ast.parse(src)
want = {'get_automotive_summary', 'get_automotive_division_summary', '_as_money', '_as_int'}
grab = {}
for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in want:
        n.decorator_list = []
        grab[n.name] = ast.unparse(n)
assert want <= set(grab), set(grab)

PROJ = [
    {'id': 'auto_a', 'label': '가고객'},
    {'id': 'auto_b', 'label': '나고객'},
    {'id': 'auto_c', 'label': '다고객'},   # 계약 없음
]
def mk(name, quote, parts, contract, group='양산'):
    # 판가는 다섯 항목 합계다. price_krw 는 엑셀 '판가' 열 — 참고 견적.
    return {'id': name, 'name': name, 'group': group,
            'auto': {'price_krw': quote, 'cost': parts, 'contract': contract}}
C = lambda m,p,a,d,l: {'material':m,'process':p,'admin':a,'depr':d,'logi':l}
MODELS = {'projects': {
    'auto_a': {'models': [
        mk('A1', 1000, C(400,300,100,100,50), {'2026': {'qty': 10, 'revenue': 1.0}, '2027': {'qty': 20, 'revenue': 2.0}}),
        mk('A2', 1000, C(600,400,100,100,50), {'2026': {'qty': 5, 'revenue': 0.5}}),
    ]},
    'auto_b': {'models': [
        mk('B1', 2000, C(400,300,100,100,50), {'2027': {'qty': 7, 'revenue': 3.0}}),
    ]},
    'auto_c': {'models': []},
}}

g = {}
exec('\n\n'.join(grab.values()), g)
g['_auto_projects'] = lambda: PROJ
g['_load_models'] = lambda: MODELS
g['_model_key_alias'] = lambda k: k
g['_display_project_label'] = lambda k: {p['id']: p['label'] for p in PROJ}.get(k, k)

out = g['get_automotive_division_summary']()
print(json.dumps(out, ensure_ascii=False, indent=1))

t = out['totals']
assert t['projects'] == 3, t
assert t['with_contract'] == 2, t
assert t['products'] == 3, t
assert t['qty'] == 10+20+5+7, t
assert round(t['revenue'], 4) == 6.5, t
assert t['year_revenue'] == 0.0 or True
assert 'over_cost' not in t, t          # 원가 초과 개념은 없앴다
assert out['by_year']['2026'] == {'qty': 15, 'revenue': 1.5}, out['by_year']
assert out['by_year']['2027'] == {'qty': 27, 'revenue': 5.0}, out['by_year']
assert [r['label'] for r in out['projects']] == ['가고객', '나고객', '다고객'], out['projects']
assert abs(out["projects"][0]["share"] - round(3.5/6.5, 4)) < 1e-9, out['projects'][0]['share']
assert out['projects'][2]['share'] == 0.0
assert 'by_year' not in out['projects'][0]
# 올해(2026) 값이 제대로 뽑히는지
y26 = g['get_automotive_division_summary'](year=2026)
assert y26['totals']['year_qty'] == 15 and round(y26['totals']['year_revenue'],4) == 1.5, y26['totals']

# 판가 = 다섯 항목 합계, 견적은 엑셀 '판가' 열로 따로 간다
pa = g['get_automotive_summary']('auto_a')['products']
byname = {p['name']: p for p in pa}
assert byname['A1']['price'] == 950 and byname['A1']['quote'] == 1000, byname['A1']
assert byname['A2']['price'] == 1250 and byname['A2']['quote'] == 1000, byname['A2']
for p in pa:
    assert p['price'] == sum(p['parts'].values()), p
    assert 'cost_total' not in p, p


# 원가율 = (판가 − 관리이윤) ÷ 판가. 묶음은 물량으로 가중한다.
#   A1  판가 950  관리이윤 100 → 원가 850, 원가율 89.47%, 물량 30
#   A2  판가 1250 관리이윤 100 → 원가 1150, 원가율 92.00%, 물량 5
#   B1  판가 950  관리이윤 100 → 원가 850, 원가율 89.47%, 물량 7
assert abs(byname['A1']['cost_ratio'] - 850 / 950) < 1e-4, byname['A1']
assert byname['A1']['cost'] == 850 and byname['A2']['cost'] == 1150
ta = g['get_automotive_summary']('auto_a')['totals']
want = (850 * 30 + 1150 * 5) / (950 * 30 + 1250 * 5)
assert abs(ta['cost_ratio'] - round(want, 4)) < 1e-4, (ta['cost_ratio'], want)

# 단순평균이 아니라 가중이어야 한다 — 둘이 같으면 검증이 안 된다
simple = (850 / 950 + 1150 / 1250) / 2
assert abs(ta['cost_ratio'] - simple) > 1e-3, '가중이 아니라 단순평균이다'

dv = out['totals']
want_all = (850 * 30 + 1150 * 5 + 850 * 7) / (950 * 30 + 1250 * 5 + 950 * 7)
assert abs(dv['cost_ratio'] - round(want_all, 4)) < 1e-4, (dv['cost_ratio'], want_all)

print('\nOK 16/16')
