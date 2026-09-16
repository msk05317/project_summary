# 판가·재료비가 바뀌어도 지난 주차 매출은 그대로여야 한다
#   python3 backend/tests/test_price_phase.py
#
# 8월에 $7,243 으로 나간 물량이, 오늘 판가를 $7,800 으로 고치는 순간
# 8월 매출까지 같이 올라가면 안 된다. 그래서 판가는 '언제부터' 를
# 달고 구간(phases)으로 쌓는다.
import ast, datetime, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_apply_price_change', '_phase_row_at', '_phase_at', '_phase_cost_at',
        '_this_week_tag', '_norm_phases', '_phase_ord', '_week_ord', '_as_money'}
g = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') == '_PHASE_EPOCH':
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        exec(ast.get_source_segment(SRC, n), g)
missing = WANT - set(g)
assert not missing, f'못 찾은 함수: {missing}'
apply_, row_at = g['_apply_price_change'], g['_phase_row_at']
at, cost_at, wk = g['_phase_at'], g['_phase_cost_at'], g['_this_week_tag']
EPOCH = g['_PHASE_EPOCH']
NOW = wk()
ok = 0

# ── 이력 없는 모델은 지금 값을 그대로 쓴다 (기존 동작) ──
m = {'group': '양산', 'price': 7243, 'material_cost': 5000}
assert at(m, '2026-08', 33) == ('양산', 7243)
assert cost_at(m, '2026-08', 33) == 5000
ok += 1

# ── 지금부터: 지난 주차는 옛 판가 그대로 ──
e = {'id': 'VCTR-1', 'group': '양산', 'price': 7800, 'material_cost': 5000}
old = {'group': '양산', 'price': 7243, 'material_cost': 5000}
ch = apply_(e, old, 'from_now')
assert ch and ch['mode'] == 'from_now' and ch['from'] == NOW
assert ch['price'] == [7243, 7800]
ph = e['phases']
assert len(ph) == 2 and ph[0]['from'] == EPOCH and ph[1]['from'] == NOW
assert at(e, '2026-08', 33) == ('양산', 7243), '8월 매출이 같이 올라갔다'
ok += 1

# 앞으로 올 주차는 새 판가
assert row_at(e, '2099-12', 50)['price'] == 7800, '앞으로는 새 판가여야 한다'
ok += 1

# ── 같은 주에 두 번 고쳐도 구간이 늘지 않는다 ──
ch2 = apply_(e, {'group': '양산', 'price': 7800, 'material_cost': 5000}, 'from_now')
assert len(e['phases']) == 2, '같은 주에 구간이 또 생겼다'
e['price'] = 8100
apply_(e, {'group': '양산', 'price': 7800, 'material_cost': 5000}, 'from_now')
assert len(e['phases']) == 2 and e['phases'][-1]['price'] == 8100
assert at(e, '2026-08', 33) == ('양산', 7243), '과거는 계속 옛 판가'
ok += 1

# ── 재료비만 놔두고 판가만 고쳐도 재료비가 0 으로 날아가지 않는다 ──
e2 = {'id': 'M2', 'group': '양산', 'price': 9000, 'material_cost': 0}
apply_(e2, {'group': '양산', 'price': 8000, 'material_cost': 6100}, 'from_now')
assert e2['phases'][-1]['material_cost'] == 6100, '재료비가 0 으로 덮였다'
assert e2['phases'][-1]['price'] == 9000
ok += 1

# 재료비만 고친 경우도 판가를 이어받는다
e3 = {'id': 'M3', 'group': '양산', 'price': 0, 'material_cost': 7000}
apply_(e3, {'group': '양산', 'price': 8000, 'material_cost': 6100}, 'from_now')
assert e3['phases'][-1]['price'] == 8000, '판가가 0 으로 덮였다'
assert e3['phases'][-1]['material_cost'] == 7000
ok += 1

# ── 개발→양산 전환한 모델: 새 구간이 개발로 되돌아가면 안 된다 ──
e4 = {'id': 'M4', 'group': '개발', 'price': 7800, 'material_cost': 70000,
      'phases': [{'from': EPOCH, 'group': '개발', 'price': 3400, 'material_cost': 70000},
                 {'from': '2026-W20', 'group': '양산', 'price': 7243,
                  'material_cost': 70000}]}
