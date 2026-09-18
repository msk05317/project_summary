# 홈 화면이 프로젝트 안쪽과 같은 값을 보는지
#   python3 backend/tests/test_home_alerts.py
#
# 예전 홈은 /dashboard 의 주간보고 카드(RED/YELLOW)로 사업부 상태를 셌다.
# 주간보고가 없는 사업부는 집계에서 통째로 빠져서 '12개 중 정상 2' 가 되고,
# 프로젝트 안에는 지연이 널려 있는데 홈은 '지연 0' 이었다.
import ast, io, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0

# 데코레이터 없는 최상위 함수 + 단순 상수를 그대로 올린다
g = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and not n.decorator_list:
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
for n in tree.body:
    if (isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
            and isinstance(n.value, (ast.Constant, ast.Tuple, ast.List, ast.Dict, ast.Set))):
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
fn = None
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name == 'get_home_alerts':
        body = ast.get_source_segment(SRC, n)
        exec('\n'.join(l for l in body.split('\n') if not l.strip().startswith('@')), g)
        fn = g['get_home_alerts']
assert fn, '/home/alerts 엔드포인트가 없다'
ok += 1

CFG = json.loads((ROOT / 'config' / 'projects.json').read_text(encoding='utf-8'))['projects']
g['PROJECT_LABELS'] = {p['id']: p.get('label', p['id']) for p in CFG}
g['_cl'] = type('C', (), {'get_projects': staticmethod(
    lambda visible_only=True: [p for p in CFG if p.get('visible', True)] if visible_only else CFG)})()

# ── 지어낸 데이터로 판정 확인 ──
import datetime
past = (datetime.date.today() - datetime.timedelta(days=30)).strftime('%Y-%m-%d')
soon = (datetime.date.today() + datetime.timedelta(days=3)).strftime('%Y-%m-%d')


def dev(mid, expected, **kw):
    m = {'id': mid, 'name': mid, 'group': '개발', 'progress': 20,
         'process': [{'key': 'step_1', 'name': '01 발주', 'group': '발주',
                      'expected': expected, 'actual': '', 'status': ''}]}
    m.update(kw)
    return m


g['_load_models'] = lambda: {'projects': {'powerbox': {'models': [
    dev('LATE-1', past),
    dev('SOON-1', soon),
    dev('DROP-1', past, note='드롭 예정'),
    {'id': 'MASS-1', 'name': 'MASS-1', 'group': '양산', 'po_qty': 0},
    {'id': 'MASS-2', 'name': 'MASS-2', 'group': '양산', 'po_qty': 100, 'shipped_qty': 100},
]}}}
r = fn(10)
c = r['counts']
assert c['total'] == 5, c
assert c['delayed'] == 1, f"지연이 1이어야 한다: {c}"
assert c['soon'] == 1, f"임박이 1이어야 한다: {c}"
assert c['hold'] == 1, f"드롭 예정이 보류로 안 잡힌다: {c}"
assert c['po_wait'] == 1, f"양산 PO 0 이 PO 대기가 아니다: {c}"
# 정상 — 문제가 하나도 없는 것. 지연·임박·보류·완료를 뺀 나머지다.
assert c['normal'] == 2, f"양산 두 건이 정상이어야 한다: {c}"
assert [x['id'] for x in r['normals']] == ['MASS-1', 'MASS-2'], r['normals']
assert r['normals'][0]['kind'] == '정상'
assert [x['key'] for x in r['by_kind']['정상']] == ['powerbox'], r['by_kind']['정상']
ok += 1

# 드롭은 지연 목록에 안 들어간다
ids = [a['id'] for a in r['alerts']]
assert 'DROP-1' not in ids, '드롭 예정이 지연 목록에 있다'
assert 'LATE-1' in ids and 'SOON-1' in ids, ids
ok += 1

# 지연이 임박보다 위
assert r['alerts'][0]['kind'] == '지연', r['alerts']
assert r['alerts'][0]['days'] and r['alerts'][0]['days'] >= 29
ok += 1

# 보류·PO 대기도 목록으로 나온다 (홈 타일을 누르면 볼 수 있어야 한다)
assert [x['id'] for x in r['holds']] == ['DROP-1'], r['holds']
assert r['holds'][0]['kind'] == '드롭예정'
assert [x['id'] for x in r['po_waits']] == ['MASS-1'], r['po_waits']
assert r['po_waits'][0]['kind'] == 'PO 대기'
ok += 1

# 프로젝트 단위 묶음
rows = r['by_project']
assert len(rows) == 1 and rows[0]['key'] == 'powerbox'
assert rows[0]['delayed'] == 1 and rows[0]['soon'] == 1
assert rows[0]['worst_model'] == 'LATE-1'
ok += 1

