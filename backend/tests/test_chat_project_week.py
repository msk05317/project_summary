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
assert '저번 주 W37: 계획 50대 / 실적 40대 (80%)' in a, a
assert '이번 주 W38: 계획 30대 / 실적 12대 (40%)' in a, a
# 순서가 뒤집히면 지난주를 이번 주로 읽는다
assert a.index('저번 주 W37') < a.index('이번 주 W38'), a
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
# 저번 주(W44)는 자료가 없으니 그 줄은 안 나온다
assert '저번 주' not in b, b
# 11월 주차가 없으면 자료가 있는 달로 떨어진다
assert '9월 합계' in b, b
ok += 1

# ── 저번 주를 두 번 적지 않는다 ──
#
# 이번 주가 비어 있고 마지막 실적이 바로 저번 주면, 같은 주차가
# '저번 주' 와 '마지막 실적' 두 줄로 나온다.
e = ci._answer_project('테스트', proj, models, mass, dev, pp,
                       now_week='W39', now_month='2026-09')
assert '저번 주 W38: 계획 30대 / 실적 12대' in e, e
assert '마지막 실적' not in e, f'저번 주를 두 번 적었다: {e}'
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

# ── PO 누계는 안 적는다 ──
#
# "PO까진 필요 없어" — 물어본 건 지금 어떤지인데, 연초부터 쌓인 숫자가
# 넉 줄을 차지하면서 이번 주와 그 달이 뒤로 밀렸다.
# 진행률 평균도 뺐다 — 양산은 PO 대비 출하, 개발은 공정 단계라
# 서로 다른 것을 한 숫자로 평균 낸 값이었다.
for _a in (a, b, c):
    assert 'PO' not in _a, f'PO 줄이 남았다: {_a}'
    assert '잔량' not in _a, f'잔량 줄이 남았다: {_a}'
    assert '진행률' not in _a, f'진행률 평균이 남았다: {_a}'
ok += 1

# ── 이슈는 무엇인지까지 적는다 ──
#
# "이슈 등록된건 그냥 짧게 요약해줘 / EFEM: 사급자재 지연"
#
# '3종입니다' 만 보면 결국 무엇인지 다시 물어봐야 한다.
iss = [{'id': 'M1', 'name': 'EFEM', 'group': '개발',
        'issues': '2대 고객 사급자재 지연'},
       {'id': 'M2', 'name': 'LPM', 'group': '개발',
        'issues': '도면 변경 대기\n2차 검토 예정'},
       {'id': 'M3', 'name': '긴놈', 'group': '양산',
        'issues': '선적 스페이스 부족으로 이번 주 미출하, 차주 복구 예정이며 고객 통보 완료'}]
f = ci._answer_project('테스트', {'models': iss}, iss, iss, [], pp,
                       now_week='W38', now_month='2026-09')
assert '이슈 3종:' in f, f
assert '· EFEM: 2대 고객 사급자재 지연' in f, f
# 여러 줄이면 첫 줄만
assert '· LPM: 도면 변경 대기' in f and '2차 검토' not in f, f
# 길면 자른다
assert '…' in f, f
ok += 1

# 다섯 종까지만 적고 나머지는 세어 준다
many = [{'id': f'M{i}', 'name': f'모델{i}', 'group': '양산', 'issues': f'사유 {i}'}
        for i in range(1, 8)]
gmany = ci._answer_project('테스트', {'models': many}, many, many, [], pp,
                           now_week='W38', now_month='2026-09')
assert '이슈 7종:' in gmany and '· 모델5: 사유 5' in gmany, gmany
assert '· 모델6' not in gmany and '· 외 2종' in gmany, gmany
ok += 1

# 옛 문구는 안 쓴다
assert '이슈가 등록된 모델은' not in f, f
ok += 1

print(f'전부 통과 · {ok}개 항목')
