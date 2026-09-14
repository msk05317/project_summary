# 보드 '비고' 칸 검증 — 우선순위 + 묶음 행 요약
#   python3 backend/tests/test_board_note.py
#
# 직접 입력 > boards.json > 모델의 '그 외 특이사항 · 메모'(m['note'])
# 메모가 3종 이상 붙은 묶음 행(Dep 챔버 등)은 상태별 종수로 접는다.
# '문제 · 리스크'(m['issues'])는 끌어오지 않는다.
import ast, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_board_row_note', '_note_groups', '_note_rollup_text', '_note_total_ok'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'

KEEP = None
for n in tree.body:
    if isinstance(n, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == '_NOTE_ROLLUP_MIN' for t in n.targets):
        KEEP = ast.literal_eval(n.value)
assert KEEP == 3, f'_NOTE_ROLLUP_MIN 이 예상과 다르다: {KEEP}'

g = {'_NOTE_ROLLUP_MIN': KEEP, 'print': lambda *a, **k: None}
for name in ('_note_groups', '_note_rollup_text', '_note_total_ok', '_board_row_note'):
    exec(srcs[name], g)
note, groups, rollup, total_ok = (g['_board_row_note'], g['_note_groups'],
                                  g['_note_rollup_text'], g['_note_total_ok'])

M002 = {'id': '715-044854-002', 'note': '제조일정 변경으로 중단 → 10월 재개', 'issues': '자재 지연'}
M205 = {'id': '715-181531-205', 'note': '305챔버로 변경 예정'}
BLANK = {'id': 'X', 'note': '', 'issues': '이건 비고가 아니다'}

# 실제 Dep 챔버 구성 (16종)
DEP = ([{'id': f'k{i}', 'note': '카이저 원소재 11월말 입고 예정'} for i in range(10)] +
       [{'id': f'a{i}', 'note': '1EA 조립 완료 (고객측 확인 중)'} for i in range(3)] +
       [{'id': 'b1', 'note': '1EA 고객사와 에폭시 2차 도포 완료\n3EA 절삭 완료'},
        {'id': 'b2', 'note': '1EA 황삭 완료'},
        {'id': 'b3', 'note': 'FAIR 승인 완료 → 33주차 출하 예정'}])

ok = 0

# ── 우선순위 ───────────────────────────────────────────────
assert note([M002], None, '손으로 적은 값') == '손으로 적은 값'
ok += 1
assert note([M002], 'boards.json 값', '') == 'boards.json 값'
ok += 1
assert note([M002], None, None) == '제조일정 변경으로 중단 → 10월 재개'
ok += 1
assert note([BLANK], None, None) == '', 'issues 를 비고로 끌어왔다'
ok += 1
assert note([], None, None) == '' and note(None, None, None) == ''
ok += 1
assert note([M002, M205], None, None) == (
    '715-044854-002: 제조일정 변경으로 중단 → 10월 재개\n'
    '715-181531-205: 305챔버로 변경 예정'), '2종 행은 그대로 나열해야 한다'
ok += 1

# ── 묶기 ──────────────────────────────────────────────────
gr = groups(DEP)
assert gr[0] == ('카이저 원소재 11월말 입고 예정', 10), f'가장 많은 묶음이 틀렸다: {gr[0]}'
assert gr[1] == ('1EA 조립 완료 (고객측 확인 중)', 3), gr[1]
assert sum(c for _, c in gr) == 16, f'종수 합이 16이 아니다: {gr}'
assert any('에폭시 2차 도포 완료 3EA 절삭 완료' in t for t, _ in gr), '줄바꿈이 안 펴졌다'
ok += 1

# ── 요약 없이(AI 미사용) ─────────────────────────────────
plain = note(DEP, None, None)
assert plain == rollup(gr), '요약기가 없으면 기본 묶음형이어야 한다'
assert plain.startswith('카이저 원소재 11월말 입고 예정 10종 · '), plain
ok += 1

# ── 요약기 사용 ──────────────────────────────────────────
called = []
def fake(gs):
    called.append(gs)
    return '원소재 입고 대기 10종 · 조립 완료 3종 · 가공 진행 2종 · 출하 예정 1종'
out = note(DEP, None, None, summarize=fake)
assert out == '원소재 입고 대기 10종 · 조립 완료 3종 · 가공 진행 2종 · 출하 예정 1종', out
assert called and sum(c for _, c in called[0]) == 16
ok += 1

# 요약기가 터지거나 빈 값이면 기본형으로 떨어진다
assert note(DEP, None, None, summarize=lambda gs: (_ for _ in ()).throw(RuntimeError('x'))) == rollup(gr)
assert note(DEP, None, None, summarize=lambda gs: '') == rollup(gr)
ok += 1

# 직접 입력은 묶음 행에서도 여전히 최우선 (요약기를 부르지 않는다)
called.clear()
assert note(DEP, None, '내가 적은 비고', summarize=fake) == '내가 적은 비고'
assert not called, '직접 입력인데 AI 를 불렀다'
ok += 1

# 3종 미만은 요약기를 부르지 않는다
called.clear()
note([M002, M205], None, None, summarize=fake)
assert not called, '2종인데 AI 를 불렀다'
ok += 1

# ── 종수 안전망 ──────────────────────────────────────────
assert total_ok('원소재 입고 대기 10종 · 조립 완료 3종 · 가공 진행 2종 · 출하 예정 1종', 16)
assert not total_ok('원소재 입고 대기 12종 · 조립 완료 3종', 16), '지어낸 종수를 못 잡았다'
assert not total_ok('원소재 입고 대기 중', 16), '종수가 없으면 통과시키면 안 된다'
ok += 1

# ── 실제 조립부가 이 경로를 쓰는지 ──────────────────────
assert '_board_row_note(models, row.get("note"), man.get("note"),' in SRC and \
       'summarize=_ai_board_note)' in SRC, '보드 조립부가 아직 옛날 방식이다'
ok += 1

print(f'전부 통과 ({ok}/14)')
