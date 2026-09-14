# 블룸 일 보드 합치기 + 그 날 요약
#   python3 backend/tests/test_bloom_merge.py
#
# 매일 같은 달 파일을 올린다. 통째로 덮으면 안 되고 날짜 단위로 합쳐야 한다.
# 파일이 한 번 잘못 와도 그 전에 쌓인 게 날아가면 안 된다.
import ast, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)

WANT = {'_bloom_pick', '_bloom_merge', '_bloom_summary'}
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef) and n.name in WANT}
assert set(srcs) == WANT, f'못 찾은 함수: {WANT - set(srcs)}'
CAP = next(ast.literal_eval(n.value) for n in tree.body
           if isinstance(n, ast.Assign)
           and any(getattr(t, 'id', '') == '_BLOOM_DIFF_CAP' for t in n.targets))
g = {'_BLOOM_DIFF_CAP': CAP}
for n in ('_bloom_pick', '_bloom_merge', '_bloom_summary'):
    exec(srcs[n], g)
merge, summary = g['_bloom_merge'], g['_bloom_summary']


def item(name, steps, ws=None, wp=None, code=''):
    return {'item': name, 'code': code, 'wait_ship': ws, 'wait_part': wp,
            'steps': [{'step': s, 'group': s.split('(')[0], 'wip': wip,
                       'month_plan': mp, 'month_actual': ma,
                       'prior_plan': None, 'prior_actual': None,
                       'note': note, 'days': days}
                      for s, wip, mp, ma, note, days in steps]}


DAY1 = {'items': [
    item('Corva KPE', [
        ('NCT(박닌)', 0, 1050, 233, '', {'2026-09-12': {'plan': 50, 'actual': 40},
                                        '2026-09-13': {'plan': 50, 'actual': 31},
                                        '2026-09-14': {'plan': 50, 'actual': None}}),
        ('조립(박닌)', 20, 1050, 213, '', {'2026-09-13': {'plan': 50, 'actual': 42},
                                         '2026-09-14': {'plan': 50, 'actual': None}}),
    ], ws=80, wp=228, code='172146'),
    item('SL7', [('출하', None, 708, 208, '', {'2026-09-14': {'plan': 0, 'actual': None}})]),
], 'notes': [{'text': '퓨즈 9/16', 'eta': '9/16'}],
    'title': '블룸 계획 대비 실적 보고(9/14)', 'report_date': '2026-09-14',
    'prior_label': '9/9 이전 데이터', 'sheet': '대표님 일 보고 자료'}

ok = 0
board, diff = merge({}, DAY1)
assert len(board['items']) == 2 and board['dates'] == ['2026-09-12', '2026-09-13', '2026-09-14']
assert diff['days_added'] == 6 and not diff['day_changes'], diff
assert diff['items_new'] == [], '첫 업로드는 전부 신규라 따로 알리지 않는다'
ok += 1

# ── 다음 날 파일: 9/14 실적이 채워지고 9/15 가 생긴다 ──────────────
DAY2 = {'items': [
    item('Corva KPE', [
        ('NCT(박닌)', 0, 1050, 283, '', {'2026-09-14': {'plan': 50, 'actual': 50},
                                        '2026-09-15': {'plan': 50, 'actual': None}}),
        ('조립(박닌)', 15, 1050, 263, '퓨즈 대기', {'2026-09-14': {'plan': 50, 'actual': 50}}),
    ], ws=60, wp=228, code='172146'),
    item('BOP Assy', [('조립(박닌)', 0, 1100, 44, '', {'2026-09-14': {'plan': 55, 'actual': 30}})]),
], 'notes': [{'text': '터미널 블록 9/18', 'eta': '9/18'}],
    'title': '블룸 계획 대비 실적 보고(9/15)', 'report_date': '2026-09-15',
    'prior_label': '', 'sheet': '대표님 일 보고 자료'}

b2, d2 = merge(board, DAY2)
items = {i['item']: i for i in b2['items']}

# 새 파일에 없는 SL7 이 남아 있어야 한다
assert 'SL7' in items and d2['items_kept'] == ['SL7'], d2
ok += 1
assert d2['items_new'] == ['BOP Assy'], d2['items_new']
ok += 1

kpe = {s['step']: s for s in items['Corva KPE']['steps']}
# 9/12·9/13 은 새 파일에 없어도 살아 있어야 한다
assert kpe['NCT(박닌)']['days']['2026-09-12'] == {'plan': 50, 'actual': 40}
assert kpe['NCT(박닌)']['days']['2026-09-13'] == {'plan': 50, 'actual': 31}
ok += 1
# 9/14 실적이 미입력 -> 50 으로 바뀐 게 잡혀야 한다
chg = [c for c in d2['day_changes'] if c['date'] == '2026-09-14' and c['step'] == 'NCT(박닌)']
assert chg and chg[0]['from']['actual'] is None and chg[0]['to']['actual'] == 50, d2['day_changes']
ok += 1
# 9/15 NCT 한 칸 + 새로 생긴 BOP Assy 의 9/14 한 칸
assert d2['days_added'] == 2, d2['days_added']
ok += 1
# 월 누적 변화
mc = {(c['item'], c['step'], c['field']): (c['from'], c['to']) for c in d2['month_changes']}
assert mc[('Corva KPE', 'NCT(박닌)', 'month_actual')] == (233, 283), mc
ok += 1
# 재고는 새 값이 이기고, 안 온 값은 옛 값을 지킨다
assert items['Corva KPE']['wait_ship'] == 60 and items['Corva KPE']['wait_part'] == 228
assert kpe['조립(박닌)']['wip'] == 15 and kpe['조립(박닌)']['note'] == '퓨즈 대기'
ok += 1
# 메모는 누적하지 않고 새것으로 바꾼다
assert b2['notes'] == [{'text': '터미널 블록 9/18', 'eta': '9/18'}]
ok += 1
# 비어서 온 prior_label 은 옛 값을 지킨다
assert b2['prior_label'] == '9/9 이전 데이터', b2['prior_label']
assert b2['report_date'] == '2026-09-15'
ok += 1

# ── 그 날 요약 ────────────────────────────────────────────────────
s14 = summary(b2, '2026-09-14')
assert s14['today']['groups']['NCT'] == {'plan': 50, 'actual': 50, 'has_actual': True}
assert s14['today']['plan'] == 50 + 50 + 55 + 0, s14['today']
assert s14['today']['actual'] == 50 + 50 + 30, s14['today']
assert s14['today']['pending'] is False
assert s14['prev_date'] == '2026-09-13', s14['prev_date']
ok += 1

# 실적이 하나도 안 들어온 날은 pending (0% 로 보이면 안 된다)
s15 = summary(b2, '2026-09-15')
assert s15['today']['plan'] == 50 and s15['today']['actual'] == 0
assert s15['today']['pending'] is True, s15['today']
assert s15['prev_date'] == '2026-09-14'
ok += 1

# 계획도 실적도 0 인 날은 pending 이 아니다 (할 일이 없던 날)
b3, _ = merge(b2, {'items': [item('SL7', [('출하', None, 708, 208, '',
              {'2026-09-16': {'plan': 0, 'actual': None}})])], 'notes': []})
assert summary(b3, '2026-09-16')['today']['pending'] is False
ok += 1

# 없는 날짜를 물으면 그 뒤 첫 날로 보낸다
assert summary(b2, '2026-01-01')['date'] == '2026-09-12'
assert summary({}, '') == {}
ok += 1

print(f'전부 통과 ({ok}/14)')
