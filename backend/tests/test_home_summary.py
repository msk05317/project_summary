# 앱 홈의 사업부별 매출 · 진행현황 — 손으로 넣는 건 타겟뿐
#   python3 backend/tests/test_home_summary.py
#
# 실적은 사업부마다 오는 자료가 다르다 (반도체 주간보고 · 블룸 보고자료 ·
# 나머지 모델 판가 × 출하). 어디서 온 숫자인지 같이 들고 나가야
# 틀렸을 때 어디를 고치는지 안다.
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)

WANT = {'_div_model_money', '_div_counts', '_as_money', '_model_alert', '_model_hold',
        '_display_group', '_norm_phases', '_phase_ord', '_parse_any_date',
        '_process_step_done', '_issue_says_delay'}
g = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in (
            '_HOLD_WORDS', '_HOLD_NEGATIONS', 'SOON_DAYS', '_DELAY_NEG'):
        exec(ast.get_source_segment(SRC, n), g)
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
for n in ('_phase_ord', '_as_money', '_norm_phases', '_display_group', '_parse_any_date',
          '_process_step_done', '_model_hold', '_issue_says_delay', '_model_alert',
          '_div_model_money', '_div_counts'):
    exec(srcs[n], g)
ok = 0

# ── 판가 × 출하 ──
money = g['_div_model_money']([
    {'price': 3400, 'shipped_qty': 10},
    {'price': '1,200.5', 'shipped_qty': 2},
    {'price': 900},                     # 출하 0 이면 0
    {'price': None, 'shipped_qty': 5},
    'x',                                # 모델이 아닌 것
])
assert money == 36401.0, money
ok += 1

# ── 정상 · 지연 · 특이사항 · 집중관리 ──
def m(**kw):
    base = {'group': '개발', 'progress': 50, 'status': '정상'}
    base.update(kw)
    return base

c = g['_div_counts']([
    m(),                                        # 정상
    m(status='지연'),                            # 지연
    m(status='주의'),                            # 집중관리
    m(status='보류'),                            # 집중관리 (보류 포함)
    m(issues='금형 수정 대기'),                    # 특이사항
    m(status='드롭예정'),                         # 집중관리
])
assert c['total'] == 6, c
assert c['delayed'] == 1, c
assert c['watch'] == 3, c
assert c['issue'] == 1, c
assert c['normal'] == 1, c
assert c['normal'] + c['delayed'] + c['issue'] + c['watch'] == c['total'], \
    '합이 전체와 안 맞는다 — 앱 화면에서 숫자가 새어 나간다'
ok += 1

# 모델이 없으면 전부 0
z = g['_div_counts']([])
assert z == {'total': 0, 'normal': 0, 'delayed': 0, 'issue': 0, 'watch': 0}, z
ok += 1

# ── 엔드포인트 · 출처 표기 ──
for need in ('@app.get("/admin/home/summary")',
             '@app.post("/admin/home/division-target")',
             'DIV_TARGET_FILE = DATA_DIR / "division_targets.json"'):
    assert need in SRC, f'{need} 가 없다'
for src_label in ('"주간보고"', '"보고자료 금액"', '"보고자료 계획"',
                  '"모델 판가 × 출하"', '"직접 입력"'):
    assert src_label in SRC, f'{src_label} 출처 표기가 없다'
ok += 1

# 블룸은 보고자료에 계획이 있으니 타겟을 손으로 안 받는다
assert '"target_editable": t_src != "보고자료 계획"' in SRC, \
    '블룸 타겟을 손으로 고치게 두면 보고자료와 어긋난다'
ok += 1

# 타겟 0 은 '미등록' (지우기)
assert 'mon.pop(division_id, None)' in SRC
ok += 1

print(f'test_home_summary: {ok} passed')