apply_(e4, {'group': '개발', 'price': 7243, 'material_cost': 70000}, 'from_now')
last = e4['phases'][-1]
assert last['group'] == '양산', f"양산 모델이 개발로 되돌아갔다: {last['group']}"
assert last['material_cost'] == 70000, '재료비 이력이 끊겼다'
assert at(e4, '2026-03', 10) == ('개발', 3400), '개발 구간이 깨졌다'
assert at(e4, '2026-06', 25) == ('양산', 7243), '전환 구간이 깨졌다'
ok += 1

# ── 처음부터 고침(입력 오류 정정): 구간을 늘리지 않고 마지막 구간을 덮는다 ──
e5 = {'id': 'M5', 'group': '양산', 'price': 7800, 'material_cost': 5200,
      'phases': [{'from': EPOCH, 'group': '양산', 'price': 7000, 'material_cost': 5000},
                 {'from': '2026-W20', 'group': '양산', 'price': 7243,
                  'material_cost': 5200}]}
ch5 = apply_(e5, {'group': '양산', 'price': 7243, 'material_cost': 5200}, 'retro')
assert ch5['mode'] == 'retro' and ch5['from'] == '2026-W20'
assert len(e5['phases']) == 2, 'retro 인데 구간이 늘었다'
assert e5['phases'][-1]['price'] == 7800
assert at(e5, '2026-06', 25) == ('양산', 7800), '적용 구간 전체가 안 바뀌었다'
assert at(e5, '2026-03', 10) == ('양산', 7000), '그 앞 구간까지 건드렸다'
ok += 1

# retro + 이력 없음 = 전 기간이 새 값 (그게 의도)
e6 = {'id': 'M6', 'group': '양산', 'price': 9500, 'material_cost': 5000}
ch6 = apply_(e6, {'group': '양산', 'price': 7243, 'material_cost': 5000}, 'retro')
assert ch6['mode'] == 'retro' and ch6['from'] == EPOCH
assert not e6.get('phases'), '이력 없는 retro 가 구간을 만들었다'
assert at(e6, '2026-01', 3) == ('양산', 9500)
ok += 1

# ── 안 바뀌었으면 아무것도 안 한다 ──
e7 = {'id': 'M7', 'group': '양산', 'price': 7243, 'material_cost': 5000}
assert apply_(e7, {'price': 7243, 'material_cost': 5000}, 'from_now') == {}
assert 'phases' not in e7, '안 바뀌었는데 구간이 생겼다'
assert apply_(e7, {'price': '7,243', 'material_cost': '5000'}, 'from_now') == {}, \
    '천단위 쉼표를 다른 값으로 읽는다'
ok += 1

# 새로 추가된 모델(old 없음)은 이력이 필요 없다
e8 = {'id': 'M8', 'group': '양산', 'price': 7243, 'material_cost': 5000}
assert apply_(e8, {}, 'from_now') == {}
assert 'phases' not in e8
ok += 1

# ── 첫 구간보다 앞선 주차는 첫 구간을 쓴다 (빈 값 아님) ──
e9 = {'id': 'M9', 'group': '양산', 'price': 7800, 'material_cost': 5000,
      'phases': [{'from': '2026-W20', 'group': '양산', 'price': 7243,
                  'material_cost': 5000}]}
assert at(e9, '2026-01', 3) == ('양산', 7243)
ok += 1

# ── 주차 태그 형식 ──
assert wk(datetime.date(2026, 1, 5)) == '2026-W02'
assert len(NOW) == 8 and NOW[4] == '-' and NOW[5] == 'W'
ok += 1

# ── admin 화면: 저장할 때 물어본다 ──
ADMIN = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'askPriceMode' in ADMIN, 'admin 에 확인 대화상자가 없다'
assert 'price_mode' in ADMIN and "'preview'" in ADMIN, '미리보기를 안 물어본다'
assert 'from_now' in ADMIN and 'retro' in ADMIN, '적용 시점 선택지가 없다'
ok += 1

# 서버가 price_mode 를 읽는지
assert 'price_mode' in SRC and '_price_changes' in SRC, '서버가 안 받는다'
assert '"preview"' in SRC or "'preview'" in SRC, '미리보기가 저장해버린다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
