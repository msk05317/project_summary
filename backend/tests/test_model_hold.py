# 드롭·보류는 지연이 아니다 / 양산 PO 0 은 'PO 대기'
#   python3 backend/tests/test_model_hold.py
#
# 파워박스 VCTR-XPRSMS 는 비고에 '드롭 예정' 이라고 적혀 있었는데
# 앱이 비고를 안 읽어서, 자재 입고 예정일(8/28)만 지나 보이고
# 그냥 일정 지연으로 잡혔다. 적어둔 말이 화면까지 이어져야 한다.
import ast, datetime, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_model_hold', '_model_po_wait', '_model_alert', '_display_group',
        '_norm_phases', '_phase_ord', '_as_money', '_process_step_done',
        '_parse_any_date', '_project_hold', '_project_hold_reason',
        '_hold_from_note', '_stamp_project_hold', '_issue_says_delay'}
g = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in (
            'MODEL_STATUSES', '_HOLD_WORDS', '_HOLD_NEGATIONS', '_DELAY_NEG'):
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        exec(ast.get_source_segment(SRC, n), g)
missing = WANT - set(g)
assert not missing, f'못 찾은 함수: {missing}'
hold, po_wait, alert = g['_model_hold'], g['_model_po_wait'], g['_model_alert']
phold, preason = g['_project_hold'], g['_project_hold_reason']
ok = 0

# ── 비고에 적은 말을 알아본다 ──
assert hold({'note': '드롭 예정'}) == '드롭예정'
assert hold({'note': '드롭예정'}) == '드롭예정'
assert hold({'issues': '고객 요청으로 보류'}) == '보류'
assert hold({'note': 'drop 검토중'}) == '드롭예정'
assert hold({'note': '자재 입고 지연'}) == ''
assert hold({}) == ''
ok += 1

# 부정문은 걸러낸다 — '드롭 안 함' 을 드롭으로 읽으면 안 된다
assert hold({'note': '드롭 안 함, 계속 진행'}) == ''
assert hold({'note': '보류 해제됨'}) == ''
ok += 1

# 상태로 직접 고른 경우
assert hold({'status': '드롭예정'}) == '드롭예정'
assert hold({'status': '보 류'}) == '보류'
assert hold({'status': '정상'}) == ''
ok += 1

# 상태 목록에 새 값이 들어 있다 (admin 저장이 거부하면 안 된다)
assert '드롭예정' in g['MODEL_STATUSES'] and '보류' in g['MODEL_STATUSES']
assert '정상' in g['MODEL_STATUSES'] and '지연' in g['MODEL_STATUSES']
ok += 1

# ── 드롭이면 예정일이 지나도 지연이 아니다 ──
past = (datetime.date.today() - datetime.timedelta(days=20)).strftime('%Y-%m-%d')
dev = {'group': '개발', 'progress': 13, 'status': '정상'}
assert alert(dict(dev), '개발', past, 13) == '지연', '예정일이 지났는데 지연이 아니다'
ok += 1
dropped = dict(dev, note='드롭 예정')
assert alert(dropped, '개발', past, 13) == '정상', \
    '드롭 예정인데 지연으로 센다 (VCTR-XPRSMS 가 이 경우였다)'
ok += 1
# 손으로 '지연' 을 골랐으면 그건 그대로 둔다
assert alert(dict(dev, status='지연', note='드롭 예정'), '개발', past, 13) == '지연'
ok += 1

# ── PO 대기: 양산인데 PO 가 0 ──
assert po_wait({'group': '양산', 'po_qty': 0}) is True
assert po_wait({'group': '양산', 'po_qty': 120}) is False
assert po_wait({'group': '개발', 'po_qty': 0}) is False, '개발은 PO 대기가 아니다'
assert po_wait({'group': '양산'}) is True
ok += 1

# ── 실제 데이터로 확인 ──
import json
bk = sorted((ROOT.parent / 'backups').glob('models_*.json'))
if bk:
    data = json.loads(bk[-1].read_text(encoding='utf-8'))
    ms = [m for m in (data['projects'].get('powerbox') or {}).get('models', [])
          if m.get('id') == '853-177575-015']
    if ms:
        m = ms[0]
        assert hold(m) == '드롭예정', f"VCTR-XPRSMS 가 드롭예정으로 안 잡힌다: {m.get('note')!r}"
        ok += 1

# ── 프로젝트 전체 보류 ──
# CUP 은 현황에 '컵 이슈 해결될 때까지 ... 홀딩' 이라고 적혀 있는데도
# 모델 15종이 전부 지연으로 세어졌다. 멈춰 세운 일정은 늦은 게 아니다.
CUPNOTE = '양산 1종\n개발 28종\n\n*컵 이슈 해결될 때까지 개발 컵 또한 LAIR 작성 홀딩'
assert phold({'status_note': CUPNOTE}) == '보류'
assert 'LAIR 작성 홀딩' in preason({'status_note': CUPNOTE})
assert phold({'status_note': '양산 3종\n개발 5종'}) == ''
assert phold({'status_note': '홀딩 해제, 재개'}) == ''
assert phold({'hold': '드롭예정'}) == '드롭예정'
assert phold({}) == ''
ok += 1

# 실제 데이터: CUP 만 걸리고 다른 프로젝트는 안 걸린다
if bk:
    ps = data['projects']
    assert phold(ps['cup']) == '보류', 'CUP 홀딩이 안 잡힌다'
    for k in ('powerbox', 'frame', 'hrva_plate', 'chamber', 'enclosure'):
        assert phold(ps.get(k) or {}) == '', f'{k} 가 잘못 보류로 잡힌다'
    ok += 1

# ── 문구가 사라져도 보류는 유지된다 ──
# 주간보고를 다시 올리거나 현황을 고치다 문구가 날아가면, 보류가 조용히
# 풀리면서 멈춰 세운 일정이 다시 지연으로 세어졌다.
stamp = g['_stamp_project_hold']
proj = {'status_note': CUPNOTE}
assert stamp(proj, proj['status_note']) is True
assert proj['hold'] == '보류' and proj['hold_source'] == 'status_note'
assert 'LAIR 작성 홀딩' in proj['hold_reason']
ok += 1

proj['status_note'] = '양산 1종\n개발 28종'          # 문구가 사라졌다
assert phold(proj) == '보류', '문구가 사라지자 보류가 풀렸다'
assert 'LAIR' in preason(proj), '근거 문장도 같이 날아갔다'
stamp(proj, proj['status_note'])                      # 다시 저장해도
assert phold(proj) == '보류'
ok += 1

# 푸는 길은 둘: 현황에 '홀딩 해제' 라고 적거나, admin 에서 '진행' 으로
proj['status_note'] = '홀딩 해제, 재개'
assert stamp(proj, proj['status_note']) is True
assert phold(proj) == '' and 'hold' not in proj
ok += 1

proj2 = {'status_note': CUPNOTE}
stamp(proj2, proj2['status_note'])
proj2['hold'] = '진행'
assert phold(proj2) == '', 'admin 에서 진행으로 바꿔도 안 풀린다'
ok += 1

# admin 화면에 그 선택지가 있는지
ADMIN = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'mdl-proj-hold' in ADMIN and '보류(홀딩)' in ADMIN, 'admin 에 프로젝트 상태가 없다'
assert "hold: (document.getElementById('mdl-proj-hold')" in ADMIN, '저장할 때 안 보낸다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
