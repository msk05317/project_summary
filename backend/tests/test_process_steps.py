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

# ── 현재 위치 한 자리: 앞은 완료, 뒤는 대기 ─────────────────────────
#
#   1) 최종 승인이 진행중·완료면 거기가 현재 위치 → 앞이 전부 완료
#   2) 아니면 '진행중' 으로 골라 둔 첫 자리
#   3) 그것도 없으면 마지막으로 끝난 자리

S = lambda r: [x['status'] for x in r]

# 1) 최종 승인까지 완료 (Mahabali MPD) → 전부 완료
mpd = P(*([('', '완료')] * 6 + [('', '')] * 3 + [('', '완료')] * 3 + [('', '')] * 2 + [('', '완료')]))
assert len(mpd) == 15
assert S(rolled(mpd)) == ['완료'] * 15, S(rolled(mpd))
assert prog(mpd) == 100
ok += 1

# 1) 최종 승인이 '진행중' 이어도 앞은 전부 완료. 자기 자리는 그대로.
lastdoing = P(*([('', '완료')] * 3 + [('', '')] * 11 + [('', '진행중')]))
assert S(rolled(lastdoing)) == ['완료'] * 14 + ['진행중'], S(rolled(lastdoing))
assert prog(lastdoing) == 93, prog(lastdoing)
ok += 1

# 2) BV2(06) 가 진행중이면 그 뒤는 전부 대기로 내려간다 — 저장된 완료까지.
#    Striker Oxide 화면이 이 모양이었다.
bv2 = P(*([('', '완료')] * 5 + [('', '진행중')] + [('', '완료')] * 8 + [('', '대기')]))
r = S(rolled(bv2))
assert r[:5] == ['완료'] * 5, r
assert r[5] == '진행중', r
assert r[6:] == ['대기'] * 9, r
assert prog(bv2) == 33, prog(bv2)
ok += 1

# 뒤로 내릴 때 실적일도 같이 내린다 — '대기' 인데 실적일이 찍혀 있으면 안 된다
late = [{'name': '01', 'actual': '', 'status': '진행중'},
        {'name': '02', 'actual': '2026-01-01', 'status': '완료'},
        {'name': '03', 'actual': '', 'status': ''}]
rl = rolled(late)
assert rl[0]['status'] == '진행중', rl[0]
assert rl[1]['status'] == '대기' and rl[1]['actual'] == '', rl[1]
assert late[1]['actual'] == '2026-01-01', '원본을 건드렸다'
ok += 1

# 3) 진행중이 없으면 마지막으로 끝난 자리가 현재 위치
hx = P(*([('', '완료')] * 5 + [('', '')] * 4 + [('', '완료')] + [('', '')] +
         [('', '완료')] + [('', '')] * 3))
r = S(rolled(hx))
assert r[:12] == ['완료'] * 12, r
assert r[12:] == ['대기'] * 3, r
assert prog(hx) == 80, prog(hx)
ok += 1

# 최종 승인이 '대기' 라도 실적일이 있으면 끝난 자리로 본다 (Striker Oxide)
striker = P(*([('', '완료')] * 5 + [('', '')] * 9 + [('2026-10-14', '대기')]))
r = S(rolled(striker))
assert r[:14] == ['완료'] * 14, r
assert r[14] == '완료', r      # 실적일이 있으니 현재 위치이자 완료
ok += 1

# 하나도 안 끝났으면 아무것도 바꾸지 않는다
none = P(('', ''), ('', ''), ('', ''))
assert S(rolled(none)) == ['', '', '']
assert prog(none) == 0
ok += 1

# 원본은 그대로 (저장된 값은 엑셀이 적은 그대로 둔다)
before = [x['status'] for x in bv2]
rolled(bv2)
assert [x['status'] for x in bv2] == before
ok += 1

print(f'전부 통과 ({ok}/14)')

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
