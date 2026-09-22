# 블룸: 품목 하나가 프로젝트 하나
#   python3 backend/tests/test_bloom_projects.py
#
# 엑셀은 품목 전체가 한 장이다. 원본은 bloom_main 한 곳에 두고 품목
# 프로젝트는 자기 몫만 잘라 본다. 갈라 저장하면 다음 업로드 때 합치는 일이
# 또 생기고, 한 번 어긋나면 되돌리기 어렵다.
import ast, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
CFG = json.loads((ROOT / 'config' / 'projects.json').read_text(encoding='utf-8'))['projects']
ok = 0

bloom = [p for p in CFG if p.get('division_id') == 'bloom']
store = [p for p in bloom if p['id'] == 'bloom_main']
items = [p for p in bloom if p.get('bloom_item')]
assert len(store) == 1 and store[0].get('visible') is False, \
    '전체 저장소(bloom_main)가 화면에 보인다'
ok += 1
assert [p['bloom_item'] for p in sorted(items, key=lambda x: x['order'])] == \
    ['YFP', 'Corva KPE', 'SL7', 'TC', 'WDM', 'BOP 기구', 'BOP Assy'], \
    [p['bloom_item'] for p in items]
ok += 1
assert all(p.get('visible') for p in items), '품목 프로젝트가 안 보인다'
assert len({p['id'] for p in items}) == 7
ok += 1
# 반도체는 안 건드렸는지
assert len([p for p in CFG if p.get('division_id') == 'semiconductor']) >= 12
ok += 1

# ── 잘라 보기 ─────────────────────────────────────────────────────
tree = ast.parse(SRC)
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef)
        and n.name in ('_norm_label', '_bloom_item_of', '_bloom_slice')}
assert set(srcs) == {'_norm_label', '_bloom_item_of', '_bloom_slice'}, srcs.keys()


class _CL:
    @staticmethod
    def get_project(pid):
        return next((p for p in CFG if p['id'] == pid), None)


g = {'_cl': _CL}
for n in ('_norm_label', '_bloom_item_of', '_bloom_slice'):
    exec(srcs[n], g)

assert g['_bloom_item_of']('bloom_sl7') == 'SL7'
assert g['_bloom_item_of']('bloom_main') == ''
assert g['_bloom_item_of']('chamber') == '', '반도체 프로젝트가 블룸으로 잡힌다'
assert g['_bloom_item_of']('없는키') == ''
ok += 1

BOARD = {'title': 't', 'report_date': '2026-09-14', 'notes': [{'text': 'n'}],
         'dates': ['2026-09-13', '2026-09-14', '2026-09-20'],
         'items': [
             {'item': 'SL7', 'steps': [
                 {'step': 'NCT(박장)', 'group': 'NCT',
                  'days': {'2026-09-13': {'plan': 27, 'actual': 10},
                           '2026-09-14': {'plan': 27, 'actual': None}}}]},
             {'item': 'Corva KPE', 'steps': [
                 {'step': '조립(박닌)', 'group': '조립',
                  'days': {'2026-09-20': {'plan': 50, 'actual': 0}}}]},
         ]}

sl = g['_bloom_slice'](BOARD, 'SL7')
assert [i['item'] for i in sl['items']] == ['SL7'], sl['items']
ok += 1
# 날짜도 그 품목 기준으로 다시 낸다 (남의 날짜가 열로 뜨면 안 된다)
assert sl['dates'] == ['2026-09-13', '2026-09-14'], sl['dates']
ok += 1
# 원본은 안 건드린다
assert len(BOARD['items']) == 2 and len(BOARD['dates']) == 3
ok += 1
# 제목·메모 같은 건 그대로 따라온다
assert sl['title'] == 't' and sl['notes'] == [{'text': 'n'}]
ok += 1
# 없는 품목이면 빈 보드
assert g['_bloom_slice'](BOARD, 'YFP')['items'] == []
ok += 1

# ── 업로드는 어느 품목에서 눌러도 한 곳에 저장 ────────────────────
assert SRC.count('_BLOOM_STORE if _bloom_item_of(_model_key_alias(project_key))') == 2, \
    '미리보기·저장 두 곳 다 전체 저장소로 보내야 한다'
ok += 1
assert '_store = _BLOOM_STORE if _item else _key' in SRC, \
    '품목 프로젝트가 자기 저장소를 따로 본다'
ok += 1

# ── 앱 ────────────────────────────────────────────────────────────
M = ROOT.parent / 'mobile' / 'lib'
SVC = (M / 'services' / 'bloom_service.dart').read_text(encoding='utf-8')
assert 'Map<String, BloomDailyBoard> _cache' in SVC, \
    '캐시가 하나뿐이면 다른 품목을 열 때 남의 값이 보인다'
assert 'static bool isItemKey(String key)' in SVC
ok += 1
OV = (M / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert 'BloomService.isItemKey(widget.projectKey)' in OV
assert 'BloomTodayCard(board: _bloom)' in OV, '품목 화면에 일 보드가 없다'
ok += 1
# 사업부 화면의 '오늘' 카드는 전체(bloom_main) 그대로
DIV = (M / 'screens' / 'division_projects_screen.dart').read_text(encoding='utf-8')
assert 'BloomTodayCard(board: _bloom)' in DIV, '사업부 오늘 카드가 사라졌다'
assert "static const String projectKey = 'bloom_main'" in SVC
ok += 1

print(f'전부 통과 ({ok}/15)')