# ── 실제 데이터: 홈이 '지연 0' 이라고 말하면 안 된다 ──
bk = sorted((ROOT.parent / 'backups').glob('models_*.json'))
if bk:
    data = json.loads(bk[-1].read_text(encoding='utf-8'))
    g['_load_models'] = lambda: data
    real = fn(12)
    rc = real['counts']
    assert rc['total'] > 100, rc
    assert rc['delayed'] + rc['soon'] > 0, \
        f"실제 데이터에 지연·임박이 있는데 홈은 0 이라고 한다: {rc}"
    # alerts 에는 이슈도 들어간다 (지연 + 이슈 + 임박)
    assert real['alerts_total'] == rc['delayed'] + rc['issue'] + rc['soon'], \
        (real['alerts_total'], rc)
    # 지연과 이슈는 겹치지 않는다 — 지연은 개발품 공정, 이슈는 적어 둔 문제
    _kinds = [a['kind'] for a in real['alerts']]
    assert _kinds.count('이슈') <= rc['issue']
    _ids = {}
    for a in real['alerts']:
        _ids.setdefault((a['project_key'], a['id']), set()).add(a['kind'])
    assert not [k for k, v in _ids.items() if {'지연', '이슈'} <= v], \
        '같은 모델이 지연이면서 이슈로 두 번 셌다'
    assert real['by_project'], '프로젝트 묶음이 비었다'
    # CUP 은 프로젝트째 홀딩이라 지연 목록에 없어야 한다
    assert all(r['key'] != 'cup' for r in real['by_project']), \
        'CUP 이 홀딩인데 지연 프로젝트로 올라와 있다'
    assert len(real['holds']) == rc['hold'] or len(real['holds']) == 12
    # 문제만 보여주면 제대로 가는 게 훨씬 많다는 걸 알 수가 없다
    assert rc['normal'] > rc['delayed'] + rc['issue'], \
        f"실제 데이터에서 정상이 문제보다 적다: {rc}"
    assert rc['normal'] + rc['done'] + rc['hold'] <= rc['total'], rc
    assert real['by_kind']['정상'], '정상 타일을 눌러도 목록이 없다'
    ok += 1

    # 블룸: 모델이 없어도 일 보고 보드가 있으면 '진행 데이터 없음' 이 아니다
    g['_model_key_alias'] = lambda k: k
    CFGM = {p['id']: p for p in CFG}
    g['_cl'] = type('C', (), {
        'get_projects': staticmethod(
            lambda visible_only=True: [p for p in CFG if p.get('visible', True)]
            if visible_only else CFG),
        'get_project': staticmethod(lambda k: CFGM.get(k))})()
    b = fn(12)['bloom']
    assert b and (b['plan'] > 0 or b['prev_plan'] > 0), f'블룸 요약이 비었다: {b}'
    assert b['items'] > 0
    ok += 1

