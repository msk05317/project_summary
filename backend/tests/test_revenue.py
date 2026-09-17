# 매출 — 실적은 주간보고, 예상은 사람이 넣는다
#   python3 backend/tests/test_revenue.py
#
# "Weekly 작성된건 작년에 작성한 파일이라 불명확 할 수 있기에 월 예상
#  매출은 내가 따로 뭐 알려주던가 아니면 파일을 업로드를 할게
#  Weekly는 그냥 그 실적 채우면 되는거야"
#
# 9월만 봐도 주간보고 실행계획은 $1,964만, 실제 예상은 $2,422만이었다.
#
# 지키는 것 다섯.
#   1. 주간보고에서 '실적' 말고는 읽지 않는다. 읽어서 어딘가 남겨 두면
#      언젠가 화면에 새어 나온다.
#   2. 묶음 합계는 [합 계] 블록 그대로 쓴다. 우리가 더해서 만들지 않는다.
#   3. 세부를 더한 값이 합계와 다르면 조용히 넘기지 않고 말해 준다.
#   4. 같은 파일을 두 번 올려도 그 해를 갈아 끼울 뿐 더해지지 않고,
#      예상은 건드리지 않는다.
#   5. 예상이 없는 달은 달성률을 지어내지 않는다.
import io, pathlib, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import revenue as R                                    # noqa: E402
import openpyxl                                        # noqa: E402

SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0

KINDS = ('사업계획', '실행계획', 'Open PO', '실적')


def book(lines, totals, weeks=None, months=None, year=2026):
    """주간보고 한 장. lines=[(사업부, 고객, 이름, {kind: {W: 값}})]"""
    weeks = weeks or ['W36', 'W37', 'W38']
    months = months or {w: '9월' for w in weeks}
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = '1. 계획 대비 실적 (수정본) Actual FCST'
    ws.cell(row=2, column=2, value='%d년 매출 계획대비 실적 분석' % year)
    for n, w in enumerate(weeks):
        ws.cell(row=4, column=8 + n, value=months[w])
        ws.cell(row=5, column=8 + n, value=w)
    r = 6

    def block(c2, c3, c4, vals):
        nonlocal r
        if c2:
            ws.cell(row=r, column=3, value=c2)
        if c3:
            ws.cell(row=r, column=4, value=c3)
        if c4:
            ws.cell(row=r, column=5, value=c4)
        for i, kind in enumerate(KINDS):
            ws.cell(row=r + i, column=6, value=kind)
            for n, w in enumerate(weeks):
                v = (vals.get(kind) or {}).get(w)
                if v is not None:
                    ws.cell(row=r + i, column=8 + n, value=v)
        r += len(KINDS)

    for c2, c3, c4, vals in lines:
        block(c2, c3, c4, vals)
    ws.cell(row=r, column=3, value='[합 계]')
    r += 1
    for c2, c3, vals in totals:
        block(c2, c3, None, vals)
    buf = io.BytesIO(); wb.save(buf); return buf.getvalue()


def W(**kw):
    return {k: dict(v) for k, v in kw.items()}


