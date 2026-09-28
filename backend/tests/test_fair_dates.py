# 고객요청일 → FAIR 제출 예정일 · 가공 완료 → FAIR 제출 실제일
#   python3 backend/tests/test_fair_dates.py
#
# 하바플레이트 주간보고(RPM 블록)와 개발현황 엑셀의 두 칸이 여기로 온다.
# 앱의 완료예정 · 지연 판정이 이 날짜로 돈다.
#
# 가공 완료가 앞으로의 날짜면 아직 한 게 아니다 — 예정일만 적고 진행중.
# 지난 날짜(오늘 포함)면 완료로 적고 다음 칸을 진행중으로 올린다.
import ast, datetime, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import hrva_import as hi              # noqa: E402

SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {}
want = {'_set_fair_dates', '_canon_step', '_parse_any_date'}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in want:
        exec(ast.get_source_segment(SRC, n), g)
assert want <= set(g), want - set(g)
F = g['_set_fair_dates']
ok = 0

def proc():
    return [{'key': 'machining', 'name': '04 가공 (조립)', 'expected': '', 'actual': '', 'status': ''},
            {'key': 'fair_write', 'name': '09 FAIR 제출', 'expected': '', 'actual': '', 'status': ''},
            {'key': 'fair_approval', 'name': '10 FAIR 승인', 'expected': '', 'actual': '', 'status': ''}]

# ── 예정일만 ──
p = F(proc(), '2026-10-23', '')
assert p[1]['expected'] == '2026-10-23' and p[1]['actual'] == ''
assert p[1]['status'] == '진행중', p[1]
assert p[0]['expected'] == '', '가공 단계를 건드렸다'
ok += 1

# ── 가공 완료가 지난 날짜면 완료 + 다음 칸 진행중 ──
TODAY = datetime.date(2026, 9, 28)
p = F(proc(), '2026-10-07', '2026-09-20', TODAY)
assert p[1]['expected'] == '2026-10-07' and p[1]['actual'] == '2026-09-20'
assert p[1]['status'] == '완료', p[1]
assert p[2]['status'] == '진행중', f'다음 칸이 안 올라간다: {p[2]}'
ok += 1

# ── 당일도 완료 ──
p = F(proc(), '2026-10-07', '2026-09-28', TODAY)
assert p[1]['actual'] == '2026-09-28' and p[1]['status'] == '완료', p[1]
ok += 1

# ── 앞으로의 날짜면 실제일을 안 적는다 ──
p = F(proc(), '2026-10-07', '2026-10-02', TODAY)
assert p[1]['expected'] == '2026-10-07', p[1]
assert p[1]['actual'] == '', f'미래 날짜가 실제일로 들어갔다: {p[1]}'
assert p[1]['status'] == '진행중', p[1]
assert p[2]['status'] in ('', '대기'), f'다음 칸이 먼저 올라갔다: {p[2]}'
ok += 1

# ── 사람이 적어 둔 다음 칸은 건드리지 않는다 ──
b = proc(); b[2].update(status='완료', actual='2026-09-10')
p = F(b, '2026-10-07', '2026-09-20', TODAY)
assert p[2]['status'] == '완료' and p[2]['actual'] == '2026-09-10', p[2]
ok += 1

# ── 빈 값은 기존 입력을 지우지 않는다 ──
base = proc(); base[1].update(expected='2026-09-01', actual='2026-09-05', status='완료')
p = F(base, '', '')
assert p[1]['expected'] == '2026-09-01' and p[1]['actual'] == '2026-09-05'
ok += 1

# ── 단계 이름으로도 찾는다 (key 가 다른 옛 데이터) ──
old = [{'key': 'step_9', 'name': 'FAIR 제출', 'expected': '', 'actual': '', 'status': ''}]
p = F(old, '2026-10-05', '')
assert p[0]['expected'] == '2026-10-05'
ok += 1

# ── 엑셀 칸 읽기: 날짜 · 'M/D (수량)' · TBD · 9999 ──
D = hi.parse_day
assert D(datetime.date(2026, 10, 23)) == '2026-10-23'
assert D('2026-10-02 00:00:00') == '2026-10-02'
assert D('9/28 (6)', 2026) == '2026-09-28', D('9/28 (6)', 2026)
assert D('10/2 (5ea)', 2026) == '2026-10-02'
assert D('TBD') == '' and D('Done') == '' and D(None) == ''
assert D(datetime.date(9999, 12, 31)) == '', '9999-12-31 은 미정 표기다'
assert D('9999-12-31') == ''
ok += 1

# ── 주간보고 파서가 두 칸을 실어 나른다 ──
src = (ROOT / 'hrva_import.py').read_text(encoding='utf-8')
assert '"고객요청일"' in src and '"가공 완료"' in src
assert '"fair_expected"' in src and '"fair_actual"' in src
ok += 1

# ── 두 업로드 경로가 모두 이 규칙을 쓴다 ──
assert '_set_fair_dates(proc, nm.get("fair_expected")' in SRC, '주간보고 업로드가 안 쓴다'
assert '_set_fair_dates(proc, _req, r.get("machining_date")' in SRC, '개발현황 업로드가 안 쓴다'
assert 'if st.get("key") == "machining":\n                    st["expected"] = r["machining_date"]' not in SRC, \
    '옛 규칙(가공 단계 계획일)이 남아 있다'
ok += 1

print(f'test_fair_dates: {ok} passed')
