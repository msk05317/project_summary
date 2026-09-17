# admin 모델 표에서 늦은 개발품이 바로 보이는지
#   python3 backend/tests/test_admin_model_alert.py
#
# "admin v2에서 개발품 중 지연된게 있으면 표시가 떴으면 좋겠어"
#
# 지키는 것 셋.
#   1. 지연 판정은 앱과 같은 규칙(_model_alert)을 쓴다. 화면에서 다시
#      계산하면 앱은 지연 6, admin 은 0 이 되는 날이 온다.
#   2. 계산한 값을 모델 안에 넣지 않는다. 이 화면은 고친 모델을 그대로
#      PUT 으로 돌려보내서, 얹은 값이 models.json 에 눌러앉는다.
#   3. 왜 늦었다고 보는지 같이 말한다. 개수만 보여주면 어느 줄인지
#      찾느라 표를 처음부터 훑게 된다.
import ast
import datetime as dt
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0

# ── 계산한 값은 모델 밖에 둔다 ──
_ep = SRC.split('def admin_get_project_models(')[1].split('\n@app')[0]
assert '"alerts": _admin_model_alerts(models)' in _ep, 'alerts 를 안 내려준다'
assert 'm["alert"]' not in _ep and "m['alert']" not in _ep, \
    '모델 안에 얹으면 저장할 때 models.json 에 눌러앉는다'
ok += 1

# ── 같은 규칙을 쓴다 ──
assert '_model_alert(m, disp, expected, progress)' in SRC, \
    'admin 이 지연을 따로 계산한다'
ok += 1

# ── 사유 문장 ──
g = {'_dt': dt}
for node in ast.parse(SRC).body:
    if isinstance(node, ast.FunctionDef) and node.name in (
            '_admin_model_alerts', '_alert_why'):
        exec(ast.get_source_segment(SRC, node), g)
for fn in ('_admin_model_alerts', '_alert_why'):
    assert fn in g, f'{fn} 이 없다'

# 바깥 함수는 규칙만 흉내 내서 끼워 넣는다 (main.py 를 통째로 못 불러온다)
g['_issue_says_delay'] = lambda t: '지연' in str(t or '')
g['_parse_any_date'] = lambda s: dt.date.fromisoformat(str(s)[:10])
g['_ensure_process'] = lambda m: (m or {}).get('process') or []
g['_process_current'] = lambda proc: (
    (proc[0].get('name', ''), proc[0].get('expected', '')) if proc else ('', ''))
g['_process_progress'] = lambda proc: 0
g['_display_group'] = lambda m: (m or {}).get('group') or '양산'

why = g['_alert_why']
assert why({'status': '지연'}, '개발', '', '지연') == '상태를 지연 으로 지정'
assert why({'issues': '2대 고객 사급자재 지연'}, '양산', '', '지연') == \
    '2대 고객 사급자재 지연'
# 날짜로 따진 것은 며칠 지났는지까지 적는다
_yday = (dt.date.today() - dt.timedelta(days=3)).isoformat()
_txt = why({'current_stage': '가공 (조립)'}, '개발', _yday, '지연')
assert '가공 (조립)' in _txt and '3일 지남' in _txt, _txt
# 양산품은 날짜로 따질 근거가 없다 — 지어내지 않는다
assert why({}, '양산', _yday, '지연') == ''
ok += 1

# ── 모아 주는 쪽 ──
_soon = (dt.date.today() + dt.timedelta(days=2)).isoformat()
g['_model_alert'] = lambda m, d='', e='', p=None: str(
    (m or {}).get('_want') or '정상')
got = g['_admin_model_alerts']([
    {'id': 'a', 'group': '개발', '_want': '지연',
     'process': [{'name': '가공', 'expected': _yday}]},
    {'id': 'b', 'group': '개발', '_want': '주의',
     'process': [{'name': '조립', 'expected': _soon}]},
    {'id': 'c', 'group': '양산', '_want': '정상'},
    {'group': '개발', '_want': '지연'},          # id 없는 줄은 건너뛴다
])
assert sorted(got) == ['a', 'b'], got
assert got['a']['kind'] == '지연' and got['a']['group'] == '개발'
assert '3일 지남' in got['a']['why'], got['a']
assert got['b']['kind'] == '주의' and '2일 남음' in got['b']['why'], got['b']
ok += 1

# ── 화면 ──
A = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'window._mdlAlerts = (d && d.alerts) || {}' in A, 'admin 이 alerts 를 안 받는다'
assert 'mdl-late-badge' in A and 'mdl-soon-badge' in A, '구분 머리줄에 표시가 없다'
assert 'mdl-why-late' in A, '왜 늦었는지 줄에 안 적는다'
assert '사유 미기재' in A, '사유가 비었을 때 말이 없다'
# 저장 payload 에 섞이면 안 된다
assert "data-field=\"alert\"" not in A, '지연 값을 입력칸으로 만들었다'
ok += 1

# ── 앱: 사유가 비었으면 그렇다고 말한다 ──
LIB = ROOT.parent / 'mobile' / 'lib'
O = (LIB / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert '지연 사유 미기재' in O, '앱이 사유 없는 지연을 빈칸으로 둔다'
assert 'r.lines.isEmpty && r.kind == StatusWords.delayed' in O, \
    '사유가 있는 줄에도 미기재라고 적는다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
