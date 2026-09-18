# 사업부 목록이 성한지
#   python3 backend/tests/test_divisions_config.py
#
# "중공업사업부, 휠사업부, 헬스케어사업부 삭제해줘"
#
# 자료가 하나도 없는 칸이 홈에 남아 있으면 누를 때마다 빈 화면이 뜬다.
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
D = json.loads((ROOT / 'config' / 'divisions.json').read_text(encoding='utf-8'))
ok = 0

divs = D['divisions']
ids = [x['id'] for x in divs]
assert len(ids) == len(set(ids)), f'id 가 겹친다: {ids}'
ok += 1

for gone in ('heavy', 'wheel', 'healthcare'):
    assert gone not in ids, f'{gone} 가 아직 있다'
ok += 1

# 쓰고 있는 사업부는 그대로 있어야 한다
for keep in ('semiconductor', 'pcb', 'network', 'system', 'ess',
             'automation', 'automotive', 'bloom', 'arista'):
    assert keep in ids, f'{keep} 가 사라졌다'
ok += 1

# order 는 1부터 빈칸 없이. 비면 화면 정렬이 들쭉날쭉해진다.
orders = sorted(x.get('order') for x in divs)
assert orders == list(range(1, len(divs) + 1)), f'순서가 비었다: {orders}'
ok += 1

for x in divs:
    for k in ('id', 'label', 'order'):
        assert x.get(k) not in (None, ''), f'{x.get("id")} 에 {k} 가 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
