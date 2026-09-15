# 홈 화면이 프로젝트 안쪽과 같은 값을 보는지
#   python3 backend/tests/test_home_alerts.py
#
# 예전 홈은 /dashboard 의 주간보고 카드(RED/YELLOW)로 사업부 상태를 셌다.
# 주간보고가 없는 사업부는 집계에서 통째로 빠져서 '12개 중 정상 2' 가 되고,
# 프로젝트 안에는 지연이 널려 있는데 홈은 '지연 0' 이었다.
import ast, io, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0

# 데코레이터 없는 최상위 함수 + 단순 상수를 그대로 올린다
g = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and not n.decorator_list:
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
for n in tree.body:
    if (isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
            and isinstance(n.value, (ast.Constant, ast.Tuple, ast.List, ast.Dict, ast.Set))):
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
fn = None
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name == 'get_home_alerts':
        body = ast.get_source_segment(SRC, n)
        exec('\n'.join(l for l in body.split('\n') if not l.strip().startswith('@')), g)
        fn = g['get_home_alerts']
assert fn, '/home/alerts 엔드포인트가 없다'
ok += 1

CFG = json.loads((ROOT / 'config' / 'projects.json').read_text(encoding='utf-8'))['projects']
g['PROJECT_LABELS'] = {p['id']: p.get('label', p['id']) for p in CFG}
g['_cl'] = type('C', (), {'get_projects': staticmethod(
    lambda visible_only=True: [p for p in CFG if p.get('visible', True)] if visible_only else CFG)})()

# ── 지어낸 데이터로 판정 확인 ──
import datetime
past = (datetime.date.today() - datetime.timedelta(days=30)).strftime('%Y-%m-%d')
soon = (datetime.date.today() + datetime.timedelta(days=3)).strftime('%Y-%m-%d')


def dev(mid, expected, **kw):
    m = {'id': mid, 'name': mid, 'group': '개발', 'progress': 20,
         'process': [{'key': 'step_1', 'name': '01 발주', 'group': '발주',
                      'expected': expected, 'actual': '', 'status': ''}]}
    m.update(kw)
    return m


g['_load_models'] = lambda: {'projects': {'powerbox': {'models': [
    dev('LATE-1', past),
    dev('SOON-1', soon),
    dev('DROP-1', past, note='드롭 예정'),
    {'id': 'MASS-1', 'name': 'MASS-1', 'group': '양산', 'po_qty': 0},
    {'id': 'MASS-2', 'name': 'MASS-2', 'group': '양산', 'po_qty': 100, 'shipped_qty': 100},
]}}}
r = fn(10)
c = r['counts']
assert c['total'] == 5, c
assert c['delayed'] == 1, f"지연이 1이어야 한다: {c}"
assert c['soon'] == 1, f"임박이 1이어야 한다: {c}"
assert c['hold'] == 1, f"드롭 예정이 보류로 안 잡힌다: {c}"
assert c['po_wait'] == 1, f"양산 PO 0 이 PO 대기가 아니다: {c}"
ok += 1

# 드롭은 지연 목록에 안 들어간다
ids = [a['id'] for a in r['alerts']]
assert 'DROP-1' not in ids, '드롭 예정이 지연 목록에 있다'
assert 'LATE-1' in ids and 'SOON-1' in ids, ids
ok += 1

# 지연이 임박보다 위
assert r['alerts'][0]['kind'] == '지연', r['alerts']
assert r['alerts'][0]['days'] and r['alerts'][0]['days'] >= 29
ok += 1

# 프로젝트 단위 묶음
rows = r['by_project']
assert len(rows) == 1 and rows[0]['key'] == 'powerbox'
assert rows[0]['delayed'] == 1 and rows[0]['soon'] == 1
assert rows[0]['worst_model'] == 'LATE-1'
ok += 1

# ── 실제 데이터: 홈이 '지연 0' 이라고 말하면 안 된다 ──
bk = sorted((ROOT.parent / 'backups').glob('models_*.json'))
if bk:
    data = json.loads(bk[-1].read_text(encoding='utf-8'))
    g['_load_models'] = lambda: data
    real = fn(12)
    rc = real['counts']
    assert rc['total'] > 100, rc
    assert rc['delayed'] + rc['soon'] > 0, \
        f"실제 데이터에 지연·임박이 있는데 홈은 0 이라고 한다: {rc}"
    assert real['alerts_total'] == rc['delayed'] + rc['soon'], real['alerts_total']
    assert real['by_project'], '프로젝트 묶음이 비었다'
    ok += 1

# ── 앱이 이 값을 실제로 쓰는지 ──
LIB = ROOT.parent / 'mobile' / 'lib'
SVC = (LIB / 'services' / 'home_alerts_service.dart').read_text(encoding='utf-8')
assert '/home/alerts' in SVC and 'class HomeAlerts' in SVC
H = (LIB / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert '_RiskSummaryCard' in H and '_RiskListCard' in H, '홈이 새 카드를 안 쓴다'
assert 'HomeAlertsService.fetch()' in H
# 못 받아왔을 때 0 을 그리면 '지연 없음' 과 구분이 안 된다
assert '!a.loaded' in H and '현황을 불러오지 못했습니다' in H
assert 'AlertListScreen' in H, '모두 보기가 새 목록으로 안 간다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