# ── 세부 + [합 계] 를 읽는다 ──
raw = book(
    lines=[
        ('반도체 (SEMI)', None, '코일 인클로저 (Coil Enclosure)',
         {'사업계획': {'W36': 500}, '실행계획': {'W36': 300, 'W37': 400},
          '실적': {'W36': 240, 'W37': 380}}),
        (None, None, '메이져모듈 (Major Module)',
         {'실행계획': {'W37': 120}, '실적': {'W37': 128}}),
        ('네트워크 사업부', '데이터센터 (Data Center)', None,
         {'실행계획': {'W36': 90}, '실적': {'W36': 31}}),
        ('우주항공', '스페이스X', '스타쉽 - 텍슨 (Starship - Texon)',
         {'실행계획': {'W38': 52}, '실적': {}}),
        # 엑셀은 사업부 칸을 한 번만 적는다. 텍슨 사이트 줄이 '우주항공'
        # 아래에 붙어 있지만 실제로는 내부거래다.
        (None, 'Texon 구미 전체 - Gumi Cable', None,
         {'실행계획': {'W36': 200}, '실적': {'W36': 180}}),
    ],
    totals=[
        ('매출합계 (Revenue)', '반도체 (SEMI)',
         {'사업계획': {'W36': 500}, '실행계획': {'W36': 300, 'W37': 520},
          '실적': {'W36': 240, 'W37': 508}}),
        (None, '데이터 센터 (Data Center)',
         {'실행계획': {'W36': 90}, '실적': {'W36': 31}}),
        (None, '우주항공 (Space X) (Excluding Starship HQ)',
         {'실행계획': {'W38': 52}, '실적': {}}),
        (None, 'Sub-total',
         {'사업계획': {'W36': 500}, '실행계획': {'W36': 390, 'W37': 520, 'W38': 52},
          '실적': {'W36': 271, 'W37': 508}}),
        ('내부거래 (Internal)', '구미/화성/미국 (Gumi/Hwaseong/USA/YONGIN)',
         {'실행계획': {'W36': 200}, '실적': {'W36': 180}}),
        ('총합 (내부거래 포함) Grand Total (Internal included)', None,
         {'사업계획': {'W36': 500}, '실행계획': {'W36': 590, 'W37': 520, 'W38': 52},
          '실적': {'W36': 451, 'W37': 508}}),
    ])
p = R.parse_weekly(raw, 2026)
assert p['year'] == 2026, p['year']
assert p['weeks'] == ['W36', 'W37', 'W38'], p['weeks']
assert p['months'] == {'2026-09': ['W36', 'W37', 'W38']}, p['months']
assert sorted(p['totals']) == ['dc', 'grand', 'internal', 'semi', 'space', 'subtotal'], \
    sorted(p['totals'])
assert len(p['lines']) == 5, len(p['lines'])
ok += 1

# 묶음 배정 — 텍슨 줄은 '우주항공' 아래 있어도 내부거래다
g = {ln['label']: ln['group'] for ln in p['lines']}
assert g['코일 인클로저 (Coil Enclosure)'] == 'semi'
assert g['메이져모듈 (Major Module)'] == 'semi', '사업부 칸이 빈 줄이 안 이어졌다'
assert g['데이터센터 (Data Center)'] == 'dc'
assert g['스타쉽 - 텍슨 (Starship - Texon)'] == 'space'
assert g['Texon 구미 전체 - Gumi Cable'] == 'internal', \
    '텍슨 사이트 줄이 우주항공으로 갔다'
ok += 1

# ── 달 보기 ──
st = R.blank()
R.apply_weekly(st, p, 'WEEKLY.xlsx')
v = R.month_view(st, '2026-09')
box = {b['key']: b for b in v['groups']}
assert box['semi']['actual'] == 748, box['semi']
assert box['dc']['actual'] == 31 and box['space']['actual'] == 0
assert v['internal']['actual'] == 180
assert v['subtotal']['actual'] == 779, v['subtotal']
assert v['grand']['actual'] == 959, v['grand']
assert v['actual'] == 959, v['actual']
ok += 1

# 주간보고의 계획 열은 읽지도 않는다
for _b in v['groups'] + [v['internal'], v['subtotal'], v['grand']]:
    assert 'plan' not in _b and 'budget' not in _b, _b
for _ln in (st['years']['2026']['lines'] + list(st['years']['2026']['totals'].values())):
    assert set(_ln) <= {'label', 'actual', 'div', 'cust', 'group'}, _ln
ok += 1

# 예상을 안 넣은 달은 달성률을 지어내지 않는다
assert v['estimate'] == 0 and v['rate'] is None and v['left'] == 0, v
assert v['has_estimate'] is False
ok += 1

# ── 예상 매출 ──
R.set_estimate(st, '2026-09', 2000, [{'item': 'Cable', 'amount': 1200},
                                     {'item': 'PBX', 'amount': 800}], 'est.xlsx')
v = R.month_view(st, '2026-09')
assert v['estimate'] == 2000 and v['rate'] == 48, (v['estimate'], v['rate'])
assert v['left'] == 2000 - 959
assert v['has_estimate'] is True
assert [x['item'] for x in v['estimate_items']] == ['Cable', 'PBX']
assert v['estimate_source'] == 'est.xlsx'
# 다른 달로 새지 않는다
assert R.month_view(st, '2026-08')['estimate'] == 0
# 0 이면 지운다
R.set_estimate(st, '2026-09', 0)
assert R.month_view(st, '2026-09')['has_estimate'] is False
R.set_estimate(st, '2026-09', 2000, [], '직접 입력')
try:
    R.set_estimate(st, '2026-9', 100)
    raise AssertionError('달 형식을 안 본다')
