# 매출 — 주간보고 엑셀이 원본이다
#   python3 backend/tests/test_revenue.py
#
# "WEEKLY 엑셀에 다 있네"
#
# '1. 계획 대비 실적 (수정본) Actual FCST' 시트 한 장에 줄마다
# 사업계획/실행계획/실적, 열마다 W1~W52, 맨 아래 [합 계] 블록에
# 보고서 묶음(반도체 · 데이터 센터 · 우주항공 · 내부거래)까지 있다.
#
# 지키는 것 셋.
#   1. 묶음 합계는 [합 계] 블록 그대로 쓴다. 우리가 더해서 만들지 않는다.
#   2. 세부를 더한 값이 합계와 다르면 조용히 넘기지 않고 말해 준다.
#   3. 같은 파일을 두 번 올려도 그 해를 갈아 끼울 뿐 더해지지 않는다.
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
assert box['semi']['actual'] == 748 and box['semi']['plan'] == 820, box['semi']
assert box['semi']['budget'] == 500
assert box['dc']['actual'] == 31 and box['space']['actual'] == 0
assert v['internal']['actual'] == 180
assert v['subtotal']['actual'] == 779, v['subtotal']
assert v['grand']['actual'] == 959, v['grand']
assert v['actual'] == 959 and v['plan'] == 1162, (v['actual'], v['plan'])
assert v['rate'] == 83, v['rate']
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
             '@app.get("/admin/revenue/state")'):
    assert path in SRC, f'{path} 가 없다'
assert 'import revenue as _rev' in SRC
assert 'mode != "commit"' in SRC, '미리보기가 그냥 저장해버린다'
assert 'parse_weekly' in SRC, '서버가 주간보고를 안 읽는다'
assert '_check_month' in SRC and SRC.count('_check_month(') >= 3, \
    '월 형식을 한 곳에서만 본다'
assert 'RevenueFileBroken' in SRC, '깨진 파일을 그냥 넘긴다'
assert '"gaps"' in SRC, '세부와 합계가 어긋나도 말을 안 한다'
ok += 1

# ── 앱 ──
LIB = ROOT.parent / 'mobile' / 'lib'
S = (LIB / 'services' / 'revenue_service.dart').read_text(encoding='utf-8')
assert '/revenue' in S, '앱이 /revenue 를 안 본다'
assert 'RevenueGroup' in S and 'internal' in S
C = (LIB / 'components' / 'home' / 'exec_revenue_card.dart').read_text(encoding='utf-8')
assert 'RevenueMonth' in C, '홈 카드가 아직 모델 계산값을 쓴다'
# 실적과 실행계획을 한 줄로. 밑에 또 적으면 같은 숫자를 두 번 말한다.
assert '실적 / 실행계획' in C and '상세 보기' in C, '홈 카드 문구가 예전 그대로다'
assert '사업부 총합' not in C, '매출을 사업부 하나로 못 박았다'
# 헤드라인 숫자가 잘리면 카드를 볼 이유가 없다.
#
# Spacer 는 flex 1 의 Expanded 다. 같은 Row 안의 Flexible 도 flex 1 이라
# 남은 폭이 똑같이 나뉘고, 카드가 넓은데도 실적이 '$67…' 로 잘렸다.
_num = C.split('실적 / 실행계획')[1].split('LinearProgressIndicator')[0]
_num = '\n'.join(ln for ln in _num.split('\n') if not ln.strip().startswith('//'))
assert 'Spacer' not in _num, '금액 줄에 Spacer 가 있어 폭이 쪼개진다'
assert 'Fmt.moneyShort(r.actual)' in _num, '홈 카드에 실적 금액이 없다'
D = (LIB / 'screens' / 'revenue_detail_screen.dart').read_text(encoding='utf-8')
assert 'RevenueService' in D, '매출 상세가 홈과 다른 값을 본다'
# 사업부 한 줄 → 누르면 부서별
assert '_openDiv' in D and 'r.lines' in D, '매출 상세가 부서별로 안 펴진다'
A2 = (LIB / 'screens' / 'alert_list_screen.dart').read_text(encoding='utf-8')
assert '_projectRow' in A2, '정상 모두 보기가 아직 품번을 늘어놓는다'
ok += 1

# ── admin ──
A = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert 'data-page="revenue"' in A, 'admin 메뉴에 매출 관리가 없다'
assert '/admin/revenue/import' in A and "'preview'" in A
assert 'data-rv-grp' in A, '큰 틀에서 세부로 펴지지 않는다'
assert '세부 합' in A, '세부와 합계가 어긋나도 화면에 말이 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
