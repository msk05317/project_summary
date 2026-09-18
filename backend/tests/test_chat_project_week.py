# 프로젝트 이름만 물으면 이번 주와 그 달까지 답하는지
#   python3 backend/tests/test_chat_project_week.py
#
# "프로젝트명만 얘기하면 현황, 이번주 주차 예상, 실적 그리고
#  그 달 토탈 예상 또는 실적이 나와야돼"
#
# 예전에는 '가장 최근 실적이 있는 주차' 만 적었다. 이번 주가 아직 비어
# 있으면 지난주 숫자가 오늘 것처럼 읽혔고, 그 달을 통틀어 얼마나 했는지는
# 아예 없었다.
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import chat_intents as ci                                   # noqa: E402

SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0


def pp(proc):
    done = sum(1 for st in (proc or []) if str((st or {}).get('actual') or '').strip())
    return round(done * 100 / len(proc)) if proc else 0


def mk(weeks_summary, models):
    proj = {'weekly_summary': {'양산': {'po_qty': 100, 'actual_total': 40,
                                       'remaining': 60,
                                       'weeks': weeks_summary}},
            'models': models}
    return proj, models, models, []


# ── 이번 주가 있으면 이번 주를 말한다 ──
proj, models, mass, dev = mk(
    {'W37': {'plan': 50, 'actual': 40}, 'W38': {'plan': 30, 'actual': 12}},
    [{'id': 'a', 'group': '양산',
      'weekly_plan': {'2026-09': {'W36': {'plan': 20, 'actual': 20},
                                  'W37': {'plan': 50, 'actual': 40},
                                  'W38': {'plan': 30, 'actual': 12},
                                  'W39': {'plan': 40, 'actual': 0}}}}])
a = ci._answer_project('테스트', proj, models, mass, dev, pp,
                       now_week='W38', now_month='2026-09')
assert '이번 주 W38: 계획 30대 / 실적 12대 (40%)' in a, a
# 그 달 합계는 그 달 주차를 모두 더한다 (W36 20 + W37 50 + W38 30 + W39 40)
assert '9월 합계: 계획 140대 / 실적 72대' in a, a
ok += 1

# 한 주차를 양쪽에서 더하지 않는다 — 집계 행과 개별 행이 겹치면 두 배가 된다
assert '계획 60대' not in a and '실적 24대' not in a, f'W38 을 두 번 더했다: {a}'
ok += 1

# ── 이번 주가 비어 있으면 그렇다고 말하고 마지막 실적을 붙인다 ──
b = ci._answer_project('테스트', proj, models, mass, dev, pp,
                       now_week='W45', now_month='2026-11')
assert '이번 주 W45: 아직 실적이 없습니다.' in b, b
assert '마지막 실적은 W38' in b, b
# 11월 주차가 없으면 자료가 있는 달로 떨어진다
assert '9월 합계' in b, b
ok += 1

# ── 계획이 0 이면 달성률을 지어내지 않는다 ──
proj2, m2, mass2, dev2 = mk(
    {'W38': {'plan': 0, 'actual': 7}},
    [{'id': 'a', 'group': '양산',
      'weekly_plan': {'2026-09': {'W38': {'plan': 0, 'actual': 7}}}}])
c = ci._answer_project('테스트', proj2, m2, mass2, dev2, pp,
                       now_week='W38', now_month='2026-09')
assert '이번 주 W38: 계획 0대 / 실적 7대' in c and '(0%)' not in c, c
ok += 1

# ── 주차 자료가 아예 없으면 그 줄은 안 나온다 ──
d = ci._answer_project('테스트', {'models': []}, [], [], [], pp,
                       now_week='W38', now_month='2026-09')
assert '이번 주' not in d and '합계' not in d, d
ok += 1

# ── 서버가 이번 주를 알려준다 ──
#
# chat_intents 는 오늘이 몇 주차인지 모른다. 안 넘겨주면 이번 주 줄이
# 통째로 빠진다.
assert "'now_week': 'W%d' % datetime.now().isocalendar()[1]" in SRC, \
    '챗 컨텍스트에 이번 주차가 없다'
assert "'now_month': datetime.now().strftime('%Y-%m')" in SRC, \
    '챗 컨텍스트에 이번 달이 없다'
assert "ctx.get('now_week')" in (ROOT / 'chat_intents.py').read_text(encoding='utf-8'), \
    '챗 답변이 이번 주차를 안 읽는다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
