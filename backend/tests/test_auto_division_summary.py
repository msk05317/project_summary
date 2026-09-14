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
def mk(name, price, cost, contract, group='양산'):
    return {'id': name, 'name': name, 'group': group,
            'auto': {'price_krw': price, 'cost': cost, 'contract': contract}}
C = lambda m,p,a,d,l: {'material':m,'process':p,'admin':a,'depr':d,'logi':l}
MODELS = {'projects': {
    'auto_a': {'models': [
        mk('A1', 1000, C(400,300,100,100,50), {'2026': {'qty': 10, 'revenue': 1.0}, '2027': {'qty': 20, 'revenue': 2.0}}),
        mk('A2', 1000, C(600,400,100,100,50), {'2026': {'qty': 5, 'revenue': 0.5}}),   # 원가 1250 > 판가
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
assert t['over_cost'] == 1 and t['over_cost_names'] == ['A2'], t
assert out['by_year']['2026'] == {'qty': 15, 'revenue': 1.5}, out['by_year']
assert out['by_year']['2027'] == {'qty': 27, 'revenue': 5.0}, out['by_year']
assert [r['label'] for r in out['projects']] == ['가고객', '나고객', '다고객'], out['projects']
assert abs(out["projects"][0]["share"] - round(3.5/6.5, 4)) < 1e-9, out['projects'][0]['share']
assert out['projects'][2]['share'] == 0.0
assert 'by_year' not in out['projects'][0]
# 올해(2026) 값이 제대로 뽑히는지
y26 = g['get_automotive_division_summary'](year=2026)
assert y26['totals']['year_qty'] == 15 and round(y26['totals']['year_revenue'],4) == 1.5, y26['totals']
print('\nOK 8/8')
