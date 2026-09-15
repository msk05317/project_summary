# 전환 주차가 지나면 구분이 양산으로 '보이는지'
#   python3 backend/tests/test_display_group.py
#
# 저장된 group 은 안 바꾼다. 진행률은 계속 공정 단계로 세야 하고,
# 지난 주차 매출도 그때 구분·판가로 남아야 한다.
import ast, datetime, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_display_group', '_norm_phases', '_phase_ord', '_as_money'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
g = {}
for n in ('_phase_ord', '_as_money', '_norm_phases', '_display_group'):
    exec(srcs[n], g)
f = g['_display_group']

Y, W = datetime.date.today().isocalendar()[0], datetime.date.today().isocalendar()[1]
def wk(off):
    return '%04d-W%02d' % (Y, W + off)

ok = 0
# 이력이 없으면 저장된 값 그대로
assert f({'group': '개발'}) == '개발'
assert f({'group': '양산'}) == '양산'
assert f({}) == '양산'
ok += 1

# 전환 주차가 지났으면 양산으로 보인다 (이번 주 포함)
past = {'group': '개발', 'phases': [
    {'from': '%04d-W01' % Y, 'group': '개발', 'price': 138470},
    {'from': wk(-1), 'group': '양산', 'price': 96000}]}
assert f(past) == '양산', '지난 전환인데 개발로 보인다'
ok += 1
this_week = {'group': '개발', 'phases': [
    {'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
    {'from': wk(0), 'group': '양산', 'price': 2}]}
assert f(this_week) == '양산', '이번 주 전환인데 개발로 보인다'
ok += 1

# 아직 안 온 전환은 개발 그대로
future = {'group': '개발', 'phases': [
    {'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
    {'from': wk(+3), 'group': '양산', 'price': 2}]}
assert f(future) == '개발', '아직 안 온 전환인데 벌써 양산으로 보인다'
ok += 1

# 이력이 내년부터 시작 — 첫 구간을 쓴다 (빈칸으로 두면 안 된다)
later = {'group': '양산', 'phases': [{'from': '%04d-W05' % (Y + 1), 'group': '개발', 'price': 1}]}
assert f(later) == '개발', later
ok += 1

# 양산 → 개발 로 되돌린 이력도 따라간다
back = {'group': '양산', 'phases': [
    {'from': '%04d-W01' % Y, 'group': '양산', 'price': 1},
    {'from': wk(-2), 'group': '개발', 'price': 2}]}
assert f(back) == '개발', back
ok += 1

# 저장된 값은 절대 안 건드린다
m = {'group': '개발', 'phases': [{'from': wk(-1), 'group': '양산', 'price': 2}]}
before = dict(m)
f(m)
assert m['group'] == '개발' == before['group'], '저장된 group 을 건드렸다'
ok += 1

# 깨진 이력은 무시하고 저장값으로
assert f({'group': '개발', 'phases': 'x'}) == '개발'
assert f({'group': '개발', 'phases': [{'from': '없음', 'group': '양산'}]}) == '개발'
ok += 1

# 실제 연결부
assert 'm["display_group"] = g' in SRC, '앱 목록이 display_group 을 안 붙인다'
assert 'out["display_group"] = _display_group(m)' in SRC, '상세가 display_group 을 안 붙인다'
assert 'g = _display_group(m) if isinstance(m, dict) else "기타"' in SRC, \
    '앱 목록 탭이 아직 저장된 group 으로 나뉜다'
ok += 1

print(f'전부 통과 ({ok}/9)')
