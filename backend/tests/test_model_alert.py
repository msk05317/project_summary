# 지연/주의 판정이 카드와 목록에서 같은지
#   python3 backend/tests/test_model_alert.py
#
# 카드는 손으로 적는 status 만 보고, 목록 줄은 완료예정일로 따졌다.
# 그래서 파워박스 목록에 '지연중' 이 다섯인데 카드는 '지연 0개' 였다.
import ast, datetime, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_model_alert', '_display_group', '_norm_phases', '_phase_ord',
        '_as_money', '_parse_any_date'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
g = {}
for n in ('_phase_ord', '_as_money', '_norm_phases', '_display_group',
          '_parse_any_date', '_model_alert'):
    exec(srcs[n], g)
f = g['_model_alert']

T = datetime.date.today()
def d(off):
    return (T + datetime.timedelta(days=off)).strftime('%Y-%m-%d')

def dev(expected, progress=30, status=''):
    return {'group': '개발', 'progress': progress, 'status': status,
            'current_expected': expected}

ok = 0
# 완료예정일이 지났으면 지연
assert f(dev(d(-1))) == '지연'
assert f(dev(d(-30))) == '지연'
ok += 1
# 7일 이내면 주의 (오늘 포함)
assert f(dev(d(0))) == '주의'
assert f(dev(d(7))) == '주의'
ok += 1
# 그 뒤는 정상
assert f(dev(d(8))) == '정상'
ok += 1
# 진행률 100% 면 날짜가 지났어도 정상
assert f(dev(d(-10), progress=100)) == '정상'
ok += 1
# 완료예정일이 없으면 정상 (근거가 없다)
assert f(dev('')) == '정상'
assert f(dev('없음')) == '정상'
ok += 1
# 손으로 적은 값이 우선
assert f(dev(d(30), status='지연')) == '지연'
assert f(dev(d(-1), status='주의')) == '주의'
assert f(dev(d(-1), status='정상')) == '지연', "'정상'은 덮어쓰기가 아니라 기본값이다"
ok += 1
# 양산은 날짜로 따지지 않는다 (완료예정일 자체가 없다)
assert f({'group': '양산', 'progress': 10, 'current_expected': d(-5)}) == '정상'
assert f({'group': '양산', 'status': '지연'}) == '지연'
ok += 1
# 전환 주차가 지나 양산으로 보이는 모델도 양산으로 본다
Y, W = T.isocalendar()[0], T.isocalendar()[1]
moved = {'group': '개발', 'progress': 10, 'current_expected': d(-5),
         'phases': [{'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
                    {'from': '%04d-W%02d' % (Y, W - 1), 'group': '양산', 'price': 2}]}
assert f(moved) == '정상', moved
ok += 1
# 인자로 받은 값이 우선 (_enrich_model 이 계산한 진행률/예정일)
assert f({'group': '개발'}, '개발', d(-1), 50) == '지연'
assert f({'group': '개발'}, '개발', d(-1), 100) == '정상'
ok += 1

# 실제 연결부
assert 'out["alert"] = _model_alert(m, _disp, expected, out["progress"])' in SRC
assert 'out.setdefault("alert", _model_alert(m, _disp))' in SRC
ok += 1

DART = (pathlib.Path(__file__).resolve().parents[2] / 'mobile' / 'lib' / 'screens'
        / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert "_alertOf(m) == '지연'" in DART and "m['status'] == '지연'" not in DART, \
    '앱이 아직 손으로 적은 status 로 센다'
assert "m['alert']" in DART, '앱이 서버 alert 를 안 읽는다'
ok += 1

print(f'전부 통과 ({ok}/11)')