except ValueError:
    pass
ok += 1

# 주간보고를 다시 올려도 예상은 그대로다 — 출처가 다르다
R.apply_weekly(st, p, 'WEEKLY.xlsx')
assert R.month_view(st, '2026-09')['estimate'] == 2000, '주간보고가 예상을 지웠다'
ok += 1

# ── Estimate 파일 읽기 ──
_ew = openpyxl.Workbook()
_es = _ew.active
_es.title = 'Sum'
_es.append(['Commodity', 'Estimate Revenue in Sep'])
for _n, _a in (('Plastic', 889433), ('Major Modules', 3136000), ('PBX', 3218743)):
    _es.append([_n, _a])
_es.append([None, 889433 + 3136000 + 3218743])          # 시트가 적어 둔 합계
_buf = io.BytesIO(); _ew.save(_buf)
_p = R.parse_estimate(_buf.getvalue())
assert _p['total'] == 7244176, _p['total']
assert len(_p['items']) == 3, _p['items']
assert _p['gap'] == 0, _p
# 시트 합계가 틀려 있으면 말해 준다 — 우리가 더한 값을 쓴다
_es.cell(row=5, column=2, value=999)
_buf2 = io.BytesIO(); _ew.save(_buf2)
_p2 = R.parse_estimate(_buf2.getvalue())
assert _p2['total'] == 7244176 and _p2['stated'] == 999 and _p2['gap'] != 0, _p2
ok += 1

# 세부가 묶음 안에 들어온다
names = [it['item'] for it in box['semi']['items']]
assert '코일 인클로저 (Coil Enclosure)' in names and '메이져모듈 (Major Module)' in names
assert [it['item'] for it in v['internal']['items']] == ['Texon 구미 전체 - Gumi Cable']
ok += 1

# ── 세부 합이 [합 계] 와 다르면 말해 준다 ──
#
# 합계는 파일이 말한 값을 그대로 쓴다. 우리가 세부를 더해서 만들면
# 파일과 어긋나도 아무도 모른다.
assert box['semi']['items_actual'] == 748, box['semi']['items_actual']
raw2 = book(
    lines=[('반도체 (SEMI)', None, '코일 인클로저 (Coil Enclosure)',
            {'실적': {'W36': 100}})],
    totals=[('매출합계 (Revenue)', '반도체 (SEMI)', {'실적': {'W36': 999}}),
            ('총합 (내부거래 포함) Grand Total', None, {'실적': {'W36': 999}})])
st2 = R.blank()
R.apply_weekly(st2, R.parse_weekly(raw2, 2026), 'x.xlsx')
v2 = R.month_view(st2, '2026-09')
b2 = v2['groups'][0]
assert b2['actual'] == 999, '합계를 세부로 덮어썼다'
assert b2['items_actual'] == 100
assert b2['actual'] != b2['items_actual'], '어긋남을 못 잡는다'
ok += 1

# ── 같은 파일을 두 번 올려도 더해지지 않는다 ──
R.apply_weekly(st, p, 'WEEKLY.xlsx')
assert R.month_view(st, '2026-09')['actual'] == 959, '두 번 올렸더니 늘었다'
ok += 1

# ── 예전 파일(version 2)에 남아 있던 계획 열은 읽을 때 털어낸다 ──
_old = {'version': 2, 'years': {'2026': {
    'weeks': ['W36'], 'months': {'2026-09': ['W36']},
    'totals': {'grand': {'label': 'g', 'actual': {'W36': 10},
                         'plan': {'W36': 99}, 'budget': {'W36': 88}}},
    'lines': [{'label': 'x', 'group': 'semi', 'actual': {'W36': 10},
               'plan': {'W36': 99}, 'budget': {'W36': 88}}]}}}
