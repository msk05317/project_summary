# 파워박스 공정 13·14번 — CDR 틀 · PRR 틀을 'CDR/PRR 작성 · 승인' 한 틀로.
#   python3 backend/tests/test_cdr_prr.py
#
# CDR 틀 26종 … 12 FAIR 승인 · 13 CDR · 14 최종 승인
# PRR 틀 22종 … 12 FAIR 승인 · 13 PRR 작성 · 14 PRR 승인 · 15 최종 승인
# Min: 안 B (작성 / 승인 두 칸).
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = (ROOT / 'backend' / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
g = {}
want = {'_canon_step', '_unify_cdr_prr', '_process_rolled', '_process_step_done',
        '_process_step_active', '_process_progress'}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in want:
        exec(ast.get_source_segment(SRC, n), g)
assert want <= set(g), want - set(g)
U = g['_unify_cdr_prr']
ok = 0

HEAD = ['FA PO', '자재 발주', '자재 입고', 'CB', 'BV1', 'BV2', 'LA 입고',
        'LAIR 작성', 'LAIR 승인', 'Source Inspection', 'FAIR 작성', 'FAIR 승인']
WANT = HEAD + ['CDR/PRR 작성', 'CDR/PRR 승인', '최종 승인']

def proc(tail, dates=None):
    names = HEAD + tail
    dates = dates or {}
    return [{'key': f'step_{i+1}', 'name': f'{i+1:02d} {n}', 'group': '승인',
             'expected': dates.get(n, ('', ''))[0], 'actual': dates.get(n, ('', ''))[1],
             'status': ''} for i, n in enumerate(names)]

def canon(p):
    return [g['_canon_step'](x['name']) for x in p]

# ── CDR 틀: CDR 날짜가 '승인' 칸으로, '작성' 은 비운다 ──
c = U(proc(['CDR', '최종 승인'], {'CDR': ('2026-10-31', ''), '최종 승인': ('2026-11-07', '')}))
assert canon(c) == WANT, canon(c)
assert c[12]['expected'] == '' and c[12]['actual'] == '', '작성 칸에 CDR 날짜가 들어갔다'
assert c[13]['expected'] == '2026-10-31', 'CDR 날짜가 승인 칸으로 안 갔다'
assert c[14]['expected'] == '2026-11-07', '최종 승인 날짜가 밀렸다'
assert [x['key'] for x in c] == [f'step_{i}' for i in range(1, 16)]
assert c[12]['name'] == '13 CDR/PRR 작성' and c[14]['name'] == '15 최종 승인'
ok += 1

# ── PRR 틀: 이름만 바뀐다 ──
p = U(proc(['PRR 작성', 'PRR 승인', '최종 승인'],
           {'PRR 작성': ('2026-10-01', '2026-10-02'), 'PRR 승인': ('2026-10-10', '')}))
assert canon(p) == WANT, canon(p)
assert p[12]['actual'] == '2026-10-02' and p[13]['expected'] == '2026-10-10'
ok += 1

# ── 두 번 돌려도 그대로 (기동할 때마다 부른다) ──
assert U(c) is None and U(p) is None, '이미 맞춘 틀을 또 바꾼다'
ok += 1

# ── 기본 13단계 틀(번호 없음 — CONGA SPDB · VDP Aux)은 안 건드린다 ──
default = [{'key': k, 'name': n, 'expected': '', 'actual': '', 'status': ''}
           for k, n in [('fa_po', 'FA PO'), ('machining', '가공 (조립)'),
                        ('lap_test', 'LAP TEST'), ('cdr', 'CDR'),
                        ('final_approval', '최종 승인 완료')]]
assert U(default) is None, '다른 틀까지 바꿨다'
assert U([]) is None
ok += 1

# ── CDR 이 끝났으면 작성 칸도 완료로 그려진다 ──
done = U(proc(['CDR', '최종 승인'], {'CDR': ('', '2026-09-01')}))
st = {g['_canon_step'](x['name']): x['status'] for x in g['_process_rolled'](done)}
assert st['CDR/PRR 작성'] == '완료' and st['CDR/PRR 승인'] == '완료', st
ok += 1

# ── 연결부 ──
assert '_CDR_PRR_PROJECTS = {"powerbox"}' in SRC, '메이저모듈까지 건드린다'
assert '\n_cleanup_cdr_prr()' in SRC, '기동 때 안 부른다'
imp = SRC[SRC.index('async def admin_import_unified'):]
imp = imp[:imp.index('\n@app.')]
assert "_unify_cdr_prr(steps)" in imp, '공정 엑셀을 올리면 옛 틀로 돌아간다'
lead = SRC[SRC.index('PROCESS_LEAD_DEFAULT = {'):]
lead = lead[:lead.index('\n}')]
assert '"CDR/PRR 작성"' in lead and '"CDR/PRR 승인"' in lead
assert '"CDR (PRR)"' not in lead and '"PRR 작성"' not in lead, '옛 이름이 기본값에 남았다'
D = (ROOT / 'mobile' / 'lib' / 'screens' / 'model_list_screen.dart').read_text(encoding='utf-8')
assert "'CDR/PRR 작성', 'CDR/PRR 승인'" in D, '앱 칩(서버 없을 때)이 옛 틀이다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
