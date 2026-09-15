# 큐리 버스바: 모델 목록에는 11개 다 남고, 보드에서만 한 줄로 묶인다
#   python3 backend/tests/test_curie_busbar.py
#
# 한 번 반대로 만든 적이 있다. 11개를 한 모델로 합쳐버리면 품번별 판가·
# 재료비를 넣을 자리가 사라진다. 모델을 지우는 코드가 다시 들어오면 실패한다.
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
BOARDS = json.loads((ROOT / 'config' / 'boards.json').read_text(encoding='utf-8'))['boards']
ok = 0

# 모델을 합치거나 지우는 마이그레이션이 없어야 한다
assert '_merge_curie_busbar' not in SRC, \
    '버스바를 한 모델로 합치는 코드가 다시 들어왔다 — 모델 목록에는 11개가 남아야 한다'
assert '_PLAN_AGG_AS_MODEL' not in SRC, \
    '묶음 행을 모델로 만드는 설정이 다시 들어왔다'
ok += 1

# 보드에만 묶음 행이 있다
sx = BOARDS['spacex']['sections'][0]
bus = [r for r in sx['rows'] if r.get('key') == 'busbar']
assert len(bus) == 1 and len(bus[0]['models']) == 11, sx['rows']
ok += 1

# 11개 품번이 실제 값과 같은지 (오타 하나면 그 모델만 조용히 빠진다)
assert sorted(bus[0]['models']) == sorted(
    ['559D', '560D', '561D', '562D', '563D', '564D',
     '565D', '566D', '568D', '569D', '570D']), sorted(bus[0]['models'])
ok += 1

# 엑셀 묶음 행을 보드 행으로 보내는 경로가 살아 있는지
assert '_board_group_rows(project_key)' in SRC, '묶음 행을 보드 행에서 찾지 않는다'
assert 'ids = agg_rows.get(_norm_label(label)) or []' in SRC
ok += 1

# 그 경로가 PO 를 건드리지 않는지 (모델별로 이미 있어서 더하면 두 배)
seg = SRC[SRC.index('ids = agg_rows.get('):]
seg = seg[:seg.index('if target is None:')]
assert 'po_qty' not in seg and 'shipped_qty' not in seg, \
    f'묶음 행이 PO/출하를 덮어쓴다:\n{seg}'
ok += 1

print(f'전부 통과 ({ok}/5)')
