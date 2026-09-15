# rows_from: "models" — 모델 하나가 보드 행 하나
#   python3 backend/tests/test_board_rows_from_models.py
#
# 큐리는 엑셀이 '모델명 x 주차' 한 장으로 온다. 행을 설정에 미리 적어둘 수
# 없다 — 모델이 늘면 보드도 같이 늘어야 한다.
import ast, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
src = next((ast.get_source_segment(SRC, n) for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name == '_spec_section_rows'), None)
assert src, '_spec_section_rows 를 못 찾았다'
g = {}
exec(src, g)
rows_of = g['_spec_section_rows']

PROJ = {'models': [
    {'id': '556B', 'name': '키스톤', 'part_number': '556B'},
    {'id': '66C', 'name': '리프트 캐리지', 'part_number': '66C'},
    {'id': '버스바/시트메탈류(11종)', 'name': '버스바/시트메탈류(11종)',
     'part_number': '버스바/시트메탈류(11종)'},
    {'id': 'NOPN', 'name': '품번없음'},
    'not a dict',
    {'name': '아이디없음'},
]}

ok = 0
rows = rows_of(PROJ, {'name': '', 'rows_from': 'models', 'rows': []})
labels = [r['label'] for r in rows]
assert labels == ['키스톤 (556B)', '리프트 캐리지 (66C)',
                  '버스바/시트메탈류(11종)', '품번없음'], labels
ok += 1
# 엑셀에 적힌 순서 그대로
assert [r['models'][0] for r in rows] == ['556B', '66C', '버스바/시트메탈류(11종)', 'NOPN']
ok += 1
# 행 키가 겹치면 안 된다 (직접 입력값이 엉뚱한 행에 붙는다)
assert len({r['key'] for r in rows}) == len(rows)
ok += 1

# rows_from 이 없으면 예전 그대로
plain = {'name': '기존', 'rows': [{'key': 'a', 'label': '4종', 'manual': True}]}
assert rows_of(PROJ, plain) == plain['rows']
ok += 1

# 설정에 적어둔 행이 있으면 그게 먼저, 중복은 안 만든다
mixed = {'name': '', 'rows_from': 'models',
         'rows': [{'key': 'fixed', 'label': '묶음', 'models': ['66C']}]}
mr = rows_of(PROJ, mixed)
assert mr[0]['key'] == 'fixed', mr
assert '66C' not in [x for r in mr[1:] for x in r['models']], \
    '이미 지목된 모델이 또 행으로 생겼다'
assert len(mr) == 4, [r['label'] for r in mr]
ok += 1

# 모델이 없으면 빈 보드
assert rows_of({'models': []}, {'rows_from': 'models', 'rows': []}) == []
assert rows_of({}, {'rows_from': 'models', 'rows': []}) == []
ok += 1

# 실제 연결부
assert 'for row in _spec_section_rows(proj, sec):' in SRC, '보드가 아직 sec["rows"] 만 본다'
ok += 1

# 큐리 보드 설정
spec = json.loads((ROOT / 'config' / 'boards.json').read_text(encoding='utf-8'))['boards']
assert 'spacex' in spec, 'boards.json 에 큐리가 없다'
sx = spec['spacex']
assert sx['columns'] == 'week' and sx['sections'][0]['rows_from'] == 'models', sx
assert sx.get('next_month') is True, '10월 열이 있어야 한다 (W40~W44 가 거기 있다)'
ok += 1

print(f'전부 통과 ({ok}/8)')