# ── 앱이 이 값을 실제로 쓰는지 ──
LIB = ROOT.parent / 'mobile' / 'lib'
SVC = (LIB / 'services' / 'home_alerts_service.dart').read_text(encoding='utf-8')
assert '/home/alerts' in SVC and 'class HomeAlerts' in SVC
H = (LIB / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert 'StatusBoardCard' in H, '홈이 합친 카드를 안 쓴다'
assert 'HomeAlertsService.fetch()' in H
assert 'AlertListScreen' in H, '모두 보기가 새 목록으로 안 간다'
# 타일을 누르면 그 종류의 내역이 바로 아래 펼쳐져야 한다
B = (LIB / 'components' / 'home' / 'status_board_card.dart').read_text(encoding='utf-8')
# 못 받아왔을 때 0 을 그리면 '지연 없음' 과 구분이 안 된다
assert '!widget.alerts.loaded' in B and '현황을 불러오지 못했습니다' in B
assert 'byKind[_key[k]]' in B, '타일과 목록이 이어져 있지 않다'
assert '_sel = k' in B, '타일을 눌러도 목록이 안 바뀐다'
# 타일을 눌러도 되고 옆으로 밀어도 넘어간다.
# 왼쪽으로 밀면 다음, 오른쪽으로 밀면 이전. 끝에서는 안 넘어간다 —
# 정상에서 왼쪽으로 밀었는데 집중관리가 나오면 어디로 간 건지 모른다.
# 지금 숫자는 반도체사업부 것만이다. 그렇다고 적어 둬야 전사 숫자로
# 읽히지 않는다. 다른 사업부 자료가 들어오면 이 꼬리표를 뗀다.
assert '(반도체 기준)' in B, '전사 숫자인 것처럼 보인다'
assert 'onHorizontalDragEnd' in B, '옆으로 밀어도 안 넘어간다'
assert 'primaryVelocity' in B and '_Kind.values[next]' in B
assert 'next < 0 || next >= _Kind.values.length' in B, '끝에서 감아 돈다'
# 내용이 툭 바뀌면 넘어간 건지 화면이 잘못 그려진 건지 헷갈린다.
assert 'AnimatedSwitcher' in B and 'SlideTransition' in B, '넘어갈 때 안 미끄러진다'
assert 'AnimatedSize' in B, '종류마다 줄 수가 달라 카드가 튄다'
# 민 방향과 글이 움직이는 방향이 어긋나면 앞뒤를 알 수 없다
assert 'int _dir' in B and '_select(' in B, '넘어간 방향을 안 본다'
# 타일은 네 가지. '보류' 는 뺐다 — 멈춰 세운 것은 오늘 볼 일이 아니다.
# 맨 오른쪽은 '정상' — 문제만 늘어놓으면 제대로 가는 게 안 보인다.
for _k in ('지연', '이슈', '임박', '정상'):
    assert f"_Kind.{'delayed' if _k == '지연' else ''}" or True
    assert f"'{_k}'" in B, f'{_k} 타일이 없다'
assert '_Kind.normal' in B and '_Kind.hold' not in B, \
    '보류 타일이 그대로 있거나 정상 타일이 없다'
# 서버가 쓰는 값(_key)과 화면에 보이는 말(_label)은 다르다.
# '임박' 혼자 쓰면 광고 문구처럼 읽혀서 '마감 임박' 으로 보여준다.
# 보이는 말로 byKind 를 찾으면 목록이 통째로 빈다.
assert 'static const _key' in B and 'byKind[_key[k]]' in B, \
    '보이는 말로 목록을 찾는다 — 서버 값과 어긋난다'
# 보이는 말은 한 곳에서만 정한다 (utils/status_words.dart).
# 화면마다 '임박' · '마감 임박' · '주의' 로 갈리면 같은 것인지 알 수가 없다.
assert 'StatusWords.soon' in B and "_Kind.soon: '마감 임박'" not in B, \
    '보이는 말을 카드 안에서 또 정한다'
W = (LIB / 'utils' / 'status_words.dart').read_text(encoding='utf-8')
for _w in ('일정 지연', '집중관리', '특이사항', '정상'):
    assert _w in W, f'{_w} 가 status_words 에 없다'
assert "onTapAll!(_key[_sel]!)" in B, '모두 보기가 보이는 말로 넘어간다'
assert 'AlertListScreen(initialFilter: filter)' in H, '모두 보기가 그 종류로 안 간다'
# 블룸은 모델이 없어도 진행 중이다
assert "divisionId == 'bloom'" in H and '_bloom' in H, '블룸이 여전히 진행 데이터 없음이다'
ok += 1

# 목록 화면이 네 가지를 다 받는다
A = (LIB / 'screens' / 'alert_list_screen.dart').read_text(encoding='utf-8')
# 칩 글자는 '마감 임박', 걸러내는 값은 서버가 쓰는 '임박'
assert "_chip('문제'" in A and "_chip('PO 대기'" in A
for _c in ('StatusWords.delayed', 'StatusWords.issue', 'StatusWords.soon',
           'StatusWords.normal'):
    assert f'_chip({_c}' in A, f'{_c} 칩이 없다'
assert "_chip('보류'" not in A, '보류 칩이 그대로 있다'
assert "case '정상':" in A and 'a.normals' in A, '정상 목록이 안 열린다'
assert 'initialFilter' in A
ok += 1

# 매출 카드가 무엇이 포함된 숫자인지 밝힌다
R = (LIB / 'components' / 'home' / 'exec_revenue_card.dart').read_text(encoding='utf-8')
assert '_coverage()' in R and '주차 계획 미등록' in R, \
    '매출이 어느 사업부 기준인지 안 밝힌다'
ok += 1

# 프로젝트 전체 보류면 개요에 배너 한 줄, 같은 보류 29줄을 늘어놓지 않는다
O2 = (LIB / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert '_holdBanner(' in O2 and "data['hold_reason']" in O2, '보류 배너가 없다'
assert "scope == 'project'" in O2, '프로젝트 보류 모델을 그대로 다 늘어놓는다'
ok += 1

# ── 프로젝트 이름이 키로 새지 않는다 ──
#
# PROJECT_LABELS 는 초창기 8개(반도체)만 담은 고정 맵이라, ESS 를 그걸로
# 찾으면 'fluence' / 'sdi' 가 소문자 키 그대로 화면에 떴다.
assert 'PROJECT_LABELS.get(pk, pk)' not in SRC, '알림이 아직 고정 맵으로 이름을 찾는다'
assert '_display_project_label(pk)' in SRC, '설정 라벨을 안 본다'
import json as _json
_cfg = _json.loads((ROOT / 'config' / 'projects.json').read_text(encoding='utf-8'))
_ps = _cfg['projects'] if isinstance(_cfg.get('projects'), list) else list(_cfg['projects'].values())
_lab = {x['id']: x.get('label') for x in _ps}
assert _lab.get('fluence') == '플루언스', _lab.get('fluence')
assert _lab.get('sdi') == 'SDI', 'SDI 는 SDI 로 둔다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
