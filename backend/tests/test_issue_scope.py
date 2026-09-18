# '일정 지연' 만 물으면 홈 카드와 같은 것을 세는지
#   python3 backend/tests/test_issue_scope.py
#
# "일정 지연이 지금 여러개인데 왜 메이저모듈만 나오는거야"
# "CUP 은 도대체 왜 들어간거야"
#
# 두 번 틀렸다. 처음엔 세션에 남은 프로젝트로 좁혀서 한 곳만 말했고,
# 고친 뒤에는 챗이 제 나름의 규칙으로 세는 바람에 '이슈 칸에 글자가
# 있는 모델' 을 전부 지연으로 끌어왔다 (CUP 은 견적 협의 메모였다).
# 홈은 8건 3곳인데 챗은 2건 2곳이었다.
#
# 규칙은 하나여야 한다 — get_home_alerts 가 세는 것을 그대로 쓴다.
import ast
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0

g = {'re': __import__('re')}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') == '_ALERT_WORD':
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.FunctionDef) and n.name in (
            '_alert_brief', '_alert_short_date', '_alert_answer_all'):
        exec(ast.get_source_segment(SRC, n), g)
for name in ('_ALERT_WORD', '_alert_brief', '_alert_short_date', '_alert_answer_all'):
    assert name in g, f'{name} 이 없다'

# ── 홈과 같은 계산을 쓴다 ──
_fn = SRC.split('def _alert_answer_all(')[1].split('\ndef ')[0]
assert 'get_home_alerts(' in _fn, '챗이 따로 센다 — 홈 숫자와 어긋난다'
assert "a.get(\"kind\") in kinds" in _fn, '물어본 종류만 거르지 않는다'
ok += 1

# ── 사유 한 줄 ──
#
# '2대 고객 사급자재 지연 (ETA: 9/20) → W39 (9/23) 출하예정' 을 통째로
# 들고 오면 화면에서 잘려 오히려 무슨 말인지 모르게 된다.
b = g['_alert_brief']
assert b({'issue': '2대 고객 사급자재 지연 (ETA: 9/20) → W39 (9/23) 출하예정'}) \
    == '2대 고객 사급자재 지연'
# 화살표에서 자르면 안 된다 — 화살표 자체가 뜻인 문장이 있다
assert b({'issue': '계획 77 → 실적 66 (미달 11 · 86%) · 사유 미입력'}) \
    == '계획 77 → 실적 66'
# 적어 둔 사유가 없으면 날짜로 말한다
assert b({'issue': '', 'expected': '2026-09-14', 'days': 4}) == '완료예정 9/14 · 4일 지남'
assert b({'issue': '', 'expected': '2026-09-14', 'days': None}) == '완료예정 9/14'
assert b({'issue': '', 'expected': '', 'stage': '가공 (조립)'}) == '가공 (조립)'
ok += 1

# ── 곳마다 묶고, 다섯 줄까지 ──
ALERTS = {'alerts': [
    {'project_key': 'a', 'project': '하바플레이트', 'kind': '지연',
     'model': f'M{i}', 'expected': '2026-09-15', 'days': 3, 'issue': ''}
    for i in range(6)
] + [
    {'project_key': 'b', 'project': '메이저모듈', 'kind': '지연',
     'model': 'EFEM', 'expected': '', 'days': None,
     'issue': '2대 고객 사급자재 지연 (ETA: 9/20)'},
    {'project_key': 'c', 'project': '파워박스', 'kind': '이슈',
     'model': 'W37 계획 미달', 'expected': '', 'days': None,
     'issue': '계획 77 → 실적 66 (미달 11)'},
    {'project_key': 'd', 'project': '챔버', 'kind': '임박',
     'model': 'X', 'expected': '2026-09-25', 'days': -7, 'issue': ''},
]}
g['get_home_alerts'] = lambda limit=500: ALERTS

out = g['_alert_answer_all'](['지연'])
assert out.startswith('일정 지연 7건 · 2곳.'), out
assert '[하바플레이트] 6건' in out and '[메이저모듈] 1건' in out, out
# 물어보지 않은 종류는 안 섞인다 — 여기서 CUP 이 들어왔었다
assert '파워박스' not in out and '챔버' not in out, out
_rows = [ln for ln in out.split('\n') if ln.startswith('· ')]
assert len(_rows) == 5 + 1 + 1, _rows        # 하바 5줄 + '외 1건' + 메이저 1줄
assert '· 외 1건' in out, out
assert '· EFEM: 2대 고객 사급자재 지연' in out, out
ok += 1

# ── 종류별로 따로 답한다 ──
o2 = g['_alert_answer_all'](['이슈'])
assert o2.startswith('특이사항 1건 · 1곳.') and '파워박스' in o2, o2
assert '하바플레이트' not in o2, o2
o3 = g['_alert_answer_all'](['지연', '이슈'])
assert o3.startswith('일정 지연 · 특이사항 8건 · 3곳.'), o3
ok += 1

# ── 없으면 없다고 한다 ──
g['get_home_alerts'] = lambda limit=500: {'alerts': []}
assert '없습니다' in g['_alert_answer_all'](['지연'])
ok += 1

# ── 질문에 나온 종류만 고른다 ──
_br = SRC.split('# ── 이슈·지연 질문은 적힌 그대로 답한다')[1].split('# ── 월 범위 기억')[0]
assert "_kinds.append('지연')" in _br and "_kinds.append('이슈')" in _br, \
    '물어본 종류를 안 가린다'
assert '_proj_in_msg' in _br and 'last_project' not in _br, \
    '아직 세션 프로젝트로 좁힌다'
assert '_alert_answer_all(_kinds)' in _br, '전 프로젝트 경로가 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