with tempfile.TemporaryDirectory() as td:
    f = pathlib.Path(td) / 'old.json'
    f.write_text(__import__('json').dumps(_old), encoding='utf-8')
    got = R.load(f)
    assert got['version'] == 3
    assert 'plan' not in got['years']['2026']['totals']['grand']
    assert 'budget' not in got['years']['2026']['lines'][0]
ok += 1

# ── 누적은 보고 있는 달까지 ──
raw3 = book(
    lines=[('반도체 (SEMI)', None, '코일 인클로저 (Coil Enclosure)',
            {'실적': {'W32': 100, 'W36': 50}})],
    totals=[('매출합계 (Revenue)', '반도체 (SEMI)', {'실적': {'W32': 100, 'W36': 50}}),
            ('총합 (내부거래 포함) Grand Total', None, {'실적': {'W32': 100, 'W36': 50}})],
    weeks=['W32', 'W36'], months={'W32': '8월', 'W36': '9월'})
st3 = R.blank()
R.apply_weekly(st3, R.parse_weekly(raw3, 2026), 'y.xlsx')
assert R.month_view(st3, '2026-08')['actual'] == 100
assert R.month_view(st3, '2026-08')['ytd'] == 100, '뒤에 오는 달이 누적에 들어갔다'
assert R.month_view(st3, '2026-09')['ytd'] == 150
assert R.month_view(st3, '2026-09')['as_of'] == 'W36'
ok += 1

# 자료가 없는 달은 has_data 가 꺼진다 (앱이 예전 계산으로 떨어진다)
assert R.month_view(st3, '2026-07')['has_data'] is False
assert R.month_view(R.blank(), '2026-09')['has_data'] is False
ok += 1

# ── 시트를 못 읽으면 예외 ──
wb = openpyxl.Workbook(); wb.active['A1'] = '아무것도 없음'
buf = io.BytesIO(); wb.save(buf)
try:
    R.parse_weekly(buf.getvalue(), 2026)
    raise AssertionError('빈 시트를 그냥 읽었다')
except ValueError:
    pass
ok += 1

# ── 저장·불러오기 ──
with tempfile.TemporaryDirectory() as td:
    f = pathlib.Path(td) / 'revenue.json'
    R.save(f, st)
    got = R.load(f)
    assert R.month_view(got, '2026-09')['actual'] == 959
    assert R.load(pathlib.Path(td) / '없는파일.json')['years'] == {}
    ok += 1

    # 깨진 파일을 빈 값으로 돌려주면 다음 저장이 멀쩡한 파일을 덮어쓴다
    f.write_text('{깨진', encoding='utf-8')
    try:
        R.load(f)
        raise AssertionError('깨진 파일을 그냥 읽었다')
    except R.RevenueFileBroken:
        pass
    ok += 1

