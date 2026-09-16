# 주차 미달과 그 사유
#   python3 backend/tests/test_week_shortfall.py
#
# "계획 대비 실적이 안 나오면 이슈가 있는거 아닐까? 그래서 거기에 사유를
#  적으면 뜨게끔 하면 되는데 (...) 엔클로저 같은 경우에는 매출을 맞추려고
#  일부러 덜 출하하는것도 있단 말이야 이건 이슈가 아니라 참고 사항인데"
#
# "계획 미달을 적어야 되는 경우는 합계가 계획대비 실적이 안 나왔을 때야
#  품목별로 할 필요는 없어"
#
# 그래서 세 가지를 지킨다.
#   1. 미달은 합계 기준이다. 품목(행)별로 따지지 않는다.
#   2. 끝난 주차만 본다. 아직 안 온 주의 실적 0 은 미달이 아니다.
#   3. 사유에 '참고' 가 달리면 문제로 세지 않는다.
import ast, datetime, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_mark_board_shortfalls', '_closed_week_labels', '_week_reasons_of',
        '_week_end_date'}
g = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') == '_WEEK_REASON_KINDS':
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        exec(ast.get_source_segment(SRC, n), g)
missing = WANT - set(g)
assert not missing, f'못 찾은 함수: {missing}'
mark, closed_of, reasons_of = (g['_mark_board_shortfalls'],
                               g['_closed_week_labels'], g['_week_reasons_of'])
TODAY = datetime.date(2026, 9, 16)      # 수요일. W37 까지 끝났다.
WEEKS = ['W36', 'W37', 'W38', 'W39', 'W40']
ok = 0

# ── 끝난 주 ──
assert closed_of('2026-09', WEEKS, TODAY) == ['W36', 'W37']
assert closed_of('2026-09', WEEKS, datetime.date(2026, 9, 1)) == []
ok += 1


def board():
    return [
        {'label': '직납', 'weeks': {
            'W36': {'plan': 34, 'actual': 21},
            'W37': {'plan': 35, 'actual': 30},
            'W38': {'plan': 40, 'actual': 0},
            'W39': {'plan': 40, 'actual': 0},
            'W40': {'plan': 40, 'actual': 0}}},
        {'label': '자빌', 'weeks': {
            'W36': {'plan': 20, 'actual': 25},
            'W37': {'plan': 20, 'actual': 0},
            'W38': {'plan': 20, 'actual': 0},
            'W39': {'plan': 20, 'actual': 0},
            'W40': {'plan': 20, 'actual': 0}}},
    ]


def total_of(rows):
    return {'label': '합계', 'weeks': {
        w: {'plan': sum(r['weeks'][w]['plan'] for r in rows),
            'actual': sum(r['weeks'][w]['actual'] for r in rows)} for w in WEEKS}}


# ── 미달은 끝난 주의 '합계' 에서만 잡힌다 ──
rows = board()
total = total_of(rows)
cl, sh = mark(rows, total, WEEKS, '2026-09', {}, TODAY)
assert cl == ['W36', 'W37']
assert [e['week'] for e in sh] == ['W36', 'W37'], [e['week'] for e in sh]
assert {e['row'] for e in sh} == {'합계'}, '행 단위로 미달을 잡고 있다'
w36, w37 = sh[0], sh[1]
assert (w36['plan'], w36['actual'], w36['short']) == (54, 46, 8), w36
assert w36['rate'] == 85
assert (w37['plan'], w37['actual'], w37['short']) == (55, 30, 25), w37
assert w37['rate'] == 55
ok += 1

# 아직 안 온 주(W38~W40)는 실적 0 이어도 미달이 아니다
assert not [e for e in sh if e['week'] in ('W38', 'W39', 'W40')], \
    '아직 안 온 주를 미달로 잡았다'
ok += 1

# ── 빨간 칸은 합계 행에만 ──
assert total['weeks']['W36']['short'] == 8
assert total['weeks']['W37']['short'] == 25
assert 'short' not in total['weeks']['W38'], '앞으로 올 주에 미달 표시가 붙었다'
for r in rows:
    for w in WEEKS:
        assert 'short' not in r['weeks'][w], f"행({r['label']} {w})에 미달 표시가 붙었다"
# 다만 '끝난 주인지' 는 행에도 달아 준다 (앱이 안 온 주를 '·' 로 그린다)
assert rows[0]['weeks']['W36']['closed'] is True
assert rows[0]['weeks']['W38']['closed'] is False
ok += 1

# ── 품목이 모자라도 합계가 넘으면 미달이 아니다 (하바플레이트 W37) ──
hava = [
    {'label': '양산', 'weeks': {w: {'plan': 0, 'actual': 0} for w in WEEKS}},
    {'label': '개발', 'weeks': {w: {'plan': 0, 'actual': 0} for w in WEEKS}},
]
hava[0]['weeks']['W37'] = {'plan': 63, 'actual': 44}    # 19대 모자라지만
hava[1]['weeks']['W37'] = {'plan': 34, 'actual': 73}    # 개발이 더 나갔다
_, sh3 = mark(hava, total_of(hava), WEEKS, '2026-09', {}, TODAY)
assert not sh3, f'합계(97 → 117)가 넘었는데 미달로 잡았다: {sh3}'
ok += 1

