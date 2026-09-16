# 홈 '이번 달' 한 장 — 끝난 주 / 남은 주 / 막힌 것
#   python3 backend/tests/test_month_split.py
#
# 월 달성률만 크게 띄우면 9월 16일에도 35% 라 '큰일났다' 로 읽힌다.
# 아직 3주가 남았고 그 3주 계획이 분모에 들어 있어서다. 끝난 2주만
# 놓고 보면 96% — 계획대로 가고 있다는 뜻이다. 둘을 갈라 둔다.
import ast, datetime, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_split_weeks_closed_open', '_week_end_date'}
g = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        exec(ast.get_source_segment(SRC, n), g)
missing = WANT - set(g)
assert not missing, f'못 찾은 함수: {missing}'
split, wend = g['_split_weeks_closed_open'], g['_week_end_date']
ok = 0

# ── 주 마감일은 그 ISO 주의 일요일 ──
assert wend('2026-09', 'W37') == datetime.date(2026, 9, 13)
assert wend('2026-09', '38') == datetime.date(2026, 9, 20)
assert wend('2026-09', '엉뚱') is None
ok += 1

# ── 9월 16일(수) 기준: W37 까지 끝났고 W38~W40 이 남았다 ──
WR = {'combined': {'weeks': {
    'W36': {'plan': 240, 'actual': 238, 'revenue': 2000000, 'plan_revenue': 2100000},
    'W37': {'plan': 244, 'actual': 240, 'revenue': 2001173, 'plan_revenue': 2056226},
    'W38': {'plan': 300, 'actual': 0, 'revenue': 0, 'plan_revenue': 2500000},
    'W39': {'plan': 300, 'actual': 0, 'revenue': 0, 'plan_revenue': 2400000},
    'W40': {'plan': 288, 'actual': 0, 'revenue': 0, 'plan_revenue': 2449893},
}}}
today = datetime.date(2026, 9, 16)
cl, op = split(WR, '2026-09', today)
assert cl['closed_weeks'] == 2, cl
assert op['open_weeks'] == 3, op
assert cl['closed_qty_plan'] == 484 and cl['closed_qty_actual'] == 478
assert cl['closed_revenue'] == 4001173
assert cl['closed_plan_revenue'] == 4156226
assert op['open_qty_plan'] == 888
assert op['open_plan_revenue'] == 7349893
ok += 1

# 끝난 주 + 남은 주 = 월 전체. 어느 한쪽이 새면 카드 두 칸이 어긋난다.
month_plan = sum(c['plan_revenue'] for c in WR['combined']['weeks'].values())
assert cl['closed_plan_revenue'] + op['open_plan_revenue'] == month_plan
ok += 1

# ── 끝난 주 달성률 96% vs 월 달성률 35% ──
assert round(cl['closed_revenue'] * 100 / cl['closed_plan_revenue']) == 96
assert round(cl['closed_revenue'] * 100 / month_plan) == 35
ok += 1

# ── 주 일요일 당일은 아직 안 끝난 것으로 본다 (그날 실적이 늦게 들어온다) ──
cl2, op2 = split(WR, '2026-09', datetime.date(2026, 9, 20))
assert cl2['closed_weeks'] == 2 and op2['open_weeks'] == 3, '일요일에 미리 마감했다'
cl3, _ = split(WR, '2026-09', datetime.date(2026, 9, 21))
assert cl3['closed_weeks'] == 3, '월요일이 되어도 안 마감된다'
ok += 1

# ── 월초: 끝난 주가 하나도 없다 ──
cl4, op4 = split(WR, '2026-09', datetime.date(2026, 9, 1))
assert cl4['closed_weeks'] == 0 and cl4['closed_plan_revenue'] == 0
assert op4['open_weeks'] == 5
ok += 1

# ── 주차 데이터가 아예 없으면 0 (화면은 이때 구간 칸을 안 그린다) ──
cl5, op5 = split({}, '2026-09', today)
assert cl5['closed_weeks'] == 0 and op5['open_weeks'] == 0
ok += 1

# ── 서버가 그 값을 실제로 내보내는지 ──
for k in ('closed_weeks', 'open_weeks', 'closed_qty_plan', 'closed_qty_actual',
          'closed_revenue', 'closed_plan_revenue', 'open_qty_plan',
          'open_plan_revenue'):
    assert f'"{k}"' in SRC, f'/overview totals 에 {k} 가 없다'
ok += 1

# ── 이슈도 alert 로 나가는지 (지연과 겹치지 않는다) ──
assert '"kind": "이슈"' in SRC, '이슈가 alert 로 안 나간다'
assert '"issue": 0' in SRC and 'counts["issue"]' in SRC, 'counts 에 이슈가 없다'
ok += 1

# ── 앱: 매출 카드가 '남은 N주 계획' 을 쓴다 ──
#
# '계획 대비 부족 $750만' 이라고 적었는데 그 $751만 중 $735만은 아직
# 안 온 3주치 계획이었다. 못 채운 게 아니라 아직 안 온 것이다.
M = ROOT.parent / 'mobile' / 'lib'
CARD = (M / 'components' / 'home' / 'exec_revenue_card.dart').read_text(encoding='utf-8')
assert "'남은 ${summary.openWeeks}주 계획'" in CARD, '아직 부족이라고 적는다'
assert 'openPlanRevenue' in CARD and 'hasWeekSplit' in CARD
# 문구는 들어간 것만. 무엇이 빠졌는지까지 적으면 카드가 변명처럼 읽힌다
assert "는 주차 계획 미등록'" not in CARD, '미등록 문구가 남아 있다'
ok += 1

SVC = (M / 'services' / 'home_alerts_service.dart').read_text(encoding='utf-8')
assert 'int get blocked => delayed + issue;' in SVC, '문제 = 지연 + 이슈 가 아니다'
assert 'blockers' in SVC, '지연·이슈만 뽑는 게 없다'
ok += 1

HOME = (M / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert 'StatusBoardCard' in HOME, '홈이 합친 카드를 안 쓴다'
assert '_RiskListCard' not in HOME.replace(
    "// 홈 상단이 모델 기준(_RiskListCard)으로 바뀌면서 안 쓰게 됐다.", ''), \
    "'지금 봐야 할 것' 이 아직 따로 있다"
assert "const Text('전체 진행률'" not in HOME, '전체 진행률 게이지가 남아 있다'
ok += 1

LIST = (M / 'screens' / 'alert_list_screen.dart').read_text(encoding='utf-8')
assert "case '이슈':" in LIST and "case '문제':" in LIST, '목록에 이슈 칩이 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