# ── 여럿이 동시에 저장해도 파일이 깨지지 않는다 ──
import threading
with tempfile.TemporaryDirectory() as td:
    f = pathlib.Path(td) / 'revenue.json'
    R.save(f, st)
    errs = []

    def hammer():
        for _ in range(12):
            try:
                R.save(f, R.load(f))
            except Exception as e:      # noqa: BLE001
                errs.append(repr(e))

    ts = [threading.Thread(target=hammer) for _ in range(6)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    assert not errs, errs[:3]
    assert R.month_view(R.load(f), '2026-09')['actual'] == 959
    assert not list(pathlib.Path(td).glob('*.tmp')), '임시 파일이 남았다'
ok += 1

# ── 서버가 받는 곳 ──
for path in ('@app.get("/revenue")', '@app.post("/admin/revenue/import")',
             '@app.get("/admin/revenue/state")',
             '@app.post("/admin/revenue/estimate")',
             '@app.post("/admin/revenue/estimate/import")'):
    assert path in SRC, f'{path} 가 없다'
assert 'import revenue as _rev' in SRC
assert 'mode != "commit"' in SRC, '미리보기가 그냥 저장해버린다'
assert 'parse_weekly' in SRC, '서버가 주간보고를 안 읽는다'
assert '_check_month' in SRC and SRC.count('_check_month(') >= 3, \
    '월 형식을 한 곳에서만 본다'
assert 'RevenueFileBroken' in SRC, '깨진 파일을 그냥 넘긴다'
assert '"gaps"' in SRC, '세부와 합계가 어긋나도 말을 안 한다'
assert 'parse_estimate' in SRC and 'set_estimate' in SRC, '예상을 받을 데가 없다'
assert '_rev.parse_weekly' in SRC and 'plan' not in SRC.split(
    '@app.post("/admin/revenue/import")')[1].split('@app.post')[0], \
    '주간보고 응답이 아직 계획을 말한다'
ok += 1

# ── 앱 ──
LIB = ROOT.parent / 'mobile' / 'lib'
S = (LIB / 'services' / 'revenue_service.dart').read_text(encoding='utf-8')
assert '/revenue' in S, '앱이 /revenue 를 안 본다'
assert 'RevenueGroup' in S and 'internal' in S
assert 'hasEstimate' in S and 'estimate' in S, '앱이 예상을 안 읽는다'
assert '.plan' not in S and 'budget' not in S, '앱 모델에 계획이 남아 있다'
C = (LIB / 'components' / 'home' / 'exec_revenue_card.dart').read_text(encoding='utf-8')
assert 'RevenueMonth' in C, '홈 카드가 아직 모델 계산값을 쓴다'
# 실적과 예상을 한 줄로. 주간보고의 '실행계획' 은 더 이상 안 쓴다.
assert '실적 / 예상' in C and '상세 보기' in C, '홈 카드 문구가 예전 그대로다'
assert '실행계획' not in C, '홈 카드가 아직 주간보고 실행계획을 말한다'
assert '사업부 총합' not in C, '매출을 사업부 하나로 못 박았다'
assert '예상 미등록' in C, '예상이 없는 달에 달성률을 지어낸다'
assert 'r.hasEstimate' in C, '예상이 있는지 안 보고 그린다'
# 헤드라인 숫자가 잘리면 카드를 볼 이유가 없다.
#
# Spacer 는 flex 1 의 Expanded 다. 같은 Row 안의 Flexible 도 flex 1 이라
# 남은 폭이 똑같이 나뉘고, 카드가 넓은데도 실적이 '$67…' 로 잘렸다.
_num = C.split("'실적 / 예상'")[1].split('LinearProgressIndicator')[0]
_num = '\n'.join(ln for ln in _num.split('\n') if not ln.strip().startswith('//'))
assert 'Spacer' not in _num, '금액 줄에 Spacer 가 있어 폭이 쪼개진다'
assert 'Fmt.moneyShort(r.actual)' in _num, '홈 카드에 실적 금액이 없다'
D = (LIB / 'screens' / 'revenue_detail_screen.dart').read_text(encoding='utf-8')
assert 'RevenueService' in D, '매출 상세가 홈과 다른 값을 본다'
# 사업부 한 줄 → 누르면 부서별
assert '_openDiv' in D and 'r.lines' in D, '매출 상세가 부서별로 안 펴진다'
# 접혀서 열리면 화면이 카드 두 장에 통째로 빈다.
assert 'bool _openDiv = true;' in D, '매출 상세가 접힌 채로 열린다'
# 값이 왼쪽에 몰리지 않게 라벨/값을 양끝으로 붙인다.
assert 'Widget kv(String k, String v)' in D, '총합 카드가 값을 왼쪽에 몰아 놓는다'
assert '실행계획' not in D, '매출 상세가 아직 주간보고 실행계획을 말한다'
A2 = (LIB / 'screens' / 'alert_list_screen.dart').read_text(encoding='utf-8')
assert '_projectRow' in A2, '정상 모두 보기가 아직 품번을 늘어놓는다'
ok += 1

# ── admin ──
A = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'data-page="revenue"' in A, 'admin 메뉴에 매출 관리가 없다'
assert '/admin/revenue/import' in A and "'preview'" in A
assert 'data-rv-grp' in A, '큰 틀에서 세부로 펴지지 않는다'
assert '세부 합' in A, '세부와 합계가 어긋나도 화면에 말이 없다'
assert '/admin/revenue/estimate' in A, 'admin 에서 예상을 넣을 데가 없다'
assert 'rv-est-save' in A and 'rv-est-pick' in A, '예상 넣는 단추가 없다'
_rv = A.split('renderRevenuePage')[1]
assert '실행계획' not in _rv and '사업계획' not in _rv, \
    'admin 매출 화면에 아직 계획이 남아 있다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
