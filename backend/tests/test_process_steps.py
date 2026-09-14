# 일정표 칸 읽는 규칙 + 진행률 계산 검증
#   python3 backend/tests/test_process_steps.py
import ast, pathlib, sys

SRC = pathlib.Path(__file__).resolve().parents[1] / 'main.py'
sys.path.insert(0, str(SRC.parent))
src = SRC.read_text(encoding='utf-8')
want = {'_step_date', '_step_actual', '_process_step_done', '_process_progress',
        '_process_rolled'}
grab = {}
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.FunctionDef) and n.name in want:
        n.decorator_list = []
        grab[n.name] = ast.unparse(n)
assert want <= set(grab), set(grab)
g = {'_STEP_NA': {'na', 'n/a', '-', '--', 'tbd', '미정', '해당없음', '없음', 'x'}}
exec('\n\n'.join(grab.values()), g)
date, actual, prog = g['_step_date'], g['_step_actual'], g['_process_progress']
rolled = g['_process_rolled']
ok = 0

# 날짜는 날짜 칸으로
assert date('2026-06-12') == '2026-06-12'
assert date('2026.6.12') == '2026-06-12'
ok += 1

# 날짜가 아닌 글자는 날짜 칸에 넣지 않는다 ('완료' 가 날짜로 들어가면 안 된다)
assert date('완료') == '' and date('NA') == '' and date('') == ''
ok += 1

# 실적 = 날짜 → 그 날짜에 완료
assert actual('2026-06-12') == ('2026-06-12', '완료')
ok += 1

# 실적 = '완료' 글자 → 완료지만 날짜는 비운다.
# (날짜 입력칸에 글자를 넣으면 화면에 안 뜨고, 저장 한 번에 지워진다)
assert actual('완료') == ('', '완료')
assert actual('Done') == ('', '완료')
ok += 1

# NA 는 '이 모델엔 없는 단계' 다. 완료로 세면 진행률이 부풀려진다.
for t in ('NA', 'N/A', 'na', '-', '미정', '해당없음'):
    assert actual(t) == ('', ''), t
ok += 1

# 빈칸은 빈칸
assert actual('') == ('', '') and actual('   ') == ('', '')
ok += 1

# ── 진행률: 최종 승인이 완료라고 100% 로 치지 않는다 ─────────────────
def P(*st):
    return [{'name': f'{i+1:02d}', 'actual': a, 'status': s}
            for i, (a, s) in enumerate(st)]

# Mahabali MPD 모양 — 10개 완료, 5개 빈칸, 마지막(최종 승인)은 완료.
# 최종 승인까지 떨어졌으면 중간 빈칸은 '안 한 일'이 아니라 '안 적은 일'이다.
mpd = P(*([('', '완료')] * 6 + [('', '')] * 3 + [('', '완료')] * 3 + [('', '')] * 2 + [('', '완료')]))
assert len(mpd) == 15
assert prog(mpd) == 100, prog(mpd)
assert all(s['status'] == '완료' for s in rolled(mpd)), rolled(mpd)
ok += 1

# 최종 승인이 안 끝났으면 채우지 않는다 — 끝난 것만 센다
half = P(('', '완료'), ('', ''), ('', '완료'), ('', ''), ('', ''))
assert prog(half) == 40, prog(half)
assert [s['status'] for s in rolled(half)] == ['완료', '', '완료', '', ''], rolled(half)
ok += 1

# 채워도 원본은 그대로다 (저장된 값은 엑셀이 적은 그대로 둔다)
before = [s['status'] for s in half]
rolled(half)
assert [s['status'] for s in half] == before
ok += 1

# 전부 완료면 100
assert prog(P(*[('', '완료')] * 5)) == 100
ok += 1

# 하나도 없으면 0
assert prog(P(*[('', '')] * 5)) == 0
assert prog([]) == 0 and rolled([]) == []
ok += 1

# 실적일만 있고 상태가 비어도 완료로 센다
assert prog(P(('2026-01-01', ''), ('', ''))) == 50
ok += 1

# 실적일이 있는 단계는 날짜를 잃지 않는다
r = rolled(P(('2026-01-01', ''), ('', ''), ('', '완료')))
assert r[0]['actual'] == '2026-01-01' and r[1]['status'] == '완료'
ok += 1

print(f'전부 통과 ({ok}/13)')