# ── 사유가 붙는다 ──
R = {'W37': {'kind': '참고', 'text': '매출 맞추려고 일부러 덜 출하', 'at': ''}}
rows2 = board()
_, sh2 = mark(rows2, total_of(rows2), WEEKS, '2026-09', R, TODAY)
by = {e['week']: e for e in sh2}
assert by['W37']['kind'] == '참고'
assert '일부러' in by['W37']['reason']
assert by['W36']['kind'] == '', '사유 없는 주에 사유가 생겼다'
assert by['W36']['reason'] == ''
ok += 1

# 합계가 없으면 잡을 것도 없다 (월 단위 보드)
_, sh4 = mark(board(), None, WEEKS, '2026-09', {}, TODAY)
assert sh4 == [], '합계 없이 미달을 만들어 냈다'
ok += 1

# ── 저장된 사유 읽기 ──
proj = {'week_reasons': {'2026-09': {
    'W37': {'kind': '참고', 'text': '출하 조절'},
    'W36': {'kind': '엉뚱', 'text': '자재 미입고'},
    'W35': '문자열',
}}}
r = reasons_of(proj, '2026-09')
assert r['W37']['kind'] == '참고'
assert r['W36']['kind'] == '문제', '모르는 값은 문제로 본다'
assert 'W35' not in r, '이상한 값을 걸러내지 않는다'
assert reasons_of({}, '2026-09') == {}
assert reasons_of(proj, '2026-08') == {}
ok += 1

# ── 서버가 그걸 내보내고 받는지 ──
for t in ('"closed_weeks"', '"shortfalls"', '"week_reasons"'):
    assert t in SRC, f'보드 응답에 {t} 가 없다'
assert '"row": "합계"' in SRC, '미달을 합계로 적지 않는다'
assert '/admin/projects/{project_key}/week-reason' in SRC, '사유를 적을 곳이 없다'
assert 'col_mode != "week"' in SRC, '월 단위 보드(챔버)에도 주차 미달을 붙였다'
ok += 1

# ── 홈: 주차 미달도 이슈. 단 '참고' 는 빼고 ──
assert 'x.get("kind") != "참고"' in SRC, "'참고' 를 문제로 세고 있다"
assert '계획 미달' in SRC, '주차 미달이 alert 로 안 나간다'
assert '사유 미입력' in SRC, '사유가 없을 때 아무 말도 안 한다'
# 방금 끝난 주만. 마감 주차가 쌓일수록 목록이 주차 미달로만 가득 찬다
assert 'closed_weeks") or [])[-1:]' in SRC, '지난 주차를 전부 올린다'
# 미달은 합계 기준이라 프로젝트당 한 줄이다
assert '"stage": "주차 합계"' in SRC, '주차 미달이 어디서 온 건지 안 적는다'
ok += 1

# ── admin: 합계 행의 미달 칸 + 사유 입력 ──
A = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'wb-short' in A and 'td.wb-short' in A, 'admin 표에 미달 칸 색이 없다'
assert '_wbTotCell' in A, 'admin 합계 행이 미달을 모른다'
assert 'tr.wb-total td.wb-short' in A, '남색 합계 행에서 미달 칸이 안 보인다'
assert '_wbShortPanel' in A and 'saveWeekReason' in A, 'admin 에 사유 입력이 없다'
assert "'/week-reason'" in A, 'admin 이 사유를 저장하지 않는다'
# 아직 안 온 주의 실적 0 은 가운뎃점
assert "c.closed || c.now || (c.actual || 0) !== 0" in A, '안 온 주의 0 을 그대로 그린다'
ok += 1

# ── 앱: 합계 행 칸 표시 + 표 밑 사유 ──
W = (ROOT.parent / 'mobile' / 'lib' / 'widgets' /
     'weekly_board_card.dart').read_text(encoding='utf-8')
assert 'class _BCell' in W and '_weekPair' in W, '앱 표가 미달을 모른다'
assert "▼" in W and "short ?" in W, '미달 칸에 표시가 없다'
assert 'short: values.last[1].short' in W, '앱 합계 행이 미달을 안 받는다'
assert W.count('short: values.last[1].short') == 2, '한쪽 표만 고쳤다'
assert '_shortfallNote' in W and '계획 미달' in W, '표 밑 사유가 없다'
assert '사유 미입력' in W or '아직 적히지 않았습니다' in W, '사유 없을 때 말이 없다'
assert "week == nowWeek || actual != 0" in W, '앞으로 올 주를 0 으로 그린다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
