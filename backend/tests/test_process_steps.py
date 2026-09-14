# 일정표 칸 읽는 규칙 + 진행률 계산 검증
#   python3 backend/tests/test_process_steps.py
import ast, pathlib, sys

SRC = pathlib.Path(__file__).resolve().parents[1] / 'main.py'
sys.path.insert(0, str(SRC.parent))
src = SRC.read_text(encoding='utf-8')
want = {'_step_date', '_step_actual', '_process_step_done', '_process_progress',
        '_process_rolled', '_process_step_active'}
grab = {}
for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.FunctionDef) and n.name in want:
        n.decorator_list = []
        grab[n.name] = ast.unparse(n)
assert want <= set(grab), set(grab)
g = {'_STEP_NA': {'na', 'n/a', '-', '--', 'tbd', '미정', '해당없음', '없음', 'x'},
     '_STEP_PICKED': ('완료', '진행중', '대기', '미승인', '미제출')}
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

# 마지막으로 끝난 단계 앞은 채우고, 그 뒤는 그대로 둔다.
# 공정은 순서대로 가니 3번이 끝났으면 2번도 지나온 것이다.
half = P(('', '완료'), ('', ''), ('', '완료'), ('', ''), ('', ''))
assert [s['status'] for s in rolled(half)] == ['완료', '완료', '완료', '', ''], rolled(half)
assert prog(half) == 60, prog(half)
ok += 1

# VXT AHM HX 모양 — 12번이 마지막 완료. 13·14·15 는 대기로 남는다.
hx = P(*([('', '완료')] * 5 + [('', '')] * 4 + [('', '완료')] + [('', '')] +
         [('', '완료')] + [('', '')] * 3))
assert len(hx) == 15
r = [s['status'] for s in rolled(hx)]
assert r[:12] == ['완료'] * 12, r
assert r[12:] == ['', '', ''], r
assert prog(hx) == 80, prog(hx)
ok += 1

# 하나도 안 끝났으면 아무것도 채우지 않는다
none = P(('', ''), ('', ''), ('', ''))
assert [s['status'] for s in rolled(none)] == ['', '', '']
ok += 1

# ── 기준선은 '끝났거나 하고 있는' 마지막 자리 ────────────────────────
# 단계 이름·순서에 기대지 않는다. LAIR·FAIR 은 순서가 바뀌고
# BV 는 BV1 에서 끝나기도 한다.

# 05 BV1 까지 완료, 06 BV2 는 없는 모델, 08 LAIR 작성이 진행중
# → 07 까지 완료로 채우고, 08 은 진행중 그대로 둔다
bv = P(*([('', '완료')] * 5 + [('', '')] * 2 + [('', '진행중')] + [('', '')] * 7))
r = [s['status'] for s in rolled(bv)]
assert r[:7] == ['완료'] * 7, r
assert r[7] == '진행중', r
assert r[8:] == [''] * 7, r
# 진행중은 끝난 게 아니다 — 7/15
assert prog(bv) == 47, prog(bv)
ok += 1

# 14 PRR 승인이 진행중 → 앞 13개 전부 완료, 15 는 대기
prr = P(*([('', '')] * 13 + [('', '진행중')] + [('', '')]))
r = [s['status'] for s in rolled(prr)]
assert r[:13] == ['완료'] * 13, r
assert r[13] == '진행중' and r[14] == '', r
assert prog(prr) == 87, prog(prr)
ok += 1

# 앞쪽에 '진행중' 이 있어도 사람이 고른 값이라 덮지 않는다.
# 빈 자리(02)만 채운다.
mix = P(('', '진행중'), ('', ''), ('', '완료'), ('', ''))
assert [s['status'] for s in rolled(mix)] == ['진행중', '완료', '완료', ''], rolled(mix)
ok += 1

# 진행중만 있고 완료가 하나도 없어도 그 앞은 채운다
only = P(('', ''), ('', '진행중'), ('', ''))
assert [s['status'] for s in rolled(only)] == ['완료', '진행중', ''], rolled(only)
ok += 1

# ── 사람이 고른 상태가 추측보다 우선한다 ─────────────────────────────

# Striker Oxide 모양: 15 최종 승인이 '대기' 인데 실적일이 있다.
# 실적일이 있으면 끝난 자리로 본다 — 그래야 그 앞이 다 채워진다.
# ('최종승인이 대기로 떠도 그 전은 다 완료' 규칙)
striker = P(*([('', '완료')] * 5 + [('', '')] * 9 + [('2026-10-14', '대기')]))
r = [s['status'] for s in rolled(striker)]
assert r[:14] == ['완료'] * 14, r
assert r[14] == '대기', r
ok += 1

# BV2 를 진행중으로 바꿔 놓으면, 뒤 단계가 끝나도 완료로 덮지 않는다
bv2 = P(*([('', '완료')] * 5 + [('', '진행중')] + [('', '')] * 7 + [('', '완료')] + [('', '')]))
assert len(bv2) == 15
r = [s['status'] for s in rolled(bv2)]
assert r[5] == '진행중', r          # 고른 값이 그대로
assert r[:5] == ['완료'] * 5, r
assert r[6:14] == ['완료'] * 8, r   # 빈 자리만 채운다
assert r[14] == '', r
ok += 1

# 사람이 '대기' 로 골라 둔 자리도 덮지 않는다
keep = P(('', '완료'), ('', '대기'), ('', ''), ('', '완료'))
assert [s['status'] for s in rolled(keep)] == ['완료', '대기', '완료', '완료'], rolled(keep)
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

print(f'전부 통과 ({ok}/22)')

# ── 비고: 사람이 적은 것만 남긴다 ────────────────────────────────────
import re as _re
_auto_src = {}
for _n in ast.walk(ast.parse(src)):
    if isinstance(_n, ast.FunctionDef) and _n.name == '_looks_auto_note':
        _n.decorator_list = []
        _auto_src['f'] = ast.unparse(_n)
assert _auto_src, '_looks_auto_note 를 못 찾음'
_g2 = {'re': _re,
       '_AUTO_NOTE_RE': _re.compile(r'^\s*\d{2}\s+[^:]+:[^·]+(·\s*\d{2}\s+[^:]+:[^·]+)*\s*$')}
exec(_auto_src['f'], _g2)
auto = _g2['_looks_auto_note']
ok2 = 0

# 예전 업로드가 적어 두던 모양 → 지운다
for t in ('10 FAIR Approval: Not yet · 11 LAP Test: Not yet',
          '03 Material Receiving: In stock · 10 FAIR Approval: Not yet · 11 LAP Test: Not yet',
          '04 Machining (Assembly): Not yet · 06 LAIR Preparation: Not yet',
          '06 LAIR Preparation: Not yet'):
    assert auto(t), t
ok2 += 1

# 사람이 적은 메모는 건드리지 않는다
for t in ('자재 지연, 8월 말 입고 예정', '고객사 확인 중', '', '   ',
          '2026년 9월 출하 예정', 'PRR 일정 미정 — 담당자 확인 필요',
          '10월 3일 회의 결과 반영'):
    assert not auto(t), t
ok2 += 1

print(f'비고 판별 통과 ({ok2}/2)')
