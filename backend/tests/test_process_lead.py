# 단계별 표준 소요(주) — admin 입력 → 앱 칩 '(2주)'.
#   python3 backend/tests/test_process_lead.py
#
# 실적일이 단계당 2~5건뿐이라 자동으로는 평균을 못 낸다.
# 계획일은 대부분 +7 / +14 로 찍혀 있어 리드타임이 아니다
# (계획일 기준 자재입고→최종승인 중앙값 5주 — 석 달의 절반도 안 된다).
# 그래서 사람이 적고, 앱은 그걸 읽어서 붙인다.
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = (ROOT / 'backend' / 'main.py').read_text(encoding='utf-8')
H = (ROOT / 'backend' / 'admin_v2.html').read_text(encoding='utf-8')
D = (ROOT / 'mobile' / 'lib' / 'screens' / 'model_list_screen.dart').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0

# ── 1) 단계 이름 정규화: '04 CB' 와 'CB' 는 같은 단계다 ──
fns = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
       if isinstance(n, ast.FunctionDef)}
assert '_canon_step' in fns, '_canon_step 이 없다'
g = {}
exec(fns['_canon_step'], g)
c = g['_canon_step']
assert c('04 CB') == 'CB' and c('CB') == 'CB' and c('10 Source Inspection') == 'Source Inspection'
assert c('') == '' and c(None) == ''
ok += 1

# ── 2) 기본값 ──
for x in tree.body:
    if isinstance(x, ast.Assign) and getattr(x.targets[0], 'id', '') == 'PROCESS_LEAD_DEFAULT':
        exec(ast.get_source_segment(SRC, x), g)
lead = g['PROCESS_LEAD_DEFAULT']
assert 'powerbox' in lead, '파워박스 기본값이 없다'
pb = lead['powerbox']
# 자재 입고 다음부터 최종 승인까지 = 석 달 언저리여야 한다 (Min: 평균 3개월)
after = sum(v for k, v in pb.items()
            if k not in ('FA PO', '자재 발주', '자재 입고'))
assert 10 <= after <= 18, f'자재 입고 이후 합이 석 달과 너무 다르다: {after}주'
# 시작점(FA PO) 말고는 0주가 없어야 한다 — 0 이면 '공짜 단계' 처럼 보인다
zero = [k for k, v in pb.items() if v == 0 and k != 'FA PO']
assert not zero, f'0주로 둔 단계가 있다: {zero}'
ok += 1

# ── 3) 조회 엔드포인트 ──
assert '@app.get("/projects/{project_key}/process-steps")' in SRC, '조회 길이 없다'
fn = SRC[SRC.index('def get_process_steps'):]
fn = fn[:fn.index('\n@app.')]
assert '_project_steps(proj)' in fn, '프로젝트가 실제 쓰는 단계를 안 본다'
assert 'process_lead' in fn and 'PROCESS_LEAD_DEFAULT' in fn, '저장값·기본값을 안 읽는다'
assert '"weeks": v' in fn and 'v = None' in fn, "안 정한 단계를 None 으로 안 둔다"
assert 'total_weeks' in fn
ok += 1

# ── 4) 저장 엔드포인트: 숫자·범위를 막는다 ──
assert '@app.put("/admin/projects/{project_key}/process-lead")' in SRC
sv = SRC[SRC.index('async def admin_set_process_lead'):]
sv = sv[:sv.index('\n@app.')]
assert 'get_admin_session' in SRC[SRC.index('async def admin_set_process_lead') - 260:
                                  SRC.index('async def admin_set_process_lead') + 260], \
    '관리자 확인이 없다'
assert 'n < 0 or n > 104' in sv, '주 수 범위를 안 막는다'
assert 'proj.pop("process_lead", None)' in sv, '전부 비우면 지워야 한다'
ok += 1

# ── 5) admin 화면 ──
assert 'mdl-lead-btn' in H, '입력 버튼이 없다'
assert 'window._openLeadEditor' in H, '입력창이 window 에 안 걸려 있다 (블록이 다르다)'
assert "'/admin/projects/' + encodeURIComponent(pk) + '/process-lead'" in H, '저장 주소가 없다'
assert "'/projects/' + encodeURIComponent(pk) + '/process-steps'" in H, '조회 주소가 없다'
ok += 1

# ── 6) 앱 ──
assert 'process-steps' in D, '앱이 단계를 안 받아온다'
assert 'class _Step' in D and 'final int? weeks' in D, '안 정한 단계를 구분 못 한다'
assert "list[i].weeks}주)" in D, "칩에 (00주) 를 안 붙인다"
assert 'list[i].weeks != null' in D, '안 정한 단계에도 괄호를 붙인다'
assert '_devProcessStepsFor(projectKey).map' in D, '서버가 안 되면 칩 줄이 사라진다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
